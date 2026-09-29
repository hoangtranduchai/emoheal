import 'package:flutter/material.dart';

import 'presentation/screens/history_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/lotus_breathing_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/radio_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/voice_memo_screen.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/otp_screen.dart';

class AppRoutes {
  static const String onboarding = '/';
  static const String home = '/home';
  static const String voiceMemo = '/voice_memos';
  static const String history = '/history';
  static const String lotusBreathing = '/lotus_breathing';
  static const String radio = '/radio';
  static const String settings = '/settings';
  static const String authLogin = '/auth/login';
  static const String authOtp = '/auth/otp';
}

class AppRouter {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final Widget page;

    switch (settings.name) {
      case AppRoutes.onboarding:
        page = const OnboardingScreen();
        break;
      case AppRoutes.home:
        page = const HomeScreen();
        break;
      case AppRoutes.voiceMemo:
        page = const VoiceMemoScreen();
        break;
      case AppRoutes.history:
        page = const HistoryScreen();
        break;
      case AppRoutes.lotusBreathing:
        page = const LotusBreathingScreen();
        break;
      case AppRoutes.radio:
        page = const RadioScreen();
        break;
      case AppRoutes.settings:
        page = const SettingsScreen();
        break;
      case AppRoutes.authLogin:
        page = const LoginScreen();
        break;
      case AppRoutes.authOtp:
        page = const OtpScreen();
        break;
      default:
        page = const OnboardingScreen();
        break;
    }

    return PageRouteBuilder<dynamic>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          ),
          child: child,
        );
      },
    );
  }
}
