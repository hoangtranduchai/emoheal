import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/logger.dart';

class ApiService {
  // Backend URL — Dynamic detection for Web, Phone ADB, and custom environments
  // Tự động nhận diện URL Backend phù hợp cho từng nền tảng, chuẩn hóa 127.0.0.1 chống lỗi DNS
  static String get baseUrl {
    const envUrl = String.fromEnvironment('BACKEND_URL');
    if (envUrl.isNotEmpty) {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && envUrl.contains('localhost')) {
        return envUrl.replaceFirst('localhost', '127.0.0.1');
      }
      return envUrl;
    }

    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isNotEmpty && host != 'localhost' && host != '127.0.0.1') {
        return 'http://$host:8000';
      }
      return 'http://localhost:8000';
    }

    if (Platform.isAndroid) {
      // ADB reverse chuyển tiếp port 8000 về 127.0.0.1:8000 trên thiết bị thật
      return 'http://127.0.0.1:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  static final http.Client httpClient = http.Client();

  // WebSocket Live AI URL
  static String get wsUrl {
    final base = baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
    return '$base/ws/live-assistant';
  }

  static Uri getLiveWsUri({String? token, String? voice, String? sessionHandle}) {
    final base = wsUrl;
    final params = <String, String>{};
    if (token != null && token.isNotEmpty) params['token'] = token;
    if (voice != null && voice.isNotEmpty) params['voice'] = voice;
    if (sessionHandle != null && sessionHandle.isNotEmpty) params['session_handle'] = sessionHandle;
    
    if (params.isEmpty) return Uri.parse(base);
    final queryString = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return Uri.parse('$base?$queryString');
  }

  /// Kiểm tra số điện thoại đã đăng ký chưa để đăng nhập trực tiếp không cần OTP
  static Future<Map<String, dynamic>?> checkRegisteredPhone(String phone) async {
    try {
      final uri = Uri.parse('$baseUrl/api/auth/check-registered');
      final res = await httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      AppLogger.d('Kiểm tra số điện thoại đăng ký: $e', tag: 'API');
    }
    return null;
  }

  static Future<Map<String, dynamic>> sendAssistantRequest({
    String? text,
    String? audioPath,
    String? voice,
    List<Map<String, dynamic>>? history,
  }) async {
    final stopwatch = Stopwatch()..start();
    String? token;
    try {
      token = Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      token = null;
    }

    final uri = Uri.parse('$baseUrl/api/assistant');
    final request = http.MultipartRequest('POST', uri);

    AppLogger.d(
      'Gửi yêu cầu AI Assistant tới $uri: [text: ${text != null && text.isNotEmpty ? '"$text"' : 'null'}, '
      'audio: ${audioPath ?? 'null'}, voice: ${voice ?? 'default'}, '
      'auth: ${token != null ? 'Bearer (kèm JWT)' : 'Chế độ Khách (Guest)'}]',
      tag: 'API',
    );

    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    if (text != null && text.isNotEmpty) {
      request.fields['text'] = text;
    }

    if (voice != null && voice.isNotEmpty) {
      request.fields['voice'] = voice;
    }

    if (history != null && history.isNotEmpty) {
      request.fields['history'] = jsonEncode(history);
      AppLogger.d('Kèm theo ${history.length} tin nhắn lịch sử trò chuyện', tag: 'API');
    }

    if (audioPath != null && audioPath.isNotEmpty) {
      final file = File(audioPath);
      if (await file.exists()) {
        final fileSize = await file.length();
        AppLogger.d('Đính kèm file ghi âm: $audioPath (${fileSize ~/ 1024} KB)', tag: 'API');
        request.files.add(await http.MultipartFile.fromPath('audio', audioPath));
      } else {
        AppLogger.w('File ghi âm không tồn tại tại đường dẫn: $audioPath', tag: 'API');
      }
    }

    try {
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      stopwatch.stop();

      AppLogger.network(
        'POST',
        uri.toString(),
        statusCode: response.statusCode,
        duration: stopwatch.elapsed,
        data: responseData.length > 300 ? '${responseData.substring(0, 300)}...' : responseData,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(responseData) as Map<String, dynamic>;
        AppLogger.i(
          'Nhận phản hồi AI thành công: Intent=${decoded['intent']}, Target=${decoded['target']}, Audio=${decoded['audio_url'] != null}',
          tag: 'API',
        );
        return decoded;
      } else {
        AppLogger.e(
          'Lỗi kết nối Backend API: HTTP ${response.statusCode}',
          tag: 'API',
          error: responseData,
        );
        throw Exception('Lỗi kết nối: ${response.statusCode} - $responseData');
      }
    } catch (e, st) {
      stopwatch.stop();
      AppLogger.network(
        'POST',
        uri.toString(),
        duration: stopwatch.elapsed,
        error: e,
      );
      AppLogger.e('Lỗi trong quá trình gửi yêu cầu AI', tag: 'API', error: e, stackTrace: st);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> sendTextAssistantRequest({
    required String text,
    String? voice,
    List<Map<String, dynamic>>? history,
  }) async {
    final stopwatch = Stopwatch()..start();
    String? token;
    try {
      token = Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      token = null;
    }

    final uri = Uri.parse('$baseUrl/api/assistant/text');
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final body = <String, String>{
      'text': text,
    };
    if (voice != null && voice.isNotEmpty) {
      body['voice'] = voice;
    }
    if (history != null && history.isNotEmpty) {
      body['history'] = jsonEncode(history);
    }

    try {
      final response = await http.post(uri, headers: headers, body: body);
      stopwatch.stop();

      AppLogger.network(
        'POST',
        uri.toString(),
        statusCode: response.statusCode,
        duration: stopwatch.elapsed,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Lỗi kết nối Text AI: ${response.statusCode}');
      }
    } catch (e) {
      stopwatch.stop();
      AppLogger.e('Lỗi gửi text AI: $e', tag: 'API');
      rethrow;
    }
  }

  /// Nhận diện giọng nói thành văn bản chuyên biệt cho Hồi ký (Gemini Multimodal STT)
  static Future<String> transcribeVoiceMemo(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      AppLogger.w('File ghi âm không tồn tại: $audioPath', tag: 'API');
      return '';
    }

    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse('$baseUrl/api/voice-memos/transcribe');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('audio', audioPath));

    try {
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      stopwatch.stop();

      AppLogger.network(
        'POST',
        uri.toString(),
        statusCode: response.statusCode,
        duration: stopwatch.elapsed,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(responseData) as Map<String, dynamic>;
        return decoded['transcription']?.toString() ?? '';
      }
    } catch (e) {
      stopwatch.stop();
      AppLogger.e('Lỗi trích xuất phụ đề hồi ký: $e', tag: 'API');
    }
    return '';
  }
}



