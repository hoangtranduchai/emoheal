import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';


/// Bảng màu ứng dụng LotusHaven — trích xuất trực tiếp từ Figma.
///
/// Mỗi hằng số được đặt tên ngữ nghĩa theo vai trò sử dụng trong giao diện.
/// Tuyệt đối KHÔNG có giá trị nào được bịa ra; tất cả đều ánh xạ 1-1 với
/// fill color của node Figma tương ứng.
class AppColors {
  AppColors._();

  // ─── Nền (Background) ───────────────────────────────────────────────
  /// Nền chính của toàn bộ ứng dụng.
  /// Figma: Frame Onboarding / Home / ... fill `r:0.969 g:0.961 b:0.941`
  static const Color backgroundLight = Color(0xFFF7F5F0);

  /// Nền card phụ / radio section.
  /// Figma: Frame "Đài Rado - Tắt" fill `r:0.894 g:0.878 b:0.867`
  static const Color backgroundMuted = Color(0xFFE4E0DD);

  // ─── Xanh lá (Primary Green) ───────────────────────────────────────
  /// Header container xanh đậm (Top bar Home).
  /// Figma: Rectangle "Container" (421:1367) fill `r:0.148 g:0.351 b:0.115`
  static const Color primaryGreenDark = Color(0xFF26591D);

  /// Nút hành động chính (Button "BẮT ĐẦU NGAY").
  /// Figma: Frame "Button" (421:1226) fill `r:0.235 g:0.447 b:0.198`
  static const Color primaryGreen = Color(0xFF3C7232);

  // ─── Cam / Đỏ — SOS ────────────────────────────────────────────────
  /// Nút SOS trung tâm (vòng trong cùng).
  /// Figma: Ellipse 1 (2411:642) fill `r:0.851 g:0.467 b:0.314`
  static const Color sosOrange = Color(0xFFD97750);

  /// Vòng giữa SOS.
  /// Figma: Ellipse 3 (2415:193) fill `r:0.904 g:0.509 b:0.352`
  static const Color sosOrangeMiddle = Color(0xFFE7825A);

  /// Vòng ngoài SOS / hào quang.
  /// Figma: Ellipse 2 (2415:185) fill `r:0.980 g:0.816 b:0.765`
  static const Color sosOrangeLight = Color(0xFFFAD0C3);

  // ─── Trợ lý AI ─────────────────────────────────────────────────────
  /// Nền bubble trợ lý AI (Ellipse 5).
  /// Figma: Ellipse 5 (2420:195) fill `r:0.878 g:0.957 b:0.782` @ 20% opacity
  static const Color assistantBubble = Color(0xFFE0F4C8);

  // ─── Văn bản (Text) ─────────────────────────────────────────────────
  /// Chữ trên nền tối (header xanh).
  /// Figma: Text "Kính chào" (421:1380) fill `r:0.977 g:0.986 b:0.919`
  static const Color textOnDark = Color(0xFFF9FBEB);

  /// Chữ chính trên nền sáng.
  /// Figma: Text "Bác đang cảm thấy..." (2411:650) fill `r:0.067 g:0.067 b:0.067`
  static const Color textPrimary = Color(0xFF111111);

  /// Chữ phụ / mô tả.
  /// Dùng textPrimary với opacity thấp hơn cho phụ đề.
  static const Color textSecondary = Color(0x99111111); // 60% opacity

  // ─── Legacy Aliases (Để tương thích với code cũ) ───────────────
  static const Color ink = textPrimary;
  static const Color neutralGrey = textSecondary;
  static const Color contentGrey = textSecondary;
  static const Color surfaceLight = white;
  static const Color warningOrange = sosOrange;

  // ─── Tiện ích ───────────────────────────────────────────────────────
  /// Màu trắng thuần tuý.
  static const Color white = Color(0xFFFFFFFF);

  /// Màu đen thuần tuý.
  static const Color black = Color(0xFF000000);

  /// Màu trong suốt.
  static const Color transparent = Color(0x00000000);

