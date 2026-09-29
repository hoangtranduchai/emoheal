import 'dart:ui';
import 'sound_coordinator.dart';

/// Bộ kịch bản giọng đọc chuẩn mực cho toàn bộ hệ thống app EmoHeal
/// Đồng bộ 100% từng ký tự với MASTER_VOICE_SCRIPTS trên Backend để đạt 0.1ms Cache Hit.
class VoiceScripts {
  // ── 1. Hướng dẫn Màn hình & Xác thực (Auth & Onboarding) ──
  static const String onboarding =
      'Kính chào Bác! Chào mừng Bác đến với EmoHeal - Vòng tay thấu cảm đồng hành cùng Cựu chiến binh và Thương binh. '
      'Bác có thể chạm vào nút Bắt đầu ngay màu xanh ở dưới, hoặc sử dụng giọng nói để điều khiển toàn bộ ứng dụng cùng cháu nhé ạ.';

  static const String login =
      'Kính chào Bác! Bác vui lòng nhập số điện thoại của mình rồi bấm nút Tiếp tục. '
      'Nếu là lần đầu sử dụng, cháu sẽ gửi mã xác thực về máy Bác để tạo tài khoản, '
      'còn nếu Bác đã có tài khoản rồi thì cháu sẽ đón Bác vào ứng dụng ngay nhé ạ.';

  static const String otp =
      'Mã xác thực gồm bốn chữ số đã được gửi qua tin nhắn đến số điện thoại của Bác. '
      'Bác vui lòng kiểm tra tin nhắn và điền bốn số đó vào các ô bên dưới nhé ạ.';

  // ── 2. Trang chủ & Trợ lý AI Tâm sự (Home & Chat) ──
  static const String home =
      'Dạ cháu chào Bác! Đây là trang chủ EmoHeal - Vòng tay thấu cảm. Tại đây, Bác có thể mở Hồi ký giọng nói, '
      'tập Nhịp thở hoa sen, nghe Đài radio, vào Cài đặt hoặc gọi cho Người thân. '
      'Bác cũng có thể bấm giữ nút SOS lớn màu đỏ khi cần trợ giúp, hoặc chỉ cần nói để cháu tự động điều khiển toàn bộ tính năng cho Bác ạ.';

  static const String chat =
      'Dạ cháu lắng nghe Bác đây ạ. Bác có thể nhắn tin hoặc bấm giữ nút micro màu xanh để nói chuyện. '
      'Cháu có thể giải đáp tâm sự, đọc thơ, hoặc tự động chuyển màn hình theo yêu cầu của Bác nhé ạ.';

  static const String assistantReady = 'Dạ cháu lắng nghe Bác đây ạ.';
  static const String assistantNetworkError =
      'Dạ kết nối mạng đang chập chờn, Bác vui lòng thử lại sau giây lát hoặc kiểm tra kết nối mạng nhé ạ.';

  // ── 3. Đài Radio & Hồi ký Giọng nói (Radio & Voice Memo) ──
  static const String radio =
      'Chào mừng Bác đến với Đài Radio Hoài Niệm. Bác có thể chạm vào danh sách bài phát để nghe, '
      'hoặc nói tên bài hát yêu thích để cháu tự động bật cho Bác nghe nhé ạ.';

  static const String radioPlaying = 'Dạ cháu đang phát chương trình đài cho Bác thưởng thức đây ạ.';

  static const String voiceMemo =
      'Đây là góc lưu giữ Hồi ký Giọng nói. Bác chạm vào nút Ghi âm lớn màu xanh để bắt đầu kể lại những kỷ niệm đáng nhớ của đời mình. '
      'Cháu sẽ tự động lưu trữ an toàn cho Bác ạ.';

  static const String recordingStarted = 'Dạ cháu đang ghi âm hồi ký cho Bác rồi ạ. Bác cứ thong thả chia sẻ nhé ạ.';
  static const String recordingSaved = 'Dạ cháu đã lưu bản hồi ký của Bác vào bộ nhớ an toàn rồi ạ.';

