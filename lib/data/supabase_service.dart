import 'package:supabase_flutter/supabase_flutter.dart';

/// Dịch vụ kết nối và thao tác dữ liệu với Supabase Backend.
/// Nằm trong layer Data của mô hình MVVM.
class SupabaseService {
  final SupabaseClient _client;

  SupabaseService() : _client = Supabase.instance.client;

  // Lấy danh sách lịch sử hội thoại, ví dụ:
  Future<List<Map<String, dynamic>>> getChatHistory() async {
    final response = await _client.from('chat_history').select();
    return response;
  }
}
