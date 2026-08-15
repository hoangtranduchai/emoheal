import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../router.dart';
import '../widgets/feature_card.dart';
import '../widgets/sos_button.dart';

/// Màn hình Trang chủ — render 100% pixel-perfect theo Frame "Home" (421:1289) trên Figma.
///
/// Layout (top → bottom):
/// 1. Top Header Container (xanh đậm, bo góc 24, có ảnh + text "Kính chào / Bác")
/// 2. SOS Section ("Bác đang cảm thấy bất an?" + nút SOS + "Nhấn và giữ trong 3 giây")
/// 3. Feature Cards Row (Hồi ký Giọng nói + Góc bình yên)
/// 4. Settings Card (Cài đặt & Hỗ trợ tiếp cận)
/// 5. Floating Assistant Bubble (bottom-right)
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    final horizontalPadding = isTablet ? 64.0 : 28.0;
    final cardSpacing = isTablet ? 40.0 : 28.0;
    final topHeaderHeight = isTablet ? 200.0 : 177.0;
    final sosSize = screenWidth * (isTablet ? 0.2 : 0.32);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0), // Figma frame fill
      body: Stack(
        children: [
          // ── Main scrollable content ──
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              children: [
                // ── 1. Top Header ──
                _TopHeader(
                  height: topHeaderHeight,
                  horizontalPadding: horizontalPadding,
                ),

                // ── 2. SOS Section ──
                Padding(
                  padding: EdgeInsets.fromLTRB(horizontalPadding, 32, horizontalPadding, 0),
                  child: _SOSSection(sosSize: sosSize),
                ),

                const SizedBox(height: 20),

                // ── 3. Feature Cards ──
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: isTablet ? 180.0 : 145.5,
                          child: FeatureCard(
                            title: 'Hồi ký\nGiọng nói',
                            svgAsset: 'assets/icons/microphone.svg',
                            onTap: () => Navigator.of(context)
                                .pushNamed(AppRoutes.voiceMemo),
                          ),
                        ),
                      ),
                      SizedBox(width: cardSpacing),
                      Expanded(
                        child: SizedBox(
                          height: isTablet ? 180.0 : 145.5,
                          child: FeatureCard(
                            title: 'Góc bình yên',
                            svgAsset: 'assets/icons/lotus.svg',
                            onTap: () => Navigator.of(context)
                                .pushNamed(AppRoutes.lotusBreathing),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18), // Figma gap ~18px

                // ── 4. Settings Card ──
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: SizedBox(
                    width: double.infinity,
                    height: 95, // Figma: 94.63
                    child: FeatureCard(
                      title: 'Cài đặt & Hỗ trợ tiếp cận',
                      svgAsset: 'assets/icons/setting.svg',
                      isHorizontal: true,
                      isPrimary: false,
                      onTap: () => Navigator.of(context)
                          .pushNamed(AppRoutes.settings),
                    ),
                  ),
                ),

                // Bottom safe area padding
                SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 16),
              ],
            ),
          ),

          // ── 5. Floating Assistant Bubble ──
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: _AssistantBubble(
              onTap: () {
                // TODO: Mở trợ lý AI
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ════════════════════════════════════════════════════════════════════

/// Header xanh đậm ở trên cùng.
/// Figma: Container (421:1367) fill #26591D.
/// Bao gồm ảnh flagpole, star, ellipse, text "Kính chào" và "Bác".
class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.height,
    required this.horizontalPadding,
  });

  final double height;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final totalHeight = height + statusBarHeight;

    return SizedBox(
      height: totalHeight,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Background Container ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: totalHeight,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              child: Container(
                color: const Color(0xFF26591D), // Figma: primaryGreenDark
              ),
            ),
          ),

          // ── Star (Bottom Left of Top Header) ──
          Positioned(
            bottom: 0,
            left: 0,
            child: SvgPicture.asset(
              'assets/icons/star.svg',
            ),
          ),

          // ── Ellipse (Bottom Right of Top Header) ──
          Positioned(
            bottom: 0,
            right: 0,
            child: SvgPicture.asset(
              'assets/icons/ellipse.svg',
            ),
          ),

          // ── Text content ──
          Positioned(
            top: 79.0 + statusBarHeight,
            left: horizontalPadding,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kính chào',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    letterSpacing: 0.24,
                    color: Color(0xFFF9FBEB),
                  ),
                ),
                Text(
                  'Bác',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 48,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: Color(0xFFF9FBEB),
                  ),
                ),
              ],
            ),
          ),

          // ── Flagpole image ──
          Positioned(
            bottom: 0,
            right: horizontalPadding,
            child: Image.asset(
              'assets/images/flagpole_image.png',
              height: 130, // Đặt mức height an toàn vừa vặn trong frame 177/200
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

/// SOS Section: tiêu đề + mô tả + nút SOS + text nhấn giữ.
/// Figma: Group "Nút hỗ trợ khẩn cấp" (2411:662), x=42, y=209, 291×265.
class _SOSSection extends StatelessWidget {
  const _SOSSection({required this.sosSize});

  final double sosSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Bác đang cảm thấy bất an?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 24,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Hãy nhấn gọi để được chuyên gia\ny tế hỗ trợ.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.5,
            color: Color(0x99111111), // 60% opacity
          ),
        ),
        const SizedBox(height: 16),
        SOSButton(size: sosSize),
        const SizedBox(height: 12),
        const Text(
          'Nhấn và giữ trong 3 giây',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.5,
            color: Color(0x99111111),
          ),
        ),
      ],
    );
  }
}

/// Nút trợ lý AI hình tròn, góc dưới bên phải.
/// Figma: Group "Trợ lý" (2678:313), Ellipse 64×64, fill #E0F4C8 @ 20% opacity.
class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFE0F4C8), // Figma: assistantBubble
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF469D60).withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(
          Icons.headset_mic_rounded,
          color: Color(0xFF3C7232),
          size: 30,
        ),
      ),
    );
  }
}
