import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme.dart';
import 'router.dart';

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

  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabaseAnonKey,
  );

  runApp(const LotusHavenApp());
}

class LotusHavenApp extends StatelessWidget {
  const LotusHavenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hành trình tri ân',
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      initialRoute: AppRoutes.onboarding,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
