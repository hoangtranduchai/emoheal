import 'dart:ui';

import 'package:flutter/material.dart';

class BreathingLotus extends StatefulWidget {
  const BreathingLotus({super.key});

  static const String imageUrl =
      'https://www.figma.com/api/mcp/asset/88a4cf09-4520-4fe5-8101-dbf84bb9a4a1.png';

  @override
  State<BreathingLotus> createState() => _BreathingLotusState();
}

class _BreathingLotusState extends State<BreathingLotus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.965, end: 1.035).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value,
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
              color: Color(0x66000000),
              blurRadius: 40,
              offset: Offset(0, 18),
            ),
          ],
          image: const DecorationImage(
            image: NetworkImage(BreathingLotus.imageUrl),
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
                    Colors.transparent,
                    Color(0x12000000),
                    Color(0x7A000000),
                    Color(0xFF08080A),
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
