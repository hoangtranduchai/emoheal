import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../router.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static const String backgroundImageUrl =
      'assets/images/onboarding_bg.png';

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final imageHeight = size.width * (442 / 375);
    
    // Đảm bảo bóng luôn đè lên ảnh tối thiểu 200px để tạo độ mượt.
    // Nếu màn hình quá ngắn (bị thu nhỏ chiều cao), đẩy bóng lên cao hơn (size.height - 380)
    // để đảm bảo chữ luôn nằm trên nền tối và dễ đọc.
    final shadowTop = math.min(imageHeight - 160, size.height - 380);

    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image (chạy full bề ngang, chiều cao giữ đúng tỷ lệ)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: imageHeight,
            child: Image.asset(
              backgroundImageUrl,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (context, error, stackTrace) {
                return Container(color: AppColors.black);
              },
            ),
          ),
          
          // Shadow Container (Bóng mờ đè lên ảnh)
          Positioned(
            top: shadowTop,
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Phần Gradient mờ dần từ trong suốt sang đen (dài 200px)
                Container(
                  height: 160,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.transparentBlack, // Trong suốt
                        AppColors.deepBlack, // Đen
                      ],
                    ),
                  ),
                ),
                // Phần còn lại đổ full đen tuyền
                Expanded(
                  child: Container(color: AppColors.deepBlack),
                ),
              ],
            ),
          ),
          
          // Content (Nội dung chữ và nút)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'HÀNH TRÌNH TRI ÂN & CHỮA LÀNH',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: AppColors.golden, // Golden color from Figma
                      letterSpacing: 0.16,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Kính chào bác. Đây là không gian an toàn để bác chia sẻ và thư giãn tâm hồn của mình.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      color: AppColors.lightGrey,
                      letterSpacing: 0.09,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    height: 68,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: AppColors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'BẮT ĐẦU NGAY',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16), // Bottom spacing for Home Indicator
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
