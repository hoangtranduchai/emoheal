import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';

class LotusBreathingScreen extends StatefulWidget {
  const LotusBreathingScreen({super.key});

  @override
  State<LotusBreathingScreen> createState() => _LotusBreathingScreenState();
}

class _LotusBreathingScreenState extends State<LotusBreathingScreen> {
  late VideoPlayerController _controller;
  String _breathText = '';
  
  @override
  void initState() {
    super.initState();
    String videoAsset = 'assets/videos/lotus-flower-video-background-Android.mp4';
    if (!kIsWeb && Platform.isIOS) {
      videoAsset = 'assets/videos/lotus-flower-video-background-iOS.mp4';
    }
    
    _controller = VideoPlayerController.asset(videoAsset)
      ..initialize().then((_) {
        _controller.setLooping(true);
        _controller.play();
        setState(() {});
      });

    _controller.addListener(_updateBreathText);
  }

  void _updateBreathText() {
    final position = _controller.value.position.inMilliseconds;
    final seconds = (position / 1000.0) % 16.0;
    
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
          if (_controller.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: VideoPlayer(_controller),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
          
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
                Text(
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
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
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
