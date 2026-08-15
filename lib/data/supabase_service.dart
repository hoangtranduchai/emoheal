import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dịch vụ kết nối và thao tác dữ liệu với Supabase Backend.
/// Nằm trong layer Data của mô hình MVVM.
class SupabaseService {
  final SupabaseClient _client;

  SupabaseService() : _client = Supabase.instance.client;

  // Lấy danh sách lịch sử hội thoại từ bảng conversations
  Future<List<Map<String, dynamic>>> getChatHistory() async {
    final response = await _client.from('conversations').select().order('created_at', ascending: false);
    return response;
  }

  Future<String> uploadVoiceMemo(String filePath, String fileName) async {
    final bytes = await File(filePath).readAsBytes();
    await _client.storage.from('voice-memos').uploadBinary(fileName, bytes);
    return _client.storage.from('voice-memos').getPublicUrl(fileName);
  }

  Future<void> saveVoiceMemoMetadata(String title, String fileUrl, int durationSeconds) async {
    final user = _client.auth.currentUser;
    await _client.from('voice_memos').insert({
      if (user != null) 'user_id': user.id,
      'title': title,
      'file_url': fileUrl,
      'duration_seconds': durationSeconds,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // Get messages from 'messages' table
  Future<List<Map<String, dynamic>>> getMessages() async {
    return await _client.from('messages').select().order('created_at', ascending: true);
  }

  // Insert a new message into 'messages' table
  Future<void> saveMessage(String content, bool isUser) async {
    await _client.from('messages').insert({
      'content': content,
      'is_user': isUser,
    });
  }

  // Lấy cài đặt của người dùng
  Future<Map<String, dynamic>?> getUserSettings() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final response = await _client
        .from('user_settings')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();
    return response;
  }

  // Lưu cài đặt của người dùng
  Future<void> saveUserSettings({
    required bool soundEnabled,
    required bool highContrastEnabled,
    required bool antiMistapEnabled,
    required String voiceType,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    
    await _client.from('user_settings').upsert({
      'user_id': user.id,
      'sound_enabled': soundEnabled,
      'high_contrast_enabled': highContrastEnabled,
      'anti_mistap_enabled': antiMistapEnabled,
      'voice_type': voiceType,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
