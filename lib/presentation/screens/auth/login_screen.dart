import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/logger.dart';
import '../../../core/theme.dart';
import '../../../core/voice_guide.dart';
import '../../../data/api_service.dart';
import '../../../data/supabase_service.dart';
import '../../../router.dart';

/// Unified Login & Register Screen / Màn hình Đăng nhập & Đăng ký tối giản cho Cựu chiến binh
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Tự động phát âm thanh hướng dẫn khi vào màn hình
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VoiceGuide.play(VoiceScripts.login);
    });
  }

  @override
  void dispose() {
    VoiceGuide.stop();
    _phoneController.dispose();
    super.dispose();
  }

  /// Xử lý đăng nhập / đăng ký thông minh cho người cao tuổi:
  /// - Nếu Bác đã đăng ký trước đó: Đăng nhập trực tiếp, không bắt buộc nhập OTP.
  /// - Nếu là người dùng mới: Gửi mã OTP và chuyển sang màn hình xác thực OTP.
  Future<void> _handleContinue() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Dạ bác ơi, bác vui lòng nhập số điện thoại ạ.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      AppLogger.i('Kiểm tra trạng thái tài khoản cho SĐT: $phone', tag: 'AUTH');

      // 1. Kiểm tra xem số điện thoại đã đăng ký chưa
      final checkRes = await ApiService.checkRegisteredPhone(phone);
      if (checkRes != null && checkRes['already_registered'] == true) {
        final userId = checkRes['user']?['id'] as String?;
        if (userId != null && userId.isNotEmpty) {
          SupabaseService.setActiveUserId(userId);
        }
        AppLogger.i('🎉 Bác đã có tài khoản ($phone) -> Đăng nhập trực tiếp!', tag: 'AUTH');

        if (mounted) {
          VoiceGuide.stop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Chào mừng Bác quay trở lại với EmoHeal!',
                style: TextStyle(fontFamily: 'Roboto', fontSize: 16, fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppColors.primaryGreen,
              duration: Duration(seconds: 5),
            ),
          );
          Navigator.of(context).pushNamedAndRemoveUntil(
            AppRoutes.home,
            (route) => false,
          );
          return;
        }
      }

      // 2. Nếu là số mới: Gửi mã OTP để tạo tài khoản lần đầu
      AppLogger.i('Gửi mã OTP đăng ký mới cho SĐT: $phone', tag: 'AUTH');
      try {
        final uri = Uri.parse('${ApiService.baseUrl}/api/auth/send-otp');
        final res = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone}),
        );

        if (res.statusCode == 200) {
          AppLogger.i('✅ Backend đã gửi mã OTP thành công cho $phone', tag: 'AUTH');
        }
      } catch (backendErr) {
        AppLogger.w('Không thể kết nối Backend FastAPI ($backendErr). Chuyển tiếp OTP fallback.', tag: 'AUTH');
      }

      if (mounted) {
        VoiceGuide.stop();
        Navigator.of(context).pushNamed(
          AppRoutes.authOtp,
          arguments: phone,
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Bác vui lòng kiểm tra lại số điện thoại hoặc kết nối mạng nhé ạ.');
      AppLogger.e('Lỗi không mong muốn trong _handleContinue', tag: 'AUTH', error: e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Skip login for quick guest access / Bỏ qua đăng nhập để trải nghiệm trước
  void _skipLogin() {
    VoiceGuide.stop();
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.home,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppColors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primaryGreenDark, size: 32),
          onPressed: () {
            VoiceGuide.stop();
            Navigator.of(context).pushReplacementNamed(AppRoutes.onboarding);
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              
              const Text(
                'Đăng ký & Đăng nhập',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryGreenDark,
                ),
              ),

              const SizedBox(height: 12),
              const Text(
                'Kính chào bác! Bác vui lòng nhập số điện thoại một lần duy nhất. Nếu là số mới, cháu sẽ tự tạo tài khoản cho bác ạ.',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textPrimary,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 32),
              
              // Ô nhập Số điện thoại cỡ lớn
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: 2,
                ),
                decoration: InputDecoration(
                  prefixIcon: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Icon(Icons.phone_android, color: AppColors.primaryGreen, size: 32),
                  ),
                  hintText: 'Ví dụ: 0912 345 678',
                  hintStyle: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 20,
                    fontWeight: FontWeight.normal,
                    color: AppColors.textSecondary,
                    letterSpacing: 0,
                  ),
                  filled: true,
                  fillColor: AppColors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 22,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFD0D7DE), width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: AppColors.primaryGreen,
                      width: 2.5,
                    ),
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.redAccent, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.redAccent, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 16,
                            color: AppColors.redAccent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 36),

              // Nút TIẾP TỤC lớn 64dp
              SizedBox(
                height: 64,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: AppColors.white)
                      : const Text(
                          'TIẾP TỤC',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // Nút Trải nghiệm trước (Khách)
              TextButton(
                onPressed: _skipLogin,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(0, 48),
                ),
                child: const Text(
                  'Bỏ qua, trải nghiệm trước',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryGreen,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

