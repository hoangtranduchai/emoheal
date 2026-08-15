import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryGreen = Color(0xFF3C7232);
  static const Color warningOrange = Color(0xFFF9D29E);
  static const Color surfaceLight = Color(0xFFF7F5F0);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color neutralGrey = Color(0xFFA2A2A2);
  static const Color contentGrey = Color(0xFFEDEDED);
  static const Color ink = Color(0xFF08080A);
  static const Color warmShadow = Color(0x33000000);
}

class AppTextSizes {
  static const double headline = 32;
  static const double body = 18;
  static const double button = 24;
  static const double label = 16;
  static const double caption = 14;
}

class AppTheme {
  static ThemeData light() {
    return _buildTheme(
      brightness: Brightness.light,
      surface: AppColors.surfaceWhite,
      onSurface: AppColors.ink,
      background: AppColors.surfaceLight,
      warning: AppColors.warningOrange,
      highContrast: false,
    );
  }

  static ThemeData dark() {
    return _buildTheme(
      brightness: Brightness.dark,
      surface: AppColors.ink,
      onSurface: AppColors.surfaceWhite,
      background: AppColors.ink,
      warning: AppColors.warningOrange,
      highContrast: false,
    );
  }

  static ThemeData highContrastLight() {
    return _buildTheme(
      brightness: Brightness.light,
      surface: AppColors.surfaceWhite,
      onSurface: Colors.black,
      background: Colors.white,
      warning: const Color(0xFFFF7A00),
      highContrast: true,
    );
  }

  static ThemeData highContrastDark() {
    return _buildTheme(
      brightness: Brightness.dark,
      surface: Colors.black,
      onSurface: Colors.white,
      background: Colors.black,
      warning: const Color(0xFFFFB000),
      highContrast: true,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color surface,
    required Color onSurface,
    required Color background,
    required Color warning,
    required bool highContrast,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primaryGreen,
      onPrimary: Colors.white,
      secondary: warning,
      onSecondary: brightness == Brightness.dark ? Colors.black : Colors.white,
      error: warning,
      onError: brightness == Brightness.dark ? Colors.black : Colors.white,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: highContrast
          ? (brightness == Brightness.dark ? Colors.white : Colors.black)
          : AppColors.contentGrey,
      onSurfaceVariant: highContrast ? onSurface : AppColors.neutralGrey,
      outline: highContrast ? onSurface : AppColors.neutralGrey,
      shadow: AppColors.warmShadow,
      scrim: Colors.black,
      inverseSurface: brightness == Brightness.dark ? Colors.white : Colors.black,
      onInverseSurface: brightness == Brightness.dark ? Colors.black : Colors.white,
      inversePrimary: AppColors.primaryGreen,
      tertiary: warning,
      onTertiary: brightness == Brightness.dark ? Colors.black : Colors.white,
      surfaceTint: AppColors.primaryGreen,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: AppTextSizes.headline,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        bodyLarge: TextStyle(
          fontSize: AppTextSizes.body,
          fontWeight: FontWeight.w400,
          height: 1.45,
        ),
        labelLarge: TextStyle(
          fontSize: AppTextSizes.button,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
        titleMedium: TextStyle(
          fontSize: AppTextSizes.label,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        bodyMedium: TextStyle(
          fontSize: AppTextSizes.caption,
          fontWeight: FontWeight.w400,
          height: 1.4,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: AppTextSizes.button,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
