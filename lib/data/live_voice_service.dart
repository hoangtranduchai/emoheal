import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/logger.dart';
import '../core/sound_coordinator.dart';
import 'api_service.dart';

/// Trạng thái phiên đàm thoại thời gian thực
enum LiveVoiceState {
  idle,
  connecting,
  listening,
  speaking,
  error,
}

/// Dịch vụ Trợ lý Giọng nói Trực tiếp (Gemini Live API Full-Duplex Streaming)
/// Tích hợp Smart Vocal Barge-In:
/// 1. Cho phép Bác cất lời ngắt AI bất cứ lúc nào ("Ý tôi không phải như vậy...")
/// 2. Dùng thuật toán RMS Vocal Gate để phân biệt giọng Bác chủ động nói (> 0.12) với tiếng loa dội nhẹ (< 0.10).
/// 3. Cắt lời ngay lập tức (< 20ms) và chuyển sang lắng nghe ý mới của Bác.
class LiveVoiceService {
  static final LiveVoiceService _instance = LiveVoiceService._internal();
  factory LiveVoiceService() => _instance;
  LiveVoiceService._internal();

  dynamic _socket; // WebSocket instance
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<List<int>>? _micStreamSubscription;

  LiveVoiceState _state = LiveVoiceState.idle;
  LiveVoiceState get state => _state;

  final _stateController = StreamController<LiveVoiceState>.broadcast();
  Stream<LiveVoiceState> get stateStream => _stateController.stream;

  final _inputTranscriptController = StreamController<String>.broadcast();
  Stream<String> get inputTranscriptStream => _inputTranscriptController.stream;

  final _outputTranscriptController = StreamController<String>.broadcast();
  Stream<String> get outputTranscriptStream => _outputTranscriptController.stream;

  final _searchGroundingController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get searchGroundingStream => _searchGroundingController.stream;

  // Callbacks
  Function(String name, Map<String, dynamic> args)? onToolCall;
  VoidCallback? onInterrupted;
  Function(String error)? onError;

  // Session Resumption
  String? _resumptionHandle;
  String? get resumptionHandle => _resumptionHandle;

  // Seamless Turn Buffer
  final List<int> _currentTurnPcm = [];
  bool _isPlayingAudio = false;
  bool _isActive = false;
  bool get isActive => _isActive;

  /// Tính năng lượng âm thanh RMS từ chunk PCM 16-bit
  static double _calculatePcmRms(List<int> chunk) {
    if (chunk.isEmpty) return 0.0;
    final sampleCount = chunk.length ~/ 2;
    if (sampleCount == 0) return 0.0;

    double sumSquares = 0.0;
    final byteData = ByteData.view(Uint8List.fromList(chunk).buffer);

    for (int i = 0; i < sampleCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      final normalized = sample / 32768.0;
      sumSquares += normalized * normalized;
    }

    return math.sqrt(sumSquares / sampleCount);
  }

