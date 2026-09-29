import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import '../data/api_service.dart';
import 'logger.dart';
import 'voice_guide.dart';

/// Các mức độ ưu tiên âm thanh toàn hệ thống EmoHeal
enum AudioPriority {
  /// Mức 1: Cực kỳ khẩn cấp - SOS (Cắt ngay lập tức toàn bộ âm thanh khác)
  urgentSos(100),

  /// Mức 2: Trợ lý AI đang nói / trả lời tâm sự
  assistantVoice(80),

  /// Mức 3: Giọng đọc hướng dẫn nhịp thở hoa sen (từng nhịp hít/giữ/thở)
  breathingGuide(60),

  /// Mức 4: Giọng đọc hướng dẫn khi vào màn hình
  screenGuide(40),

  /// Mức 5: Âm thanh nền / Đài radio hoài niệm
  backgroundRadio(10);

  final int value;
  const AudioPriority(this.value);
}

/// Bộ Điều Phối Âm Thanh Toàn Cục (Central Sound Coordinator)
/// Tích hợp cơ chế Asset-First (Phát tức thì 0.00ms từ file đóng gói sẵn) + Fallback Backend Dynamic.
class SoundCoordinator {
  static final AudioPlayer _voicePlayer = AudioPlayer();
  static AudioPlayer? _activeRadioPlayer;
  static bool _isRadioPausedByVoice = false;

  static AudioPriority _currentPriority = AudioPriority.backgroundRadio;
  static bool _isPlayingVoice = false;
  static int _currentToken = 0;
  static bool _isAudioConfigured = false;
  static bool isSoundEnabled = true;

  static bool get isPlayingVoice => _isPlayingVoice;
  static AudioPriority get currentPriority => _currentPriority;

  /// Bảng ánh xạ kịch bản sang tên tệp đóng gói sẵn trong assets/audio/
  static final Map<String, String> _scriptKeyMap = {
    VoiceScripts.onboarding: 'onboarding',
    VoiceScripts.login: 'login',
    VoiceScripts.otp: 'otp',
    VoiceScripts.home: 'home',
    VoiceScripts.chat: 'chat',
    VoiceScripts.radio: 'radio',
    VoiceScripts.voiceMemo: 'voicememo',
    VoiceScripts.breathing: 'breathing_intro',
    VoiceScripts.breathInhale: 'inhale',
    VoiceScripts.breathHold: 'hold',
    VoiceScripts.breathExhale: 'exhale',
    VoiceScripts.breathingCompleted: 'breathing_completed',
    VoiceScripts.history: 'history',
    VoiceScripts.settings: 'settings',
    VoiceScripts.sosTriggered: 'sos',
  };

  /// Đăng ký AudioPlayer của Đài Radio để tự động tạm dừng/tiếp tục khi có giọng nói
  static void registerRadioPlayer(AudioPlayer? radioPlayer) {
    _activeRadioPlayer = radioPlayer;
  }

