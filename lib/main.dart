import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/logger.dart';
import 'core/theme.dart';
import 'router.dart';
import 'presentation/widgets/global_draggable_assistant.dart';

// Supabase config — use --dart-define for production builds / Cấu hình Supabase
const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://dahysdyexofpqfkibobz.supabase.co',
);
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRhaHlzZHlleG9mcHFma2lib2J6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY2MjA3MzksImV4cCI6MjEwMjE5NjczOX0.9Agj7InImtFOoYVHjh7U28uhnVVJIq-zqOLNF0qvOH0',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global Flutter Framework Error Handler / Bắt và ghi log toàn bộ lỗi Framework Flutter
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.e(
      'Flutter Framework Exception: ${details.exceptionAsString()}',
      tag: 'CRASH',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  // Global Asynchronous Error Handler / Bắt và ghi log toàn bộ lỗi bất đồng bộ không xử lý
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.e(
      'Unhandled Asynchronous Error: $error',
      tag: 'CRASH-ASYNC',
      error: error,
      stackTrace: stack,
    );
    return true; // Ngăn chặn crash app đột ngột
  };

  // Custom UI Error Widget / Màn hình lỗi mềm mại tránh hiển thị màn hình đỏ
  ErrorWidget.builder = (FlutterErrorDetails details) {
    AppLogger.w(
      'Rendering fallback ErrorWidget: ${details.exception}',
      tag: 'UI-ERROR',
    );
    return const Material(
      color: AppColors.backgroundLight,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Dạ Bác ơi, giao diện đang gặp chút trục trặc nhỏ.\nCháu đang tự động tải lại ạ.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  };

  AppLogger.i('Khởi động ứng dụng EmoHeal "Vòng tay thấu cảm"', tag: 'BOOT');
  AppLogger.d('Supabase URL: $_supabaseUrl', tag: 'CONFIG');

  try {
    final initStart = DateTime.now();
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
    );
    final initDuration = DateTime.now().difference(initStart);
    AppLogger.i('Khởi tạo Supabase thành công (${initDuration.inMilliseconds}ms)', tag: 'BOOT');
  } catch (e, st) {
    AppLogger.e('Lỗi khởi tạo Supabase', tag: 'BOOT', error: e, stackTrace: st);
  }

  runApp(const EmoHealApp());
}

class EmoHealApp extends StatelessWidget {
  const EmoHealApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppRouter.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'EmoHeal - Vòng tay thấu cảm',
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      initialRoute: AppRoutes.onboarding,
      onGenerateRoute: AppRouter.onGenerateRoute,
      navigatorObservers: [
        AppNavigatorObserver(),
      ],
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            const GlobalDraggableAssistant(),
          ],
        );
      },
    );
  }
}

/// Navigator Observer to automatically log all route transitions
/// Trình theo dõi chuyển trang tự động ghi log điều hướng
class AppNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    AppLogger.nav('${route.settings.name ?? route.runtimeType}', arguments: route.settings.arguments);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    AppLogger.d('Quay lại từ trang: ${route.settings.name ?? route.runtimeType}', tag: 'NAV');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    AppLogger.nav('Chuyển trang (Replace) sang: ${newRoute?.settings.name ?? newRoute.runtimeType}');
  }
}
