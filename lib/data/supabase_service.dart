import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/logger.dart';

/// Dịch vụ kết nối và thao tác dữ liệu với Supabase Backend & Bộ nhớ cục bộ (Local Storage).
/// Hỗ trợ cả 2 chế độ:
/// 1. Khách trải nghiệm trước (Guest Mode - Zero Barrier / Offline-First)
/// 2. Đã đăng nhập số điện thoại (Cloud Sync)
class SupabaseService {
  final SupabaseClient? _client;

  SupabaseService([SupabaseClient? client])
      : _client = client ?? _getSafeClient();

  static SupabaseClient? _getSafeClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static const String defaultVeteranUserId = 'a0000000-0000-0000-0000-000000000001';
  static String _activeUserId = defaultVeteranUserId;

  static void setActiveUserId(String userId) {
    _activeUserId = userId;
    AppLogger.i('Đã cập nhật Active User ID cho phiên: $userId', tag: 'SUPABASE');
  }

  static String get activeUserId => _activeUserId;

  bool get isAuthenticated {
    return _client?.auth.currentUser != null;
  }

  String get _currentUserId {
    final user = _client?.auth.currentUser;
    return user?.id ?? _activeUserId;
  }

  // ── 1. Tên Người Dùng & Danh Xưng (Display Name) ──

  /// Lấy danh xưng / tên gọi của Bác (mặc định "Bác")
  Future<String> getDisplayName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localName = prefs.getString('user_display_name');
      if (localName != null && localName.trim().isNotEmpty) {
        return localName.trim();
      }

