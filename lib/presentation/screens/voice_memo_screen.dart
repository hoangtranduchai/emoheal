import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/responsive_utils.dart';
import '../../core/theme.dart';
import '../../data/supabase_service.dart';
import '../../router.dart';

/// Màn hình 'Hồi ký Giọng nói' — Voice Memoir Screen
///
/// Tuân thủ nghiêm ngặt tiêu chuẩn Zero-Barrier dành cho cựu chiến binh và người cao tuổi:
/// - Kích thước chữ tối thiểu 16sp, độ tương phản cao, phông chữ Roboto.
/// - Kích thước vùng chạm tối thiểu 48dp x 48dp.
/// - Tích hợp đầy đủ các tài nguyên thiết kế từ Figma:
///   + Trợ lý: `assets/icons/support.gif`
///   + Gợi ý chủ đề: `bird-thema-0.svg`, `bird-thema-1.svg`, `fun-thema-0.svg`, `fun-thema-1.svg`, `letter-thema-0.svg`, `letter-thema-1.svg`
///   + Thu âm: `soundwave-0.svg`, `soundwave-1.svg`, `playback-start.svg`, `pause.svg`, `trash-bin.svg`, `send.svg`
///   + Màn hình & Điều hướng: `back.svg`, `favourite.svg`, `mic-button.svg`
class VoiceMemoScreen extends StatefulWidget {
  const VoiceMemoScreen({super.key});

  @override
  State<VoiceMemoScreen> createState() => _VoiceMemoScreenState();
}