  // ── 4. Nhịp thở Hoa Sen (Chu kỳ 4 - 4 - 6) ──
  static const String breathing =
      'Chào Bác! Đây là bài tập Nhịp thở Hoa Sen giúp Bác thư giãn tâm trí và điều hòa huyết áp.';

  static const String breathInhale = 'Bác hãy hít vào từ từ nhé...';
  static const String breathHold = 'Bác nín thở một chút nhé...';
  static const String breathExhale = 'Bác hãy từ từ thở ra cùng cháu nhé...';
  static const String breathingCompleted =
      'Chúc mừng Bác đã hoàn thành bài tập nhịp thở hoa sen. Chúc Bác có một ngày thật nhiều sức khỏe và an vui ạ.';

  // ── 5. Lịch sử, Cài đặt & Khẩn cấp (History, Settings & SOS) ──
  static const String history =
      'Đây là nơi lưu giữ tất cả các bản hồi ký giọng nói của Bác. Bác có thể mở lại để nghe hoặc xem phụ đề bất cứ lúc nào ạ.';

  static const String settings =
      'Đây là trang Cài đặt và Hỗ trợ tiếp cận. Bác có thể đổi tên hiển thị, điều chỉnh cỡ chữ lớn hơn, '
      'bật tính năng chống chạm nhầm, kích hoạt điều khiển bằng giọng nói toàn hệ thống, và lựa chọn giọng đọc ấm áp của cháu Aoede hoặc Charon ạ.';

  static const String sosTriggered =
      'Hệ thống khẩn cấp đã được kích hoạt. Đang liên hệ với người thân của Bác ngay lập tức.';
  static const String sosNoContacts =
      'Bác ơi, danh bạ khẩn cấp chưa có số người thân. Mời Bác thêm số điện thoại người thân để cháu hỗ trợ Bác kịp thời khi cần thiết nhé ạ.';
  static const String contactSaved = 'Đã lưu số điện thoại người thân vào danh bạ khẩn cấp thành công rồi ạ.';

  // ── 6. Phản hồi Điều hướng Tức thì ──
  static const String navHome = 'Dạ cháu đang đưa Bác về Trang chủ đây ạ.';
  static const String navVoiceMemo = 'Dạ cháu đang mở Hồi ký Giọng nói cho Bác đây ạ.';
  static const String navRadio = 'Dạ cháu đang mở Đài Radio Hoài Niệm cho Bác đây ạ.';
  static const String navBreathing = 'Dạ cháu đang mở bài tập Nhịp thở Hoa Sen cho Bác đây ạ.';
  static const String navSettings = 'Dạ cháu đang mở phần Cài đặt cho Bác đây ạ.';
  static const String navHistory = 'Dạ cháu đang mở Lịch sử Hồi ký cho Bác đây ạ.';
}

/// Trình quản lý phát giọng đọc hướng dẫn tự động toàn hệ thống
/// Tích hợp trực tiếp với SoundCoordinator để triệt tiêu chập âm.
class VoiceGuide {
  static bool get isVoiceEnabled => SoundCoordinator.isSoundEnabled;
  static set isVoiceEnabled(bool value) => SoundCoordinator.isSoundEnabled = value;

  static bool get isPlaying => SoundCoordinator.isPlayingVoice;

  /// Phát âm thanh hướng dẫn màn hình (có callback khi hoàn thành)
  static Future<void> play(
    String scriptText, {
    String voice = 'aoede',
    VoidCallback? onComplete,
  }) async {
    await SoundCoordinator.playVoice(
      text: scriptText,
      voice: voice,
      priority: AudioPriority.screenGuide,
      onComplete: onComplete,
    );
  }

  /// Phát âm thanh từng bước trong bài tập nhịp thở
  static Future<void> playBreathingStep(
    String scriptText, {
    String voice = 'aoede',
    VoidCallback? onComplete,
  }) async {
    await SoundCoordinator.playVoice(
      text: scriptText,
      voice: voice,
      priority: AudioPriority.breathingGuide,
      onComplete: onComplete,
    );
  }

  /// Dừng phát âm thanh
  static Future<void> stop() async {
    await SoundCoordinator.stopVoice();
  }
}
