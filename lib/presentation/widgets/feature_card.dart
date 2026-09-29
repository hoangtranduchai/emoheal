import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme.dart';


/// Thẻ chức năng tái sử dụng cho màn hình Home.
///
/// Figma specs:
/// - Fill: #F7F5F0 (backgroundLight)
/// - Corner radius: 12
/// - Primary stroke: LinearGradient from #72CE50 → #469D60 (top→bottom)
/// - Secondary stroke: Solid #A2A2A2
/// - Shadow: drop-shadow(0px 4px 15px rgba(0,0,0,0.1))
class FeatureCard extends StatelessWidget {
  final String title;
  final String svgAsset;
  final VoidCallback onTap;
  final bool isHorizontal;
  final bool isPrimary;

  const FeatureCard({
    super.key,
    required this.title,
    required this.svgAsset,
    required this.onTap,
    this.isHorizontal = false,
    this.isPrimary = true,
  });

  @override
  Widget build(BuildContext context) {
    // Figma: text fill r:0.067 = #111111
    const textStyle = TextStyle(
      fontFamily: 'Roboto',
      fontSize: 16,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    );

    // Figma: icon color from gradient stop colors
    final iconColor =
        isPrimary ? AppColors.primaryGreenLight : AppColors.darkGrey;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        // Shadow: Figma drop_shadow blur 15, offset(0,4), rgba(0,0,0,0.1)
        boxShadow: const [
          BoxShadow(
            color: AppColors.black1A, // 10% opacity
            blurRadius: 15,
            spreadRadius: 0,
            offset: Offset(0, 4),
          ),
        ],
        // Outer container acts as the gradient/solid border
        gradient: isPrimary
            ? const LinearGradient(
                colors: [AppColors.accentGreen, AppColors.primaryGreenLight],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : null,
        color: isPrimary ? null : AppColors.mediumGrey,
      ),
      padding: const EdgeInsets.all(1), // Stroke width = 1px
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundLight, // Figma fill #F7F5F0
          borderRadius: BorderRadius.circular(11),
        ),
        child: Material(
          color: AppColors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: isHorizontal
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          svgAsset,
                          width: 36,
                          height: 36,
                          colorFilter: ColorFilter.mode(
                              iconColor, BlendMode.srcIn),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(title, style: textStyle),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          svgAsset,
                          width: 44,
                          height: 44,
                          colorFilter: ColorFilter.mode(
                              iconColor, BlendMode.srcIn),
                        ),
                        const SizedBox(height: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              style: textStyle,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
