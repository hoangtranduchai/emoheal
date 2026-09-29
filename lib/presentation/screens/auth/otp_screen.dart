import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pinput/pinput.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logger.dart';
import '../../../core/theme.dart';
import '../../../core/voice_guide.dart';
import '../../../data/api_service.dart';
import '../../../data/supabase_service.dart';
import '../../../router.dart';

/// 4-Digit Large OTP Verification Screen / Màn hình xác thực OTP 4 số ô lớn Pinput
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = false;
  String? _errorMessage;
  String? _phone;

  int _resendCountdown = 60;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && _phone == null) {
      _phone = args;
      // Tự động phát âm thanh hướng dẫn khi vào màn hình nhập OTP
      VoiceGuide.play(VoiceScripts.otp);
      _startResendTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    VoiceGuide.stop();
    _otpController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendCountdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCountdown > 0) {
        if (mounted) setState(() => _resendCountdown--);
      } else {
        t.cancel();
      }
    });
  }

  /// Verify 4-digit OTP via Backend & Supabase / Xác thực OTP 4 số
  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 4) {
      setState(() => _errorMessage = 'Dạ bác ơi, mã xác thực gồm 4 chữ số ạ.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final phone = _phone ?? '+84912345678';
      AppLogger.i('Xác thực OTP 4 số: phone=$phone, otp=$otp', tag: 'AUTH');

      // 1. Gọi Backend Verify OTP (Cấp JWT token & đồng bộ Supabase)
      try {
        final uri = Uri.parse('${ApiService.baseUrl}/api/auth/verify-otp');
        final res = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone, 'otp': otp}),
        );

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final userId = data['user']?['id'] as String?;
          if (userId != null && userId.isNotEmpty) {
            SupabaseService.setActiveUserId(userId);
          }
          AppLogger.i('✅ Xác thực Fullstack thành công cho $phone (UserID: $userId)', tag: 'AUTH');
        } else {
          final errJson = jsonDecode(res.body);
          if (otp != '8888') {
            throw Exception(errJson['detail'] ?? 'Mã xác thực chưa chính xác.');
          }
        }
      } catch (netErr) {
        AppLogger.w('Backend verify call error: $netErr', tag: 'AUTH');
        if (otp == '8888') {
          AppLogger.i('⚡ Tự động thông qua mã thử nghiệm 8888 (Chế độ Fallback)', tag: 'AUTH');
        } else {
          rethrow;
        }
      }

      // 2. Tự động đồng bộ tài khoản trực tiếp vào Supabase Database & Auth
      try {
        final displayName = 'Bác (${phone.length >= 4 ? phone.substring(phone.length - 4) : phone})';
        final sbResult = await Supabase.instance.client.rpc(
          'register_phone_user',
          params: {
            'p_phone': phone,
            'p_display_name': displayName,
          },
        );
        if (sbResult != null && sbResult is Map && sbResult['user_id'] != null) {
          SupabaseService.setActiveUserId(sbResult['user_id'].toString());
        }
        AppLogger.i('✅ Đã đồng bộ tài khoản $phone lên Supabase Database!', tag: 'AUTH');
      } catch (sbErr) {
        AppLogger.w('Supabase direct sync warning: $sbErr', tag: 'AUTH');
      }

      if (mounted) {
        VoiceGuide.stop();
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceAll('Exception:', '').trim());
      AppLogger.e('Lỗi xác thực OTP', tag: 'AUTH', error: e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Điền mã thử nghiệm
  void _fillTestOtp() {
    _otpController.text = '8888';
    _verifyOtp();
  }

  /// Resend OTP / Gửi lại mã OTP
  Future<void> _resendOtp() async {
    if (_resendCountdown > 0) return;
    if (_phone == null) return;

    try {
      AppLogger.i('Gửi lại mã OTP cho: $_phone', tag: 'AUTH');
      
      try {
        final uri = Uri.parse('${ApiService.baseUrl}/api/auth/send-otp');
        await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': _phone}),
        ).timeout(const Duration(seconds: 4));
      } catch (backendErr) {
        AppLogger.w('Backend resend-otp offline ($backendErr)', tag: 'AUTH');
      }

      _startResendTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dạ cháu đã gửi lại mã xác thực mới rồi ạ.'),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
      }
    } catch (e) {
      AppLogger.e('Lỗi gửi lại OTP', tag: 'AUTH', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pin Theme khổ lớn đạt chuẩn WCAG AAA cho Người cao tuổi
    final defaultPinTheme = PinTheme(
      width: 70,
      height: 75,
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 32,
        fontWeight: FontWeight.w900,
        color: AppColors.primaryGreenDark,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD0D7DE), width: 2),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: AppColors.primaryGreen, width: 3),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppColors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primaryGreenDark, size: 32),
          onPressed: () {
            VoiceGuide.stop();
            Navigator.of(context).pop();
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
                'Xác thực mã OTP',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryGreenDark,
                ),
              ),

              const SizedBox(height: 12),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 18,
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'Mã xác thực gồm 4 chữ số đã được gửi đến số điện thoại:\n'),
                    TextSpan(
                      text: _phone ?? 'của bác',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreenDark,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // Giao diện Pinput 4 Ô PIN cỡ lớn 70x75dp
              Center(
                child: Pinput(
                  length: 4,
                  controller: _otpController,
                  focusNode: _focusNode,
                  defaultPinTheme: defaultPinTheme,
                  focusedPinTheme: focusedPinTheme,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  onCompleted: (pin) => _verifyOtp(),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
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

              const SizedBox(height: 28),

              // Nút Tự Điền Thử Nghiệm $0 cước phí SMS
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _fillTestOtp,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryGreenDark,
                    side: const BorderSide(color: AppColors.primaryGreen, width: 1.8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    backgroundColor: const Color(0xFFE8F5E9),
                  ),
                  icon: const Icon(Icons.bolt, color: AppColors.primaryGreen, size: 28),
                  label: const Text(
                    '⚡ Điền mã thử nghiệm (8888)',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Nút XÁC NHẬN lớn 64dp
              SizedBox(
                height: 64,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
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
                          'XÁC NHẬN',
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

              // Nút Gửi lại mã với đếm ngược 60s
              Center(
                child: TextButton(
                  onPressed: _resendCountdown == 0 ? _resendOtp : null,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(
                    _resendCountdown > 0
                        ? 'Gửi lại mã sau ($_resendCountdown giây)'
                        : 'Gửi lại mã xác thực',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _resendCountdown > 0 ? AppColors.textSecondary : AppColors.primaryGreen,
                      decoration: _resendCountdown == 0 ? TextDecoration.underline : TextDecoration.none,
                    ),
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

