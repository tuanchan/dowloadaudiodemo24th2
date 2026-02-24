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

  Future<void> _downloadStream({
    required StreamInfo streamInfo,
    required String savePath,
    required int totalBytes,
    required Function(double) onProgress,
    required DownloadTask task,
  }) async {
    final file = File(savePath);
    IOSink? output;
    Timer? watchdog;

    // ✅ force UI move immediately
    onProgress(0.001);
    task.progress = 0.001;
    _notifyHistoryUpdate();

    int received = 0;
    int lastUiMs = 0;
    DateTime lastDataAt = DateTime.now();

    try {
      output = file.openWrite();
      final stream = _yt.videos.streamsClient.get(streamInfo);

      watchdog = Timer.periodic(const Duration(seconds: 2), (_) async {
        final stalled = DateTime.now().difference(lastDataAt).inSeconds >= 20;
        if (stalled) {
          watchdog?.cancel();
          try {
            await output?.flush();
            await output?.close();
          } catch (_) {}
          throw Exception('Kết nối tải bị đứng (20s không nhận dữ liệu). Thử lại hoặc đổi chất lượng.');
        }
      });

      await for (final chunk in stream) {
        output.add(chunk);
        received += chunk.length;
        lastDataAt = DateTime.now();

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - lastUiMs >= 200) {
          lastUiMs = nowMs;

          double p;
          if (totalBytes > 0) {
            p = (received / totalBytes).clamp(0.0, 1.0);
          } else {
            // totalBytes đôi khi 0 -> vẫn nhúc nhích nhẹ
            p = (task.progress + 0.003).clamp(0.0, 0.95);
          }

          onProgress(p);
          task.progress = p;
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

  Future<String> downloadAudio({
    required VideoInfo videoInfo,
    required AudioStream stream,
    required Function(double progress) onProgress,
  }) async {
    final dir = await _getDownloadDirectory();
    final safeName = _sanitizeFilename(videoInfo.title);
    final ext = stream.container ?? 'webm';
    final filePath = '${dir.path}/${safeName}_audio.$ext';

    final task = DownloadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: videoInfo.title,
      url: videoInfo.id,
      type: DownloadType.audio,
      quality: '${stream.bitrate ?? 0}kbps',
    );
    _downloadHistory.insert(0, task);
    _notifyHistoryUpdate();

    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoInfo.id);

      AudioOnlyStreamInfo? streamInfo;
      for (final s in manifest.audioOnly) {
        if (s.tag == stream.itag) {
          streamInfo = s;
          break;
        }
      }

      if (streamInfo == null && manifest.audioOnly.isNotEmpty) {
        final sorted = manifest.audioOnly.toList()
          ..sort((a, b) =>
              b.bitrate.kiloBitsPerSecond.compareTo(a.bitrate.kiloBitsPerSecond));
        streamInfo = sorted.first;
      }

      if (streamInfo == null) {
        throw Exception('Không tìm thấy stream audio. Vui lòng thử lại.');
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

      final f = File(filePath);
      if (await f.exists()) await f.delete();

      throw Exception('Lỗi tải audio: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  Future<String> downloadVideo({
    required VideoInfo videoInfo,
    required VideoStream stream,
    required Function(double progress) onProgress,
  }) async {
    final dir = await _getDownloadDirectory();
    final safeName = _sanitizeFilename(videoInfo.title);
    final ext = stream.container ?? 'mp4';

    final qualityTag = stream.quality.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final filePath = '${dir.path}/${safeName}_$qualityTag.$ext';

    final task = DownloadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: videoInfo.title,
      url: videoInfo.id,
      type: DownloadType.video,
      quality: stream.quality,
    );
    _downloadHistory.insert(0, task);
    _notifyHistoryUpdate();

    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoInfo.id);

      StreamInfo? streamInfo;

      if (stream.isMuxed) {
        for (final s in manifest.muxed) {
          if (s.tag == stream.itag) {
            streamInfo = s;
            break;
          }
        }
        if (streamInfo == null && manifest.muxed.isNotEmpty) {
          final list = manifest.muxed.toList()
            ..sort((a, b) => _extractQualityNumber(a.qualityLabel)
                .compareTo(_extractQualityNumber(b.qualityLabel)));
          streamInfo = list.last;
        }
      } else {
        for (final s in manifest.videoOnly) {
          if (s.tag == stream.itag) {
            streamInfo = s;
            break;
          }
        }
        if (streamInfo == null && manifest.videoOnly.isNotEmpty) {
          final list = manifest.videoOnly.toList()
            ..sort((a, b) => _extractQualityNumber(a.qualityLabel)
                .compareTo(_extractQualityNumber(b.qualityLabel)));
          streamInfo = list.last;
        }
      }

      if (streamInfo == null) {
        throw Exception('Không tìm thấy stream. Vui lòng thử chất lượng khác.');
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

      final f = File(filePath);
      if (await f.exists()) await f.delete();

      throw Exception('Lỗi tải video: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  int _extractQualityNumber(String quality) {
    final match = RegExp(r'(\d+)').firstMatch(quality);
    return match != null ? int.parse(match.group(1)!) : 0;
  }

  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${dir.path}/Downloads');
      if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
      return downloadDir;
    } else {
      final status = await Permission.storage.request();
      if (!status.isGranted && !status.isLimited) {
        throw Exception('Cần cấp quyền truy cập bộ nhớ để tải file.');
      }
      final dir = Directory('/storage/emulated/0/Download/YTDownloader');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
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