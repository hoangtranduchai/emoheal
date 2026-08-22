import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:lotus_haven/core/theme.dart';
import 'package:lotus_haven/data/supabase_service.dart';
import 'package:lotus_haven/data/api_service.dart';
import 'package:lotus_haven/router.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final SupabaseService _supabaseService = SupabaseService();
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isRecording = false;
  bool _isSending = false;
  String? _conversationId;
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        _conversationId = args;
        _loadMessages();
      } else {
        _initConversation();
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initConversation() async {
    try {
      final history = await _supabaseService.getChatHistory();
      if (history.isNotEmpty) {
        _conversationId = history.first['id'] as String;
      } else {
        final newConv = await _supabaseService.createConversation();
        _conversationId = newConv['id'] as String;
      }
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMessages() async {
    if (_conversationId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final messages = await _supabaseService.getMessages(_conversationId!);
      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(messages);
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    _messageController.clear();
    setState(() => _isSending = true);

    // Đảm bảo có conversation_id
    if (_conversationId == null) {
      final newConv = await _supabaseService.createConversation();
      _conversationId = newConv['id'] as String;
    }
    
    // Hiển thị lạc quan (Optimistic UI update)
    final newMessage = {
      'content': text,
      'sender': 'user',
      'created_at': DateTime.now().toIso8601String(),
    };
    
    setState(() {
      _messages.add(newMessage);
    });
    _scrollToBottom();

    try {
      await _supabaseService.saveMessage(
        conversationId: _conversationId!,
        sender: 'user',
        content: text,
      );
      
      final response = await ApiService.sendAssistantRequest(text: text);
      final aiText = response['text'] ?? 'Cháu chào Bác, Bác cần cháu hỗ trợ thêm gì ạ?';
      final audioUrl = response['audio_url'] as String?;
      final intent = response['intent'] as String?;
      final target = response['target'] as String?;
      
      final aiMessage = {
        'content': aiText,
        'sender': 'assistant',
        'created_at': DateTime.now().toIso8601String(),
      };
      
      await _supabaseService.saveMessage(
        conversationId: _conversationId!,
        sender: 'assistant',
        content: aiText,
        audioUrl: audioUrl,
      );
      
      if (mounted) {
        setState(() {
          _messages.add(aiMessage);
        });
        _scrollToBottom();
      }

      if (audioUrl != null && audioUrl.isNotEmpty) {
        final fullAudioUrl = audioUrl.startsWith('http') 
            ? audioUrl 
            : '${ApiService.baseUrl}$audioUrl';
        try {
          await _audioPlayer.play(UrlSource(fullAudioUrl));
        } catch (e) {
          debugPrint('Lỗi phát âm thanh: $e');
        }
      }

      // Xử lý Intent điều hướng nếu Bác yêu cầu
      if (mounted) {
        if (intent == 'PANIC' || target == 'breathing') {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.of(context).pushNamed(AppRoutes.lotusBreathing);
          });
        }
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi gửi tin nhắn: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        setState(() {
          _isRecording = true;
        });

        if (kIsWeb) {
          await _audioRecorder.start(const RecordConfig(), path: '');
        } else {
          await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: '');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vui lòng cấp quyền micro để thu âm.')),
          );
        }
      }
    } catch (e) {
      setState(() => _isRecording = false);
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
      });
      
      if (path != null && path.isNotEmpty) {
        await _sendAudioMessage(path);
      }
    } catch (e) {
      setState(() => _isRecording = false);
    }
  }

  Future<void> _sendAudioMessage(String audioPath) async {
    if (_conversationId == null) {
      final newConv = await _supabaseService.createConversation();
      _conversationId = newConv['id'] as String;
    }

    setState(() => _isSending = true);

    try {
      final response = await ApiService.sendAssistantRequest(audioPath: audioPath);
      final aiText = response['text'] ?? 'Cháu chào Bác, Bác cần cháu hỗ trợ gì ạ?';
      final audioUrl = response['audio_url'] as String?;
      
      final aiMessage = {
        'content': aiText,
        'sender': 'assistant',
        'created_at': DateTime.now().toIso8601String(),
      };
      
      await _supabaseService.saveMessage(
        conversationId: _conversationId!,
        sender: 'assistant',
        content: aiText,
        audioUrl: audioUrl,
      );
      
      if (mounted) {
        setState(() {
          _messages.add(aiMessage);
        });
        _scrollToBottom();
      }

      if (audioUrl != null && audioUrl.isNotEmpty) {
        final fullAudioUrl = audioUrl.startsWith('http') 
            ? audioUrl 
            : '${ApiService.baseUrl}$audioUrl';
        try {
          await _audioPlayer.play(UrlSource(fullAudioUrl));
        } catch (e) {
          debugPrint('Lỗi phát âm thanh: $e');
        }
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xử lý giọng nói: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text(
          'Trò chuyện cùng cháu',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
                  : _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 40,
                                  color: AppColors.primaryGreen,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Bắt đầu cuộc trò chuyện cùng cháu...',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 18,
                                  color: AppColors.neutralGrey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isUser = (message['sender'] == 'user') || (message['is_user'] == true);
                            
                            return Align(
                              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                                ),
                                decoration: BoxDecoration(
                                  color: isUser ? AppColors.primaryGreen : AppColors.white,
                                  borderRadius: BorderRadius.circular(20).copyWith(
                                    bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
                                    bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  message['content']?.toString() ?? '',
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 17, // Dễ đọc cho người cao tuổi
                                    height: 1.4,
                                    color: isUser ? Colors.white : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onLongPressStart: (_) => _startRecording(),
            onLongPressEnd: (_) => _stopRecording(),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Nhấn giữ nút micro để nói cho cháu nghe nhé Bác.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording ? Colors.red.shade100 : AppColors.surfaceLight,
              ),
              child: Icon(
                _isRecording ? Icons.mic : Icons.mic_none_rounded,
                size: 28,
                color: _isRecording ? Colors.red : AppColors.primaryGreen,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(fontFamily: 'Roboto', fontSize: 17),
              decoration: InputDecoration(
                hintText: 'Nhập tin nhắn cho cháu...',
                hintStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 16, color: AppColors.neutralGrey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                filled: true,
                fillColor: AppColors.backgroundLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isSending ? null : _sendMessage,
            icon: _isSending 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen))
                : const Icon(Icons.send_rounded, size: 30),
            color: AppColors.primaryGreen,
            padding: const EdgeInsets.all(10),
          ),
        ],
      ),
    );
  }
}
