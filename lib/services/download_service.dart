import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/download_model.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final YoutubeExplode _yt = YoutubeExplode();
  final Dio _dio = Dio();
  final List<DownloadTask> _downloadHistory = [];
  final StreamController<List<DownloadTask>> _historyController =
      StreamController<List<DownloadTask>>.broadcast();

  List<DownloadTask> get downloadHistory => List.unmodifiable(_downloadHistory);
  Stream<List<DownloadTask>> get historyStream => _historyController.stream;

  /// Parse and validate YouTube URL, extract video ID
  String? extractVideoId(String url) {
    url = url.trim();
    // youtu.be/ID
    final shortRegex = RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})');
    final shortMatch = shortRegex.firstMatch(url);
    if (shortMatch != null) return shortMatch.group(1);

    // youtube.com/watch?v=ID
    final longRegex = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})');
    final longMatch = longRegex.firstMatch(url);
    if (longMatch != null) return longMatch.group(1);

    // youtube.com/embed/ID or /shorts/ID
    final embedRegex = RegExp(r'youtube\.com/(?:embed|shorts)/([a-zA-Z0-9_-]{11})');
    final embedMatch = embedRegex.firstMatch(url);
    if (embedMatch != null) return embedMatch.group(1);

    // raw 11-char video ID
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(url)) return url;

    return null;
  }

  /// Fetch video metadata + available streams
  Future<VideoInfo> fetchVideoInfo(String url) async {
    final videoId = extractVideoId(url);
    if (videoId == null) {
      throw Exception('URL YouTube không hợp lệ. Vui lòng kiểm tra lại.');
    }

    try {
      final video = await _yt.videos.get(videoId);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);

      // Build video streams (muxed = video+audio combined, easier for users)
      final videoStreams = <VideoStream>[];

      // Muxed streams (video + audio)
      for (final s in manifest.muxed) {
        videoStreams.add(VideoStream(
          quality: s.qualityLabel,
          container: s.container.name,
          url: s.url.toString(),
          fileSize: s.size.totalBytes.toInt(),
        ));
      }

      // Video-only streams (higher quality options)
      for (final s in manifest.videoOnly) {
        videoStreams.add(VideoStream(
          quality: '${s.qualityLabel} (video only)',
          container: s.container.name,
          url: s.url.toString(),
          fileSize: s.size.totalBytes.toInt(),
        ));
      }

      // Build audio streams
      final audioStreams = <AudioStream>[];
      for (final s in manifest.audioOnly) {
        audioStreams.add(AudioStream(
          quality: s.audioCodec,
          container: s.container.name,
          bitrate: s.bitrate.kiloBitsPerSecond.toInt(),
          url: s.url.toString(),
          fileSize: s.size.totalBytes.toInt(),
        ));
      }

      // Sort by quality (highest first)
      videoStreams.sort((a, b) {
        final aQ = _extractQualityNumber(a.quality);
        final bQ = _extractQualityNumber(b.quality);
        return bQ.compareTo(aQ);
      });

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
      throw Exception('Video không tồn tại hoặc bị xóa.');
    } on VideoRequiresPurchaseException {
      throw Exception('Video yêu cầu mua trả phí, không thể tải.');
    } catch (e) {
      throw Exception('Không thể lấy thông tin video: ${e.toString()}');
    }
  }

  int _extractQualityNumber(String quality) {
    final match = RegExp(r'(\d+)').firstMatch(quality);
    return match != null ? int.parse(match.group(1)!) : 0;
  }

  /// Get downloads directory
  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${dir.path}/Downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      return downloadDir;
    } else {
      // Android
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('Cần cấp quyền truy cập bộ nhớ để tải file.');
      }
      final dir = Directory('/storage/emulated/0/Download/YTDownloader');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
  }

  /// Sanitize filename
  String _sanitizeFilename(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .substring(0, name.length > 100 ? 100 : name.length);
  }

  /// Download video
  Future<String> downloadVideo({
    required VideoInfo videoInfo,
    required VideoStream stream,
    required Function(double progress) onProgress,
  }) async {
    final dir = await _getDownloadDirectory();
    final safeName = _sanitizeFilename(videoInfo.title);
    final ext = stream.container ?? 'mp4';
    final quality = stream.quality.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final filePath = '${dir.path}/${safeName}_${quality}.$ext';

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
      await _dio.download(
        stream.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            onProgress(progress);
            task.progress = progress;
            _notifyHistoryUpdate();
          }
        },
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 30),
        ),
      );

      task.status = DownloadStatus.completed;
      task.filePath = filePath;
      task.progress = 1.0;
      _notifyHistoryUpdate();
      return filePath;
    } catch (e) {
      task.status = DownloadStatus.error;
      task.errorMessage = e.toString();
      _notifyHistoryUpdate();
      // Clean up partial file
      final file = File(filePath);
      if (await file.exists()) await file.delete();
      throw Exception('Lỗi tải video: ${e.toString()}');
    }
  }

  /// Download audio
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
      await _dio.download(
        stream.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            onProgress(progress);
            task.progress = progress;
            _notifyHistoryUpdate();
          }
        },
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 30),
        ),
      );

      task.status = DownloadStatus.completed;
      task.filePath = filePath;
      task.progress = 1.0;
      _notifyHistoryUpdate();
      return filePath;
    } catch (e) {
      task.status = DownloadStatus.error;
      task.errorMessage = e.toString();
      _notifyHistoryUpdate();
      final file = File(filePath);
      if (await file.exists()) await file.delete();
      throw Exception('Lỗi tải audio: ${e.toString()}');
    }
  }

  void _notifyHistoryUpdate() {
    _historyController.add(List.from(_downloadHistory));
  }

  void dispose() {
    _yt.close();
    _historyController.close();
  }
}
