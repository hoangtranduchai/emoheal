import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/logger.dart';
import '../../core/theme.dart';
import '../../core/voice_command_bus.dart';
import '../../data/live_voice_service.dart';
import '../../data/supabase_service.dart';
import '../../router.dart';
import 'assistant_bubble.dart';

/// Nút "Bạn đồng hành" Toàn Cục (Global Draggable Assistant Button & AI Subtitle Box)
/// Xuất hiện trên 100% tất cả các màn hình của EmoHeal:
/// - Vị trí mặc định: Góc Dưới Bên Phải (right: 28px, bottom: 96px phía trên thanh điều hướng).
/// - Hỗ trợ kéo thả (Draggable): Bác có thể tự do di chuyển sang trái/phải/lên/xuống để tránh che nút bấm khác.
/// - Tự động hít (Snap): Khi thả tay, nút tự động trượt nhẹ và bám vào mép màn hình gần nhất.
/// - Văn bản lời nói của AI: Khung hình chữ nhật bo góc 342px x 100px ở giữa và phía dưới màn hình, nền xanh đậm, chữ trắng.
class GlobalDraggableAssistant extends StatefulWidget {
  const GlobalDraggableAssistant({super.key});

  @override
  State<GlobalDraggableAssistant> createState() => _GlobalDraggableAssistantState();
}

class _GlobalDraggableAssistantState extends State<GlobalDraggableAssistant> with SingleTickerProviderStateMixin {
  Offset? _offset;
  late AnimationController _snapController;
  Animation<Offset>? _snapAnimation;

  final LiveVoiceService _liveService = LiveVoiceService();
  StreamSubscription<LiveVoiceState>? _stateSub;
  StreamSubscription<String>? _inputSub;
  StreamSubscription<String>? _outputSub;
  StreamSubscription<VoiceNavigationCommand>? _navSub;
  StreamSubscription<VoiceSosCommand>? _sosSub;
  StreamSubscription<VoiceSettingsCommand>? _settingsSub;

  LiveVoiceState _voiceState = LiveVoiceState.idle;
  String _userTranscript = '';
  String _aiTranscript = '';
  bool _dismissedBanner = false;

  // Trạng thái đếm ngược SOS khẩn cấp bằng giọng nói
  bool _isSosActive = false;
  int _sosCountdown = 3;
  String _sosReason = '';
  Timer? _sosTimer;