  static void _ensureAudioConfigured() {
    if (_isAudioConfigured) return;
    _isAudioConfigured = true;

    try {
      AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.assistanceNavigationGuidance,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.duckOthers,
            },
          ),
        ),
      );
    } catch (_) {}
  }

  /// Phát giọng đọc thông minh (Ưu tiên tệp Asset 0.00ms, không tốn mạng và chi phí)
  static Future<void> playVoice({
    required String text,
    String voice = 'aoede',
    AudioPriority priority = AudioPriority.screenGuide,
    VoidCallback? onComplete,
  }) async {
    if (!isSoundEnabled) {
      AppLogger.d('Âm thanh đang tắt trong cài đặt.', tag: 'SOUND-COORD');
      onComplete?.call();
      return;
    }

    // Nếu đang phát âm thanh có độ ưu tiên cao hơn, bỏ qua âm thanh thấp hơn
    if (_isPlayingVoice && _currentPriority.value > priority.value) {
      AppLogger.d('Bỏ qua âm thanh ưu tiên thấp hơn: "$text"', tag: 'SOUND-COORD');
      return;
    }

    _ensureAudioConfigured();
    final int token = ++_currentToken;

    // 1. Tạm dừng Đài Radio nếu đang phát để nhường chỗ cho giọng nói
    if (_activeRadioPlayer != null && priority.value >= AudioPriority.screenGuide.value) {
      try {
        if (_activeRadioPlayer!.state == PlayerState.playing) {
          _isRadioPausedByVoice = true;
          await _activeRadioPlayer!.pause();
          AppLogger.d('Đã tạm dừng Đài Radio để nhường chỗ cho giọng nói', tag: 'SOUND-COORD');
        }
      } catch (_) {}
    }

    // 2. Dừng âm thanh giọng nói trước đó
    try {
      await _voicePlayer.stop();
    } catch (_) {}

    _isPlayingVoice = true;
    _currentPriority = priority;

    // Chuẩn hóa tên giọng thuần Google Gemini Native
    final voicePrefix = (voice.toLowerCase() == 'charon' || voice.toLowerCase() == 'male') ? 'charon' : 'aoede';

    // 3. CHIẾN LƯỢC TẦNG 1: Kiểm tra tệp đóng gói sẵn trong assets/audio/ (0.00ms, Offline, $0 Cost)
    final scriptKey = _scriptKeyMap[text];
    if (scriptKey != null) {
      final assetPath = 'audio/${voicePrefix}_$scriptKey.mp3';
      try {
        AppLogger.i('⚡ [ASSET-AUDIO] Phát ngay từ bộ nhớ máy (0.00ms): $assetPath', tag: 'SOUND-COORD');
        await _voicePlayer.setVolume(1.0);
        await _voicePlayer.play(AssetSource(assetPath));

        _voicePlayer.onPlayerComplete.first.then((_) {
          if (token == _currentToken) {
            _isPlayingVoice = false;
            _currentPriority = AudioPriority.backgroundRadio;
            
            if (_isRadioPausedByVoice && _activeRadioPlayer != null) {
              _isRadioPausedByVoice = false;
              _activeRadioPlayer!.resume();
            }

            onComplete?.call();
          }
        });
        return;
      } catch (assetErr) {
        AppLogger.w('Không tải được asset $assetPath ($assetErr), chuyển sang tầng 2 backend.', tag: 'SOUND-COORD');
      }
    }

    // 4. CHIẾN LƯỢC TẦNG 2: Gọi Backend TTS nếu là câu nói động tùy biến
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/tts');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text, 'voice': voicePrefix}),
      );

      if (token != _currentToken) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final audioUrl = data['audio_url'] as String?;
        if (audioUrl != null && audioUrl.isNotEmpty) {
          final fullUrl = audioUrl.startsWith('http')
              ? audioUrl
              : (audioUrl.startsWith('/')
                  ? '${ApiService.baseUrl}$audioUrl'
                  : '${ApiService.baseUrl}/$audioUrl');

          final audioRes = await http.get(Uri.parse(fullUrl));
          if (token != _currentToken) return;

          if (audioRes.statusCode == 200 && audioRes.bodyBytes.isNotEmpty) {
            await _voicePlayer.setVolume(1.0);
            await _voicePlayer.play(BytesSource(audioRes.bodyBytes));

            _voicePlayer.onPlayerComplete.first.then((_) {
              if (token == _currentToken) {
                _isPlayingVoice = false;
                _currentPriority = AudioPriority.backgroundRadio;
                
                if (_isRadioPausedByVoice && _activeRadioPlayer != null) {
                  _isRadioPausedByVoice = false;
                  _activeRadioPlayer!.resume();
                }

                onComplete?.call();
              }
            });
            return;
          }
        }
      }
    } catch (e) {
      AppLogger.w('Không thể phát giọng đọc qua backend: $e', tag: 'SOUND-COORD');
    }

    // Giải phóng trạng thái khi kết thúc hoặc gặp sự cố
    if (token == _currentToken) {
      _isPlayingVoice = false;
      _currentPriority = AudioPriority.backgroundRadio;
      if (_isRadioPausedByVoice && _activeRadioPlayer != null) {
        _isRadioPausedByVoice = false;
        _activeRadioPlayer?.resume();
      }
      onComplete?.call();
    }
  }

  /// Dừng giọng nói ngay lập tức
  static Future<void> stopVoice({AudioPriority? ifPriorityMatchesOrLower}) async {
    if (ifPriorityMatchesOrLower != null &&
        _isPlayingVoice &&
        _currentPriority.value > ifPriorityMatchesOrLower.value) {
      return;
    }

    _currentToken++;
    _isPlayingVoice = false;
    _currentPriority = AudioPriority.backgroundRadio;
    try {
      await _voicePlayer.stop();
    } catch (_) {}

    if (_isRadioPausedByVoice && _activeRadioPlayer != null) {
      _isRadioPausedByVoice = false;
      _activeRadioPlayer?.resume();
    }
  }

  /// Dừng toàn bộ âm thanh (khi người dùng thoát app hoặc nhấn SOS)
  static Future<void> stopAll() async {
    _currentToken++;
    _isPlayingVoice = false;
    _isRadioPausedByVoice = false;
    _currentPriority = AudioPriority.backgroundRadio;
    try {
      await _voicePlayer.stop();
      await _activeRadioPlayer?.stop();
    } catch (_) {}
  }
}
