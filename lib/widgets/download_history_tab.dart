import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import '../models/download_model.dart';
import '../services/download_service.dart';

class DownloadHistoryTab extends StatelessWidget {
  final DownloadService service;

  const DownloadHistoryTab({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DownloadTask>>(
      stream: service.historyStream,
      initialData: service.downloadHistory,
      builder: (context, snapshot) {
        final tasks = snapshot.data ?? [];

        if (tasks.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: Color(0xFF333333)),
                SizedBox(height: 16),
                Text(
                  'Chưa có lịch sử tải xuống',
                  style: TextStyle(color: Color(0xFF666666), fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: tasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, index) {
            return _DownloadTaskCard(task: tasks[index]);
          },
        );
      },
    );
  }
}

class _DownloadTaskCard extends StatelessWidget {
  final DownloadTask task;

  const _DownloadTaskCard({required this.task});

  Color get _statusColor {
    switch (task.status) {
      case DownloadStatus.completed:
        return const Color(0xFF4CAF50);
      case DownloadStatus.error:
        return Colors.red;
      case DownloadStatus.downloading:
        return const Color(0xFF2196F3);
      case DownloadStatus.fetching:
        return const Color(0xFFFFC107);
      default:
        return const Color(0xFF666666);
    }
  }

  String get _statusText {
    switch (task.status) {
      case DownloadStatus.completed:
        return 'Hoàn tất';
      case DownloadStatus.error:
        return 'Lỗi';
      case DownloadStatus.downloading:
        return '${(task.progress * 100).toInt()}%';
      case DownloadStatus.fetching:
        return 'Đang phân tích';
      default:
        return 'Chờ';
    }
  }

  Future<File?> _ensureFile(BuildContext context) async {
    if (task.filePath == null) return null;
    final file = File(task.filePath!);
    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File không còn tồn tại')),
        );
      }
      return null;
    }
    return file;
  }

  Future<void> _openFile(BuildContext context) async {
    final file = await _ensureFile(context);
    if (file == null) return;
    await OpenFile.open(file.path);
  }

  Future<void> _shareToFiles(BuildContext context) async {
    final file = await _ensureFile(context);
    if (file == null) return;

    // iOS: user chọn "Save to Files" trong share sheet
    await Share.shareXFiles([XFile(file.path)], text: task.title);
  }

  @override
  Widget build(BuildContext context) {
    final isAudio = task.type == DownloadType.audio;
    final color = isAudio ? const Color(0xFF1DB954) : const Color(0xFFFF0000);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isAudio ? Icons.music_note : Icons.videocam,
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${isAudio ? "Audio" : "Video"} • ${task.quality}',
                        style: const TextStyle(color: Color(0xFF666666), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _statusText,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            if (task.status == DownloadStatus.downloading) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: task.progress,
                  backgroundColor: const Color(0xFF333333),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 4,
                ),
              ),
            ],

            if (task.status == DownloadStatus.error && task.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                task.errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 11),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            if (task.status == DownloadStatus.completed) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.play_arrow,
                      label: 'Mở file',
                      onTap: () => _openFile(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.save_alt,
                      label: 'Lưu vào Tệp',
                      onTap: () => _shareToFiles(context),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: const Color(0xFFCCCCCC)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}