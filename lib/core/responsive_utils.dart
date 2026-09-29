import 'package:flutter/material.dart';

class ResponsiveUtils {
  static const double mobileMaxSize = 600;

  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < mobileMaxSize;
  }

  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width >= mobileMaxSize;
  }

  static double getCardSize(BuildContext context) {
    return isTablet(context) ? 180.0 : 160.0;
  }

  static double getCardPadding(BuildContext context) {
    if (isTablet(context)) return 64.0;
    final width = MediaQuery.of(context).size.width;
    if (width <= 340) return 16.0;
    return 24.0;
  }

  static double getCardGap(BuildContext context) {
    if (isTablet(context)) return 40.0;
    final width = MediaQuery.of(context).size.width;
    if (width <= 340) return 14.0;
    return 20.0;
  }
}
