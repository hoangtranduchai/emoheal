import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../data/supabase_service.dart';
import '../../core/theme.dart';
import '../../core/voice_guide.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  
  bool _isLoading = true;
  bool _soundEnabled = true;
  bool _antiMistapEnabled = false;
  bool _voiceControlEnabled = true;
  double _fontSizeScale = 1.15; // 1.0 = Vừa, 1.15 = Lớn, 1.3 = Rất lớn
  String _voiceType = 'aoede';

  String _displayName = 'Bác';
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadDisplayName();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VoiceGuide.play(VoiceScripts.settings);
    });
  }

  Future<void> _loadDisplayName() async {
    final name = await _supabaseService.getDisplayName();
    if (mounted) {
      setState(() {
        _displayName = name;
        _nameController.text = name == 'Bác' ? '' : name;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    VoiceGuide.stop();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _supabaseService.getUserSettings();
      if (mounted) {
        setState(() {
          _soundEnabled = settings['sound_enabled'] ?? true;
          _fontSizeScale = (settings['font_size_scale'] as num?)?.toDouble() ?? 1.15;
          _antiMistapEnabled = settings['anti_mis_tap'] ?? settings['anti_mistap_enabled'] ?? false;
          _voiceControlEnabled = settings['voice_control_enabled'] ?? true;
          _voiceType = settings['voice_type'] ?? 'aoede';
          VoiceGuide.isVoiceEnabled = _soundEnabled;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải cài đặt: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    VoiceGuide.isVoiceEnabled = _soundEnabled;
    try {
      await _supabaseService.saveUserSettings(
        soundEnabled: _soundEnabled,
        fontSizeScale: _fontSizeScale,
        antiMisTap: _antiMistapEnabled,
        voiceControlEnabled: _voiceControlEnabled,
        voiceType: _voiceType,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi khi lưu cài đặt.')),
        );
      }
    }
  }

  void _onSettingChanged() {
    _saveSettings();
  }

  void _showEditNameDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Nhập tên hoặc danh xưng',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreenDark),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ví dụ: Bác nhập "Hải" thì ứng dụng và cháu AI sẽ gọi là "Bác Hải":',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Nhập tên của Bác (ví dụ: Hải)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: AppColors.white,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: AppColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () async {
              final newName = _nameController.text.trim();
              final savedName = newName.isEmpty ? 'Bác' : newName;
              Navigator.pop(ctx);
              await _supabaseService.updateDisplayName(savedName);
              if (mounted) {
                setState(() => _displayName = savedName);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã lưu tên gọi: $savedName')),
                );
              }
            },
            child: const Text('Lưu lại', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    const cardColor = AppColors.white;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text(
          'Cài đặt & Trợ năng',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryGreenDark,
          ),
        ),
        backgroundColor: AppColors.backgroundLight,
        iconTheme: const IconThemeData(color: AppColors.primaryGreenDark, size: 28),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // 0. TÊN GỌI / DANH XƯNG
                const Text(
                  '1. Tên gọi & Danh xưng của Bác',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreenDark,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 26,
                        backgroundColor: Color(0xFFE8F5E9),
                        child: Icon(Icons.person, color: AppColors.primaryGreen, size: 30),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Danh xưng hiển thị',
                              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _displayName.startsWith('Bác') ? _displayName : 'Bác $_displayName',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showEditNameDialog,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Đổi tên'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryGreenDark,
                          side: const BorderSide(color: AppColors.primaryGreen),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 1. ĐIỀU CHỈNH CỠ CHỮ
                const Text(
                  '2. Điều chỉnh cỡ chữ',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreenDark,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chữ mẫu: Kính chào Bác!',
                        style: TextStyle(
                          fontSize: 18 * _fontSizeScale,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<double>(
                        segments: const [
                          ButtonSegment(value: 1.0, label: Text('Vừa')),
                          ButtonSegment(value: 1.15, label: Text('Lớn')),
                          ButtonSegment(value: 1.3, label: Text('Rất lớn')),
                        ],
                        selected: {_fontSizeScale},
                        onSelectionChanged: (newSelection) {
                          setState(() => _fontSizeScale = newSelection.first);
                          _onSettingChanged();
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 2. CHỐNG CHẠM NHẦM
                const Text(
                  '3. An toàn thao tác',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreenDark,
                  ),
                ),
                const SizedBox(height: 10),
                _buildToggleItem(
                  title: 'Chống chạm nhầm',
                  subtitle: 'Yêu cầu nhấn giữ 0.5 giây để tránh bấm nhầm khi tay run',
                  value: _antiMistapEnabled,
                  onChanged: (val) {
                    setState(() => _antiMistapEnabled = val);
                    _onSettingChanged();
                  },
                ),

                const SizedBox(height: 24),

                // 3. ĐIỀU KHIỂN BẰNG GIỌNG NÓI TOÀN HỆ THỐNG
                const Text(
                  '4. Điều khiển bằng giọng nói',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreenDark,
                  ),
                ),
                const SizedBox(height: 10),
                _buildToggleItem(
                  title: 'Điều khiển giọng nói toàn hệ thống',
                  subtitle: 'Cho phép Bác ra lệnh bằng giọng nói để mở mọi chức năng trên ứng dụng',
                  value: _voiceControlEnabled,
                  onChanged: (val) {
                    setState(() => _voiceControlEnabled = val);
                    _onSettingChanged();
                  },
                ),

                const SizedBox(height: 24),

                // 4. GIỌNG NÓI TRỢ LÝ
                const Text(
                  '5. Giọng nói trợ lý',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreenDark,
                  ),
                ),
                const SizedBox(height: 10),
                _buildVoiceOption(
                  title: 'Giọng Nữ Aoede (Google Native)',
                  subtitle: 'Giọng nữ cháu gái dịu dàng, ân cần, lắng nghe',
                  value: 'aoede',
                  isSelected: _voiceType == 'aoede' || _voiceType == 'female',
                  onTap: () {
                    setState(() => _voiceType = 'aoede');
                    _onSettingChanged();
                    VoiceGuide.play('Dạ, cháu kính chào Bác ạ! Cháu luôn sẵn sàng đồng hành cùng Bác.', voice: 'aoede');
                  },
                ),
                const SizedBox(height: 12),
                _buildVoiceOption(
                  title: 'Giọng Nam Charon (Google Native)',
                  subtitle: 'Giọng nam cháu trai điềm đạm, truyền cảm, rõ ràng',
                  value: 'charon',
                  isSelected: _voiceType == 'charon' || _voiceType == 'male',
                  onTap: () {
                    setState(() => _voiceType = 'charon');
                    _onSettingChanged();
                    VoiceGuide.play('Dạ, cháu kính chào Bác ạ! Cháu luôn sẵn sàng đồng hành cùng Bác.', voice: 'charon');
                  },
                ),

                const SizedBox(height: 32),

                // 6. THÔNG TIN HỆ THỐNG
                Center(
                  child: Column(
                    children: [
                      SvgPicture.asset(
                        'assets/icons/app_icon.svg',
                        width: 56,
                        height: 56,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'EmoHeal — Vòng tay thấu cảm',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreenDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Hệ thống Hỗ trợ tâm lý Cựu chiến binh\nqua Phân tích Cảm xúc Giọng nói\nPhiên bản 5.8.2\nHoàng Trần Đức Phát',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildToggleItem({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Material(
      color: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: subtitle != null
            ? Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            : null,
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.primaryGreen,
      ),
    );
  }

  Widget _buildVoiceOption({
    required String title,
    required String subtitle,
    required String value,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8F5E9) : AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primaryGreen : const Color(0xFFE0E0E0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppColors.primaryGreen : AppColors.mediumGrey,
              size: 26,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.volume_up_outlined, color: AppColors.primaryGreen, size: 24),
          ],
        ),
      ),
    );
  }
}
