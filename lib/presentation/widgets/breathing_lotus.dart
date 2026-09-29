import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../core/logger.dart';
import '../../core/theme.dart';

class BreathingLotus extends StatefulWidget {
  const BreathingLotus({
    super.key,
    required this.scaleAnimation,
    this.subtitleText,
    this.isPlaying = true,
  });

  final Animation<double> scaleAnimation;
  final String? subtitleText;
  final bool isPlaying;

  static const String imageUrl = 'assets/images/breathing_lotus.png';
  static const String videoAndroid = 'assets/videos/lotus-flower-video-background-Android.mp4';
  static const String videoIOS = 'assets/videos/lotus-flower-video-background-iOS.mp4';

  @override
  State<BreathingLotus> createState() => _BreathingLotusState();
}

class _BreathingLotusState extends State<BreathingLotus> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void didUpdateWidget(covariant BreathingLotus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying && _videoController != null && _isVideoInitialized) {
      if (widget.isPlaying) {
        _videoController!.seekTo(Duration.zero);
        _videoController!.play();
      } else {
        _videoController!.pause();
        _videoController!.seekTo(Duration.zero);
      }
    }
  }

  Future<void> _initVideo() async {
    try {
      final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
      final videoAsset = isIOS ? BreathingLotus.videoIOS : BreathingLotus.videoAndroid;

      final controller = VideoPlayerController.asset(
        videoAsset,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0.0); // Muted background video / Video nền không tiếng

      if (widget.isPlaying) {
        await controller.play();
      } else {
        await controller.pause();
        await controller.seekTo(Duration.zero);
      }

      // Đảm bảo video tự động chạy tiếp liên tục nếu bài tập đang diễn ra mà bị ngắt
      controller.addListener(() {
        if (mounted && widget.isPlaying && controller.value.isInitialized && !controller.value.isPlaying) {
          controller.play();
        }
      });

      if (mounted) {
        setState(() {
          _videoController = controller;
          _isVideoInitialized = true;
        });
        AppLogger.i('Khởi tạo VideoPlayer hoa sen (H.264 & MixWithOthers) thành công', tag: 'BREATHING');
      } else {
        controller.dispose();
      }
    } catch (e) {
      AppLogger.e('Lỗi khởi tạo VideoPlayer hoa sen ($e), chuyển sang ảnh tĩnh dự phòng', tag: 'BREATHING', error: e);
      if (mounted) {
        setState(() => _isVideoInitialized = false);
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.scaleAnimation.value,
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
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── 1. Video or Image Background ──
              if (_isVideoInitialized && _videoController != null)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController!.value.size.width > 0 ? _videoController!.value.size.width : 327,
                    height: _videoController!.value.size.height > 0 ? _videoController!.value.size.height : 452,
                    child: VideoPlayer(_videoController!),
                  ),
                )
              else
                Image.asset(
                  BreathingLotus.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: AppColors.primaryGreenDark,
                    child: const Icon(Icons.spa_rounded, color: AppColors.white, size: 80),
                  ),
                ),

              // ── 2. Calming Gradient Overlay ──
              Container(
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
            ],
          ),
        ),
      ),
    );
  }
}
