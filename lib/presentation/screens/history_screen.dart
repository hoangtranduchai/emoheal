import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/theme.dart';
import '../../data/supabase_service.dart';
import '../../router.dart';
import '../widgets/chat_history_item.dart';

/// Màn hình Lịch sử & Hồi ký đã lưu — Zero-Barrier UI cho Cựu chiến binh
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  late TabController _tabController;
  late Future<List<Map<String, dynamic>>> _chatHistoryFuture;
  late Future<List<Map<String, dynamic>>> _voiceMemosFuture;

  String? _currentlyPlayingUrl;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _currentlyPlayingUrl = null;
          _isPlaying = false;
        });
      }
    });
  }

  void _loadData() {
    setState(() {
      _chatHistoryFuture = _supabaseService.getChatHistory();
      _voiceMemosFuture = _supabaseService.getVoiceMemos();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString).toLocal();
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return dateString;
    }
  }

  String _formatDuration(dynamic seconds) {
    if (seconds == null) return '00:00';
    final sec = (seconds is int) ? seconds : int.tryParse(seconds.toString()) ?? 0;
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggleAudio(String audioUrl) async {
    try {
      if (_currentlyPlayingUrl == audioUrl && _isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.stop();
        _currentlyPlayingUrl = audioUrl;
        await _audioPlayer.play(UrlSource(audioUrl));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể phát âm thanh này.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppColors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryGreenDark, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Lịch sử & Hồi ký',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryGreenDark,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.lightGrey),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.primaryGreen,
                  borderRadius: BorderRadius.circular(14),
                ),
                labelColor: AppColors.white,
                unselectedLabelColor: AppColors.textPrimary,
                labelStyle: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Hội thoại AI'),
                  Tab(text: 'Hồi ký đã lưu'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            // ── Tab 1: Hội thoại AI ──
            _buildChatHistoryTab(),

            // ── Tab 2: Hồi ký Giọng nói đã lưu ──
            _buildVoiceMemosTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildChatHistoryTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _chatHistoryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryGreen),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Có lỗi xảy ra khi tải dữ liệu.',
              style: const TextStyle(fontFamily: 'Roboto', fontSize: 16, color: AppColors.sosOrange),
            ),
          );
        }

        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return const Center(
            child: Text(
              'Bác chưa có cuộc trò chuyện nào được lưu.',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _loadData(),
          color: AppColors.primaryGreen,
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final title = item['title']?.toString() ?? 'Trò chuyện cùng cháu';
              final date = _formatDate(item['last_message_at']?.toString() ?? item['created_at']?.toString());

              return ChatHistoryItem(
                title: title,
                subtitle: 'Chạm để xem lại cuộc trò chuyện',
                date: date,
                onTap: () {
                  final convId = item['id']?.toString();
                  Navigator.of(context).pushNamed(
                    AppRoutes.chat,
                    arguments: convId,
                  ).then((_) => _loadData());
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildVoiceMemosTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _voiceMemosFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryGreen),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Có lỗi xảy ra khi tải hồi ký.',
              style: const TextStyle(fontFamily: 'Roboto', fontSize: 16, color: AppColors.sosOrange),
            ),
          );
        }

        final memos = snapshot.data ?? [];
        if (memos.isEmpty) {
          return const Center(
            child: Text(
              'Bác chưa có bản ghi âm hồi ký nào.',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _loadData(),
          color: AppColors.primaryGreen,
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: memos.length,
            itemBuilder: (context, index) {
              final memo = memos[index];
              final title = memo['title']?.toString() ?? 'Hồi ký không tên';
              final topic = memo['topic']?.toString() ?? 'Kỷ niệm';
              final duration = _formatDuration(memo['duration_seconds']);
              final date = _formatDate(memo['created_at']?.toString());
              final audioUrl = memo['audio_url']?.toString() ?? '';
              final isCurrentPlaying = _currentlyPlayingUrl == audioUrl && _isPlaying;

              return Card(
                margin: const EdgeInsets.only(bottom: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.lightGrey),
                ),
                color: AppColors.white,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Nút Play / Pause tròn to dễ bấm
                      GestureDetector(
                        onTap: audioUrl.isNotEmpty ? () => _toggleAudio(audioUrl) : null,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: isCurrentPlaying ? AppColors.sosOrange : AppColors.primaryGreen,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isCurrentPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: AppColors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryGreen.withAlpha(20),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    topic,
                                    style: const TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primaryGreenDark,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '⏱ $duration',
                                  style: const TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 14,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        date,
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
