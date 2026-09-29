import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' if (dart.library.html) 'dart:html';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// AppLogger — Centralized logging utility for EmoHeal
/// Hệ thống ghi log tập trung cho toàn bộ ứng dụng EmoHeal, hỗ trợ xuất log ra file và truyền lỗi từ điện thoại về máy tính.
class AppLogger {
  // ANSI escape codes for formatted console colors (in terminal/debug mode)
  // Mã màu ANSI cho terminal debug
  static const String _resetColor = '\x1B[0m';
  static const String _grayColor = '\x1B[90m';
  static const String _blueColor = '\x1B[34m';
  static const String _greenColor = '\x1B[32m';
  static const String _yellowColor = '\x1B[33m';
  static const String _redColor = '\x1B[31m';
  static const String _magentaColor = '\x1B[35m';

  // Backend URL for remote error telemetry / Cấu hình URL Backend để gửi log lỗi từ điện thoại
  static String get _backendBaseUrl {
    const envUrl = String.fromEnvironment('BACKEND_URL');
    if (envUrl.isNotEmpty) {
      if (!kIsWeb && envUrl.contains('localhost')) {
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
    return 'http://127.0.0.1:8000';
  }

  // In-memory buffer of recent logs / Bộ đệm trong bộ nhớ lưu các dòng log gần nhất
  static final List<String> _logBuffer = [];
  static const int _maxBufferSize = 1000;

  // Optional custom log file path
  static String? _customLogFilePath;

  /// Configure custom log file path / Cấu hình đường dẫn file log
  static void setLogFilePath(String path) {
    _customLogFilePath = path;
  }

  /// Get all captured logs in memory / Lấy toàn bộ log trong bộ đệm
  static List<String> get capturedLogs => List.unmodifiable(_logBuffer);

  /// Export logs as a single string / Xuất chuỗi log hoàn chỉnh
  static String exportLogsToString() => _logBuffer.join('\n');

  /// Format timestamp HH:mm:ss.SSS / Định dạng thời gian
  static String get _timestamp {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
  }

  /// Internal logger implementation / Hàm log nội bộ
  static void _log({
    required String level,
    required String message,
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    String color = _resetColor,
  }) {
    final effectiveTag = tag != null ? '[$tag]' : '[EmoHeal]';
    final formattedMessage = '[$_timestamp] $level $effectiveTag $message';

    // 1. Lưu vào In-memory buffer
    _logBuffer.add(formattedMessage);
    if (error != null) {
      _logBuffer.add('  ↳ Error: $error');
    }
    if (stackTrace != null) {
      _logBuffer.add('  ↳ StackTrace: $stackTrace');
    }
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeAt(0);
    }

    // 2. Ghi ra File vật lý nếu không phải môi trường Web
    if (!kIsWeb) {
      _appendToFile(formattedMessage, error, stackTrace);
    }

    // 3. Tự động gửi lỗi từ điện thoại về máy tính qua HTTP (Remote Telemetry)
    if (level.contains('ERR') || level.contains('ERROR') || level.contains('CRASH')) {
      _sendRemoteErrorTelemetry(
        level: level,
        message: message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }

    // 4. In ra Terminal Console trong Debug mode
    if (kDebugMode) {
      // ignore: avoid_print
      print('$color$formattedMessage$_resetColor');
      if (error != null) {
        // ignore: avoid_print
        print('$_redColor  ↳ Error: $error$_resetColor');
      }
      if (stackTrace != null) {
        // ignore: avoid_print
        print('$_grayColor  ↳ StackTrace: $stackTrace$_resetColor');
      }
    }

    // 5. Đăng ký vào Timeline của Dart Developer
    developer.log(
      message,
      time: DateTime.now(),
      name: tag ?? 'EmoHeal',
      level: level.contains('ERR') ? 1000 : (level.contains('WARN') ? 900 : 800),
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Tự động gửi ngầm thông tin lỗi từ điện thoại về Backend để AI nhận diện và fix liền
  static void _sendRemoteErrorTelemetry({
    required String level,
    required String message,
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    try {
      final uri = Uri.parse('$_backendBaseUrl/api/logs/client-error');
      final breadcrumbs = _logBuffer.length > 12 
          ? _logBuffer.sublist(_logBuffer.length - 12) 
          : List<String>.from(_logBuffer);

      final payload = {
        'level': level,
        'tag': tag ?? 'CLIENT',
        'message': message,
        'error': error?.toString() ?? '',
        'stack_trace': stackTrace?.toString() ?? '',
        'breadcrumbs': breadcrumbs,
        'timestamp': DateTime.now().toIso8601String(),
        'platform': kIsWeb ? 'Web (Phone Browser)' : defaultTargetPlatform.name,
      };

      await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Không ném lỗi ra ngoài để tránh làm gián đoạn trải nghiệm người dùng
    }
  }

  /// Ghi nối tiếp vào file log trên ổ đĩa
  static void _appendToFile(String formattedMessage, Object? error, StackTrace? stackTrace) {
    try {
      final logPath = _customLogFilePath ?? 'logs/flutter_app.log';
      final file = File(logPath);
      
      // Tạo thư mục cha nếu chưa tồn tại
      final parentDir = file.parent;
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }

      final buffer = StringBuffer();
      buffer.writeln(formattedMessage);
      if (error != null) {
        buffer.writeln('  ↳ Error: $error');
      }
      if (stackTrace != null) {
        buffer.writeln('  ↳ StackTrace: $stackTrace');
      }

      file.writeAsStringSync(buffer.toString(), mode: FileMode.append, flush: true);
    } catch (_) {
      // Bỏ qua lỗi I/O để không ảnh hưởng luồng chính của ứng dụng
    }
  }

  /// Debug level log / Log mức Debug
  static void d(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(
      level: '[DEBUG]',
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      color: _grayColor,
    );
  }

  /// Info level log / Log mức Thông tin
  static void i(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(
      level: '[INFO]',
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      color: _greenColor,
    );
  }

  /// Warning level log / Log mức Cảnh báo
  static void w(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(
      level: '[WARN]',
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      color: _yellowColor,
    );
  }

  /// Error level log / Log mức Lỗi
  static void e(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(
      level: '[ERROR]',
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      color: _redColor,
    );
  }

  /// Network request log / Ghi log cuộc gọi mạng (HTTP/REST)
  static void network(
    String method,
    String url, {
    int? statusCode,
    Duration? duration,
    dynamic data,
    Object? error,
  }) {
    final statusStr = statusCode != null ? '[$statusCode]' : '[PENDING]';
    final durStr = duration != null ? '(${duration.inMilliseconds}ms)' : '';
    final logMsg = '🌐 HTTP $method $statusStr $url $durStr';

    if (error != null || (statusCode != null && statusCode >= 400)) {
      _log(
        level: '[HTTP-ERR]',
        message: '$logMsg\n  ↳ Data: $data',
        tag: 'NETWORK',
        error: error,
        color: _redColor,
      );
    } else {
      _log(
        level: '[HTTP]',
        message: logMsg,
        tag: 'NETWORK',
        color: _blueColor,
      );
    }
  }

  /// Database operation log / Ghi log thao tác cơ sở dữ liệu Supabase
  static void db(
    String operation,
    String table, {
    Duration? duration,
    dynamic data,
    Object? error,
  }) {
    final durStr = duration != null ? '(${duration.inMilliseconds}ms)' : '';
    final logMsg = '🗄️ DB $operation on "$table" $durStr';

    if (error != null) {
      _log(
        level: '[DB-ERR]',
        message: '$logMsg\n  ↳ Data: $data',
        tag: 'SUPABASE',
        error: error,
        color: _redColor,
      );
    } else {
      _log(
        level: '[DB]',
        message: logMsg,
        tag: 'SUPABASE',
        color: _magentaColor,
      );
    }
  }

  /// User action or system event log / Ghi log sự kiện người dùng hoặc hệ thống
  static void event(String eventName, {Map<String, dynamic>? params}) {
    final paramsStr = params != null && params.isNotEmpty ? ' | Params: $params' : '';
    _log(
      level: '[EVENT]',
      message: '⚡ $eventName$paramsStr',
      tag: 'EVENT',
      color: _blueColor,
    );
  }

  /// Navigation route log / Ghi log điều hướng màn hình
  static void nav(String routeName, {Object? arguments}) {
    final argsStr = arguments != null ? ' | Args: $arguments' : '';
    _log(
      level: '[NAV]',
      message: '🧭 Navigating to: $routeName$argsStr',
      tag: 'ROUTER',
      color: _greenColor,
    );
  }
}
