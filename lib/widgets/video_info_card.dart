import 'package:flutter/material.dart';
import '../models/download_model.dart';

class VideoInfoCard extends StatelessWidget {
  final VideoInfo videoInfo;

  const VideoInfoCard({super.key, required this.videoInfo});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    videoInfo.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF333333),
                      child: const Icon(Icons.movie, size: 64, color: Color(0xFF666666)),
                    ),
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: const Color(0xFF333333),
                        child: const Center(
                          child: CircularProgressIndicator(color: Color(0xFFFF0000)),
                        ),
                      );
                    },
                  ),
                  // Duration badge
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        videoInfo.durationFormatted,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  videoInfo.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.person, size: 14, color: Color(0xFF999999)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        videoInfo.author,
                        style: const TextStyle(color: Color(0xFF999999), fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Stream count badges
                    _StreamBadge(
                      icon: Icons.videocam,
                      label: '${videoInfo.videoStreams.length} video',
                      color: const Color(0xFFFF0000),
                    ),
                    const SizedBox(width: 6),
                    _StreamBadge(
                      icon: Icons.music_note,
                      label: '${videoInfo.audioStreams.length} audio',
                      color: const Color(0xFF1DB954),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StreamBadge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
