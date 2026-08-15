import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'router.dart';

void main() {
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
