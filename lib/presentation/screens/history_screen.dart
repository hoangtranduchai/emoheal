import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/logger.dart';
import '../../core/responsive_utils.dart';
import '../../core/theme.dart';
import '../../core/voice_guide.dart';
import '../../data/supabase_service.dart';

/// Màn hình Lịch sử Hồi ký Giọng nói — Chuẩn Figma (Node 2490:528)
///
/// Thẻ Hồi ký Pill bo tròn (Rectangle 99) 79dp, nền #CFEAC7 (50%),
/// đầy đủ thông tin Tên hồi ký, Ngày ghi âm, Thời lượng, Nút Nghe lại và Xem phụ đề toàn văn.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  late Future<List<Map<String, dynamic>>> _voiceMemosFuture;
  String? _currentlyPlayingUrl;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VoiceGuide.play(VoiceScripts.history);
    });

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

  @override
  void dispose() {
    VoiceGuide.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _loadData() {
    setState(() {
      _voiceMemosFuture = _supabaseService.getVoiceMemos();
    });
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
        
        AppLogger.i('Bắt đầu phát âm thanh hồi ký: $audioUrl', tag: 'HISTORY');

        if (audioUrl.startsWith('http://') || audioUrl.startsWith('https://')) {
          await _audioPlayer.play(UrlSource(audioUrl));
        } else {
          String cleanPath = audioUrl.replaceFirst('local://voice_memos/', '').replaceFirst('local://', '');
          final file = File(cleanPath);
          if (await file.exists()) {
            await _audioPlayer.play(DeviceFileSource(file.path));
          } else {
            final docDir = await getApplicationDocumentsDirectory();
            final localFile = File('${docDir.path}/voice_memos/$cleanPath');
            if (await localFile.exists()) {
              await _audioPlayer.play(DeviceFileSource(localFile.path));
            } else {
              await _audioPlayer.play(UrlSource(audioUrl));
            }
          }
        }
      }
    } catch (e) {
      AppLogger.w('Lỗi phát âm thanh hồi ký: $e', tag: 'HISTORY');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bác ơi, cháu đang chuẩn bị tệp âm thanh này ạ.',
              style: TextStyle(fontFamily: 'Roboto', fontSize: 16),
            ),
          ),
        );
      }
    }
  }

  void _showTranscriptDialog(String title, String transcript) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          title,
          style: GoogleFonts.roboto(
            fontWeight: FontWeight.bold,
            color: AppColors.primaryGreenDark,
            fontSize: 20,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            transcript.isNotEmpty ? transcript : 'Bản ghi âm này chưa có phụ đề văn bản.',
            style: GoogleFonts.roboto(
              fontSize: 17,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.all(16),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: AppColors.white,
              minimumSize: const Size(100, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              'Đóng',
              style: GoogleFonts.roboto(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
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
            constraints: BoxConstraints(maxWidth: isTablet ? 720 : double.infinity),
            child: Column(
              children: [
                // ── Top Header Chuẩn Figma ──
                Padding(
                  padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 12),
                  child: Row(
                    children: [
                      Material(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.of(context).pop(),
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
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lịch sử Hồi ký',
                              style: GoogleFonts.roboto(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF242424),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Kỷ niệm và câu chuyện của Bác',
                              style: GoogleFonts.roboto(
                                fontSize: 16,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Danh Sách Thẻ Hồi Ký Chuẩn Figma (Rectangle 99) ──
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
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
                            'Có lỗi xảy ra khi tải danh sách hồi ký.',
                            style: GoogleFonts.roboto(
                              fontSize: 16,
                              color: AppColors.sosOrange,
                            ),
                          ),
                        );
                      }

                      final memos = snapshot.data ?? [];
                      if (memos.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgPicture.asset(
                                  'assets/icons/favourite.svg',
                                  width: 64,
                                  height: 64,
                                  colorFilter: ColorFilter.mode(
                                    AppColors.primaryGreen.withValues(alpha: 0.5),
                                    BlendMode.srcIn,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  'Bác chưa có bản hồi ký nào',
                                  style: GoogleFonts.roboto(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Bác hãy mở mục "Hồi ký" ở Trang chủ và bấm ghi âm để lưu lại những câu chuyện kỷ niệm nhé ạ.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.roboto(
                                    fontSize: 16,
                                    color: AppColors.textSecondary,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: () async => _loadData(),
                        color: AppColors.primaryGreen,
                        child: ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12),
                          itemCount: memos.length,
                          itemBuilder: (context, index) {
                            final memo = memos[index];
                            final title = memo['title']?.toString() ?? 'Hồi ký kỷ niệm';
                            final duration = _formatDuration(memo['duration_seconds']);
                            final date = _formatDate(memo['created_at']?.toString());
                            final audioUrl = memo['audio_url']?.toString() ?? '';
                            final transcript = memo['transcript']?.toString() ?? '';
                            final isCurrentPlaying = _currentlyPlayingUrl == audioUrl && _isPlaying;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFCFEAC7).withValues(alpha: 0.45), // Figma Rectangle 99
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: const Color(0xFFB8E0AE),
                                  width: 1.5,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x0F000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        // Nút Play / Pause tròn to (Figma Ellipse 88)
                                        GestureDetector(
                                          onTap: audioUrl.isNotEmpty ? () => _toggleAudio(audioUrl) : null,
                                          child: Container(
                                            width: 52,
                                            height: 52,
                                            decoration: BoxDecoration(
                                              color: isCurrentPlaying ? AppColors.sosOrange : AppColors.primaryGreen,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: (isCurrentPlaying ? AppColors.sosOrange : AppColors.primaryGreen)
                                                      .withValues(alpha: 0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            alignment: Alignment.center,
                                            child: Icon(
                                              isCurrentPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                              color: AppColors.white,
                                              size: 32,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),

                                        // Thông tin Tên hồi ký & Ngày tháng
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                title,
                                                style: GoogleFonts.roboto(
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
                                                  Text(
                                                    '⏱ $duration',
                                                    style: GoogleFonts.roboto(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w700,
                                                      color: AppColors.primaryGreenDark,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    '📅 $date',
                                                    style: GoogleFonts.roboto(
                                                      fontSize: 14,
                                                      color: AppColors.textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Phụ đề trích đoạn nếu có
                                    if (transcript.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: AppColors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: const Color(0xFFD4E6D0), width: 1.0),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '"$transcript"',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.roboto(
                                                  fontSize: 15,
                                                  fontStyle: FontStyle.italic,
                                                  color: AppColors.textPrimary,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            TextButton(
                                              onPressed: () => _showTranscriptDialog(title, transcript),
                                              style: TextButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                minimumSize: const Size(48, 36),
                                              ),
                                              child: Text(
                                                'Xem đủ',
                                                style: GoogleFonts.roboto(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.primaryGreenDark,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
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
