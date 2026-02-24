import 'package:flutter/material.dart';
import '../models/download_model.dart';

class DownloadProgressCard extends StatelessWidget {
  final double progress;
  final String statusMessage;
  final DownloadType type;

  const DownloadProgressCard({
    super.key,
    required this.progress,
    required this.statusMessage,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final isAudio = type == DownloadType.audio;
    final color = isAudio ? const Color(0xFF1DB954) : const Color(0xFFFF0000);
    final icon = isAudio ? Icons.music_note : Icons.videocam;
    final percent = (progress * 100).toInt();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                // Animated icon container
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusMessage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Vui lòng đợi, không tắt ứng dụng...',
                        style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$percent%',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: const Color(0xFF333333),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
              ),
            ),

            if (progress > 0) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  progress < 1.0 ? 'Đang tải... $percent%' : 'Hoàn tất!',
                  style: TextStyle(
                    color: color.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
