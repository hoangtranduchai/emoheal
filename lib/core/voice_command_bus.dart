import 'dart:async';
import 'logger.dart';

/// Các hành động điều khiển đài phát thanh qua giọng nói
enum VoiceRadioAction {
  play,
  pause,
  resume,
  stop,
  next,
  prev,
  selectGenre,
}

/// Lệnh điều khiển đài Radio
class VoiceRadioCommand {
  final VoiceRadioAction action;
  final String? genre;
  final String? trackTitle;

  const VoiceRadioCommand({
    required this.action,
    this.genre,
    this.trackTitle,
  });

  @override
  String toString() => 'VoiceRadioCommand(action: $action, genre: $genre, trackTitle: $trackTitle)';
}

/// Các hành động điều khiển bài tập thở qua giọng nói
enum VoiceBreathingAction {
  start,
  pause,
  resume,
  stop,
}

/// Lệnh điều khiển Nhịp thở Hoa Sen
class VoiceBreathingCommand {
  final VoiceBreathingAction action;

  const VoiceBreathingCommand({required this.action});

  @override
  String toString() => 'VoiceBreathingCommand(action: $action)';
}

/// Các hành động điều khiển Hồi ký qua giọng nói
enum VoiceMemoAction {
  startRecording,
  pauseRecording,
  stopAndSave,
  changeTopic,
}

/// Lệnh điều khiển Hồi ký Giọng nói
class VoiceMemoCommand {
  final VoiceMemoAction action;
  final String? topic;

  const VoiceMemoCommand({
    required this.action,
    this.topic,
  });

  @override
  String toString() => 'VoiceMemoCommand(action: $action, topic: $topic)';
}

/// Lệnh điều khiển Cài đặt Trợ năng qua giọng nói
class VoiceSettingsCommand {
  final double? fontDelta;
  final String? voiceType;
  final bool? soundEnabled;

  const VoiceSettingsCommand({
    this.fontDelta,
    this.voiceType,
    this.soundEnabled,
  });

  @override
  String toString() => 'VoiceSettingsCommand(fontDelta: $fontDelta, voiceType: $voiceType, soundEnabled: $soundEnabled)';
}

/// Lệnh kích hoạt báo động khẩn cấp SOS
class VoiceSosCommand {
  final String reason;
  final int countdownSeconds;

  const VoiceSosCommand({
    this.reason = 'Bác kích hoạt khẩn cấp qua giọng nói',
    this.countdownSeconds = 3,
  });

  @override
  String toString() => 'VoiceSosCommand(reason: $reason, countdownSeconds: $countdownSeconds)';
}

/// Lệnh điều hướng màn hình tổng quát
class VoiceNavigationCommand {
  final String targetRoute;
  final String screenName;

  const VoiceNavigationCommand({
    required this.targetRoute,
    required this.screenName,
  });

  @override
  String toString() => 'VoiceNavigationCommand(targetRoute: $targetRoute, screenName: $screenName)';
}

/// Bus Điều Phối Lệnh Giọng Nói Toàn Cục (Central Voice Command Bus)
/// Nhận lệnh từ Gemini Live API (Spoken Function Calling) và REST Multimodal SER,
/// sau đó phân phát chính xác tới các màn hình và widget đang hoạt động.
class VoiceCommandBus {
  VoiceCommandBus._();
  static final VoiceCommandBus _instance = VoiceCommandBus._();
  factory VoiceCommandBus() => _instance;

  final _radioController = StreamController<VoiceRadioCommand>.broadcast();
  Stream<VoiceRadioCommand> get radioCommands => _radioController.stream;

  final _breathingController = StreamController<VoiceBreathingCommand>.broadcast();
  Stream<VoiceBreathingCommand> get breathingCommands => _breathingController.stream;

  final _memoController = StreamController<VoiceMemoCommand>.broadcast();
  Stream<VoiceMemoCommand> get memoCommands => _memoController.stream;

  final _settingsController = StreamController<VoiceSettingsCommand>.broadcast();
  Stream<VoiceSettingsCommand> get settingsCommands => _settingsController.stream;

  final _sosController = StreamController<VoiceSosCommand>.broadcast();
  Stream<VoiceSosCommand> get sosCommands => _sosController.stream;

