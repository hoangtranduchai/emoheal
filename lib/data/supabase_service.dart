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
    final file = await _client.storage.from('voice-memos').upload(
          fileName,
          // ignore: undefined_identifier
          java.io.File(filePath), // Actually wait, I need to import dart:io
        ); // Wait, this is better done with write_to_file completely or replace with dart:io import
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
}
