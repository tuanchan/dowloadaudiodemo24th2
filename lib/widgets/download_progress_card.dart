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

    // ✅ show 1 decimal so <1% still visible
    final percentText = (progress * 100).clamp(0, 100).toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
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
                      const Text(
                        'Vui lòng đợi, không tắt ứng dụng...',
                        style: TextStyle(color: Color(0xFF666666), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$percentText%',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: const Color(0xFF333333),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                progress < 1.0 ? 'Đang tải... $percentText%' : 'Hoàn tất!',
                style: TextStyle(
                  color: color.withOpacity(0.8),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}