  final _navController = StreamController<VoiceNavigationCommand>.broadcast();
  Stream<VoiceNavigationCommand> get navigationCommands => _navController.stream;

  /// Phát lệnh điều khiển Radio
  void dispatchRadio(VoiceRadioAction action, {String? genre, String? trackTitle}) {
    final cmd = VoiceRadioCommand(action: action, genre: genre, trackTitle: trackTitle);
    AppLogger.i('📻 [VOICE-BUS] Phát lệnh Radio: $cmd', tag: 'VOICE-BUS');
    _radioController.add(cmd);
  }

  /// Phát lệnh điều khiển Nhịp thở
  void dispatchBreathing(VoiceBreathingAction action) {
    final cmd = VoiceBreathingCommand(action: action);
    AppLogger.i('🌸 [VOICE-BUS] Phát lệnh Nhịp thở: $cmd', tag: 'VOICE-BUS');
    _breathingController.add(cmd);
  }

  /// Phát lệnh điều khiển Hồi ký
  void dispatchMemo(VoiceMemoAction action, {String? topic}) {
    final cmd = VoiceMemoCommand(action: action, topic: topic);
    AppLogger.i('🎙️ [VOICE-BUS] Phát lệnh Hồi ký: $cmd', tag: 'VOICE-BUS');
    _memoController.add(cmd);
  }

  /// Phát lệnh điều khiển Cài đặt
  void dispatchSettings({double? fontDelta, String? voiceType, bool? soundEnabled}) {
    final cmd = VoiceSettingsCommand(fontDelta: fontDelta, voiceType: voiceType, soundEnabled: soundEnabled);
    AppLogger.i('⚙️ [VOICE-BUS] Phát lệnh Cài đặt: $cmd', tag: 'VOICE-BUS');
    _settingsController.add(cmd);
  }

  /// Phát lệnh kích hoạt SOS
  void dispatchSos({String? reason, int countdownSeconds = 3}) {
    final cmd = VoiceSosCommand(reason: reason ?? 'Khẩn cấp từ giọng nói', countdownSeconds: countdownSeconds);
    AppLogger.e('🚨 [VOICE-BUS] Phát lệnh SOS khẩn cấp: $cmd', tag: 'VOICE-BUS');
    _sosController.add(cmd);
  }

  /// Phát lệnh điều hướng màn hình
  void dispatchNavigation(String targetRoute, String screenName) {
    final cmd = VoiceNavigationCommand(targetRoute: targetRoute, screenName: screenName);
    AppLogger.i('🧭 [VOICE-BUS] Phát lệnh Điều hướng: $cmd', tag: 'VOICE-BUS');
    _navController.add(cmd);
  }

