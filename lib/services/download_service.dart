import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/download_model.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final YoutubeExplode _yt = YoutubeExplode();

  final List<DownloadTask> _downloadHistory = [];
  final StreamController<List<DownloadTask>> _historyController =
      StreamController<List<DownloadTask>>.broadcast();

  List<DownloadTask> get downloadHistory => List.unmodifiable(_downloadHistory);
  Stream<List<DownloadTask>> get historyStream => _historyController.stream;

  // ─── Extract Video ID ─────────────────────────────────────────────────────
  String? extractVideoId(String url) {
    url = url.trim();
    final patterns = [
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/(?:embed|shorts|live)/([a-zA-Z0-9_-]{11})'),
    ];
    for (final regex in patterns) {
      final match = regex.firstMatch(url);
      if (match != null) return match.group(1);
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(url)) return url;
    return null;
  }

  // ─── Fetch Video Info ─────────────────────────────────────────────────────
  Future<VideoInfo> fetchVideoInfo(String url) async {
    final videoId = extractVideoId(url);
    if (videoId == null) {
      throw Exception('URL YouTube không hợp lệ. Vui lòng kiểm tra lại.');
    }

    try {
      final video = await _yt.videos.get(videoId);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);

      final videoStreams = <VideoStream>[];
      for (final s in manifest.muxed) {
        videoStreams.add(VideoStream(
          quality: s.qualityLabel,
          container: s.container.name,
          fileSize: s.size.totalBytes.toInt(),
          itag: s.tag,
          isMuxed: true,
        ));
      }
      for (final s in manifest.videoOnly) {
        videoStreams.add(VideoStream(
          quality: '${s.qualityLabel} (video only)',
          container: s.container.name,
          fileSize: s.size.totalBytes.toInt(),
          itag: s.tag,
          isMuxed: false,
        ));
      }

      final audioStreams = <AudioStream>[];
      for (final s in manifest.audioOnly) {
        audioStreams.add(AudioStream(
          quality: s.audioCodec,
          container: s.container.name,
          bitrate: s.bitrate.kiloBitsPerSecond.toInt(),
          fileSize: s.size.totalBytes.toInt(),
          itag: s.tag,
        ));
      }

      videoStreams.sort((a, b) =>
          _extractQualityNumber(b.quality).compareTo(_extractQualityNumber(a.quality)));
      audioStreams.sort((a, b) => (b.bitrate ?? 0).compareTo(a.bitrate ?? 0));

      return VideoInfo(
        id: videoId,
        title: video.title,
        author: video.author,
        thumbnailUrl: video.thumbnails.maxResUrl,
        duration: video.duration ?? Duration.zero,
        videoStreams: videoStreams,
        audioStreams: audioStreams,
      );
    } on VideoUnavailableException {
      throw Exception('Video không tồn tại hoặc đã bị xóa.');
    } on VideoRequiresPurchaseException {
      throw Exception('Video yêu cầu mua trả phí, không thể tải.');
    } catch (e) {
      throw Exception('Không thể lấy thông tin video: ${e.toString()}');
    }
  }

  // ─── Core download (throttle + watchdog) ──────────────────────────────────
  Future<void> _downloadStream({
    required StreamInfo streamInfo,
    required String savePath,
    required int totalBytes,
    required Function(double) onProgress,
    required DownloadTask task,
  }) async {
    final file = File(savePath);
    IOSink? output;

    // throttle UI
    int lastUiMs = 0;
    int lastReceivedForFake = 0;
    DateTime lastDataAt = DateTime.now();

    Timer? watchdog;

    try {
      output = file.openWrite();
      final stream = _yt.videos.streamsClient.get(streamInfo);

      int received = 0;
      final total = totalBytes > 0 ? totalBytes : 0;

      // watchdog: nếu 20s không có data => abort để khỏi đứng %
      watchdog = Timer.periodic(const Duration(seconds: 5), (_) async {
        final stalled = DateTime.now().difference(lastDataAt).inSeconds >= 20;
        if (stalled) {
          watchdog?.cancel();
          try {
            await output?.flush();
            await output?.close();
          } catch (_) {}
        }
      });

      await for (final chunk in stream) {
        output.add(chunk);
        received += chunk.length;
        lastDataAt = DateTime.now();

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - lastUiMs >= 250) {
          lastUiMs = nowMs;

          if (total > 0) {
            final p = (received / total).clamp(0.0, 1.0);
            onProgress(p);
            task.progress = p;
          } else {
            // totalBytes không có => fake progress nhẹ để UI không đứng 0%
            final delta = received - lastReceivedForFake;
            lastReceivedForFake = received;
            if (delta > 0) {
              final p = (task.progress + 0.005).clamp(0.0, 0.95);
              onProgress(p);
              task.progress = p;
            }
          }

          _notifyHistoryUpdate();
        }
      }

      watchdog?.cancel();
      await output.flush();
      await output.close();
    } catch (e) {
      watchdog?.cancel();
      try {
        await output?.close();
      } catch (_) {}
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  // ─── Download Video ───────────────────────────────────────────────────────
  Future<String> downloadVideo({
    required VideoInfo videoInfo,
    required VideoStream stream,
    required Function(double progress) onProgress,
    required String sourceUrl, // URL gốc
  }) async {
    final dir = await _getDownloadDirectory();

    final safeName = _sanitizeFilename(videoInfo.title);
    final ext = stream.container ?? 'mp4';
    final qualityTag = stream.quality.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final suffix = DateTime.now().millisecondsSinceEpoch.toString();
    final filePath = '${dir.path}/${safeName}_$qualityTag_$suffix.$ext';

    final task = DownloadTask(
      id: suffix,
      title: videoInfo.title,
      url: sourceUrl, // FIX: lưu URL thật
      type: DownloadType.video,
      quality: stream.quality,
    );
    _downloadHistory.insert(0, task);
    _notifyHistoryUpdate();

    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoInfo.id);

      StreamInfo? streamInfo;
      if (stream.isMuxed) {
        streamInfo = manifest.muxed.firstWhere(
          (s) => s.tag == stream.itag,
          orElse: () {
            final list = manifest.muxed.toList()
              ..sort((a, b) => a.videoQuality.compareTo(b.videoQuality));
            return list.isNotEmpty ? list.last : throw Exception('No muxed stream');
          },
        );
      } else {
        streamInfo = manifest.videoOnly.firstWhere(
          (s) => s.tag == stream.itag,
          orElse: () {
            final list = manifest.videoOnly.toList()
              ..sort((a, b) => a.videoQuality.compareTo(b.videoQuality));
            return list.isNotEmpty ? list.last : throw Exception('No video-only stream');
          },
        );
      }

      await _downloadStream(
        streamInfo: streamInfo,
        savePath: filePath,
        totalBytes: streamInfo.size.totalBytes.toInt(),
        onProgress: onProgress,
        task: task,
      );

      task.status = DownloadStatus.completed;
      task.filePath = filePath;
      task.progress = 1.0;
      _notifyHistoryUpdate();

      return filePath;
    } catch (e) {
      task.status = DownloadStatus.error;
      task.errorMessage = e.toString().replaceAll('Exception: ', '');
      _notifyHistoryUpdate();

      final file = File(filePath);
      if (await file.exists()) await file.delete();

      throw Exception('Lỗi tải video: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // ─── Download Audio ───────────────────────────────────────────────────────
  Future<String> downloadAudio({
    required VideoInfo videoInfo,
    required AudioStream stream,
    required Function(double progress) onProgress,
    required String sourceUrl, // URL gốc
  }) async {
    final dir = await _getDownloadDirectory();

    final safeName = _sanitizeFilename(videoInfo.title);
    final ext = stream.container ?? 'webm';
    final suffix = DateTime.now().millisecondsSinceEpoch.toString();
    final filePath = '${dir.path}/${safeName}_audio_${suffix}.$ext';

    final task = DownloadTask(
      id: suffix,
      title: videoInfo.title,
      url: sourceUrl, // FIX: URL thật
      type: DownloadType.audio,
      quality: '${stream.bitrate ?? 0}kbps',
    );
    _downloadHistory.insert(0, task);
    _notifyHistoryUpdate();

    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoInfo.id);

      AudioOnlyStreamInfo? streamInfo;
      streamInfo = manifest.audioOnly.firstWhere(
        (s) => s.tag == stream.itag,
        orElse: () {
          final sorted = manifest.audioOnly.toList()
            ..sort((a, b) => b.bitrate.kiloBitsPerSecond.compareTo(a.bitrate.kiloBitsPerSecond));
          return sorted.isNotEmpty ? sorted.first : throw Exception('No audio stream');
        },
      );

      await _downloadStream(
        streamInfo: streamInfo,
        savePath: filePath,
        totalBytes: streamInfo.size.totalBytes.toInt(),
        onProgress: onProgress,
        task: task,
      );

      task.status = DownloadStatus.completed;
      task.filePath = filePath;
      task.progress = 1.0;
      _notifyHistoryUpdate();

      return filePath;
    } catch (e) {
      task.status = DownloadStatus.error;
      task.errorMessage = e.toString().replaceAll('Exception: ', '');
      _notifyHistoryUpdate();

      final file = File(filePath);
      if (await file.exists()) await file.delete();

      throw Exception('Lỗi tải audio: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  int _extractQualityNumber(String quality) {
    final match = RegExp(r'(\d+)').firstMatch(quality);
    return match != null ? int.parse(match.group(1)!) : 0;
  }

  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isIOS) {
      // ✅ iOS: Documents/Downloads (sẽ hiện trong Files nếu bật UIFileSharingEnabled)
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${dir.path}/Downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      return downloadDir;
    } else {
      // ✅ Android: app-specific external (chắc chạy trên Android 10-14)
      // Nếu anh muốn lưu đúng "Download" hệ thống => phải làm SAF/MediaStore (phức tạp hơn)
      final extDir = await getExternalStorageDirectory();
      if (extDir == null) {
        // fallback internal
        final dir = await getApplicationDocumentsDirectory();
        final d = Directory('${dir.path}/Downloads');
        if (!await d.exists()) await d.create(recursive: true);
        return d;
      }

      // xin quyền cho Android cũ (<= 12) nếu cần
      final status = await Permission.storage.request();
      if (!status.isGranted && !status.isLimited) {
        // vẫn cho chạy nếu app-specific, nhưng để minh bạch thì báo
        // (tuỳ máy vẫn ok)
      }

      final d = Directory('${extDir.path}/YTDownloader');
      if (!await d.exists()) await d.create(recursive: true);
      return d;
    }
  }

  String _sanitizeFilename(String name) {
    final sanitized = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    return sanitized.length > 100 ? sanitized.substring(0, 100) : sanitized;
  }

  void _notifyHistoryUpdate() {
    if (!_historyController.isClosed) {
      _historyController.add(List.from(_downloadHistory));
    }
  }

  void dispose() {
    _yt.close();
    _historyController.close();
  }
}