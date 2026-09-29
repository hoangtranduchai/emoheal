import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/logger.dart';
import '../../core/responsive_utils.dart';
import '../../core/theme.dart';
import '../../core/voice_guide.dart';
import '../../data/api_service.dart';
import '../../data/supabase_service.dart';
import '../../router.dart';

/// Mô hình tin nhắn trong cuộc hội thoại Hồi ký (Multi-turn 1-N)
class _ChatMessage {
  _ChatMessage({
    required this.id,
    required this.isAssistant,
    required this.text,
    this.audioUrl,
    this.audioPath,
    this.durationSeconds = 0,
    this.emotion,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String id;
  final bool isAssistant;
  final String text;
  final String? audioUrl;
  final String? audioPath;
  final int durationSeconds;
  final String? emotion;
  final DateTime timestamp;
}

/// Màn hình 'Hồi ký Giọng nói' — Voice Memoir Screen (Hội thoại Đa Lượt 1-N)
///
/// Các tính năng then chốt:
/// 1. Bong bóng Trợ lý AI: Hiển thị văn bản text trả về từ API và tự động phát âm thanh câu trả lời.
/// 2. Bong bóng Người dùng: Hiển thị văn bản text được chuyển từ chính giọng nói của Bác (transcription).
/// 3. Hội thoại liên tục 1-N: Bác và Trợ lý AI có thể trò chuyện nhiều lượt liên tiếp không gián đoạn.
/// 4. Không tự ngắt thu âm: Bác nói bao lâu tùy thích; khi bấm nút "GỬI" thì AI mới bắt đầu tiếp nhận và xử lý.
/// 5. Nút "GỬI" (send.svg): Gửi đoạn thu âm trực tiếp vào hội thoại.
/// 6. Tự động lưu và đặt tên Hồi ký: Tự động khởi tạo phiên Hồi ký ngay từ tin nhắn đầu tiên và tiếp tục lưu các tin nhắn tiếp theo lên Supabase Database & Storage.
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
  final ScrollController _scrollController = ScrollController();

  // ── Animation Controllers ──
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // ── Recording & Playback States ──
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isPlayingAiAudio = false;
  bool _isSending = false;

  // ── Multi-turn Chat & Session State (1-N) ──
  final List<_ChatMessage> _messages = [];
  String? _currentSessionId;
  String? _currentSessionTitle;
  int _totalSessionDuration = 0;

  // ── Speech Emotion Recognition (SER) State ──
  Map<String, dynamic>? _lastEmotionResult;
  bool _showIntervention = false;
  String _voiceType = 'aoede';

  Timer? _timer;
  int _currentRecordDuration = 0;
  String? _currentAudioPath;

  // ── Topic Suggestions (Chủ đề gợi ý từ Figma) ──
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
    _loadVoiceSettings();

    // Khởi tạo tin nhắn chào / gợi ý ban đầu của Trợ lý AI
    _initFirstAssistantMessage();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      VoiceGuide.play(VoiceScripts.voiceMemo);
    });

    // Pulse animation cho sóng âm khi đang ghi âm
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isPlayingAiAudio = false);
      }
    });
  }

  void _initFirstAssistantMessage() {
    final topic = _topics[_selectedTopicIndex];
    _messages.add(
      _ChatMessage(
        id: 'init-msg',
        isAssistant: true,
        text: topic.prompt,
      ),
    );
  }

  @override
  void dispose() {
    VoiceGuide.stop();
    _timer?.cancel();
    _pulseController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Tải Cài đặt Giọng nói từ Supabase ──
  Future<void> _loadVoiceSettings() async {
    try {
      final settings = await _supabaseService.getUserSettings();
      if (mounted && settings['voice_type'] != null) {
        setState(() {
          _voiceType = settings['voice_type'].toString();
        });
      }
    } catch (e) {
      AppLogger.w('Không thể tải cài đặt giọng nói: $e', tag: 'VOICE-MEMO');
    }
  }

  // ── Cuộn xuống cuối danh sách hội thoại ──
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Đếm thời gian ghi âm (Không giới hạn, không tự ngắt) ──
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (mounted) {
        setState(() => _currentRecordDuration++);
      }
    });
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  // ── 1. Bắt đầu Ghi âm (Start Recording - Bác nói bao lâu tùy thích) ──
  Future<void> _startRecording() async {
    // Dừng âm thanh AI đang phát nếu có
    if (_isPlayingAiAudio) {
      await _audioPlayer.stop();
      setState(() => _isPlayingAiAudio = false);
    }

    try {
      if (await _audioRecorder.hasPermission()) {
        String? filePath;
        if (kIsWeb) {
          await _audioRecorder.start(const RecordConfig(), path: '');
        } else {
          final dir = await getTemporaryDirectory();
          filePath = '${dir.path}/memo_turn_${DateTime.now().millisecondsSinceEpoch}.m4a';
          try {
            await _audioRecorder.start(
              const RecordConfig(encoder: AudioEncoder.aacLc),
              path: filePath,
            );
          } catch (codecErr) {
            AppLogger.w('Thử lại ghi âm với RecordConfig mặc định: $codecErr', tag: 'VOICE-MEMO');
            await _audioRecorder.start(
              const RecordConfig(),
              path: filePath,
            );
          }
        }

        AppLogger.i('Bắt đầu thu âm lượt thoại: ${filePath ?? "Web Blob"}', tag: 'VOICE-MEMO');
        _pulseController.repeat(reverse: true);
        setState(() {
          _isRecording = true;
          _isPaused = false;
          _currentRecordDuration = 0;
          _currentAudioPath = filePath;
        });
        _startTimer();
      } else {
        AppLogger.w('Chưa cấp quyền Microphone cho Hồi ký', tag: 'VOICE-MEMO');
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
    } catch (e, st) {
      AppLogger.e('Lỗi bắt đầu ghi âm', tag: 'VOICE-MEMO', error: e, stackTrace: st);
    }
  }

  // ── 2. Tạm dừng / Tiếp tục Ghi âm (Pause / Resume) ──
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
    } catch (e, st) {
      AppLogger.e('Lỗi tạm dừng ghi âm', tag: 'VOICE-MEMO', error: e, stackTrace: st);
    }
  }

  // ── 3. Hủy / Xóa lượt thu âm hiện tại ──
  Future<void> _cancelRecording() async {
    if (_isRecording) {
      await _audioRecorder.stop();
    }
    _pulseController.stop();
    _pulseController.reset();
    _timer?.cancel();

    if (_currentAudioPath != null && !kIsWeb) {
      try {
        final file = File(_currentAudioPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    setState(() {
      _isRecording = false;
      _isPaused = false;
      _currentRecordDuration = 0;
      _currentAudioPath = null;
    });
  }

  // ── 4. GỬI TIN NHẮN (Bác bấm nút Gửi -> Dừng thu, AI xử lý & Tự động lưu 1-N) ──
  Future<void> _sendVoiceTurn() async {
    if (!_isRecording) return;

    try {
      final isRec = await _audioRecorder.isRecording();
      String? recordedPath;
      if (isRec) {
        recordedPath = await _audioRecorder.stop();
      } else {
        recordedPath = _currentAudioPath;
      }

      final duration = _currentRecordDuration;
      _pulseController.stop();
      _pulseController.reset();
      _timer?.cancel();

      setState(() {
        _isRecording = false;
        _isPaused = false;
        _isSending = true;
        _currentAudioPath = recordedPath;
      });

      if (recordedPath == null || recordedPath.isEmpty) {
        setState(() => _isSending = false);
        return;
      }

      AppLogger.i('Gửi đoạn ghi âm ($duration giây) lên AI Gateway: "$recordedPath"', tag: 'VOICE-MEMO');

      // Xây dựng lịch sử hội thoại dạng Map để AI nhớ ngữ cảnh
      final historyList = _messages.map((m) => {
        'role': m.isAssistant ? 'assistant' : 'user',
        'content': m.text,
      }).toList();

      // Gửi yêu cầu lên Backend FastAPI (Gemini SER + Multimodal STT & Response + TTS)
      final response = await ApiService.sendAssistantRequest(
        audioPath: recordedPath,
        voice: _voiceType,
        history: historyList,
      );

      final transcription = (response['transcription'] as String?)?.trim() ?? 'Bác vừa chia sẻ một đoạn hồi ký.';
      final aiText = (response['text'] as String?)?.trim() ?? 'Dạ cháu đã lắng nghe câu chuyện của Bác!';
      final aiAudioUrl = response['audio_url'] as String?;
      final emotion = (response['emotion'] ?? 'NEUTRAL').toString().toUpperCase();
      final intent = (response['intent'] ?? 'CHAT').toString().toUpperCase();

      AppLogger.i('Kết quả AI: Transcription="$transcription", Emotion=$emotion, Text="$aiText"', tag: 'VOICE-MEMO');

      // Thêm tin nhắn của Bác và tin nhắn của AI vào danh sách hội thoại
      final userMsg = _ChatMessage(
        id: 'user-${DateTime.now().millisecondsSinceEpoch}',
        isAssistant: false,
        text: transcription,
        audioPath: recordedPath,
        durationSeconds: duration,
        emotion: emotion,
      );

      final aiMsg = _ChatMessage(
        id: 'ai-${DateTime.now().millisecondsSinceEpoch}',
        isAssistant: true,
        text: aiText,
        audioUrl: aiAudioUrl,
      );

      final isDistressed = emotion == 'PANIC_STRESS' || emotion == 'SADNESS' || intent == 'PANIC';

      if (mounted) {
        setState(() {
          _messages.add(userMsg);
          _messages.add(aiMsg);
          _isSending = false;
          _currentRecordDuration = 0;
          _currentAudioPath = null;
          _totalSessionDuration += duration;
          _lastEmotionResult = response;
          if (isDistressed) {
            _showIntervention = true;
          }
        });

        _scrollToBottom();

        // ── TỰ ĐỘNG PHÁT ÂM THANH CÂU TRẢ LỜI CỦA AI ──
        if (aiAudioUrl != null && aiAudioUrl.isNotEmpty) {
          _playAiAudioResponse(aiAudioUrl);
        }

        // ── TỰ ĐỘNG LƯU VÀO SUPABASE (QUAN HỆ 1-N) ──
        _autoSaveSessionAndMessages(userMsg, aiMsg, recordedPath, duration);
      }
    } catch (e, st) {
      AppLogger.e('Lỗi xử lý gửi tin nhắn hồi ký', tag: 'VOICE-MEMO', error: e, stackTrace: st);
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi gửi tin nhắn: $e'),
            backgroundColor: AppColors.sosOrange,
          ),
        );
      }
    }
  }

  // ── Phát âm thanh phản hồi của AI ──
  Future<void> _playAiAudioResponse(String audioUrl) async {
    try {
      final fullAudioUrl = audioUrl.startsWith('http')
          ? audioUrl
          : '${ApiService.baseUrl}$audioUrl';
      AppLogger.d('Tự động phát giọng đọc của AI: $fullAudioUrl', tag: 'VOICE-MEMO');
      setState(() => _isPlayingAiAudio = true);
      await _audioPlayer.play(UrlSource(fullAudioUrl));
    } catch (e) {
      AppLogger.w('Không thể phát âm thanh AI: $e', tag: 'VOICE-MEMO');
      if (mounted) setState(() => _isPlayingAiAudio = false);
    }
  }

  // ── TỰ ĐỘNG KHỞI TẠO & LƯU HỒI KÝ LÊN SUPABASE (1-N) ──
  Future<void> _autoSaveSessionAndMessages(
    _ChatMessage userMsg,
    _ChatMessage aiMsg,
    String localAudioPath,
    int duration,
  ) async {
    try {
      final topicTitle = _topics[_selectedTopicIndex].title;

      // 1. Nếu là tin nhắn đầu tiên: Tạo Session và Đặt tên tự động
      if (_currentSessionId == null) {
        final words = userMsg.text.split(' ');
        final snippet = words.take(6).join(' ');
        final sessionTitle = snippet.isNotEmpty
            ? '$topicTitle: "$snippet..."'
            : '$topicTitle - Hồi ký ngày ${DateTime.now().day}/${DateTime.now().month}';

        _currentSessionId = 'session-${DateTime.now().millisecondsSinceEpoch}';
        _currentSessionTitle = sessionTitle;
        AppLogger.i('Tự động khởi tạo phiên Hồi ký: "$sessionTitle"', tag: 'VOICE-MEMO');
      }

      // 2. Upload file âm thanh của Bác lên Supabase Storage
      String cloudAudioUrl = localAudioPath;
      try {
        final fileName = 'turn_${DateTime.now().millisecondsSinceEpoch}.m4a';
        Uint8List bytes;
        if (kIsWeb) {
          final res = await http.get(Uri.parse(localAudioPath));
          bytes = res.bodyBytes;
        } else {
          bytes = await File(localAudioPath).readAsBytes();
        }
        cloudAudioUrl = await _supabaseService.uploadVoiceMemoBytes(bytes, fileName);
      } catch (uploadErr) {
        AppLogger.w('Upload audio fallback local: $uploadErr', tag: 'VOICE-MEMO');
      }

      // 3. Xây dựng toàn văn transcript nối dài của cả phiên
      final fullTranscript = _messages
          .map((m) => '${m.isAssistant ? "Cháu" : "Bác"}: ${m.text}')
          .join('\n\n');

      // 4. Lưu metadata vào Supabase Database & SharedPreferences local cache
      await _supabaseService.saveVoiceMemoMetadata(
        title: _currentSessionTitle ?? topicTitle,
        audioUrl: cloudAudioUrl,
        durationSeconds: _totalSessionDuration,
        topic: topicTitle,
        transcript: fullTranscript,
      );

      AppLogger.i('Đã tự động cập nhật lưu trữ Hồi ký vào Database', tag: 'VOICE-MEMO');
    } catch (e) {
      AppLogger.w('Tự động lưu hồi ký gặp sự cố (vẫn lưu local): $e', tag: 'VOICE-MEMO');
    }
  }

  // ── Can thiệp tâm lý: Gọi điện người thân ──
  Future<void> _callEmergencyContact() async {
    AppLogger.w('📞 Gọi điện người thân từ can thiệp cảm xúc Hồi ký', tag: 'SER-MEMO');
    String targetPhone = '115';
    try {
      final contacts = await _supabaseService.getEmergencyContacts();
      if (contacts.isNotEmpty) {
        final primary = contacts.first;
        final phone = (primary['contact_phone'] ?? '').toString().trim();
        if (phone.isNotEmpty) targetPhone = phone;
      }
    } catch (_) {}

    final cleanPhone = targetPhone.replaceAll(RegExp(r'[^\d+]'), '');
    final telUri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri);
      }
    } catch (e) {
      AppLogger.e('Lỗi quay số điện thoại', tag: 'SER-MEMO', error: e);
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
                // ── 1. Top Navigation Bar (Figma Node 421:1886) ──
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

                // ── 2. Vùng Nội dung Cuộn (Scrollable Body) ──
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),

                        // ── Trợ lý AI Đồng hành (support.gif) ──
                        const _AssistantCompanionCard(),

                        const SizedBox(height: 16),

                        // ── Gợi ý chủ đề (Figma Node 2474:168 & 2505:212 - Không có chữ "Chọn 1 chủ đề") ──
                        _TopicSuggestionsSection(
                          topics: _topics,
                          selectedIndex: _selectedTopicIndex,
                          onTopicSelected: (index) {
                            setState(() {
                              _selectedTopicIndex = index;
                              // Khi đổi chủ đề và chưa có tin nhắn nào từ Bác, cập nhật câu hỏi gợi ý đầu tiên
                              if (_messages.length <= 1) {
                                _messages.clear();
                                _initFirstAssistantMessage();
                              }
                            });
                          },
                        ),

                        const SizedBox(height: 16),

                        // ── Thẻ Can Thiệp Cảm Xúc (Khi SER phát hiện dấu hiệu mệt mỏi/hoảng loạn) ──
                        if (_showIntervention && _lastEmotionResult != null) ...[
                          _EmotionInterventionCard(
                            emotionResult: _lastEmotionResult,
                            onNavigateBreathing: () {
                              _audioPlayer.stop();
                              Navigator.of(context).pushNamed(AppRoutes.lotusBreathing);
                            },
                            onNavigateRadio: () {
                              _audioPlayer.stop();
                              Navigator.of(context).pushNamed(AppRoutes.radio);
                            },
                            onCallFamily: () {
                              _audioPlayer.stop();
                              _callEmergencyContact();
                            },
                            onDismiss: () {
                              _audioPlayer.stop();
                              setState(() => _showIntervention = false);
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ── 3. KHUNG HỘI THOẠI ĐA LƯỢT 1-N & STUDIO CARD CHUẨN FIGMA ──
                        _VoiceStudioCard(
                          topic: _topics[_selectedTopicIndex],
                          messages: _messages,
                          isRecording: _isRecording,
                          isPaused: _isPaused,
                          isSending: _isSending,
                          isPlayingAiAudio: _isPlayingAiAudio,
                          recordDurationFormatted: _formatDuration(_currentRecordDuration),
                          pulseAnimation: _pulseAnimation,
                          onStartRecord: _startRecording,
                          onTogglePause: _togglePauseRecording,
                          onCancelRecord: _cancelRecording,
                          onSendTurn: _sendVoiceTurn,
                        ),

                        const SizedBox(height: 28),
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
// SUB-WIDGETS CHUẨN FIGMA & TRẢI NGHIỆM 1-N
// ════════════════════════════════════════════════════════════════════

/// Top App Bar (Figma Node 421:1886)
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
          // Nút Quay lại (Vùng chạm >= 48dp x 48dp, Figma 421:1887)
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

          // Tiêu đề màn hình (Figma 421:1889: Roboto 20sp SemiBold #242424)
          Expanded(
            child: Column(
              children: [
                Text(
                  'Hồi ký Giọng nói',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.roboto(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF242424),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Lưu giữ ký ức cuộc đời',
                  style: GoogleFonts.roboto(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Nút Lịch sử hồi ký (Figma 421:1890: favourite.svg, vùng chạm >= 48dp)
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

/// Khung Trợ lý AI đồng hành sử dụng `support.gif`
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Trợ lý EmoHeal',
                      style: GoogleFonts.roboto(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryGreenDark,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Đang lắng nghe',
                        style: GoogleFonts.roboto(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Cháu chào Bác! Hôm nay Bác muốn kể lại kỷ niệm nào ạ? Bác cứ bấm ghi âm và tâm sự thoải mái, cháu luôn ở đây lắng nghe Bác.',
                  style: GoogleFonts.roboto(
                    fontSize: 16,
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

/// Gợi ý chủ đề với chuyển đổi icon active/inactive (Figma Node 2474:168 & 2505:212)
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
        Text(
          'Gợi ý chủ đề',
          style: GoogleFonts.roboto(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 155,
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
    final assetPath = isSelected ? topic.activeAsset : topic.inactiveAsset;

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 195,
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
                  fontSize: 16,
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

/// Khung Hội Thoại Đa Lượt & Thu Âm Studio Chuẩn Figma (1-N)
class _VoiceStudioCard extends StatelessWidget {
  const _VoiceStudioCard({
    required this.topic,
    required this.messages,
    required this.isRecording,
    required this.isPaused,
    required this.isSending,
    required this.isPlayingAiAudio,
    required this.recordDurationFormatted,
    required this.pulseAnimation,
    required this.onStartRecord,
    required this.onTogglePause,
    required this.onCancelRecord,
    required this.onSendTurn,
  });

  final _TopicItem topic;
  final List<_ChatMessage> messages;
  final bool isRecording;
  final bool isPaused;
  final bool isSending;
  final bool isPlayingAiAudio;
  final String recordDurationFormatted;
  final Animation<double> pulseAnimation;
  final VoidCallback onStartRecord;
  final VoidCallback onTogglePause;
  final VoidCallback onCancelRecord;
  final VoidCallback onSendTurn;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E0DD), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A3B3B3B),
            blurRadius: 40,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── 1. Tiêu đề "HỘI THOẠI" kẹp giữa 2 vạch chỉ báo (Figma 2474:122) ──
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 30,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3C4158).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'HỘI THOẠI',
                  style: GoogleFonts.roboto(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: const Color(0xFF3C4158),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 30,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3C4158).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ── 2. DANH SÁCH BONG BÓNG HỘI THOẠI ĐA LƯỢT (1-N) ──
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: messages.length,
            separatorBuilder: (context, index) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final msg = messages[index];
              return _MessageBubbleItem(
                message: msg,
                isPlaying: isPlayingAiAudio && index == messages.length - 1 && msg.isAssistant,
              );
            },
          ),

          // Hiệu ứng "Đang xử lý & AI đang lắng nghe..." khi Bác bấm Gửi
          if (isSending) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF62AD55).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Cháu đang lắng nghe và trích xuất lời kể...',
                      style: GoogleFonts.roboto(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryGreenDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ── 3. Khung Sóng Âm Visualizer & Bộ Đếm Giờ (Figma 2490:384 & 2575:683) ──
          Container(
            width: double.infinity,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF62AD55).withValues(alpha: isRecording ? 0.95 : 0.8),
              borderRadius: BorderRadius.circular(100), // Capsule viên thuốc
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF62AD55).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Hoạt họa Sóng âm
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: isRecording && !isPaused ? pulseAnimation : const AlwaysStoppedAnimation(1.0),
                        child: SvgPicture.asset(
                          'assets/icons/soundwave-0.svg',
                          width: 28,
                          height: 24,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          isRecording
                              ? (isPaused ? 'Tạm dừng thu' : 'Đang thu âm...')
                              : (isSending ? 'Đang gửi...' : 'Sẵn sàng tâm sự'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.roboto(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Đồng hồ đếm giờ (Không giới hạn)
                Text(
                  isRecording ? recordDurationFormatted : '00:00',
                  style: GoogleFonts.roboto(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.white,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── 4. CỤM NÚT ĐIỀU KHIỂN THU ÂM & GỬI TIN NHẮN (Figma 2474:201 & 2490:268) ──
          _StudioControls(
            isRecording: isRecording,
            isPaused: isPaused,
            isSending: isSending,
            pulseAnimation: pulseAnimation,
            onStartRecord: onStartRecord,
            onTogglePause: onTogglePause,
            onCancelRecord: onCancelRecord,
            onSendTurn: onSendTurn,
          ),
        ],
      ),
    );
  }
}

/// Item Bong bóng tin nhắn riêng lẻ (AI hoặc Bác)
class _MessageBubbleItem extends StatelessWidget {
  const _MessageBubbleItem({
    required this.message,
    this.isPlaying = false,
  });

  final _ChatMessage message;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    if (message.isAssistant) {
      // ── Bong bóng Trợ lý AI (Figma Node 2473:197) ──
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 295),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF62AD55).withValues(alpha: 0.88),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
              bottomLeft: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF62AD55).withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    'Trợ lý EmoHeal',
                    style: GoogleFonts.roboto(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  if (isPlaying)
                    const Icon(
                      Icons.volume_up_rounded,
                      color: AppColors.white,
                      size: 18,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                message.text,
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.white,
                  height: 1.38,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // ── Bong bóng của Bác (Figma Node 2473:129 & 2717:631) ──
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 295),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFECEEEB),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(4),
            ),
            border: Border.all(color: const Color(0xFFDDDEDC), width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  const Icon(
                    Icons.mic_rounded,
                    color: AppColors.primaryGreenDark,
                    size: 18,
                  ),
                  Text(
                    'Lời kể của Bác',
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
                message.text,
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}

/// Cụm Nút Điều Khiển Thu Âm & Gửi Tin Nhắn (Figma 2474:201, 2490:268)
class _StudioControls extends StatelessWidget {
  const _StudioControls({
    required this.isRecording,
    required this.isPaused,
    required this.isSending,
    required this.pulseAnimation,
    required this.onStartRecord,
    required this.onTogglePause,
    required this.onCancelRecord,
    required this.onSendTurn,
  });

  final bool isRecording;
  final bool isPaused;
  final bool isSending;
  final Animation<double> pulseAnimation;
  final VoidCallback onStartRecord;
  final VoidCallback onTogglePause;
  final VoidCallback onCancelRecord;
  final VoidCallback onSendTurn;

  @override
  Widget build(BuildContext context) {
    if (isSending) {
      return Container(
        width: double.infinity,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primaryGreen, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primaryGreen,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              'Đang gửi lời kể...',
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

    // ── Trạng thái 1: Chưa bắt đầu thu (Idle Ellipse 108 Gradient 80x80) ──
    if (!isRecording) {
      return Column(
        children: [
          // Nút tròn Gradient to 80x80dp
          GestureDetector(
            onTap: onStartRecord,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF7EC365),
                    Color(0xFF57A36E),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF57A36E).withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: SvgPicture.asset(
                'assets/icons/mic-button.svg',
                width: 36,
                height: 36,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bấm để trò chuyện',
            style: GoogleFonts.roboto(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryGreenDark,
            ),
          ),
        ],
      );
    }

    // ── Trạng thái 2: Đang ghi âm (Xóa, Tạm dừng 76x76, Nút GỬI TIN NHẮN) ──
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Nút Hủy / Xóa đoạn thu
        _ControlIconButton(
          iconAsset: 'assets/icons/trash-bin.svg',
          label: 'Hủy',
          color: AppColors.sosOrange,
          bgColor: const Color(0xFFFFF0EB),
          onTap: onCancelRecord,
        ),

        // Nút Tạm dừng / Tiếp tục (76x76dp)
        ScaleTransition(
          scale: !isPaused ? pulseAnimation : const AlwaysStoppedAnimation(1.0),
          child: GestureDetector(
            onTap: onTogglePause,
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isPaused ? AppColors.primaryGreen : AppColors.sosOrange,
                    boxShadow: [
                      BoxShadow(
                        color: (isPaused ? AppColors.primaryGreen : AppColors.sosOrange).withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: SvgPicture.asset(
                    isPaused ? 'assets/icons/playback-start.svg' : 'assets/icons/pause.svg',
                    width: 28,
                    height: 28,
                    colorFilter: const ColorFilter.mode(AppColors.white, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isPaused ? 'Tiếp tục' : 'Tạm dừng',
                  style: GoogleFonts.roboto(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isPaused ? AppColors.primaryGreen : AppColors.sosOrange,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Nút GỬI TIN NHẮN (send.svg - Bấm để gửi đoạn thu vào hội thoại)
        _ControlIconButton(
          iconAsset: 'assets/icons/send.svg',
          label: 'Gửi',
          color: AppColors.white,
          bgColor: AppColors.primaryGreen,
          iconColor: AppColors.white,
          onTap: onSendTurn,
        ),
      ],
    );
  }
}

/// Nút bấm tròn điều khiển thu âm nhỏ (Hủy / Gửi)
class _ControlIconButton extends StatelessWidget {
  const _ControlIconButton({
    required this.iconAsset,
    required this.label,
    required this.color,
    required this.bgColor,
    this.iconColor,
    required this.onTap,
  });

  final String iconAsset;
  final String label;
  final Color color;
  final Color bgColor;
  final Color? iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
              border: Border.all(
                color: (iconColor ?? color).withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: bgColor.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: SvgPicture.asset(
              iconAsset,
              width: 26,
              height: 26,
              colorFilter: iconColor != null
                  ? ColorFilter.mode(iconColor!, BlendMode.srcIn)
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.roboto(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: iconColor == AppColors.white ? AppColors.primaryGreenDark : color,
            ),
          ),
        ],
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

/// Thẻ Gợi Ý Can Thiệp Cảm Xúc (Emotion Intervention Card)
class _EmotionInterventionCard extends StatelessWidget {
  const _EmotionInterventionCard({
    required this.emotionResult,
    required this.onNavigateBreathing,
    required this.onNavigateRadio,
    required this.onCallFamily,
    required this.onDismiss,
  });

  final Map<String, dynamic>? emotionResult;
  final VoidCallback onNavigateBreathing;
  final VoidCallback onNavigateRadio;
  final VoidCallback onCallFamily;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final rawEmotion = (emotionResult?['emotion'] ?? 'NEUTRAL').toString().toUpperCase();
    final intent = (emotionResult?['intent'] ?? 'CHAT').toString().toUpperCase();
    final aiText = (emotionResult?['text'] ?? '').toString().trim();

    final isPanic = rawEmotion == 'PANIC_STRESS' || intent == 'PANIC';
    final isSadness = rawEmotion == 'SADNESS';

    final Color bgColor = isPanic ? const Color(0xFFFFF6F0) : const Color(0xFFF2F7FD);
    final Color borderColor = isPanic ? AppColors.sosOrange : const Color(0xFF4A7C59);
    final Color titleColor = isPanic ? const Color(0xFFC04B00) : const Color(0xFF1B4D3E);
    final String title = isPanic
        ? 'Cháu thấy Bác hơi mệt hoặc khó thở'
        : 'Cháu luôn bên cạnh lắng nghe Bác';
    final String defaultMsg = isPanic
        ? 'Dạ cháu thấy giọng Bác hơi run và khó thở. Bác hãy nghỉ ngơi cùng cháu một lát và tập thở hoa sen để điều hòa huyết áp nhé ạ.'
        : 'Dạ cháu luôn đồng hành cùng Bác. Cháu mời Bác nghe khúc ca xưa, ngâm thơ hoặc tâm sự cùng người thân để vơi bớt nỗi buồn nhé ạ.';
    final String displayMsg = aiText.isNotEmpty ? aiText : defaultMsg;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.15),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: borderColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPanic ? Icons.spa_rounded : Icons.volunteer_activism_rounded,
                  color: borderColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.roboto(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gợi ý hỗ trợ thấu cảm tức thì',
                      style: GoogleFonts.roboto(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: onDismiss,
                tooltip: 'Đóng gợi ý',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor.withValues(alpha: 0.25)),
            ),
            child: Text(
              displayMsg,
              style: GoogleFonts.roboto(
                fontSize: 16,
                height: 1.45,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const SizedBox(height: 16),

          Column(
            children: [
              _InterventionActionButton(
                label: isPanic ? '🌸 Tập Nhịp thở Hoa Sen (Khuyên dùng)' : '🌸 Tập Nhịp thở Tĩnh Tâm',
                subtitle: 'Chu kỳ thở 4-4-6 giúp bình tĩnh & điều hòa huyết áp',
                isPrimary: isPanic,
                primaryColor: AppColors.primaryGreen,
                onPressed: onNavigateBreathing,
              ),
              const SizedBox(height: 10),
              _InterventionActionButton(
                label: isSadness ? '📻 Mở Đài Radio Hoài Niệm (Khuyên dùng)' : '📻 Nghe Đài Radio Hoài Niệm',
                subtitle: 'Khúc ca xưa, dân ca, ngâm thơ xoa dịu tâm hồn',
                isPrimary: isSadness,
                primaryColor: const Color(0xFF2C5E8A),
                onPressed: onNavigateRadio,
              ),
              const SizedBox(height: 10),
              _InterventionActionButton(
                label: '📞 Gọi Điện Cho Người Thân',
                subtitle: 'Kết nối ngay với gia đình để trò chuyện tâm sự',
                isPrimary: false,
                isWarning: true,
                primaryColor: AppColors.sosOrange,
                onPressed: onCallFamily,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InterventionActionButton extends StatelessWidget {
  const _InterventionActionButton({
    required this.label,
    required this.subtitle,
    required this.isPrimary,
    required this.primaryColor,
    required this.onPressed,
    this.isWarning = false,
  });

  final String label;
  final String subtitle;
  final bool isPrimary;
  final Color primaryColor;
  final VoidCallback onPressed;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final bgColor = isPrimary
        ? primaryColor
        : (isWarning ? const Color(0xFFFFF0EB) : const Color(0xFFF2FAF5));
    final textColor = isPrimary
        ? AppColors.white
        : (isWarning ? const Color(0xFFB33E00) : primaryColor);
    final borderColor = isPrimary ? primaryColor : (isWarning ? AppColors.sosOrange : primaryColor);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor.withValues(alpha: isPrimary ? 1.0 : 0.6),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.roboto(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: isPrimary
                      ? AppColors.white.withValues(alpha: 0.9)
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
