import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/theme.dart';
import '../../data/api_service.dart';

class AssistantBubble extends StatefulWidget {
  final VoidCallback onTap;

  const AssistantBubble({
    super.key,
    required this.onTap,
  });

  @override
  State<AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<AssistantBubble> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isProcessing = false;

  @override
  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/bubble_audio.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() {
          _isRecording = true;
        });
      }
    } catch (e) {
      debugPrint('Lỗi ghi âm: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });
      
      if (path != null) {
        final response = await ApiService.sendAssistantRequest(audioPath: path);
        final audioUrl = response['audio_url'];
        
        if (audioUrl != null && audioUrl.toString().isNotEmpty) {
          await _audioPlayer.play(UrlSource(audioUrl));
        }
      }
    } catch (e) {
      debugPrint('Lỗi: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPressStart: (_) => _startRecording(),
        onLongPressEnd: (_) => _stopRecording(),
        child: Container(
          decoration: BoxDecoration(
            color: _isRecording ? Colors.red.shade100 : AppColors.assistantBubble,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: _isProcessing 
              ? const CircularProgressIndicator(color: AppColors.primaryGreen)
              : Text(
                  _isRecording ? '🎙️' : '🤖',
                  style: const TextStyle(fontSize: 32),
                ),
          ),
        ),
      ),
    );
  }
}