class _VoiceMemoScreenState extends State<VoiceMemoScreen>
    with SingleTickerProviderStateMixin {
  // ── Services & Controllers ──
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final SupabaseService _supabaseService = SupabaseService();

  // ── Animation Controllers ──
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // ── Recording & Playback States ──
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isPlaying = false;
  bool _isUploading = false;

  Timer? _timer;
  int _recordDuration = 0;
  String? _audioPath;

  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;

  // ── Topic Suggestions (Chủ đề gợi ý) ──
  int _selectedTopicIndex = 0;

  final List<_TopicItem> _topics = const [
    _TopicItem(
      title: 'Chiến trường & Đồng đội',
      prompt: 'Kỷ niệm sâu sắc nhất cùng đồng đội thời hoa lửa?',
      subPrompt:
          'Kể về trận đánh đáng nhớ, những người bạn cùng chiến hào, hoặc tình đồng chí thiêng liêng...',
      activeAsset: 'assets/icons/bird-thema-1.svg',
      inactiveAsset: 'assets/icons/bird-thema-0.svg',
    ),
    _TopicItem(
      title: 'Niềm vui & Con cháu',
      prompt: 'Điều gì khiến Bác cảm thấy nhẹ lòng và vui vẻ nhất?',
      subPrompt:
          'Bữa cơm gia đình ấm cúng, niềm vui bình dị bên con cháu, hay khoảnh khắc thanh thản mỗi ngày...',
      activeAsset: 'assets/icons/fun-thema-1.svg',
      inactiveAsset: 'assets/icons/fun-thema-0.svg',
    ),
    _TopicItem(
      title: 'Lá thư gửi tương lai',
      prompt: 'Lời nhắn nhủ, dặn dò của Bác gửi thế hệ mai sau?',
      subPrompt:
          'Những kinh nghiệm sống quý báu, giá trị hòa bình và kỳ vọng của Bác cho thế hệ trẻ...',
      activeAsset: 'assets/icons/letter-thema-1.svg',
      inactiveAsset: 'assets/icons/letter-thema-0.svg',
    ),
  ];

  @override
  void initState() {
    super.initState();

    // Pulse animation cho hiệu ứng sóng âm khi đang thu âm
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Lắng nghe sự kiện từ AudioPlayer
    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _playbackPosition = pos);
    });

    _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _playbackDuration = dur);
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _playbackPosition = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── Đếm thời gian ghi âm ──
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (mounted) {
        setState(() => _recordDuration++);
      }
    });
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  // ── 1. Bắt đầu Ghi âm (Start Recording) ──
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final filePath =
            '${dir.path}/voice_memo_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: filePath,
        );

        _pulseController.repeat(reverse: true);
        setState(() {
          _isRecording = true;
          _isPaused = false;
          _recordDuration = 0;
          _audioPath = null;
          _isPlaying = false;
        });
        _startTimer();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Vui lòng cấp quyền truy cập micro để ghi âm.',
                style: TextStyle(fontFamily: 'Roboto', fontSize: 16),
              ),
              backgroundColor: AppColors.sosOrange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Lỗi bắt đầu ghi âm: $e');
    }
  }

  // ── 2. Tạm dừng / Tiếp tục Ghi âm (Pause / Resume Recording) ──
  Future<void> _togglePauseRecording() async {
    if (!_isRecording) return;
    try {
      if (_isPaused) {
        await _audioRecorder.resume();
        _pulseController.repeat(reverse: true);
        _startTimer();
        setState(() => _isPaused = false);
      } else {
        await _audioRecorder.pause();
        _pulseController.stop();
        _timer?.cancel();
        setState(() => _isPaused = true);
      }
    } catch (e) {
      debugPrint('Lỗi tạm dừng ghi âm: $e');
    }
  }

  // ── 3. Kết thúc Ghi âm (Stop / Complete Recording) ──
  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    try {
      final path = await _audioRecorder.stop();
      _pulseController.stop();
      _pulseController.reset();
      _timer?.cancel();

      setState(() {
        _isRecording = false;
        _isPaused = false;
        _audioPath = path;
      });

      // Tải trước nguồn âm thanh để sẵn sàng phát lại
      if (path != null) {
        await _audioPlayer.setSource(DeviceFileSource(path));
      }
    } catch (e) {
      debugPrint('Lỗi dừng ghi âm: $e');
    }
  }

  // ── 4. Nghe lại bản ghi (Playback Preview) ──
  Future<void> _togglePlayback() async {
    if (_audioPath == null) return;
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        setState(() => _isPlaying = false);
      } else {
        await _audioPlayer.play(DeviceFileSource(_audioPath!));
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('Lỗi phát âm thanh: $e');
    }
  }

  // ── 5. Xóa bản ghi có hộp thoại xác nhận (Delete Recording) ──
  Future<void> _confirmDelete() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.backgroundLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Xác nhận xóa bản ghi',
            style: GoogleFonts.roboto(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: Text(
            'Bác có chắc chắn muốn xóa đoạn ghi âm này không? Hành động này sẽ không thể khôi phục.',
            style: GoogleFonts.roboto(
              fontSize: 16,
              height: 1.45,
              color: AppColors.textPrimary,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(100, 48),
                side: const BorderSide(color: AppColors.mediumGrey),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Không',
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(110, 48),
                backgroundColor: AppColors.sosOrange,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Xác nhận xóa',
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      if (_isRecording) {
        await _audioRecorder.stop();
      }
      if (_isPlaying) {
        await _audioPlayer.stop();
      }
      _pulseController.stop();
      _pulseController.reset();
      _timer?.cancel();

      if (_audioPath != null) {
        try {
          final file = File(_audioPath!);
          if (await file.exists()) await file.delete();
        } catch (e) {
          debugPrint('Lỗi xóa tệp: $e');
        }
      }

      setState(() {
        _isRecording = false;
        _isPaused = false;
        _isPlaying = false;
        _recordDuration = 0;
        _playbackPosition = Duration.zero;
        _playbackDuration = Duration.zero;
        _audioPath = null;
      });
    }
  }

  // ── 6. Lưu và Gửi hồi ký lên Supabase (Save & Upload) ──
  Future<void> _uploadVoiceMemo() async {
    if (_audioPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chưa có bản ghi âm nào để lưu trữ.',
            style: TextStyle(fontFamily: 'Roboto', fontSize: 16),
          ),
          backgroundColor: AppColors.sosOrange,
        ),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      final topicTitle = _topics[_selectedTopicIndex].title;
      final fileName = 'memo_${DateTime.now().millisecondsSinceEpoch}.m4a';

      final fileUrl = await _supabaseService.uploadVoiceMemo(_audioPath!, fileName);
      await _supabaseService.saveVoiceMemoMetadata(
        topicTitle,
        fileUrl,
        _recordDuration > 0 ? _recordDuration : _playbackDuration.inSeconds,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppColors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Đã lưu giữ hồi ký "$topicTitle" thành công!',
                    style: GoogleFonts.roboto(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        setState(() {
          _audioPath = null;
          _recordDuration = 0;
          _playbackPosition = Duration.zero;
          _playbackDuration = Duration.zero;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.sosOrange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Text(
              'Lưu hồi ký thất bại: $e',
              style: GoogleFonts.roboto(fontSize: 16, color: AppColors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveUtils.isTablet(context);
    final horizontalPadding = ResponsiveUtils.getCardPadding(context);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isTablet ? 720 : double.infinity,
            ),
            child: Column(
              children: [
                // ── 1. Top Navigation Bar (Back, Title, History/Favourite) ──
                _VoiceMemoTopBar(
                  horizontalPadding: horizontalPadding,
                  onBack: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
                    }
                  },
                  onHistoryTap: () {
                    Navigator.of(context).pushNamed(AppRoutes.history);
                  },
                ),

                // ── Scrollable Body (Chống tràn giao diện trên mọi thiết bị) ──
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),

                        // ── 2. AI Assistant Companion Banner (Trợ lý) ──
                        const _AssistantCompanionCard(),

                        const SizedBox(height: 20),

                        // ── 3. Topic Suggestions (Gợi ý chủ đề đổi màu icon) ──
                        _TopicSuggestionsSection(
                          topics: _topics,
                          selectedIndex: _selectedTopicIndex,
                          onTopicSelected: (index) {
                            setState(() => _selectedTopicIndex = index);
                          },
                        ),

                        const SizedBox(height: 20),

                        // ── 4. Active Prompt Highlight (Câu hỏi chi tiết) ──
                        _ActivePromptBanner(
                          topic: _topics[_selectedTopicIndex],
                        ),

                        const SizedBox(height: 20),

                        // ── 5. Main Recording Status & Sóng âm (Thu âm) ──
                        _RecordingStatusCard(
                          isRecording: _isRecording,
                          isPaused: _isPaused,
                          isPlaying: _isPlaying,
                          hasRecorded: _audioPath != null,
                          recordDurationFormatted: _formatDuration(_recordDuration),
                          pulseAnimation: _pulseAnimation,
                          playbackPosition: _playbackPosition,
                          playbackDuration: _playbackDuration,
                          onSeek: (value) {
                            final newPosition = Duration(seconds: value.toInt());
                            _audioPlayer.seek(newPosition);
                          },
                        ),

                        const SizedBox(height: 20),

                        // ── 6. Recording & Action Controls (Cụm nút điều khiển) ──
                        _RecordingControls(
                          isRecording: _isRecording,
                          isPaused: _isPaused,
                          isPlaying: _isPlaying,
                          isUploading: _isUploading,
                          hasRecorded: _audioPath != null,
                          onStartRecord: _startRecording,
                          onTogglePause: _togglePauseRecording,
                          onStopRecord: _stopRecording,
                          onTogglePlayback: _togglePlayback,
                          onDelete: _confirmDelete,
                          onSend: _uploadVoiceMemo,
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ════════════════════════════════════════════════════════════════════

/// Top App Bar chứa nút Back (`back.svg`), Tiêu đề và nút Lịch sử (`favourite.svg`).
class _VoiceMemoTopBar extends StatelessWidget {
  const _VoiceMemoTopBar({
    required this.horizontalPadding,
    required this.onBack,
    required this.onHistoryTap,
  });

  final double horizontalPadding;
  final VoidCallback onBack;
  final VoidCallback onHistoryTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Nút Quay lại (Vùng chạm >= 48dp x 48dp)
          Material(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onBack,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE4E0DD), width: 1.2),
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  'assets/icons/back.svg',
                  width: 24,
                  height: 24,
                ),
              ),
            ),
          ),

          // Tiêu đề màn hình
          Expanded(
            child: Column(
              children: [
                Text(
                  'Hồi ký Giọng nói',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.roboto(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Lưu giữ ký ức cuộc đời',
                  style: GoogleFonts.roboto(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Nút Lịch sử hồi ký (sử dụng favourite.svg)
          Material(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onHistoryTap,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE4E0DD), width: 1.2),
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  'assets/icons/favourite.svg',
                  width: 26,
                  height: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Phần Trợ lý AI đồng hành sử dụng `support.gif`.
class _AssistantCompanionCard extends StatelessWidget {
  const _AssistantCompanionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.assistantBubble.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hoạt họa Trợ lý AI
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/icons/support.gif',
              width: 52,
              height: 52,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 14),
          // Lời chào khích lệ từ trợ lý
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Trợ lý Điểm Tựa',
                      style: GoogleFonts.roboto(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryGreenDark,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Đang lắng nghe',
                        style: GoogleFonts.roboto(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Cháu chào Bác! Hôm nay Bác muốn kể lại kỷ niệm nào ạ? Bác hãy chọn chủ đề hoặc nhấn nút bên dưới để bắt đầu tâm sự nhé.',
                  style: GoogleFonts.roboto(
                    fontSize: 14,
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gợi ý chủ đề với chuyển đổi icon active/inactive giữa `bird-thema-0/1`, `fun-thema-0/1`, `letter-thema-0/1`.
class _TopicSuggestionsSection extends StatelessWidget {
  const _TopicSuggestionsSection({
    required this.topics,
    required this.selectedIndex,
    required this.onTopicSelected,
  });

  final List<_TopicItem> topics;
  final int selectedIndex;
  final ValueChanged<int> onTopicSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Gợi ý chủ đề',
              style: GoogleFonts.roboto(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'Chọn 1 chủ đề',
              style: GoogleFonts.roboto(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 125,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: topics.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final topic = topics[index];
              final isSelected = selectedIndex == index;

              return _TopicCard(
                topic: topic,
                isSelected: isSelected,
                onTap: () => onTopicSelected(index),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.isSelected,
    required this.onTap,
  });

  final _TopicItem topic;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Đổi icon tương ứng: active nếu được chọn, inactive nếu chưa chọn
    final assetPath = isSelected ? topic.activeAsset : topic.inactiveAsset;

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 175,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.assistantBubble.withValues(alpha: 0.3)
                : AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppColors.primaryGreen : const Color(0xFFE4E0DD),
              width: isSelected ? 2.2 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? AppColors.primaryGreen.withValues(alpha: 0.15)
                    : AppColors.black0F,
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryGreen.withValues(alpha: 0.15)
                          : const Color(0xFFF3F3F3),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: SvgPicture.asset(
                      assetPath,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.primaryGreen,
                      size: 22,
                    ),
                ],
              ),
              Text(
                topic.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.roboto(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? AppColors.primaryGreenDark : AppColors.textPrimary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hiển thị câu hỏi gợi ý chi tiết của chủ đề đang được chọn.
class _ActivePromptBanner extends StatelessWidget {
  const _ActivePromptBanner({required this.topic});

  final _TopicItem topic;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E0DD), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: AppColors.black0F,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                color: AppColors.primaryGreen,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Câu hỏi gợi ý cho Bác:',
                style: GoogleFonts.roboto(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryGreenDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            topic.prompt,
            style: GoogleFonts.roboto(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            topic.subPrompt,
            style: GoogleFonts.roboto(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Khung trạng thái thu âm, hiển thị sóng âm (`soundwave-0.svg`/`soundwave-1.svg`) và bộ đếm thời gian.
class _RecordingStatusCard extends StatelessWidget {
  const _RecordingStatusCard({
    required this.isRecording,
    required this.isPaused,
    required this.isPlaying,
    required this.hasRecorded,
    required this.recordDurationFormatted,
    required this.pulseAnimation,
    required this.playbackPosition,
    required this.playbackDuration,
    required this.onSeek,
  });

  final bool isRecording;
  final bool isPaused;
  final bool isPlaying;
  final bool hasRecorded;
  final String recordDurationFormatted;
  final Animation<double> pulseAnimation;
  final Duration playbackPosition;
  final Duration playbackDuration;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    String statusTitle = 'Sẵn sàng ghi âm';
    String statusSubtitle = 'Giữ nhịp thật chậm, cháu luôn lắng nghe Bác.';
    Color statusColor = AppColors.primaryGreen;

    if (isRecording) {
      if (isPaused) {
        statusTitle = 'Đang tạm dừng ghi âm';
        statusSubtitle = 'Nhấn nút "Tiếp tục" để thu thêm hoặc "Hoàn tất" để lưu bản ghi.';
        statusColor = AppColors.sosOrange;
      } else {
        statusTitle = 'Đang lắng nghe Bác kể...';
        statusSubtitle = 'Bác cứ nói tự nhiên theo mạch suy nghĩ của mình nhé.';
        statusColor = AppColors.primaryGreen;
      }
    } else if (hasRecorded) {
      statusTitle = 'Bản ghi âm đã sẵn sàng';
      statusSubtitle = 'Bác có thể nghe lại thử hoặc nhấn "Lưu hồi ký" để gửi.';
      statusColor = AppColors.primaryGreenDark;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isRecording
              ? statusColor.withValues(alpha: 0.4)
              : const Color(0xFFE4E0DD),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.black12,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Visualizer Icon with Sóng âm (soundwave) ──
          ScaleTransition(
            scale: isRecording && !isPaused
                ? pulseAnimation
                : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor.withValues(alpha: 0.12),
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: isRecording
                  ? SvgPicture.asset(
                      'assets/icons/soundwave-0.svg',
                      width: 44,
                      height: 40,
                    )
                  : hasRecorded
                      ? SvgPicture.asset(
                          isPlaying
                              ? 'assets/icons/soundwave-0.svg'
                              : 'assets/icons/playback-start.svg',
                          width: 36,
                          height: 36,
                          colorFilter: const ColorFilter.mode(
                            AppColors.primaryGreen,
                            BlendMode.srcIn,
                          ),
                        )
                      : Container(
                          width: 54,
                          height: 54,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primaryGreen,
                          ),
                          alignment: Alignment.center,
                          child: SvgPicture.asset(
                            'assets/icons/mic-button.svg',
                            width: 32,
                            height: 32,
                          ),
                        ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Status Title ──
          Text(
            statusTitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: statusColor,
            ),
          ),

          const SizedBox(height: 4),

          // ── Timer / Duration Display ──
          if (isRecording)
            Text(
              recordDurationFormatted,
              style: GoogleFonts.roboto(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: statusColor,
              ),
            ),

          // ── Playback Progress Bar (khi đã thu âm xong) ──
          if (hasRecorded && !isRecording) ...[
            const SizedBox(height: 10),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                activeTrackColor: AppColors.primaryGreen,
                inactiveTrackColor: const Color(0xFFE4E0DD),
                thumbColor: AppColors.primaryGreenDark,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              ),
              child: Slider(
                value: playbackPosition.inSeconds
                    .toDouble()
                    .clamp(0.0, (playbackDuration.inSeconds > 0 ? playbackDuration.inSeconds : 1).toDouble()),
                max: (playbackDuration.inSeconds > 0 ? playbackDuration.inSeconds : 1).toDouble(),
                onChanged: onSeek,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatTimeDuration(playbackPosition),
                    style: GoogleFonts.roboto(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    _formatTimeDuration(playbackDuration),
                    style: GoogleFonts.roboto(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 6),

          // ── Subtitle helper ──
          Text(
            statusSubtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Cụm nút điều khiển Thu âm 7 trạng thái, tích hợp `pause.svg`, `playback-start.svg`, `send.svg`, `soundwave-1.svg`, `trash-bin.svg`, `mic-button.svg`.
class _RecordingControls extends StatelessWidget {
  const _RecordingControls({
    required this.isRecording,
    required this.isPaused,
    required this.isPlaying,
    required this.isUploading,
    required this.hasRecorded,
    required this.onStartRecord,
    required this.onTogglePause,
    required this.onStopRecord,
    required this.onTogglePlayback,
    required this.onDelete,
    required this.onSend,
  });

  final bool isRecording;
  final bool isPaused;
  final bool isPlaying;
  final bool isUploading;
  final bool hasRecorded;
  final VoidCallback onStartRecord;
  final VoidCallback onTogglePause;
  final VoidCallback onStopRecord;
  final VoidCallback onTogglePlayback;
  final VoidCallback onDelete;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    if (isUploading) {
      return Container(
        width: double.infinity,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primaryGreen),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primaryGreen,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              'Đang lưu giữ hồi ký của Bác...',
              style: GoogleFonts.roboto(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryGreenDark,
              ),
            ),
          ],
        ),
      );
    }

    // ── Trạng thái 1: Chưa bắt đầu thu (Idle) ──
    if (!isRecording && !hasRecorded) {
      return SizedBox(
        width: double.infinity,
        height: 64,
        child: ElevatedButton(
          onPressed: onStartRecord,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: AppColors.white,
            elevation: 4,
            shadowColor: AppColors.primaryGreen.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'assets/icons/mic-button.svg',
                width: 28,
                height: 28,
              ),
              const SizedBox(width: 12),
              Text(
                'BẮT ĐẦU GHI ÂM',
                style: GoogleFonts.roboto(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Trạng thái 2: Đang ghi âm (Recording / Paused) ──
    if (isRecording) {
      return Row(
        children: [
          // Nút Xóa / Hủy (trash-bin.svg)
          Expanded(
            flex: 1,
            child: _ActionButton(
              label: 'Xóa',
              borderColor: AppColors.sosOrange,
              backgroundColor: AppColors.white,
              textColor: AppColors.sosOrange,
              iconWidget: SvgPicture.asset(
                'assets/icons/trash-bin.svg',
                width: 24,
                height: 24,
              ),
              onTap: onDelete,
            ),
          ),
          const SizedBox(width: 10),

          // Nút Tạm dừng / Tiếp tục (pause.svg / playback-start.svg)
          Expanded(
            flex: 1,
            child: _ActionButton(
              label: isPaused ? 'Tiếp tục' : 'Tạm dừng',
              backgroundColor: isPaused ? AppColors.primaryGreen : AppColors.sosOrange,
              textColor: AppColors.white,
              iconWidget: SvgPicture.asset(
                isPaused
                    ? 'assets/icons/playback-start.svg'
                    : 'assets/icons/pause.svg',
                width: 22,
                height: 22,
              ),
              onTap: onTogglePause,
            ),
          ),
          const SizedBox(width: 10),

          // Nút Hoàn thành thu (Check / Stop)
          Expanded(
            flex: 1,
            child: _ActionButton(
              label: 'Hoàn tất',
              backgroundColor: AppColors.primaryGreenDark,
              textColor: AppColors.white,
              iconWidget: const Icon(
                Icons.check_circle_outline_rounded,
                color: AppColors.white,
                size: 24,
              ),
              onTap: onStopRecord,
            ),
          ),
        ],
      );
    }

    // ── Trạng thái 3: Đã thu xong (Recorded / Playback ready) ──
    return Column(
      children: [
        Row(
          children: [
            // Nút Xóa thu lại (trash-bin.svg)
            Expanded(
              child: _ActionButton(
                label: 'Thu lại',
                borderColor: AppColors.sosOrange,
                backgroundColor: AppColors.white,
                textColor: AppColors.sosOrange,
                iconWidget: SvgPicture.asset(
                  'assets/icons/trash-bin.svg',
                  width: 22,
                  height: 22,
                ),
                onTap: onDelete,
              ),
            ),
            const SizedBox(width: 12),

            // Nút Nghe lại (playback-start.svg / pause.svg)
            Expanded(
              child: _ActionButton(
                label: isPlaying ? 'Tạm dừng' : 'Nghe lại',
                borderColor: AppColors.primaryGreen,
                backgroundColor: AppColors.white,
                textColor: AppColors.primaryGreen,
                iconWidget: SvgPicture.asset(
                  isPlaying
                      ? 'assets/icons/pause.svg'
                      : 'assets/icons/playback-start.svg',
                  width: 22,
                  height: 22,
                  colorFilter: const ColorFilter.mode(
                    AppColors.primaryGreen,
                    BlendMode.srcIn,
                  ),
                ),
                onTap: onTogglePlayback,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Nút Lưu & Gửi hồi ký (send.svg)
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: onSend,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: AppColors.white,
              elevation: 4,
              shadowColor: AppColors.primaryGreen.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  'assets/icons/send.svg',
                  width: 26,
                  height: 26,
                ),
                const SizedBox(width: 12),
                Text(
                  'LƯU & GỬI HỒI KÝ',
                  style: GoogleFonts.roboto(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Nút bấm hành động tiêu chuẩn Zero-Barrier (Touch target >= 48dp, height 56dp).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.backgroundColor = AppColors.white,
    this.textColor = AppColors.textPrimary,
    this.borderColor,
    this.iconWidget,
  });

  final String label;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderColor ?? AppColors.transparent,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (iconWidget != null) ...[
                iconWidget!,
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.roboto(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Model dữ liệu cho Gợi ý chủ đề
class _TopicItem {
  const _TopicItem({
    required this.title,
    required this.prompt,
    required this.subPrompt,
    required this.activeAsset,
    required this.inactiveAsset,
  });

  final String title;
  final String prompt;
  final String subPrompt;
  final String activeAsset;
  final String inactiveAsset;
}