  /// Khởi động phiên thoại trực tiếp (Full-Duplex Voice)
  Future<bool> startSession({String voice = 'aoede', bool resumeExisting = true}) async {
    if (_isActive) {
      AppLogger.w('Phiên Live Voice đang hoạt động, bỏ qua khởi động lại', tag: 'LIVE-VOICE');
      return true;
    }

    _setState(LiveVoiceState.connecting);
    _isActive = true;

    try {
      // 1. Kiểm tra quyền microphone
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        AppLogger.e('Chưa cấp quyền microphone cho Live Voice', tag: 'LIVE-VOICE');
        _setState(LiveVoiceState.error);
        _isActive = false;
        onError?.call('Vui lòng cấp quyền micro để trò chuyện trực tiếp cùng cháu.');
        return false;
      }

      // 2. Tạm dừng Radio và âm thanh khác để ưu tiên đàm thoại
      await SoundCoordinator.stopVoice(ifPriorityMatchesOrLower: AudioPriority.screenGuide);

      // 3. Kết nối WebSocket tới Backend với session handle (nếu có)
      String? token;
      try {
        token = Supabase.instance.client.auth.currentSession?.accessToken;
      } catch (_) {
        token = null;
      }

      final handleToUse = resumeExisting ? _resumptionHandle : null;
      final wsUri = ApiService.getLiveWsUri(token: token, voice: voice, sessionHandle: handleToUse);
      AppLogger.i('📡 Kết nối WebSocket Live Assistant tới: $wsUri', tag: 'LIVE-VOICE');

      if (!kIsWeb) {
        _socket = await WebSocket.connect(wsUri.toString());
        _socket.listen(
          _onSocketData,
          onError: (err) {
            AppLogger.e('Lỗi WebSocket Live: $err', tag: 'LIVE-VOICE');
            _handleError('Lỗi đường truyền kết nối: $err');
          },
          onDone: () {
            AppLogger.i('WebSocket Live đã ngắt kết nối', tag: 'LIVE-VOICE');
            if (_isActive) {
              stopSession();
            }
          },
        );
      } else {
        AppLogger.w('Nền tảng Web cần kết nối qua browser websocket adapter', tag: 'LIVE-VOICE');
      }

      // 4. Khởi động Micro Stream với Smart Vocal Barge-In Gate
      await _startMicStream();

      _setState(LiveVoiceState.listening);
      AppLogger.i('🎙️ Phiên đàm thoại Gemini Live đã sẵn sàng!', tag: 'LIVE-VOICE');
      return true;
    } catch (e, st) {
      AppLogger.e('Lỗi khởi tạo phiên Live Voice', tag: 'LIVE-VOICE', error: e, stackTrace: st);
      _handleError('Không thể kết nối Trợ lý AI trực tiếp: $e');
      return false;
    }
  }

  /// Bắt đầu stream dữ liệu âm thanh từ Microphone (16kHz PCM 16-bit Mono)
  Future<void> _startMicStream() async {
    try {
      const recordConfig = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      );

      final stream = await _audioRecorder.startStream(recordConfig);
      _micStreamSubscription?.cancel();
      _micStreamSubscription = stream.listen((chunk) {
        if (!_isActive || _socket == null) return;

        // SMART VOCAL BARGE-IN:
        // Nếu AI đang nói, chỉ truyền micro khi Bác thực sự cất lời nói chủ động (RMS >= 0.10)
        // để vừa cho phép Bác ngắt lời ("Ý tôi không phải như vậy"), vừa không bị tiếng dội loa tự ngắt.
        if (_isPlayingAudio || _state == LiveVoiceState.speaking) {
          final rms = _calculatePcmRms(chunk);
          if (rms >= 0.10) {
            AppLogger.i('⚡ [BARGE-IN] Bác cất lời ngắt AI (RMS: ${rms.toStringAsFixed(3)}) -> Dừng loa ngay lập tức!', tag: 'LIVE-VOICE');
            _handleInterruption();
          } else {
            // Tiếng loa dội nhẹ (< 0.10) -> Bỏ qua để AI nói trôi chảy
            return;
          }
        }

        try {
          final base64Audio = base64Encode(chunk);
          final msg = jsonEncode({
            'type': 'audio',
            'data': base64Audio,
          });
          if (!kIsWeb && _socket != null) {
            _socket.add(msg);
          }
        } catch (e) {
          AppLogger.d('Lỗi gửi mic chunk: $e', tag: 'LIVE-VOICE');
        }
      });
      AppLogger.d('Đã kích hoạt luồng 16kHz PCM Microphone Stream với Smart Vocal Barge-In Gate', tag: 'LIVE-VOICE');
    } catch (e, st) {
      AppLogger.e('Lỗi khởi động mic stream', tag: 'LIVE-VOICE', error: e, stackTrace: st);
    }
  }

  /// Gửi tín hiệu báo dừng lượt nói (Hybrid VAD fast finalization)
  void sendEndOfTurn() {
    if (!_isActive || _socket == null) return;
    try {
      final msg = jsonEncode({'type': 'audio_stream_end'});
      if (!kIsWeb && _socket != null) {
        _socket.add(msg);
      }
      AppLogger.d('⚡ Gửi tín hiệu audio_stream_end cho Hybrid VAD', tag: 'LIVE-VOICE');
    } catch (e) {
      AppLogger.d('Lỗi gửi audio_stream_end: $e', tag: 'LIVE-VOICE');
    }
  }

  /// Xử lý gói tin nhận từ WebSocket Server
  void _onSocketData(dynamic rawData) {
    try {
      final jsonStr = rawData.toString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'session_started':
          AppLogger.i('⚡ Nhận sự kiện Session Started: ${data['model']}', tag: 'LIVE-VOICE');
          break;

        case 'resumption_handle':
          final handle = data['handle'] as String?;
          if (handle != null && handle.isNotEmpty) {
            _resumptionHandle = handle;
            AppLogger.d('🔑 Đã lưu Session Resumption Handle mới', tag: 'LIVE-VOICE');
          }
          break;

        case 'go_away':
          final timeLeft = data['time_left'] as String? ?? '';
          AppLogger.w('⏳ Máy chủ thông báo GoAway, thời gian còn lại: $timeLeft', tag: 'LIVE-VOICE');
          break;

        case 'interrupted':
          // Chỉ nhận diện interrupted khi người dùng thực sự chủ động cắt lời
          AppLogger.i('⚡ [BARGE-IN] Cắt lời -> Dừng phát âm thanh', tag: 'LIVE-VOICE');
          _handleInterruption();
          break;

        case 'audio_chunk':
          final base64Audio = data['data'] as String?;
          if (base64Audio != null && base64Audio.isNotEmpty) {
            final pcmBytes = base64Decode(base64Audio);
            _currentTurnPcm.addAll(pcmBytes);
            if (_state != LiveVoiceState.speaking) {
              _setState(LiveVoiceState.speaking);
            }
          }
          break;

        case 'transcript_input':
          final text = data['text'] as String?;
          if (text != null && text.isNotEmpty) {
            AppLogger.d('🗣️ Bác nói: "$text"', tag: 'LIVE-VOICE');
            _inputTranscriptController.add(text);
          }
          break;

        case 'transcript_output':
          final text = data['text'] as String?;
          if (text != null && text.isNotEmpty) {
            AppLogger.d('🤖 Cháu nói: "$text"', tag: 'LIVE-VOICE');
            _outputTranscriptController.add(text);
          }
          break;

        case 'search_grounding':
          final queries = (data['queries'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          final sources = (data['sources'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
          AppLogger.i('🌐 Nhận kết quả Google Search Grounding: $queries', tag: 'LIVE-VOICE');
          _searchGroundingController.add({'queries': queries, 'sources': sources});
          break;

        case 'generation_complete':
          AppLogger.d('🏁 AI hoàn tất câu trả lời -> Bắt đầu phát âm thanh mượt mà liên tục', tag: 'LIVE-VOICE');
          _flushTurnAudioAndPlay();
          break;

        case 'tool_call':
          final name = data['name'] as String? ?? '';
          final args = (data['args'] as Map<String, dynamic>?) ?? {};
          AppLogger.i('🛠️ Nhận yêu cầu Tool Call từ Gemini: $name, args: $args', tag: 'LIVE-VOICE');
          onToolCall?.call(name, args);
          break;

        case 'error':
          final msg = data['message'] as String? ?? 'Sự cố không xác định';
          AppLogger.w('Cảnh báo từ Live Server: $msg', tag: 'LIVE-VOICE');
          _outputTranscriptController.add(msg);
          _setState(LiveVoiceState.error);
          break;
      }
    } catch (e) {
      AppLogger.w('Lỗi giải mã gói tin WebSocket: $e', tag: 'LIVE-VOICE');
    }
  }

  /// Phát toàn bộ lượt thoại của AI trong một luồng WAV liên tục (Zero-Gap Playback)
  Future<void> _flushTurnAudioAndPlay() async {
    if (_currentTurnPcm.isEmpty) {
      if (_isActive && !_isPlayingAudio) {
        _setState(LiveVoiceState.listening);
      }
      return;
    }

    final pcmBytes = Uint8List.fromList(List.from(_currentTurnPcm));
    _currentTurnPcm.clear();

    final wavBytes = _createWavBuffer(pcmBytes, sampleRate: 24000);
    _isPlayingAudio = true;
    _setState(LiveVoiceState.speaking);

    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(BytesSource(wavBytes));
      
      _audioPlayer.onPlayerComplete.first.then((_) {
        _isPlayingAudio = false;
        if (_isActive) {
          // Nếu còn dữ liệu mới đến tiếp, phát tiếp
          if (_currentTurnPcm.isNotEmpty) {
            _flushTurnAudioAndPlay();
          } else {
            _setState(LiveVoiceState.listening);
            AppLogger.d('🎧 Đã hoàn tất phát câu trả lời -> Mở lại Microphone lắng nghe Bác', tag: 'LIVE-VOICE');
          }
        }
      });
    } catch (e) {
      AppLogger.d('Lỗi phát lượt thoại: $e', tag: 'LIVE-VOICE');
      _isPlayingAudio = false;
      if (_isActive) {
        _setState(LiveVoiceState.listening);
      }
    }
  }

  /// Xử lý cắt lời tức thì (Barge-in < 50ms)
  void _handleInterruption() {
    _currentTurnPcm.clear();
    _isPlayingAudio = false;
    try {
      _audioPlayer.stop();
    } catch (_) {}
    _setState(LiveVoiceState.listening);
    onInterrupted?.call();
  }

  /// Đóng phiên đàm thoại
  Future<void> stopSession() async {
    if (!_isActive) return;
    _isActive = false;
    AppLogger.i('🛑 Đang đóng phiên Live Voice...', tag: 'LIVE-VOICE');

    _currentTurnPcm.clear();
    _isPlayingAudio = false;

    try {
      await _audioPlayer.stop();
    } catch (_) {}

    try {
      _micStreamSubscription?.cancel();
      _micStreamSubscription = null;
      await _audioRecorder.stop();
    } catch (_) {}

    try {
      if (!kIsWeb && _socket != null) {
        _socket.close();
        _socket = null;
      }
    } catch (_) {}

    _setState(LiveVoiceState.idle);
  }

  void _handleError(String message) {
    _setState(LiveVoiceState.error);
    onError?.call(message);
    stopSession();
  }

  void _setState(LiveVoiceState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(_state);
    }
  }

  /// Tạo WAV Buffer 44-byte chuẩn cho 24kHz 16-bit Mono PCM
  Uint8List _createWavBuffer(Uint8List pcmBytes, {int sampleRate = 24000, int channels = 1, int bitsPerSample = 16}) {
    final totalDataLen = pcmBytes.length;
    final totalAudioLen = totalDataLen + 36;
    final byteRate = (sampleRate * channels * bitsPerSample) ~/ 8;
    final blockAlign = (channels * bitsPerSample) ~/ 8;

    final header = Uint8List(44);
    final buffer = ByteData.view(header.buffer);

    // RIFF header
    header[0] = 0x52; // 'R'
    header[1] = 0x49; // 'I'
    header[2] = 0x46; // 'F'
    header[3] = 0x46; // 'F'
    buffer.setUint32(4, totalAudioLen, Endian.little);
    header[8] = 0x57;  // 'W'
    header[9] = 0x41;  // 'A'
    header[10] = 0x56; // 'V'
    header[11] = 0x45; // 'E'

    // fmt chunk
    header[12] = 0x66; // 'f'
    header[13] = 0x6D; // 'm'
    header[14] = 0x74; // 't'
    header[15] = 0x20; // ' '
    buffer.setUint32(16, 16, Endian.little); // Chunk size
    buffer.setUint16(20, 1, Endian.little);  // Format: PCM
    buffer.setUint16(22, channels, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, blockAlign, Endian.little);
    buffer.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    header[36] = 0x64; // 'd'
    header[37] = 0x61; // 'a'
    header[38] = 0x74; // 't'
    header[39] = 0x61; // 'a'
    buffer.setUint32(40, totalDataLen, Endian.little);

    final result = Uint8List(44 + totalDataLen);
    result.setRange(0, 44, header);
    result.setRange(44, 44 + totalDataLen, pcmBytes);
    return result;
  }

  void dispose() {
    stopSession();
    _stateController.close();
    _inputTranscriptController.close();
    _outputTranscriptController.close();
    _searchGroundingController.close();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
  }
}
