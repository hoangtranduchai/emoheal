import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dịch vụ kết nối và thao tác dữ liệu với Supabase Backend.
/// Nằm trong layer Data của mô hình kiến trúc ứng dụng.
class SupabaseService {
  final SupabaseClient _client;

  SupabaseService() : _client = Supabase.instance.client;

  // ── 1. Hội thoại & Lịch sử Chat ──

  /// Lấy danh sách lịch sử hội thoại từ bảng conversations
  Future<List<Map<String, dynamic>>> getChatHistory() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final response = await _client
        .from('conversations')
        .select()
        .eq('user_id', user.id)
        .order('last_message_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Tạo cuộc hội thoại mới
  Future<Map<String, dynamic>> createConversation({String title = 'Trò chuyện cùng cháu'}) async {
    final user = _client.auth.currentUser;
    final data = {
      if (user != null) 'user_id': user.id,
      'title': title,
      'last_message_at': DateTime.now().toIso8601String(),
    };
    final response = await _client.from('conversations').insert(data).select().single();
    return response;
  }

  /// Lấy danh sách tin nhắn theo conversation_id
  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async {
    final response = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Lưu một tin nhắn mới vào bảng messages
  Future<void> saveMessage({
    required String conversationId,
    required String sender, // 'user' hoặc 'assistant'
    required String content,
    String? audioUrl,
  }) async {
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender': sender,
      'content': content,
      if (audioUrl != null) 'audio_url': audioUrl,
      'created_at': DateTime.now().toIso8601String(),
    });

    // Cập nhật thời điểm tin nhắn cuối cho cuộc trò chuyện
    await _client.from('conversations').update({
      'last_message_at': DateTime.now().toIso8601String(),
    }).eq('id', conversationId);
  }

  // ── 2. Hồi ký giọng nói (Voice Memos) ──

  /// Tải file ghi âm dạng binary bytes lên Supabase Storage (hỗ trợ cả Web & Mobile)
  Future<String> uploadVoiceMemoBytes(Uint8List bytes, String fileName) async {
    await _client.storage.from('voice-memos').uploadBinary(
      fileName,
      bytes,
      fileOptions: const FileOptions(contentType: 'audio/m4a', upsert: true),
    );
    return _client.storage.from('voice-memos').getPublicUrl(fileName);
  }

  /// Lưu thông tin bản ghi âm vào bảng voice_memos
  Future<void> saveVoiceMemoMetadata({
    required String title,
    required String audioUrl,
    required int durationSeconds,
    String? transcript,
    String? topic,
  }) async {
    final user = _client.auth.currentUser;
    await _client.from('voice_memos').insert({
      if (user != null) 'user_id': user.id,
      'title': title,
      'audio_url': audioUrl,
      'duration_seconds': durationSeconds,
      if (transcript != null) 'transcript': transcript,
      if (topic != null) 'topic': topic,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Lấy danh sách các bản hồi ký giọng nói đã lưu
  Future<List<Map<String, dynamic>>> getVoiceMemos() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final response = await _client
        .from('voice_memos')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // ── 3. Đài Radio (Radio Stations) ──

  /// Lấy danh sách các kênh radio từ bảng radio_stations
  Future<List<Map<String, dynamic>>> getRadioStations() async {
    final response = await _client
        .from('radio_stations')
        .select()
        .eq('is_active', true)
        .order('sort_order', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  // ── 4. Cài đặt người dùng (User Settings) ──

  /// Lấy cấu hình cài đặt của người dùng từ bảng user_settings
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

  /// Lưu hoặc cập nhật cấu hình cài đặt
  Future<void> saveUserSettings({
    required bool soundEnabled,
    required bool highContrast,
    required bool antiMisTap,
    required String voiceType,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('user_settings').upsert({
      'user_id': user.id,
      'sound_enabled': soundEnabled,
      'high_contrast': highContrast,
      'anti_mis_tap': antiMisTap,
      'voice_type': voiceType,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // ── 5. Danh bạ khẩn cấp (Emergency Contacts) ──

  /// Lấy danh sách liên hệ khẩn cấp của người dùng
  Future<List<Map<String, dynamic>>> getEmergencyContacts() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final response = await _client
        .from('emergency_contacts')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Thêm liên hệ khẩn cấp mới (tối đa 5 liên hệ)
  Future<void> addEmergencyContact(String name, String phone) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('emergency_contacts').insert({
      'user_id': user.id,
      'contact_name': name,
      'contact_phone': phone,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Xóa liên hệ khẩn cấp
  Future<void> deleteEmergencyContact(String id) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('emergency_contacts').delete().match({'id': id, 'user_id': user.id});
  }
}