      if (isAuthenticated && _client != null) {
        final profile = await _client
            .from('profiles')
            .select('display_name')
            .eq('id', _currentUserId)
            .maybeSingle();
        if (profile != null && profile['display_name'] != null) {
          final cloudName = profile['display_name'] as String;
          await prefs.setString('user_display_name', cloudName);
          return cloudName;
        }
      }
    } catch (e) {
      AppLogger.w('Không thể lấy display_name: $e', tag: 'SUPABASE');
    }
    return 'Bác';
  }

  /// Cập nhật tên của Bác (Ví dụ: "Hải" -> lưu "Bác Hải" hoặc "Hải")
  Future<void> updateDisplayName(String name) async {
    final cleanName = name.trim();
    final displayName = cleanName.isEmpty ? 'Bác' : cleanName;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_display_name', displayName);

      if (isAuthenticated && _client != null) {
        await _client.from('profiles').update({
          'display_name': displayName,
        }).eq('id', _currentUserId);
      }
      AppLogger.i('Đã cập nhật Tên hiển thị của Bác: $displayName', tag: 'SUPABASE');
    } catch (e) {
      AppLogger.e('Lỗi cập nhật display_name', tag: 'SUPABASE', error: e);
    }
  }

  // ── 2. Hồi ký giọng nói (Voice Memos) ──

  /// Tải file ghi âm dạng binary bytes lên Supabase Storage và lưu trữ cục bộ an toàn
  Future<String> uploadVoiceMemoBytes(Uint8List bytes, String fileName) async {
    final sw = Stopwatch()..start();

    // Luôn lưu một bản copy vật lý vào thư mục Document trên thiết bị để phát offline/guest
    String localFilePath = '';
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final memoDir = Directory('${docDir.path}/voice_memos');
      if (!await memoDir.exists()) {
        await memoDir.create(recursive: true);
      }
      final file = File('${memoDir.path}/$fileName');
      await file.writeAsBytes(bytes);
      localFilePath = file.path;
      AppLogger.d('Đã ghi bản ghi âm vật lý vào thiết bị: $localFilePath', tag: 'STORAGE');
    } catch (e) {
      AppLogger.w('Không thể lưu file âm thanh vật lý: $e', tag: 'STORAGE');
    }

    final client = _client;
    if (client == null || !isAuthenticated) {
      AppLogger.w('Đang ở chế độ Khách/Offline, lưu đường dẫn file cục bộ', tag: 'STORAGE');
      return localFilePath.isNotEmpty ? localFilePath : 'local://$fileName';
    }

    AppLogger.d('Bắt đầu tải file ghi âm lên Storage: $fileName (${bytes.lengthInBytes ~/ 1024} KB)', tag: 'STORAGE');
    try {
      await client.storage.from('voice-memos').uploadBinary(
        fileName,
        bytes,
        fileOptions: const FileOptions(contentType: 'audio/m4a', upsert: true),
      );
      final publicUrl = client.storage.from('voice-memos').getPublicUrl(fileName);
      sw.stop();
      AppLogger.db('UPLOAD', 'storage/voice-memos', duration: sw.elapsed, data: 'URL: $publicUrl');
      return publicUrl;
    } catch (e, st) {
      sw.stop();
      AppLogger.db('UPLOAD', 'storage/voice-memos', duration: sw.elapsed, error: e);
      AppLogger.e('Lỗi tải file ghi âm lên Storage, sử dụng đường dẫn cục bộ', tag: 'STORAGE', error: e, stackTrace: st);
      return localFilePath.isNotEmpty ? localFilePath : 'local://$fileName';
    }
  }

  /// Lưu thông tin bản ghi âm vào bảng voice_memos hoặc SharedPreferences nếu là Khách
  Future<void> saveVoiceMemoMetadata({
    required String title,
    required String audioUrl,
    required int durationSeconds,
    String? transcript,
    String? topic,
  }) async {
    final sw = Stopwatch()..start();
    final memoData = {
      'id': 'memo-${DateTime.now().millisecondsSinceEpoch}',
      'title': title,
      'audio_url': audioUrl,
      'duration_seconds': durationSeconds,
      'transcript': transcript ?? '',
      'topic': topic ?? 'Kỷ niệm',
      'created_at': DateTime.now().toIso8601String(),
    };

    // Luôn lưu vào local cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final listJson = prefs.getStringList('local_voice_memos') ?? [];
      listJson.insert(0, jsonEncode(memoData));
      await prefs.setStringList('local_voice_memos', listJson);
    } catch (_) {}

    final client = _client;
    if (client != null && isAuthenticated) {
      try {
        await client.from('voice_memos').insert({
          'user_id': _currentUserId,
          'title': title,
          'topic': topic ?? 'Kỷ niệm',
          'audio_url': audioUrl,
          'duration_seconds': durationSeconds,
          if (transcript != null) 'transcript': transcript,
          'created_at': DateTime.now().toIso8601String(),
        });
        sw.stop();
        AppLogger.db('INSERT', 'voice_memos', duration: sw.elapsed, data: 'Title: "$title"');
      } catch (e, st) {
        sw.stop();
        AppLogger.db('INSERT', 'voice_memos', duration: sw.elapsed, error: e);
        AppLogger.e('Lỗi khi lưu cloud voice_memos (đã lưu local fallback)', tag: 'SUPABASE', error: e, stackTrace: st);
      }
    }
  }


  /// Lấy danh sách các bản hồi ký giọng nói đã lưu
  Future<List<Map<String, dynamic>>> getVoiceMemos() async {
    final sw = Stopwatch()..start();
    final client = _client;

    if (client != null && isAuthenticated) {
      try {
        final response = await client
            .from('voice_memos')
            .select()
            .eq('user_id', _currentUserId)
            .order('created_at', ascending: false);
        sw.stop();
        AppLogger.db('SELECT', 'voice_memos', duration: sw.elapsed, data: 'Số hồi ký Cloud: ${response.length}');
        return List<Map<String, dynamic>>.from(response);
      } catch (e) {
        AppLogger.w('Không tải được cloud voice_memos, đọc local fallback: $e', tag: 'SUPABASE');
      }
    }

    // Đọc từ Local Storage
    try {
      final prefs = await SharedPreferences.getInstance();
      final listJson = prefs.getStringList('local_voice_memos') ?? [];
      final localList = listJson.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
      sw.stop();
      AppLogger.db('SELECT', 'local_voice_memos', duration: sw.elapsed, data: 'Số hồi ký Local: ${localList.length}');
      return localList;
    } catch (_) {
      return [];
    }
  }

  // ── 3. Đài Radio (Radio Stations) ──

  /// Lấy danh sách các kênh radio từ bảng radio_stations kèm Fallback phong phú
  Future<List<Map<String, dynamic>>> getRadioStations() async {
    final sw = Stopwatch()..start();
    final client = _client;
    if (client != null) {
      try {
        final response = await client
            .from('radio_stations')
            .select()
            .eq('is_active', true);
        sw.stop();
        if (response.isNotEmpty) {
          AppLogger.db('SELECT', 'radio_stations', duration: sw.elapsed, data: 'Số kênh hoạt động: ${response.length}');
          return List<Map<String, dynamic>>.from(response);
        }
      } catch (e) {
        AppLogger.w('Không tải được cloud radio_stations, dùng danh sách đài phát thanh mặc định: $e', tag: 'SUPABASE');
      }
    }

    // Danh mục kênh Đài Tiếng Nói Việt Nam (VOV) & Ca khúc Kháng chiến bất hủ
    return [
      {
        'id': 'vov1',
        'name': 'VOV1 - Thời sự & Chính trị',
        'stream_url': 'https://stream.vovmedia.vn/vov1',
        'genre': 'khac',
        'is_active': true,
      },
      {
        'id': 'vov2',
        'name': 'VOV2 - Văn hóa & Đời sống',
        'stream_url': 'https://stream.vovmedia.vn/vov2',
        'genre': 'dan_ca',
        'is_active': true,
      },
      {
        'id': 'vov3',
        'name': 'VOV3 - Âm nhạc Kháng chiến & Cách mạng',
        'stream_url': 'https://stream.vovmedia.vn/vov3',
        'genre': 'nhac_cach_mang',
        'is_active': true,
      },
      {
        'id': 'tho_xua',
        'name': 'Tiếng Thơ - Ngâm Thơ Đêm Khuya',
        'stream_url': 'https://stream.vovmedia.vn/vov6',
        'genre': 'tho',
        'is_active': true,
      },
    ];
  }

  // ── 4. Cài đặt người dùng (User Settings) ──

  /// Lấy cấu hình cài đặt của người dùng từ local hoặc cloud
  Future<Map<String, dynamic>> getUserSettings() async {
    final client = _client;
    if (client != null && isAuthenticated) {
      try {
        final response = await client
            .from('user_settings')
            .select()
            .eq('user_id', _currentUserId)
            .maybeSingle();
        if (response != null) return response;
      } catch (e) {
        AppLogger.w('Không đọc được cloud settings, dùng local: $e', tag: 'SUPABASE');
      }
    }

    // Local SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    return {
      'sound_enabled': prefs.getBool('setting_sound_enabled') ?? true,
      'voice_type': prefs.getString('setting_voice_type') ?? 'aoede',
      'font_size_scale': prefs.getDouble('setting_font_size_scale') ?? 1.15,
      'anti_mis_tap': prefs.getBool('setting_anti_mis_tap') ?? false,
      'voice_control_enabled': prefs.getBool('setting_voice_control_enabled') ?? true,
    };
  }

  /// Lưu hoặc cập nhật cấu hình cài đặt
  Future<void> saveUserSettings({
    required bool soundEnabled,
    required double fontSizeScale,
    required bool antiMisTap,
    required bool voiceControlEnabled,
    required String voiceType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setting_sound_enabled', soundEnabled);
    await prefs.setDouble('setting_font_size_scale', fontSizeScale);
    await prefs.setBool('setting_anti_mis_tap', antiMisTap);
    await prefs.setBool('setting_voice_control_enabled', voiceControlEnabled);
    await prefs.setString('setting_voice_type', voiceType);

    final client = _client;
    if (client != null && isAuthenticated) {
      try {
        await client.from('user_settings').upsert({
          'user_id': _currentUserId,
          'sound_enabled': soundEnabled,
          'font_size_scale': fontSizeScale,
          'anti_mis_tap': antiMisTap,
          'voice_control_enabled': voiceControlEnabled,
          'voice_type': voiceType,
        });
        AppLogger.db('UPSERT', 'user_settings', data: 'voice=$voiceType');
      } catch (e) {
        AppLogger.e('Lỗi cloud user_settings', tag: 'SUPABASE', error: e);
      }
    }
  }

  // ── 5. Danh bạ khẩn cấp (Emergency Contacts - Max 5) ──

  /// Lấy danh sách liên hệ khẩn cấp của người dùng
  Future<List<Map<String, dynamic>>> getEmergencyContacts() async {
    final client = _client;
    if (client != null && isAuthenticated) {
      try {
        final response = await client
            .from('emergency_contacts')
            .select()
            .eq('user_id', _currentUserId)
            .order('priority_order', ascending: true);
        return List<Map<String, dynamic>>.from(response);
      } catch (e) {
        AppLogger.w('Không tải được cloud contacts, dùng local: $e', tag: 'SUPABASE');
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final listJson = prefs.getStringList('local_emergency_contacts') ?? [];
      return listJson.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  /// Thêm liên hệ khẩn cấp mới (tối đa 5 liên hệ)
  Future<void> addEmergencyContact(String name, String phone) async {
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    final newContact = {
      'id': 'contact-${DateTime.now().millisecondsSinceEpoch}',
      'contact_name': cleanName,
      'contact_phone': cleanPhone,
      'priority_order': 1,
      'created_at': DateTime.now().toIso8601String(),
    };

    // 1. Lưu vào Local SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final listJson = prefs.getStringList('local_emergency_contacts') ?? [];
    if (listJson.length >= 5) {
      throw Exception('Bác chỉ có thể lưu tối đa 5 liên hệ khẩn cấp.');
    }
    listJson.add(jsonEncode(newContact));
    await prefs.setStringList('local_emergency_contacts', listJson);

    // 2. Đồng bộ lên Cloud nếu đã đăng nhập
    final client = _client;
    if (client != null && isAuthenticated) {
      try {
        await client.from('emergency_contacts').insert({
          'user_id': _currentUserId,
          'contact_name': cleanName,
          'contact_phone': cleanPhone,
          'priority_order': listJson.length,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        AppLogger.e('Lỗi cloud emergency_contacts', tag: 'SUPABASE', error: e);
      }
    }
  }

  /// Xóa liên hệ khẩn cấp
  Future<void> deleteEmergencyContact(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final listJson = prefs.getStringList('local_emergency_contacts') ?? [];
    listJson.removeWhere((s) {
      try {
        final decoded = jsonDecode(s) as Map<String, dynamic>;
        return decoded['id'] == id;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList('local_emergency_contacts', listJson);

    final client = _client;
    if (client != null && isAuthenticated) {
      try {
        await client.from('emergency_contacts').delete().match({'id': id, 'user_id': _currentUserId});
      } catch (e) {
        AppLogger.e('Lỗi xóa cloud contact', tag: 'SUPABASE', error: e);
      }
    }
  }

  // ── 6. Tự Động Đồng Bộ Dữ Liệu Sau Khi Đăng Nhập SĐT (Auto-Sync) ──

  /// Di chuyển toàn bộ danh bạ khẩn cấp và hồi ký cục bộ lên Supabase Cloud
  Future<void> syncLocalDataToCloud() async {
    if (!isAuthenticated || _client == null) return;
    AppLogger.i('Bắt đầu tự động đồng bộ dữ liệu cục bộ lên Cloud...', tag: 'SUPABASE');

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Đồng bộ Display Name
      final localName = prefs.getString('user_display_name');
      if (localName != null && localName.isNotEmpty) {
        await _client.from('profiles').update({'display_name': localName}).eq('id', _currentUserId);
      }

      // 2. Đồng bộ Emergency Contacts
      final localContacts = prefs.getStringList('local_emergency_contacts') ?? [];
      for (final s in localContacts) {
        try {
          final c = jsonDecode(s) as Map<String, dynamic>;
          await _client.from('emergency_contacts').insert({
            'user_id': _currentUserId,
            'contact_name': c['contact_name'],
            'contact_phone': c['contact_phone'],
            'priority_order': c['priority_order'] ?? 1,
          });
        } catch (_) {}
      }

      AppLogger.i('✅ Đã đồng bộ hoàn tất dữ liệu cục bộ lên Cloud!', tag: 'SUPABASE');
    } catch (e) {
      AppLogger.w('Cảnh báo quá trình đồng bộ: $e', tag: 'SUPABASE');
    }
  }
}

