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
  DownloadService._internal() {
    _setupDio();
  }

  final YoutubeExplode _yt = YoutubeExplode();
  late final Dio _dio;
  final List<DownloadTask> _downloadHistory = [];
  final StreamController<List<DownloadTask>> _historyController =
      StreamController<List<DownloadTask>>.broadcast();

  List<DownloadTask> get downloadHistory => List.unmodifiable(_downloadHistory);
  Stream<List<DownloadTask>> get historyStream => _historyController.stream;

  // ─── Headers YouTube CDN chấp nhận ───────────────────────────────────────
  static const Map<String, String> _ytHeaders = {
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
    'Referer': 'https://www.youtube.com/',
    'Origin': 'https://www.youtube.com',
    'Accept': '*/*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept-Encoding': 'identity', // không nén để progress chính xác
  };

  void _setupDio() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
      followRedirects: true,
      maxRedirects: 5,
      // Không throw với 4xx/5xx → tự xử lý bên dưới
      validateStatus: (status) => status != null && status < 500,
    ));
  }

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
          url: s.url.toString(),
          fileSize: s.size.totalBytes.toInt(),
          itag: s.tag,
          isMuxed: true,
        ));
      }

      for (final s in manifest.videoOnly) {
        videoStreams.add(VideoStream(
          quality: '${s.qualityLabel} (video only)',
          container: s.container.name,
          url: s.url.toString(),
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
          url: s.url.toString(),
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
      final msg = e.toString();
      if (msg.contains('403') || msg.contains('forbidden')) {
        throw Exception('YouTube từ chối truy cập. Thử lại sau vài giây.');
      }
      throw Exception('Không thể lấy thông tin video: $msg');
    }
  }

  // ─── FIX CHÍNH: Re-fetch URL mới ngay trước khi download ─────────────────
  // Không dùng URL cũ từ fetchVideoInfo vì URL stream có expire token
  // → gọi getManifest() lại để lấy URL còn sống
  Future<String> _getFreshVideoUrl(String videoId, int itag) async {
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);

    for (final s in manifest.muxed) {
      if (s.tag == itag) return s.url.toString();
    }
    for (final s in manifest.videoOnly) {
      if (s.tag == itag) return s.url.toString();
    }

    // Fallback: chất lượng muxed cao nhất
    if (manifest.muxed.isNotEmpty) {
      return manifest.muxed.last.url.toString();
    }
    throw Exception('Không tìm thấy stream video. Thử chọn chất lượng khác.');
  }

  Future<String> _getFreshAudioUrl(String videoId, int itag) async {
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);

    for (final s in manifest.audioOnly) {
      if (s.tag == itag) return s.url.toString();
    }

    // Fallback: bitrate cao nhất
    if (manifest.audioOnly.isNotEmpty) {
      final sorted = manifest.audioOnly.toList()
        ..sort((a, b) =>
            b.bitrate.kiloBitsPerSecond.compareTo(a.bitrate.kiloBitsPerSecond));
      return sorted.first.url.toString();
    }
    throw Exception('Không tìm thấy stream audio. Thử lại.');
  }

  // ─── Download helper dùng chung ───────────────────────────────────────────
  Future<void> _downloadWithDio({
    required String url,
    required String savePath,
    required Function(double) onProgress,
    required DownloadTask task,
  }) async {
    try {
      final response = await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final p = received / total;
            onProgress(p);
            task.progress = p;
            _notifyHistoryUpdate();
          }
        },
        options: Options(
          headers: _ytHeaders,
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 30),
        ),
        deleteOnError: true,
      );

      // Kiểm tra status thủ công vì validateStatus cho qua 4xx
      final status = response.statusCode ?? 0;
      if (status == 403) {
        throw Exception('URL stream hết hạn (403). Vui lòng thử lại.');
      }
      if (status >= 400 && status < 500) {
        throw Exception('Lỗi HTTP $status. Thử chọn chất lượng khác.');
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout) {
        throw Exception('Timeout kết nối. Kiểm tra mạng và thử lại.');
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        throw Exception('Tải quá lâu do mạng yếu. Thử lại.');
      }
      throw Exception('Lỗi tải: ${e.message}');
    }
  }

  // ─── Download Video ───────────────────────────────────────────────────────
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
      // FIX: Re-fetch URL mới ngay lúc này, không dùng stream.url cũ
      final freshUrl = await _getFreshVideoUrl(videoInfo.id, stream.itag);

      await _downloadWithDio(
        url: freshUrl,
        savePath: filePath,
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
      rethrow;
    }
  }

  // ─── Download Audio ───────────────────────────────────────────────────────
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
      // FIX: Re-fetch URL mới ngay lúc này
      final freshUrl = await _getFreshAudioUrl(videoInfo.id, stream.itag);

      await _downloadWithDio(
        url: freshUrl,
        savePath: filePath,
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
      rethrow;
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  int _extractQualityNumber(String quality) {
    final match = RegExp(r'(\d+)').firstMatch(quality);
    return match != null ? int.parse(match.group(1)!) : 0;
  }

  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${dir.path}/Downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      return downloadDir;
    } else {
      // Android: request permission nếu cần
      final status = await Permission.storage.request();
      if (!status.isGranted && !status.isLimited) {
        throw Exception('Cần cấp quyền truy cập bộ nhớ để tải file.');
      }
      final dir = Directory('/storage/emulated/0/Download/YTDownloader');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
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
