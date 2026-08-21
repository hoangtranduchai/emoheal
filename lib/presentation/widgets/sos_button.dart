import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';


class SOSButton extends StatefulWidget {
  final double size;
  
  const SOSButton({
    super.key,
    this.size = 120.0,
  });

  @override
  State<SOSButton> createState() => _SOSButtonState();
}

class _SOSButtonState extends State<SOSButton> with TickerProviderStateMixin {
  late AnimationController _rippleController;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    
    // Ripple Animation (Infinite)
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Progress Animation (3 seconds)
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _progressController,
        curve: Curves.linear,
      ),
    );

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        _makeEmergencyCall();
        _progressController.reset();
      }
    });

    _progressController.addListener(() {
      // Provide light haptic feedback occasionally while holding
      if (_progressController.value > 0.0 &&
          _progressController.value < 1.0 &&
          (_progressController.value * 10).toInt() % 3 == 0) {
        // Just an example, maybe better to just vibrate on start and end
      }
    });
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _onPointerDown() {
    HapticFeedback.mediumImpact();
    _progressController.forward();
  }

  void _onPointerUp() {
    _progressController.reverse();
  }

  void _onPointerCancel() {
    _progressController.reverse();
  }

  Future<void> _makeEmergencyCall() async {
    final Uri url = Uri.parse('tel:115');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể thực hiện cuộc gọi. Vui lòng quay số 115 thủ công.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _onPointerDown(),
      onPointerUp: (_) => _onPointerUp(),
      onPointerCancel: (_) => _onPointerCancel(),
      child: SizedBox(
        width: widget.size * 1.5,
        height: widget.size * 1.5,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ripples
            ...List.generate(3, (index) {
              return AnimatedBuilder(
                animation: _rippleController,
                builder: (context, child) {
                  // Offset each ripple by a fraction
                  double progress = (_rippleController.value + (index * 0.33)) % 1.0;
                  return Opacity(
                    opacity: 1.0 - progress,
                    child: Transform.scale(
                      scale: 1.0 + (progress * 0.5),
                      child: Container(
                        width: widget.size,
                        height: widget.size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.sosOrangeLight2.withAlpha(77), // 0.3 * 255
                        ),
                      ),
                    ),
                  );
                },
              );
            }),

            // Progress Ring
            AnimatedBuilder(
              animation: _progressAnimation,
              builder: (context, child) {
                return SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: CircularProgressIndicator(
                    value: _progressAnimation.value,
                    strokeWidth: 16,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.redAccent),
                    backgroundColor: AppColors.transparent,
                  ),
                );
              },
            ),

            // Main Button
            Container(
              width: widget.size,
              height: widget.size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.sosGradientStart,
                    AppColors.sosGradientEnd,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.sosGradientEnd66,
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'SOS',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: widget.size * 0.35,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
