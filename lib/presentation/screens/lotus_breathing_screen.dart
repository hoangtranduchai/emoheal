import 'package:flutter/material.dart';
import '../../core/logger.dart';
import '../../core/theme.dart';
import '../../core/voice_guide.dart';
import '../widgets/breathing_lotus.dart';

/// Màn hình Nhịp thở Hoa Sen (Chu kỳ 4 - 4 - 6 chuẩn y khoa thư giãn)
/// Tự động đồng bộ: Âm thanh chuyển trang -> Hoàn tất -> Video & Nhịp thở & Text & Đếm giây bắt đầu đồng thời.
class LotusBreathingScreen extends StatefulWidget {
  const LotusBreathingScreen({super.key});

  @override
  State<LotusBreathingScreen> createState() => _LotusBreathingScreenState();
}

class _LotusBreathingScreenState extends State<LotusBreathingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  
  String _lotusSubtitle = 'Bác hãy hít vào';
  int _currentPhase = 1;
  bool _isIntroFinished = false;

  @override
  void initState() {
    super.initState();
    AppLogger.i('Bắt đầu phiên "Nhịp thở Hoa Sen" (Chu kỳ thở 4-4-6)', tag: 'BREATHING');
    AppLogger.event('LOTUS_BREATHING_START');

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );

    // Chu kỳ 4s Hít vào -> 4s Giữ hơi -> 6s Thở ra -> 2s Nghỉ
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.94, end: 1.06)
            .chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 4,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.06),
        weight: 4,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.06, end: 0.94)
            .chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 6,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0.94),
        weight: 2,
      ),
    ]).animate(_controller);

    _controller.addListener(_updateBreathingState);

    // Tự động phát âm thanh hướng dẫn mở đầu, khi phát xong mới bắt đầu video và nhịp thở
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VoiceGuide.play(
        VoiceScripts.breathing,
        onComplete: () {
          if (mounted) {
            setState(() {
              _isIntroFinished = true;
              _lotusSubtitle = 'Bác hãy hít vào';
              _currentPhase = 1;
            });
            _controller.repeat();
            _triggerPhaseSpeech(1);
          }
        },
      );
    });
  }

  void _updateBreathingState() {
    if (!_isIntroFinished) return;

    final seconds = _controller.value * 16.0;
    int newPhase = 1;
    String newSubtitle = '';

    if (seconds < 4.0) {
      newPhase = 1;
      newSubtitle = 'Bác hãy hít vào';
    } else if (seconds < 8.0) {
      newPhase = 2;
      newSubtitle = 'Bác nín thở một chút nhé';
    } else if (seconds < 14.0) {
      newPhase = 3;
      newSubtitle = 'Bác hãy từ từ thở ra';
    } else {
      newPhase = 4;
      newSubtitle = 'Bác thả lỏng cơ thể nhé';
    }

    if (newPhase != _currentPhase) {
      setState(() {
        _currentPhase = newPhase;
        _lotusSubtitle = newSubtitle;
      });

      _triggerPhaseSpeech(newPhase);
    }
  }

  void _triggerPhaseSpeech(int phase) {
    if (!mounted || !_isIntroFinished) return;

    switch (phase) {
      case 1:
        VoiceGuide.playBreathingStep(VoiceScripts.breathInhale);
        break;
      case 2:
        VoiceGuide.playBreathingStep(VoiceScripts.breathHold);
        break;
      case 3:
        VoiceGuide.playBreathingStep(VoiceScripts.breathExhale);
        break;
      case 4:
        break;
    }
  }

  @override
  void dispose() {
    VoiceGuide.stop();
    _controller.removeListener(_updateBreathingState);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                const Text(
                  'Nhịp thở Hoa Sen',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Chu kỳ thở 4 - 4 - 6 (Thư giãn & Điều hòa)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFCCCCCC),
                  ),
                ),
                const Spacer(),
                // Video Hoa Sen
                BreathingLotus(
                  scaleAnimation: _isIntroFinished
                      ? _scaleAnimation
                      : const AlwaysStoppedAnimation<double>(1.0),
                  isPlaying: _isIntroFinished,
                ),
                const SizedBox(height: 20),
                // Dòng chữ hướng dẫn màu trắng nằm dưới video, cách video 20px
                SizedBox(
                  height: 56,
                  child: _isIntroFinished && _lotusSubtitle.isNotEmpty
                      ? AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.0, 0.18),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: Container(
                            key: ValueKey<String>(_lotusSubtitle),
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.52),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.28),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              _lotusSubtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.white,
                                letterSpacing: 0.3,
                                height: 1.25,
                                shadows: [
                                  Shadow(
                                    offset: Offset(0, 2),
                                    blurRadius: 8,
                                    color: Colors.black,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const Spacer(),
              ],
            ),
          ),
          
          Positioned(
            top: 48,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.white, size: 28),
              onPressed: () {
                VoiceGuide.stop();
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  Navigator.of(context).pushReplacementNamed('/home');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
