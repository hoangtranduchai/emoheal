import 'dart:ui';

import 'package:flutter/material.dart';
import '../../core/theme.dart';

class BreathingLotus extends StatelessWidget {
  const BreathingLotus({
    super.key,
    required this.scaleAnimation,
  });

  final Animation<double> scaleAnimation;

  static const String imageUrl = 'assets/images/breathing_lotus.png';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: scaleAnimation.value,
          child: child,
        );
      },
      child: Container(
        width: 327,
        height: 452,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: AppColors.black66,
              blurRadius: 40,
              offset: Offset(0, 18),
            ),
          ],
          image: const DecorationImage(
            image: AssetImage(imageUrl),
            fit: BoxFit.cover,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.transparent,
                    AppColors.black12,
                    AppColors.black7A,
                    AppColors.deepBlackDark,
                  ],
                  stops: [0.0, 0.55, 0.82, 1.0],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
