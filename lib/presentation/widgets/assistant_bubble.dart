import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/theme.dart';
import '../../data/api_service.dart';
import '../../router.dart';

/// Nút Trợ lý AI hình tròn 64x64dp — Voice-First Overlay
/// Tuân thủ nghiêm ngặt ai_architecture.md và ui_components.md
class AssistantBubble extends StatefulWidget {
  final VoidCallback? onTap;

  const AssistantBubble({
    super.key,
    this.onTap,
  });

  @override
  State<AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<AssistantBubble> with SingleTickerProviderStateMixin {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isRecording = false;
  bool _isProcessing = false;
  Timer? _silenceTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _pulseController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // Bắt đầu / dừng ghi âm khi Bác chạm vào nút Trợ lý
  Future<void> _toggleRecording() async {
    if (_isProcessing) return;

    if (_isRecording) {
      await _stopAndSendAudio();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        setState(() {
          _isRecording = true;
        });
        _pulseController.repeat(reverse: true);

        // Quy tắc "No Dead-Ends": Tự động dừng sau 5 giây nếu không nói
        _silenceTimer?.cancel();
        _silenceTimer = Timer(const Duration(seconds: 5), () {
          if (_isRecording && mounted) {
            _stopAndSendAudio();
          }
        });

        await _audioRecorder.start(const RecordConfig(), path: '');
      } else {
        // Nếu chưa cấp quyền mic, chuyển sang trang Chat để Bác có thể nhập chữ
        if (widget.onTap != null) {
          widget.onTap!();
        } else {
          Navigator.of(context).pushNamed(AppRoutes.chat);
        }
      }
    } catch (e) {
      setState(() => _isRecording = false);
      _pulseController.stop();
    }
  }

  Future<void> _stopAndSendAudio() async {
    _silenceTimer?.cancel();
    _pulseController.stop();
    _pulseController.reset();

    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });

      if (path != null && path.isNotEmpty) {
        final response = await ApiService.sendAssistantRequest(audioPath: path);
        _handleAssistantResponse(response);
      }
    } catch (e) {
      debugPrint('Lỗi xử lý Trợ lý: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _handleAssistantResponse(Map<String, dynamic> response) async {
    final intent = response['intent'] as String?;
    final text = response['text'] as String?;
    final target = response['target'] as String?;
    final audioUrl = response['audio_url'] as String?;

    // 1. Phát âm thanh phản hồi từ AI
    if (audioUrl != null && audioUrl.isNotEmpty) {
      final fullAudioUrl = audioUrl.startsWith('http') 
          ? audioUrl 
          : '${ApiService.baseUrl}$audioUrl';
      try {
        await _audioPlayer.play(UrlSource(fullAudioUrl));
      } catch (e) {
        debugPrint('Lỗi phát âm thanh: $e');
      }
    }

    // 2. Hiển thị thông điệp ngắn ân cần cho Bác
    if (text != null && text.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text,
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: AppColors.primaryGreenDark,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }

    // 3. Tự động điều hướng theo Intent
    if (!mounted) return;
    if (intent == 'PANIC' || target == 'breathing') {
      Navigator.of(context).pushNamed(AppRoutes.lotusBreathing);
    } else if (target == 'radio') {
      Navigator.of(context).pushNamed(AppRoutes.radio);
    } else if (target == 'voice-memo' || target == 'voice_memos') {
      Navigator.of(context).pushNamed(AppRoutes.voiceMemo);
    } else if (target == 'settings') {
      Navigator.of(context).pushNamed(AppRoutes.settings);
    } else if (target == 'home') {
      Navigator.of(context).pushNamed(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isRecording ? _pulseAnimation.value : 1.0,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: _toggleRecording,
        onLongPress: () {
          if (widget.onTap != null) {
            widget.onTap!();
          } else {
            Navigator.of(context).pushNamed(AppRoutes.chat);
          }
        },
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: _isRecording 
                ? AppColors.sosOrange 
                : AppColors.backgroundLight,
            shape: BoxShape.circle,
            border: Border.all(
              color: _isRecording ? Colors.white : AppColors.primaryGreen,
              width: 2.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: _isProcessing
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: AppColors.primaryGreen,
                      strokeWidth: 3,
                    ),
                  )
                : _isRecording
                    ? const Icon(Icons.mic, color: Colors.white, size: 32)
                    : ClipOval(
                        child: Image.asset(
                          'assets/icons/support.gif',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.smart_toy_rounded,
                            color: AppColors.primaryGreen,
                            size: 32,
                          ),
                        ),
                      ),
          ),
        ),
      ),
    );
  }
}
