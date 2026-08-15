import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../widgets/breathing_lotus.dart';

class LotusBreathingScreen extends StatefulWidget {
  const LotusBreathingScreen({super.key});

  @override
  State<LotusBreathingScreen> createState() => _LotusBreathingScreenState();
}

class _LotusBreathingScreenState extends State<LotusBreathingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  String _breathText = '';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.965, end: 1.035)
            .chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 4,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.035),
        weight: 4,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.035, end: 0.965)
            .chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 6,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0.965),
        weight: 2,
      ),
    ]).animate(_controller);

    _controller.addListener(_updateBreathText);
  }

  void _updateBreathText() {
    final seconds = _controller.value * 16.0;
    
    String newText = '';
    if (seconds < 4) {
      newText = 'Bác hít vào từ từ nhé...';
    } else if (seconds < 8) {
      newText = 'Bác nín thở giữ lại chút nào...';
    } else if (seconds < 14) {
      newText = 'Bác thở ra từ từ cùng cháu nhé...';
    } else {
      newText = ''; // Rest
    }
    
    if (newText != _breathText) {
      setState(() {
        _breathText = newText;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateBreathText);
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
          Center(
            child: BreathingLotus(
              scaleAnimation: _scaleAnimation,
            ),
          ),
          
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
                  'Chu kỳ thở 4 - 4 - 6',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                ),
                const Spacer(),
                if (_breathText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
                    child: Text(
                      _breathText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: AppColors.white,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          Positioned(
            top: 48,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.white),
              onPressed: () {
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

