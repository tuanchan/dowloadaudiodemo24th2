enum DownloadType { audio, video }
enum DownloadStatus { idle, fetching, downloading, completed, error }

class VideoInfo {
  final String id;
  final String title;
  final String author;
  final String thumbnailUrl;
  final Duration duration;
  final List<VideoStream> videoStreams;
  final List<AudioStream> audioStreams;

  const VideoInfo({
    required this.id,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.duration,
    required this.videoStreams,
    required this.audioStreams,
  });

  String get durationFormatted {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class VideoStream {
  final String quality;
  final String? container;
  final int? bitrate;
  final String url;
  final int? fileSize;

  const VideoStream({
    required this.quality,
    this.container,
    this.bitrate,
    required this.url,
    this.fileSize,
  });

  String get label {
    final size = fileSize != null ? ' (~${_formatSize(fileSize!)})' : '';
    return '$quality${container != null ? ' [$container]' : ''}$size';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class AudioStream {
  final String quality;
  final String? container;
  final int? bitrate;
  final String url;
  final int? fileSize;

  const AudioStream({
    required this.quality,
    this.container,
    this.bitrate,
    required this.url,
    this.fileSize,
  });

  String get label {
    final bitrateStr = bitrate != null ? ' ${bitrate}kbps' : '';
    final size = fileSize != null ? ' (~${_formatSize(fileSize!)})' : '';
    return '$quality$bitrateStr${container != null ? ' [$container]' : ''}$size';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class DownloadTask {
  final String id;
  final String title;
  final String url;
  final DownloadType type;
  final String quality;
  DownloadStatus status;
  double progress;
  String? filePath;
  String? errorMessage;
  DateTime startTime;

  DownloadTask({
    required this.id,
    required this.title,
    required this.url,
    required this.type,
    required this.quality,
    this.status = DownloadStatus.downloading,
    this.progress = 0.0,
    this.filePath,
    this.errorMessage,
  }) : startTime = DateTime.now();
}
