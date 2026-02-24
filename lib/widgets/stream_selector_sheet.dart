import 'package:flutter/material.dart';
import '../models/download_model.dart';

class StreamSelectorSheet extends StatelessWidget {
  final VideoInfo videoInfo;
  final DownloadType type;

  const StreamSelectorSheet({
    super.key,
    required this.videoInfo,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final isAudio = type == DownloadType.audio;
    final color = isAudio ? const Color(0xFF1DB954) : const Color(0xFFFF0000);
    final title = isAudio ? 'Chọn chất lượng Audio' : 'Chọn chất lượng Video';
    final icon = isAudio ? Icons.music_note : Icons.videocam;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF444444),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            videoInfo.title,
                            style: const TextStyle(color: Color(0xFF999999), fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF999999)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(color: Color(0xFF333333), height: 1),

              // Stream list
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: isAudio
                      ? videoInfo.audioStreams.length
                      : videoInfo.videoStreams.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Color(0xFF2A2A2A), height: 1, indent: 20, endIndent: 20),
                  itemBuilder: (ctx, index) {
                    if (isAudio) {
                      final stream = videoInfo.audioStreams[index];
                      return _AudioStreamTile(
                        stream: stream,
                        isRecommended: index == 0,
                        color: color,
                        onTap: () => Navigator.pop(ctx, stream),
                      );
                    } else {
                      final stream = videoInfo.videoStreams[index];
                      return _VideoStreamTile(
                        stream: stream,
                        isRecommended: index == 0,
                        color: color,
                        onTap: () => Navigator.pop(ctx, stream),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VideoStreamTile extends StatelessWidget {
  final VideoStream stream;
  final bool isRecommended;
  final Color color;
  final VoidCallback onTap;

  const _VideoStreamTile({
    required this.stream,
    required this.isRecommended,
    required this.color,
    required this.onTap,
  });

  IconData _qualityIcon(String quality) {
    final q = int.tryParse(RegExp(r'(\d+)').firstMatch(quality)?.group(1) ?? '0') ?? 0;
    if (q >= 1080) return Icons.hd;
    if (q >= 720) return Icons.high_quality;
    return Icons.sd;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(_qualityIcon(stream.quality), color: color, size: 22),
      ),
      title: Row(
        children: [
          Text(
            stream.quality,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          if (isRecommended) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Đề xuất',
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${stream.container?.toUpperCase() ?? 'MP4'}'
        '${stream.fileSize != null ? " • ${_formatSize(stream.fileSize!)}" : ""}',
        style: const TextStyle(color: Color(0xFF999999), fontSize: 12),
      ),
      trailing: Icon(Icons.download, color: color, size: 20),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _AudioStreamTile extends StatelessWidget {
  final AudioStream stream;
  final bool isRecommended;
  final Color color;
  final VoidCallback onTap;

  const _AudioStreamTile({
    required this.stream,
    required this.isRecommended,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.music_note, color: color, size: 22),
      ),
      title: Row(
        children: [
          Text(
            stream.bitrate != null ? '${stream.bitrate}kbps' : stream.quality,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          if (isRecommended) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Tốt nhất',
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${stream.container?.toUpperCase() ?? 'WebM'}'
        '${stream.fileSize != null ? " • ${_formatSize(stream.fileSize!)}" : ""}',
        style: const TextStyle(color: Color(0xFF999999), fontSize: 12),
      ),
      trailing: Icon(Icons.download, color: color, size: 20),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
