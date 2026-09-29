import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/logger.dart';
import '../../core/theme.dart';
import '../../data/live_voice_service.dart';
import '../../data/supabase_service.dart';
import '../../router.dart';

/// Nút Bong bóng "Bạn đồng hành" / "Đang lắng nghe"
/// Thiết kế chuẩn Zero-Barrier cho người cao tuổi:
/// - Bình thường: Vòng tròn Avatar nhịp đập + Huy hiệu chữ "Bạn đồng hành" nền xanh đậm chữ trắng.
/// - Khi hoạt động: Chuyển chữ thành "Đang lắng nghe" / "Đang nói", icon đổi thành sóng âm động (không hiện popup).
/// - Chạm nhẹ (Tap): Bật/Tắt đàm thoại trực tiếp hai chiều với Gemini Live API và điều khiển app bằng giọng nói.
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
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final LiveVoiceService _liveService = LiveVoiceService();
  StreamSubscription<LiveVoiceState>? _stateSub;
  LiveVoiceState _voiceState = LiveVoiceState.idle;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _voiceState = _liveService.state;
    _stateSub = _liveService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _voiceState = state;
        });
      }
    });

    _liveService.onToolCall = (name, args) {
      _handleLiveToolCall(name, args);
    };
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // Khởi động hoặc dừng phiên Live Voice đàm thoại trực tiếp
  Future<void> _toggleLiveVoiceSession() async {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }

    if (_liveService.isActive) {
      AppLogger.i('🛑 Bác chạm vào nút -> Dừng phiên đàm thoại Live', tag: 'ASSISTANT');
      await _liveService.stopSession();
      return;
    }

    AppLogger.i('🎙️ Bác chạm vào Bạn đồng hành -> Khởi động Gemini Live API trực tiếp', tag: 'ASSISTANT');

    // Lấy giọng đọc người dùng đã chọn trong Cài đặt (mặc định aoede)
    String selectedVoice = 'aoede';
    try {
      final settings = await SupabaseService().getUserSettings();
      selectedVoice = (settings['voice_type'] ?? 'aoede').toString();
    } catch (_) {}

    // Bắt đầu phiên Live Voice trực tiếp không cần mở Pop-up
    await _liveService.startSession(voice: selectedVoice);
  }

  // Xử lý Function Calling (Spoken-First Tool Execution)
  void _handleLiveToolCall(String name, Map<String, dynamic> args) {
    AppLogger.i('🛠️ Thực thi Tool Calling từ giọng nói: $name (Đối số: $args)', tag: 'ASSISTANT');

    // Chờ 1.2s để Bác nghe câu xác nhận ân cần từ AI trước khi chuyển màn hình
    Future.delayed(const Duration(milliseconds: 1200), () {
      final navState = AppRouter.navigatorKey.currentState;
      final navContext = AppRouter.navigatorKey.currentContext;

      switch (name) {
        case 'start_breathing_exercise':
          AppLogger.nav(AppRoutes.lotusBreathing, arguments: 'Live tool: start_breathing_exercise');
          navState?.pushNamed(AppRoutes.lotusBreathing);
          break;

        case 'open_radio':
          AppLogger.nav(AppRoutes.radio, arguments: 'Live tool: open_radio');
          navState?.pushNamed(AppRoutes.radio);
          break;

        case 'open_voice_memo':
          AppLogger.nav(AppRoutes.voiceMemo, arguments: 'Live tool: open_voice_memo');
          navState?.pushNamed(AppRoutes.voiceMemo);
          break;

        case 'open_history':
          AppLogger.nav(AppRoutes.history, arguments: 'Live tool: open_history');
          navState?.pushNamed(AppRoutes.history);
          break;

        case 'open_settings':
          AppLogger.nav(AppRoutes.settings, arguments: 'Live tool: open_settings');
          navState?.pushNamed(AppRoutes.settings);
          break;

        case 'translate_speech':
          AppLogger.i('🗣️ Chuyển sang chế độ phiên dịch đàm thoại', tag: 'ASSISTANT');
          break;

        case 'navigate_to_screen':
          final target = (args['screen'] as String?)?.toLowerCase() ?? 'home';
          if (target == 'voice_memo' || target == 'voice-memo') {
            AppLogger.nav(AppRoutes.voiceMemo);
            navState?.pushNamed(AppRoutes.voiceMemo);
          } else if (target == 'radio') {
            AppLogger.nav(AppRoutes.radio);
            navState?.pushNamed(AppRoutes.radio);
          } else if (target == 'breathing' || target == 'lotus_breathing') {
            AppLogger.nav(AppRoutes.lotusBreathing);
            navState?.pushNamed(AppRoutes.lotusBreathing);
          } else if (target == 'settings') {
            AppLogger.nav(AppRoutes.settings);
            navState?.pushNamed(AppRoutes.settings);
          } else if (target == 'history') {
            AppLogger.nav(AppRoutes.history);
            navState?.pushNamed(AppRoutes.history);
          } else {
            AppLogger.nav(AppRoutes.home);
            navState?.pushNamed(AppRoutes.home);
          }
          break;

        case 'trigger_sos_emergency':
          AppLogger.e('🚨 Kích hoạt SOS từ lệnh thoại AI!', tag: 'ASSISTANT');
          if (navContext != null && navContext.mounted) {
            ScaffoldMessenger.of(navContext).showSnackBar(
              const SnackBar(
                content: Text(
                  'Hệ thống đang kết nối liên hệ khẩn cấp cho Bác...',
                  style: TextStyle(fontFamily: 'Roboto', fontSize: 18, fontWeight: FontWeight.w600),
                ),
                backgroundColor: AppColors.sosOrange,
                duration: Duration(seconds: 4),
              ),
            );
          }
          break;
      }
    });
  }

  String _getBadgeText() {
    switch (_voiceState) {
      case LiveVoiceState.listening:
        return 'Đang lắng nghe';
      case LiveVoiceState.speaking:
        return 'Đang nói';
      case LiveVoiceState.connecting:
        return 'Đang kết nối';
      case LiveVoiceState.error:
        return 'Thử lại';
      case LiveVoiceState.idle:
        return 'Bạn đồng hành';
    }
  }

  Color _getBadgeColor() {
    switch (_voiceState) {
      case LiveVoiceState.listening:
        return AppColors.sosOrange;
      case LiveVoiceState.speaking:
      case LiveVoiceState.idle:
        return AppColors.primaryGreenDark;
      case LiveVoiceState.connecting:
        return Colors.blue.shade800;
      case LiveVoiceState.error:
        return Colors.red.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isActive = _voiceState == LiveVoiceState.listening ||
        _voiceState == LiveVoiceState.speaking ||
        _voiceState == LiveVoiceState.connecting;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: isActive ? _pulseAnimation.value : 1.0,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: _toggleLiveVoiceSession,
        child: SizedBox(
          width: 114.0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _getBadgeColor(),
                    width: 2.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _getBadgeColor().withValues(alpha: isActive ? 0.45 : 0.25),
                      blurRadius: isActive ? 12 : 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: isActive
                      ? _WaveformIndicator(
                          color: _getBadgeColor(),
                          animation: _pulseAnimation,
                        )
                      : ClipOval(
                          child: Image.asset(
                            'assets/icons/support.gif',
                            width: 46,
                            height: 46,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.smart_toy_rounded,
                              color: AppColors.primaryGreenDark,
                              size: 32,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                decoration: BoxDecoration(
                  color: _getBadgeColor(),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x28000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _getBadgeText(),
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 12.0,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
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

/// Icon sóng âm động cho trạng thái Đang lắng nghe / Đang nói
class _WaveformIndicator extends StatelessWidget {
  final Color color;
  final Animation<double> animation;

  const _WaveformIndicator({required this.color, required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = animation.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _bar(10 + 8 * v, color),
            const SizedBox(width: 3),
            _bar(16 + 14 * (1 - v), color),
            const SizedBox(width: 3),
            _bar(26 + 10 * v, color),
            const SizedBox(width: 3),
            _bar(16 + 14 * (1 - v), color),
            const SizedBox(width: 3),
            _bar(10 + 8 * v, color),
          ],
        );
      },
    );
  }

  Widget _bar(double height, Color color) {
    return Container(
      width: 4,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
