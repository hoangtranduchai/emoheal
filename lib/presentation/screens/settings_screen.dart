import 'package:flutter/material.dart';
import '../../data/supabase_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  
  bool _isLoading = true;
  bool _soundEnabled = true;
  bool _highContrastEnabled = false;
  bool _antiMistapEnabled = false;
  String _voiceType = 'hoai_my';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _supabaseService.getUserSettings();
      if (settings != null) {
        setState(() {
          _soundEnabled = settings['sound_enabled'] ?? true;
          _highContrastEnabled = settings['high_contrast_enabled'] ?? false;
          _antiMistapEnabled = settings['anti_mistap_enabled'] ?? false;
          _voiceType = settings['voice_type'] ?? 'hoai_my';
        });
      }
    } catch (e) {
      // Handle error implicitly
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _supabaseService.saveUserSettings(
        soundEnabled: _soundEnabled,
        highContrastEnabled: _highContrastEnabled,
        antiMistapEnabled: _antiMistapEnabled,
        voiceType: _voiceType,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi khi lưu cài đặt')),
        );
      }
    }
  }

  void _onSettingChanged() {
    _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    // Zero-Barrier UI approach: big text, clear contrast, large tap targets
    final theme = Theme.of(context);
    final bgColor = _highContrastEnabled ? Colors.black : theme.scaffoldBackgroundColor;
    final textColor = _highContrastEnabled ? Colors.white : theme.textTheme.bodyLarge?.color;
    final cardColor = _highContrastEnabled ? Colors.grey[900] : theme.cardColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          'Cài đặt',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        backgroundColor: bgColor,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              children: [
                _buildToggleItem(
                  title: 'Âm thanh (Sound)',
                  value: _soundEnabled,
                  onChanged: (val) {
                    setState(() => _soundEnabled = val);
                    _onSettingChanged();
                  },
                  textColor: textColor,
                  cardColor: cardColor,
                ),
                const SizedBox(height: 16),
                _buildToggleItem(
                  title: 'Tương phản cao',
                  value: _highContrastEnabled,
                  onChanged: (val) {
                    setState(() => _highContrastEnabled = val);
                    _onSettingChanged();
                  },
                  textColor: textColor,
                  cardColor: cardColor,
                ),
                const SizedBox(height: 16),
                _buildToggleItem(
                  title: 'Chống chạm nhầm',
                  subtitle: 'Yêu cầu nhấn giữ để thực hiện hành động',
                  value: _antiMistapEnabled,
                  onChanged: (val) {
                    setState(() => _antiMistapEnabled = val);
                    _onSettingChanged();
                  },
                  textColor: textColor,
                  cardColor: cardColor,
                ),
                const SizedBox(height: 32),
                Text(
                  'Giọng nói trợ lý',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 16),
                _buildVoiceOption(
                  title: 'Hoài My',
                  subtitle: 'Giọng nữ nhẹ nhàng',
                  value: 'hoai_my',
                  groupValue: _voiceType,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _voiceType = val);
                      _onSettingChanged();
                    }
                  },
                  textColor: textColor,
                  cardColor: cardColor,
                ),
                const SizedBox(height: 12),
                _buildVoiceOption(
                  title: 'Nam Minh',
                  subtitle: 'Giọng nam trầm ấm',
                  value: 'nam_minh',
                  groupValue: _voiceType,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _voiceType = val);
                      _onSettingChanged();
                    }
                  },
                  textColor: textColor,
                  cardColor: cardColor,
                ),
              ],
            ),
    );
  }

  Widget _buildToggleItem({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? textColor,
    Color? cardColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        subtitle: subtitle != null
            ? Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 18,
                    color: textColor?.withOpacity(0.7),
                  ),
                ),
              )
            : null,
        value: value,
        onChanged: onChanged,
        activeColor: Colors.teal,
      ),
    );
  }

  Widget _buildVoiceOption({
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
    Color? textColor,
    Color? cardColor,
  }) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal.withOpacity(0.1) : cardColor,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: Colors.teal, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: Colors.teal,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 18,
                      color: textColor?.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
