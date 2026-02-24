import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import '../models/download_model.dart';
import '../services/download_service.dart';
import '../widgets/video_info_card.dart';
import '../widgets/stream_selector_sheet.dart';
import '../widgets/download_progress_card.dart';
import '../widgets/download_history_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _urlController = TextEditingController();
  final _service = DownloadService();
  late TabController _tabController;

  VideoInfo? _videoInfo;
  bool _isFetching = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';
  DownloadType? _currentDownloadType;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tabController.dispose();
    _service.dispose(); // ✅ FIX: tránh leak stream/youtube client
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _urlController.text = data!.text!;
      _urlController.selection = TextSelection.fromPosition(
        TextPosition(offset: _urlController.text.length),
      );
      setState(() {}); // để suffixIcon update
    }
  }

  Future<void> _fetchVideoInfo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showSnackBar('Vui lòng nhập URL YouTube', isError: true);
      return;
    }

    setState(() {
      _isFetching = true;
      _videoInfo = null;
      _statusMessage = 'Đang lấy thông tin video...';
    });

    try {
      final info = await _service.fetchVideoInfo(url);
      setState(() {
        _videoInfo = info;
        _isFetching = false;
        _statusMessage = '';
      });
    } catch (e) {
      setState(() {
        _isFetching = false;
        _statusMessage = '';
      });
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  Future<void> _showVideoStreamSelector() async {
    if (_videoInfo == null) return;
    final stream = await showModalBottomSheet<VideoStream>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StreamSelectorSheet(
        videoInfo: _videoInfo!,
        type: DownloadType.video,
      ),
    );
    if (stream != null) {
      _startVideoDownload(stream);
    }
  }

  Future<void> _showAudioStreamSelector() async {
    if (_videoInfo == null) return;
    final stream = await showModalBottomSheet<AudioStream>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StreamSelectorSheet(
        videoInfo: _videoInfo!,
        type: DownloadType.audio,
      ),
    );
    if (stream != null) {
      _startAudioDownload(stream);
    }
  }

  Future<void> _startVideoDownload(VideoStream stream) async {
    final sourceUrl = _urlController.text.trim();

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _currentDownloadType = DownloadType.video;
      _statusMessage = 'Đang tải video ${stream.quality}...';
    });

    try {
      final path = await _service.downloadVideo(
  videoInfo: _videoInfo!,
  stream: stream,
  
  onProgress: (p) => setState(() => _downloadProgress = p),
);

      setState(() {
        _isDownloading = false;
        _statusMessage = '';
      });

      _showDownloadSuccessDialog(path, DownloadType.video);
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusMessage = '';
      });
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  Future<void> _startAudioDownload(AudioStream stream) async {
    final sourceUrl = _urlController.text.trim();

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _currentDownloadType = DownloadType.audio;
      _statusMessage = 'Đang tải audio ${stream.bitrate ?? 0}kbps...';
    });

    try {
      final path = await _service.downloadAudio(
        videoInfo: _videoInfo!,
        stream: stream,
        sourceUrl: sourceUrl,
        onProgress: (p) => setState(() => _downloadProgress = p),
      );

      setState(() {
        _isDownloading = false;
        _statusMessage = '';
      });

      _showDownloadSuccessDialog(path, DownloadType.audio);
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusMessage = '';
      });
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  void _showDownloadSuccessDialog(String path, DownloadType type) {
    final label = type == DownloadType.audio ? 'Audio' : 'Video';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 28),
            const SizedBox(width: 8),
            Text('Tải $label thành công!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('File đã lưu tại:', style: TextStyle(color: Color(0xFF999999))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                path,
                style: const TextStyle(fontSize: 12, color: Color(0xFFCCCCCC)),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'iOS: vào Tệp > Trên iPhone của tôi > YT Downloader > Downloads\n'
              '(cần bật UIFileSharingEnabled trong Info.plist).',
              style: TextStyle(color: Color(0xFF777777), fontSize: 12, height: 1.3),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // ✅ Lưu vào Tệp (Share sheet -> Save to Files)
              await Share.shareXFiles([XFile(path)], text: 'YT Downloader');
            },
            child: const Text('Lưu vào Tệp'),
          ),
          TextButton(
            onPressed: () async {
              await OpenFile.open(path);
            },
            child: const Text('Mở file'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFFF0000),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'YT Downloader',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF0000),
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF666666),
          tabs: const [
            Tab(icon: Icon(Icons.download), text: 'Tải xuống'),
            Tab(icon: Icon(Icons.history), text: 'Lịch sử'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDownloadTab(),
          DownloadHistoryTab(service: _service),
        ],
      ),
    );
  }

  Widget _buildDownloadTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildUrlInputCard(),
          const SizedBox(height: 16),

          if (_isDownloading) ...[
            DownloadProgressCard(
              progress: _downloadProgress,
              statusMessage: _statusMessage,
              type: _currentDownloadType ?? DownloadType.video,
            ),
            const SizedBox(height: 16),
          ],

          if (_isFetching)
            const Center(
              child: Column(
                children: [
                  SizedBox(height: 32),
                  CircularProgressIndicator(color: Color(0xFFFF0000)),
                  SizedBox(height: 12),
                  Text('Đang phân tích URL...', style: TextStyle(color: Color(0xFF999999))),
                  SizedBox(height: 32),
                ],
              ),
            ),

          if (_videoInfo != null && !_isFetching) ...[
            VideoInfoCard(videoInfo: _videoInfo!),
            const SizedBox(height: 16),
            _buildDownloadButtons(),
          ],

          if (_videoInfo == null && !_isFetching && !_isDownloading) ...[
            const SizedBox(height: 32),
            _buildEmptyState(),
          ],
        ],
      ),
    );
  }

  Widget _buildUrlInputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập URL YouTube',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'https://youtube.com/watch?v=...',
                      prefixIcon: const Icon(Icons.link, color: Color(0xFF666666)),
                      suffixIcon: _urlController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Color(0xFF666666)),
                              onPressed: () {
                                _urlController.clear();
                                setState(() => _videoInfo = null);
                              },
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _fetchVideoInfo(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste),
                  tooltip: 'Dán từ clipboard',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isFetching || _isDownloading ? null : _fetchVideoInfo,
                icon: const Icon(Icons.search),
                label: const Text('Phân tích URL', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadButtons() {
    return Row(
      children: [
        Expanded(
          child: _DownloadButton(
            icon: Icons.music_note,
            label: 'Tải Audio',
            sublabel: 'WebM (gốc)',
            color: const Color(0xFF1DB954),
            onPressed: _isDownloading ? null : _showAudioStreamSelector,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DownloadButton(
            icon: Icons.videocam,
            label: 'Tải Video',
            sublabel: 'MP4 / WebM',
            color: const Color(0xFFFF0000),
            onPressed: _isDownloading ? null : _showVideoStreamSelector,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(40),
          ),
          child: const Icon(Icons.youtube_searched_for, size: 40, color: Color(0xFFFF0000)),
        ),
        const SizedBox(height: 16),
        const Text(
          'Dán link YouTube\nvà nhấn Phân tích URL',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF666666), fontSize: 16, height: 1.6),
        ),
        const SizedBox(height: 8),
        const Text(
          'Hỗ trợ: youtube.com, youtu.be',
          style: TextStyle(color: Color(0xFF444444), fontSize: 13),
        ),
      ],
    );
  }
}

class _DownloadButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback? onPressed;

  const _DownloadButton({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.8), color.withOpacity(0.5)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              children: [
                Icon(icon, color: Colors.white, size: 32),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sublabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}