import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:lotus_haven/core/theme.dart';
import 'package:lotus_haven/data/supabase_service.dart';
import 'package:lotus_haven/data/api_service.dart';

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
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await _supabaseService.getMessages();
      setState(() {
        _messages = List<Map<String, dynamic>>.from(messages);
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải tin nhắn: $e')),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    
    // Optimistic UI update
    final newMessage = {
      'content': text,
      'is_user': true,
      'created_at': DateTime.now().toIso8601String(),
    };
    
    setState(() {
      _messages.add(newMessage);
    });
    _scrollToBottom();

    try {
      await _supabaseService.saveMessage(text, true);
      
      final response = await ApiService.sendAssistantRequest(text: text);
      final aiText = response['text'] ?? 'Xin lỗi, tôi không hiểu.';
      final audioUrl = response['audio_url'];
      
      final aiMessage = {
        'content': aiText,
        'is_user': false,
        'created_at': DateTime.now().toIso8601String(),
      };
      
      await _supabaseService.saveMessage(aiText, false);
      
      if (mounted) {
        setState(() {
          _messages.add(aiMessage);
        });
        _scrollToBottom();
      }

      if (audioUrl != null && audioUrl.toString().isNotEmpty) {
        await _audioPlayer.play(UrlSource(audioUrl));
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi gửi tin nhắn: $e')),
        );
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/chat_audio.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() {
          _isRecording = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi ghi âm: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
      });
      
      if (path != null) {
        await _sendAudioMessage(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi gửi ghi âm: $e')),
        );
      }
    }
  }

  Future<void> _sendAudioMessage(String audioPath) async {
    try {
      final response = await ApiService.sendAssistantRequest(audioPath: audioPath);
      final aiText = response['text'] ?? 'Xin lỗi, tôi không hiểu.';
      final audioUrl = response['audio_url'];
      
      final aiMessage = {
        'content': aiText,
        'is_user': false,
        'created_at': DateTime.now().toIso8601String(),
      };
      
      await _supabaseService.saveMessage(aiText, false);
      
      if (mounted) {
        setState(() {
          _messages.add(aiMessage);
        });
        _scrollToBottom();
      }

      if (audioUrl != null && audioUrl.toString().isNotEmpty) {
        await _audioPlayer.play(UrlSource(audioUrl));
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
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
      appBar: AppBar(
        title: const Text('Trò chuyện', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const Center(
                          child: Text(
                            'Bắt đầu cuộc trò chuyện...',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isUser = message['is_user'] == true;
                            
                            return Align(
                              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isUser ? AppTheme.primaryLight : Colors.white,
                                  borderRadius: BorderRadius.circular(20).copyWith(
                                    bottomRight: isUser ? const Radius.circular(0) : const Radius.circular(20),
                                    bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(0),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  message['content']?.toString() ?? '',
                                  style: TextStyle(
                                    fontSize: 18, // Large, readable font
                                    color: isUser ? AppTheme.textPrimary : AppTheme.textSecondary,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording ? Colors.red.shade100 : Colors.transparent,
              ),
              child: Icon(
                _isRecording ? Icons.mic : Icons.mic_none,
                size: 32,
                color: _isRecording ? Colors.red : AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(fontSize: 18), // Readable font
              decoration: InputDecoration(
                hintText: 'Nhập tin nhắn...',
                hintStyle: const TextStyle(fontSize: 18, color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: AppTheme.primary),
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send, size: 32),
            color: AppTheme.primary,
            padding: const EdgeInsets.all(12), // Large touch target
          ),
        ],
      ),
    );
  }
}
