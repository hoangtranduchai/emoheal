import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/live_voice_service.dart';
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

  LiveVoiceState _voiceState = LiveVoiceState.idle;
  String _userTranscript = '';
  String _aiTranscript = '';
  bool _dismissedBanner = false;

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
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _inputSub?.cancel();
    _outputSub?.cancel();
    _snapController.dispose();
    super.dispose();
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
      ],
    );
  }
}