  static const double _bubbleWidth = 114.0;
  static const double _bubbleHeight = 92.0;
  static const double _edgeMargin = 16.0;
  static const double _bottomMargin = 96.0;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_snapAnimation != null) {
          setState(() {
            _offset = _snapAnimation!.value;
          });
        }
      });

    _voiceState = _liveService.state;
    _stateSub = _liveService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _voiceState = state;
          if (state == LiveVoiceState.idle) {
            _dismissedBanner = false;
            _userTranscript = '';
            _aiTranscript = '';
          }
        });
      }
    });

    _inputSub = _liveService.inputTranscriptStream.listen((text) {
      if (mounted) {
        setState(() {
          _userTranscript = text;
          _dismissedBanner = false;
        });
      }
    });

    _outputSub = _liveService.outputTranscriptStream.listen((text) {
      if (mounted) {
        setState(() {
          _aiTranscript = text;
          _dismissedBanner = false;
        });
      }
    });

    // Lắng nghe lệnh điều hướng toàn cục từ giọng nói
    _navSub = VoiceCommandBus().navigationCommands.listen((cmd) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        final navState = AppRouter.navigatorKey.currentState;
        if (cmd.targetRoute == AppRoutes.home) {
          navState?.popUntil((route) => route.isFirst);
        } else {
          navState?.pushNamed(cmd.targetRoute);
        }
      });
    });

    // Lắng nghe lệnh kích hoạt khẩn cấp SOS bằng giọng nói
    _sosSub = VoiceCommandBus().sosCommands.listen((cmd) {
      if (mounted) {
        _triggerSosEmergency(cmd.reason, cmd.countdownSeconds);
      }
    });

    // Lắng nghe lệnh thay đổi cài đặt bằng giọng nói
    _settingsSub = VoiceCommandBus().settingsCommands.listen((cmd) {
      if (cmd.fontDelta != null) {
        _handleFontDelta(cmd.fontDelta!);
      }
      if (cmd.voiceType != null) {
        _handleVoiceType(cmd.voiceType!);
      }
    });
  }

  @override
  void dispose() {
    _navSub?.cancel();
    _sosSub?.cancel();
    _settingsSub?.cancel();
    _sosTimer?.cancel();
    _stateSub?.cancel();
    _inputSub?.cancel();
    _outputSub?.cancel();
    _snapController.dispose();
    super.dispose();
  }

  void _triggerSosEmergency(String reason, int countdownSeconds) {
    _sosTimer?.cancel();
    setState(() {
      _isSosActive = true;
      _sosCountdown = countdownSeconds;
      _sosReason = reason;
    });

    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_sosCountdown <= 1) {
        timer.cancel();
        setState(() {
          _isSosActive = false;
        });
        _executeEmergencyCall();
      } else {
        setState(() {
          _sosCountdown--;
        });
      }
    });
  }

  void _cancelSosEmergency() {
    _sosTimer?.cancel();
    setState(() {
      _isSosActive = false;
    });
    AppLogger.i('🛑 Bác đã bấm hủy cuộc gọi khẩn cấp SOS', tag: 'SOS');
  }

  Future<void> _executeEmergencyCall() async {
    AppLogger.e('🚨 Hết 3 giây đếm ngược -> Bắt đầu quay số khẩn cấp!', tag: 'SOS');
    String phoneToCall = '115';
    try {
      final contacts = await SupabaseService().getEmergencyContacts();
      if (contacts.isNotEmpty) {
        final firstPhone = contacts.first['contact_phone']?.toString();
        if (firstPhone != null && firstPhone.trim().isNotEmpty) {
          phoneToCall = firstPhone.trim();
        }
      }
    } catch (_) {}

    final cleanPhone = phoneToCall.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      AppLogger.e('Lỗi quay số gọi khẩn cấp: $e', tag: 'SOS');
    }
  }

  Future<void> _handleFontDelta(double delta) async {
    try {
      final settings = await SupabaseService().getUserSettings();
      double currentScale = (settings['font_size_scale'] as num?)?.toDouble() ?? 1.15;
      double newScale = (currentScale + delta).clamp(1.0, 1.6);
      await SupabaseService().saveUserSettings(fontSizeScale: newScale);
      AppLogger.i('Cập nhật cỡ chữ qua giọng nói: $newScale', tag: 'SETTINGS');
    } catch (e) {
      AppLogger.w('Lỗi chỉnh cỡ chữ: $e', tag: 'SETTINGS');
    }
  }

  Future<void> _handleVoiceType(String voiceType) async {
    try {
      await SupabaseService().saveUserSettings(voiceType: voiceType);
      AppLogger.i('Cập nhật giọng đọc qua giọng nói: $voiceType', tag: 'SETTINGS');
    } catch (e) {
      AppLogger.w('Lỗi đổi giọng đọc: $e', tag: 'SETTINGS');
    }
  }

  void _snapToNearestEdge(Size screenSize, EdgeInsets padding) {
    if (_offset == null || screenSize.width <= 0 || screenSize.height <= 0) return;

    const double minX = _edgeMargin;
    final double maxX = (screenSize.width - _bubbleWidth - _edgeMargin).clamp(minX, double.infinity);
    final double minY = padding.top + 8.0;
    final double maxY = (screenSize.height - _bubbleHeight - padding.bottom - 16.0).clamp(minY, double.infinity);

    // Xác định mép gần nhất (trái hoặc phải) dựa theo tâm của nút
    final double centerX = _offset!.dx + _bubbleWidth / 2;
    final double targetX = (centerX < screenSize.width / 2) ? minX : maxX;
    final double targetY = _offset!.dy.clamp(minY, maxY);

    final targetOffset = Offset(targetX, targetY);

    _snapAnimation = Tween<Offset>(
      begin: _offset,
      end: targetOffset,
    ).animate(CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic));

    _snapController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final viewInsets = MediaQuery.of(context).viewInsets;

    // Không tính toán vị trí nếu kích thước màn hình chưa được layout
    if (screenSize.width <= 0 || screenSize.height <= 0) {
      return const SizedBox.shrink();
    }

    const double minX = _edgeMargin;
    final double maxX = (screenSize.width - _bubbleWidth - _edgeMargin).clamp(minX, double.infinity);
    final double minY = padding.top + 8.0;
    final double maxY = (screenSize.height - _bubbleHeight - padding.bottom - viewInsets.bottom - 16.0).clamp(minY, double.infinity);

    // Vị trí mặc định chuẩn: Góc Dưới Bên Phải (Right: _edgeMargin, Bottom: _bottomMargin)
    _offset ??= Offset(
      maxX,
      (screenSize.height - _bubbleHeight - padding.bottom - _bottomMargin).clamp(minY, maxY),
    );

    final currentX = _offset!.dx.clamp(minX, maxX);
    final currentY = _offset!.dy.clamp(minY, maxY);

    // Chiều rộng hộp phụ đề: 342px (hoặc tối đa chiều rộng màn hình - 24px trên màn hình nhỏ)
    final double bannerWidth = math.min(342.0, screenSize.width - 24.0);
    const double bannerHeight = 100.0;

    final bool isLiveActive = _voiceState != LiveVoiceState.idle && !_dismissedBanner;

    return Stack(
      children: [
        // ── 1. Khung Văn Bản Lời Nói Của AI (342px x 100px, Nền xanh đậm, Chữ trắng) ──
        if (isLiveActive)
          Positioned(
            left: (screenSize.width - bannerWidth) / 2,
            bottom: padding.bottom + 16.0,
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                width: bannerWidth,
                height: bannerHeight,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreenDark,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Stack(
                  children: [
                    // Nội dung văn bản
                    Positioned.fill(
                      right: 28,
                      child: Center(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Text(
                            _aiTranscript.isNotEmpty
                                ? _aiTranscript
                                : (_userTranscript.isNotEmpty
                                    ? '🗣️ Bác: "$_userTranscript"'
                                    : (_voiceState == LiveVoiceState.connecting
                                        ? 'Đang kết nối cùng Bác...'
                                        : '🌸 Cháu đang lắng nghe Bác tâm sự ạ...')),
                            textAlign: TextAlign.left,
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Nút thu nhỏ / đóng phụ đề
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _dismissedBanner = true;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── 2. Nút "Bạn đồng hành" Kéo / Thả Nổi ──
        Positioned(
          left: currentX,
          top: currentY,
          child: GestureDetector(
            onPanStart: (_) {
              _snapController.stop();
            },
            onPanUpdate: (details) {
              setState(() {
                final newX = (currentX + details.delta.dx).clamp(minX, maxX);
                final newY = (currentY + details.delta.dy).clamp(minY, maxY);
                _offset = Offset(newX, newY);
              });
            },
            onPanEnd: (_) {
              _snapToNearestEdge(screenSize, padding);
            },
            child: const Material(
              type: MaterialType.transparency,
              child: AssistantBubble(),
            ),
          ),
        ),

        // ── 3. Khung Cảnh Báo Khẩn Cấp SOS (Đếm ngược 3 giây an toàn) ──
        if (_isSosActive)
          Positioned.fill(
            child: Material(
              color: Colors.black.withValues(alpha: 0.65),
              child: Center(
                child: Container(
                  width: math.min(360.0, screenSize.width - 32.0),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.sosOrange, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66D97750),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: AppColors.sosOrangeLight,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$_sosCountdown',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: AppColors.sosOrange,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'CẢNH BÁO KHẨN CẤP',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.sosOrange,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _sosReason.isNotEmpty ? _sosReason : 'Trợ lý đang kích hoạt cuộc gọi trợ giúp y tế...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tự động gọi khẩn cấp sau $_sosCountdown giây...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _cancelSosEmergency,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4A4A4A),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                          ),
                          icon: const Icon(Icons.close_rounded, size: 28),
                          label: const Text(
                            'HỦY GỌI KHẨN CẤP',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