  /// Xử lý và phân bổ Tool Call nhận từ AI (Function Calling Router)
  void dispatchToolCall(String name, Map<String, dynamic> args) {
    AppLogger.i('⚡ [VOICE-BUS] Phân tích Spoken Tool Call: $name (Args: $args)', tag: 'VOICE-BUS');

    switch (name) {
      // 1. Radio
      case 'open_radio':
        final genre = args['genre'] as String?;
        dispatchNavigation('/radio', 'radio');
        if (genre != null && genre.isNotEmpty) {
          dispatchRadio(VoiceRadioAction.selectGenre, genre: genre);
        } else {
          dispatchRadio(VoiceRadioAction.play);
        }
        break;

      case 'control_radio':
        final rawAction = (args['action'] as String?)?.toLowerCase() ?? 'play';
        final genre = args['genre'] as String?;
        final trackTitle = args['track_title'] as String?;

        VoiceRadioAction action = VoiceRadioAction.play;
        if (rawAction == 'pause' || rawAction == 'stop') {
          action = VoiceRadioAction.pause;
        } else if (rawAction == 'resume' || rawAction == 'play') {
          action = VoiceRadioAction.resume;
        } else if (rawAction == 'next') {
          action = VoiceRadioAction.next;
        } else if (rawAction == 'prev' || rawAction == 'previous') {
          action = VoiceRadioAction.prev;
        } else if (rawAction == 'select_genre') {
          action = VoiceRadioAction.selectGenre;
        }
        dispatchRadio(action, genre: genre, trackTitle: trackTitle);
        break;

      // 2. Nhịp thở Hoa Sen
      case 'start_breathing_exercise':
        dispatchNavigation('/lotus_breathing', 'breathing');
        dispatchBreathing(VoiceBreathingAction.start);
        break;

      case 'control_breathing':
        final rawAction = (args['action'] as String?)?.toLowerCase() ?? 'start';
        VoiceBreathingAction action = VoiceBreathingAction.start;
        if (rawAction == 'pause') {
          action = VoiceBreathingAction.pause;
        } else if (rawAction == 'resume') {
          action = VoiceBreathingAction.resume;
        } else if (rawAction == 'stop') {
          action = VoiceBreathingAction.stop;
        }
        dispatchBreathing(action);
        break;

      // 3. Hồi ký Giọng nói
      case 'open_voice_memo':
        final promptTitle = args['prompt_title'] as String?;
        dispatchNavigation('/voice_memos', 'voice_memo');
        if (promptTitle != null && promptTitle.isNotEmpty) {
          dispatchMemo(VoiceMemoAction.changeTopic, topic: promptTitle);
        }
        break;

      case 'control_voice_memo':
        final rawAction = (args['action'] as String?)?.toLowerCase().replaceAll('_', '') ?? 'startrecording';
        final topic = args['topic'] as String?;
        VoiceMemoAction action = VoiceMemoAction.startRecording;
        if (rawAction == 'pauserecording' || rawAction == 'pause') {
          action = VoiceMemoAction.pauseRecording;
        } else if (rawAction == 'stopandsave' || rawAction == 'save' || rawAction == 'stopsave') {
          action = VoiceMemoAction.stopAndSave;
        } else if (rawAction == 'changetopic' || rawAction == 'topic') {
          action = VoiceMemoAction.changeTopic;
        }
        dispatchMemo(action, topic: topic);
        break;

      // 4. Cài đặt & Trợ năng
      case 'open_settings':
        dispatchNavigation('/settings', 'settings');
        break;

      case 'adjust_settings':
        final settingType = (args['setting_type'] as String?)?.toLowerCase() ?? '';
        final fontDeltaRaw = args['font_delta'];
        double? fontDelta;
        if (fontDeltaRaw is num) {
          fontDelta = fontDeltaRaw.toDouble();
        } else if (settingType == 'font_size') {
          fontDelta = 0.15;
        }
        final voiceType = args['voice_type'] as String?;
        final soundEnabled = args['sound_enabled'] as bool?;

        dispatchSettings(
          fontDelta: fontDelta,
          voiceType: voiceType,
          soundEnabled: soundEnabled,
        );
        break;

      // 5. Lịch sử
      case 'open_history':
        dispatchNavigation('/history', 'history');
        break;

      // 6. Điều hướng tổng quát
      case 'navigate_to_screen':
        final rawTarget = ((args['screen_name'] ?? args['screen'] ?? args['target'] ?? args['destination']) as String?)?.toLowerCase() ?? 'home';
        final target = rawTarget.replaceAll('-', '_');
        if (target == 'voice_memo' || target == 'voicememo' || target == 'voice_memos') {
          dispatchNavigation('/voice_memos', 'voice_memo');
        } else if (target == 'radio') {
          dispatchNavigation('/radio', 'radio');
        } else if (target == 'breathing' || target == 'lotus_breathing' || target == 'lotusbreathing') {
          dispatchNavigation('/lotus_breathing', 'breathing');
        } else if (target == 'settings') {
          dispatchNavigation('/settings', 'settings');
        } else if (target == 'history') {
          dispatchNavigation('/history', 'history');
        } else {
          dispatchNavigation('/home', 'home');
        }
        break;

      // 7. Kích hoạt khẩn cấp SOS
      case 'trigger_sos_emergency':
        final reason = (args['reason'] as String?) ?? 'Phát hiện khẩn cấp qua giọng nói';
        dispatchSos(reason: reason, countdownSeconds: 3);
        break;
    }
  }

  void dispose() {
    _radioController.close();
    _breathingController.close();
    _memoController.close();
    _settingsController.close();
    _sosController.close();
    _navController.close();
  }
}
