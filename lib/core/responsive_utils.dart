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
    return isTablet(context) ? 180.0 : 145.5;
  }

  static double getCardPadding(BuildContext context) {
    return isTablet(context) ? 64.0 : 28.0;
  }

  static double getCardGap(BuildContext context) {
    return isTablet(context) ? 40.0 : 28.0;
  }
}
