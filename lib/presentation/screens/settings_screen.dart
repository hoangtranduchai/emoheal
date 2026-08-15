import 'package:flutter/material.dart';

import '../../core/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ValueNotifier<bool> _highContrast = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _globalVoice = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _antiMisTap = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _highContrast.dispose();
    _globalVoice.dispose();
    _antiMisTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cài đặt hỗ trợ',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Điều chỉnh trải nghiệm để phù hợp với bác',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 14,
                  color: AppColors.neutralGrey,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: _highContrast,
                      builder: (context, value, child) {
                        return SwitchListTile(
                          title: const Text('Chế độ tương phản cao'),
                          subtitle: const Text('Tăng độ rõ nét cho chữ và giao diện'),
                          value: value,
                          onChanged: (nextValue) => _highContrast.value = nextValue,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<bool>(
                      valueListenable: _globalVoice,
                      builder: (context, value, child) {
                        return SwitchListTile(
                          title: const Text('Kích hoạt giọng nói toàn hệ thống'),
                          subtitle: const Text('Sẵn sàng cho phản hồi bằng giọng đọc'),
                          value: value,
                          onChanged: (nextValue) => _globalVoice.value = nextValue,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<bool>(
                      valueListenable: _antiMisTap,
                      builder: (context, value, child) {
                        return SwitchListTile(
                          title: const Text('Chống chạm nhầm'),
                          subtitle: const Text('Tăng thời gian xác nhận với thao tác nguy cơ cao'),
                          value: value,
                          onChanged: (nextValue) => _antiMisTap.value = nextValue,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