  // ─── Các màu mới thêm ────────────────────────────────────────────────
  static const Color primaryGreenLight = Color(0xFF469D60);
  static const Color golden = Color(0xFFF9D29E);
  static const Color lightGrey = Color(0xFFEDEDED);
  static const Color mediumGrey = Color(0xFFA2A2A2);
  static const Color darkGrey = Color(0xFF636363);
  static const Color deepBlack = Color(0xFF080709);
  static const Color deepBlackDark = Color(0xFF08080A);
  static const Color accentGreen = Color(0xFF72CE50);
  static const Color sosOrangeLight2 = Color(0xFFF26842);
  static const Color sosGradientStart = Color(0xFFF9875F);
  static const Color sosGradientEnd = Color(0xFFE94E23);
  static const Color redAccent = Color(0xFFFF5252);
  
  static const Color black12 = Color(0x12000000);
  static const Color black0F = Color(0x0F000000);
  static const Color black66 = Color(0x66000000);
  static const Color black7A = Color(0x7A000000);
  static const Color black33 = Color(0x33000000);
  static const Color black1A = Color(0x1A000000);
  static const Color white1A = Color(0x1AFFFFFF);
  static const Color sosGradientEnd66 = Color(0x66E94E23);
  static const Color transparentBlack = Color(0x00100F13);
}

/// Các hằng số kích thước chữ cũ
class AppTextSizes {
  static const double headline = 24.0;
  static const double body = 14.0;
}

/// Theme chính của ứng dụng LotusHaven.
///
/// Tích hợp GoogleFonts để nạp font Roboto hỗ trợ chuẩn Tiếng Việt (UTF-8).
class AppTheme {
  AppTheme._();

  // ─── Text Styles (trích từ Figma) ─────────────────────────────────

  static final TextStyle headingLarge = GoogleFonts.roboto(
    fontSize: 24,
    fontWeight: FontWeight.w400,
    height: 1.2,
    letterSpacing: 0.24,
    color: AppColors.textOnDark,
  );

  static final TextStyle headingBold = GoogleFonts.roboto(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: AppColors.textOnDark,  
  );

  static final TextStyle titleSemiBold = GoogleFonts.roboto(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static final TextStyle bodyRegular = GoogleFonts.roboto(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static final TextStyle captionRegular = GoogleFonts.roboto(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textSecondary,
  );

  static final TextStyle buttonText = GoogleFonts.roboto(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 1.0,
    color: AppColors.white,
  );

  // ─── TextTheme ────────────────────────────────────────────────────

  static final TextTheme textTheme = TextTheme(
    headlineLarge: headingLarge,
    headlineMedium: headingBold,
    titleLarge: titleSemiBold,
    bodyLarge: bodyRegular,
    bodyMedium: bodyRegular,
    labelLarge: buttonText,
    bodySmall: captionRegular,
  );

  // ─── ColorScheme ──────────────────────────────────────────────────

  static const ColorScheme colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primaryGreen,
    onPrimary: AppColors.white,
    primaryContainer: AppColors.primaryGreenDark,
    onPrimaryContainer: AppColors.textOnDark,
    secondary: AppColors.sosOrange,
    onSecondary: AppColors.white,
    secondaryContainer: AppColors.sosOrangeLight,
    onSecondaryContainer: AppColors.textPrimary,
    tertiary: AppColors.assistantBubble,
    onTertiary: AppColors.textPrimary,
    error: AppColors.sosOrange,
    onError: AppColors.white,
    surface: AppColors.backgroundLight,
    onSurface: AppColors.textPrimary,
    surfaceContainerHighest: AppColors.backgroundMuted,
    onSurfaceVariant: AppColors.textSecondary,
  );

  // ─── ThemeData ────────────────────────────────────────────────────

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: AppColors.backgroundLight,
        textTheme: GoogleFonts.robotoTextTheme(textTheme),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.primaryGreenDark,
          foregroundColor: AppColors.textOnDark,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: headingBold,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: AppColors.white,
            textStyle: buttonText,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      );
}
