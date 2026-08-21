import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  // Backend URL — set via --dart-define=BACKEND_URL=... / Cấu hình URL backend
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:8000',
  );

  static Future<Map<String, dynamic>> sendAssistantRequest({
    String? text,
    String? audioPath,
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;

    final uri = Uri.parse('$baseUrl/api/assistant');
    final request = http.MultipartRequest('POST', uri);

    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    if (text != null && text.isNotEmpty) {
      request.fields['text'] = text;
    }

    if (audioPath != null && audioPath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath('audio', audioPath));
    }

    final response = await request.send();
    final responseData = await response.stream.bytesToString();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(responseData);
    } else {
      throw Exception('Lỗi kết nối: ${response.statusCode} - $responseData');
    }
  }
}
