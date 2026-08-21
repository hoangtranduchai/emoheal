import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme.dart';
import '../../../router.dart';

/// Login screen — phone number input → Supabase OTP / Màn hình đăng nhập
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
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  /// Send OTP to phone via Supabase Auth / Gửi OTP qua Supabase
  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Bác vui lòng nhập số điện thoại.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Format VN phone: 0912... → +84912...
      String formattedPhone = phone;
      if (phone.startsWith('0')) {
        formattedPhone = '+84${phone.substring(1)}';
      } else if (!phone.startsWith('+')) {
        formattedPhone = '+84$phone';
      }

      await Supabase.instance.client.auth.signInWithOtp(phone: formattedPhone);

      if (mounted) {
        Navigator.of(context).pushNamed(
          AppRoutes.authOtp,
          arguments: formattedPhone,
        );
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = 'Lỗi: ${e.message}');
    } catch (e) {
      setState(() => _errorMessage = 'Không thể gửi mã. Vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Skip login for quick access / Bỏ qua đăng nhập để trải nghiệm nhanh
  void _skipLogin() {
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
        iconTheme: const IconThemeData(color: AppColors.primaryGreenDark, size: 32),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Đăng nhập',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryGreenDark,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Vui lòng nhập số điện thoại của bác để tiếp tục.',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 24,
                  color: AppColors.textPrimary,
                  letterSpacing: 2,
                ),
                decoration: InputDecoration(
                  hintText: 'Nhập số điện thoại',
                  hintStyle: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 20,
                    color: AppColors.textSecondary,
                    letterSpacing: 0,
                  ),
                  filled: true,
                  fillColor: AppColors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: AppColors.primaryGreen,
                      width: 2,
                    ),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16,
                    color: AppColors.redAccent,
                  ),
                ),
              ],
              const SizedBox(height: 48),
              SizedBox(
                height: 64,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: AppColors.white)
                      : const Text(
                          'TIẾP TỤC',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              // Skip login button for guest access / Nút bỏ qua cho khách
              TextButton(
                onPressed: _skipLogin,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  minimumSize: const Size(0, 48),
                ),
                child: const Text(
                  'Bỏ qua, trải nghiệm trước',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
