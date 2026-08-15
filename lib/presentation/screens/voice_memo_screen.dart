import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/theme.dart';
import '../../data/supabase_service.dart';

class VoiceMemoScreen extends StatefulWidget {
  const VoiceMemoScreen({super.key});

  @override
  State<VoiceMemoScreen> createState() => _VoiceMemoScreenState();
}

class _VoiceMemoScreenState extends State<VoiceMemoScreen> {
  final List<String> _suggestions = const [
    'Bác đang cảm thấy thế nào hôm nay?',
    'Điều gì khiến bác thấy nhẹ lòng nhất?',
    'Bác muốn chia sẻ một kỷ niệm cũ không?',
    'Có điều gì bác muốn cháu lắng nghe?',
    'Bác có muốn hít thở cùng cháu một chút không?',
  ];

  final _audioRecorder = AudioRecorder();
  final _supabaseService = SupabaseService();
  
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isUploading = false;
  
  Timer? _timer;
  int _recordDuration = 0;
  String? _audioPath;

  @override
  void dispose() {
    _timer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      setState(() => _recordDuration++);
    });
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmDelete() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Xác nhận xóa',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text(
            'Bác có chắc chắn muốn xóa đoạn ghi âm này không?',
            style: TextStyle(
              fontFamily: 'Roboto',
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Không'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: AppColors.white,
              ),
              child: const Text('Có'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      if (_isRecording) {
        await _audioRecorder.stop();
      }
      _timer?.cancel();
      if (_audioPath != null) {
        try {
          final file = File(_audioPath!);
          if (await file.exists()) await file.delete();
        } catch (e) {
          debugPrint('Error deleting file: $e');
        }
      }
      setState(() {
        _isRecording = false;
        _isPaused = false;
        _recordDuration = 0;
        _audioPath = null;
      });
    }
  }

  Future<void> _toggleRecord() async {
    try {
      if (_isRecording) {
        final path = await _audioRecorder.stop();
        _timer?.cancel();
        setState(() {
          _isRecording = false;
          _isPaused = false;
          _audioPath = path;
        });
      } else {
        if (await _audioRecorder.hasPermission()) {
          final dir = await getApplicationDocumentsDirectory();
          final filePath = '${dir.path}/voice_memo_${DateTime.now().millisecondsSinceEpoch}.m4a';
          await _audioRecorder.start(const RecordConfig(), path: filePath);
          setState(() {
            _isRecording = true;
            _isPaused = false;
            _recordDuration = 0;
            _audioPath = null;
          });
          _startTimer();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Vui lòng cấp quyền ghi âm.')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Record error: $e');
    }
  }

  Future<void> _togglePause() async {
    if (!_isRecording) return;
    try {
      if (_isPaused) {
        await _audioRecorder.resume();
        _startTimer();
        setState(() => _isPaused = false);
      } else {
        await _audioRecorder.pause();
        _timer?.cancel();
        setState(() => _isPaused = true);
      }
    } catch (e) {
      debugPrint('Pause error: $e');
    }
  }

  Future<void> _uploadVoiceMemo() async {
    if (_audioPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có bản ghi âm nào để gửi.')),
      );
      return;
    }
    
    setState(() => _isUploading = true);
    try {
      final fileName = 'memo_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final fileUrl = await _supabaseService.uploadVoiceMemo(_audioPath!, fileName);
      await _supabaseService.saveVoiceMemoMetadata('Hồi ký giọng nói', fileUrl, _recordDuration);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi hồi ký thành công!')),
        );
        setState(() {
          _audioPath = null;
          _recordDuration = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ghi âm lời kể',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Chọn một gợi ý hoặc nói tự nhiên theo nhịp của bác',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 14,
                  color: AppColors.neutralGrey,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Câu hỏi gợi ý',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _suggestions.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return Container(
                      width: 220,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [
                          BoxShadow(
                            color: AppColors.black12,
                            blurRadius: 18,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primaryGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.record_voice_over_rounded,
                              color: AppColors.primaryGreen,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              suggestion,
                              style: const TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 14,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Spacer(),
              _RecordingStatusCard(
                isRecording: _isRecording,
                isPaused: _isPaused,
                durationFormatted: _formatDuration(_recordDuration),
                hasRecorded: _audioPath != null,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _ControlButton(
                      icon: _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      label: _isRecording ? 'Dừng' : 'Ghi âm',
                      color: _isRecording ? AppColors.warningOrange : AppColors.primaryGreen,
                      onTap: _isUploading ? () {} : _toggleRecord,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ControlButton(
                      icon: _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      label: _isPaused ? 'Tiếp tục' : 'Tạm dừng',
                      color: _isPaused ? AppColors.primaryGreen : AppColors.ink,
                      onTap: (_isUploading || (!_isRecording && _audioPath == null)) ? () {} : _togglePause,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ControlButton(
                      icon: Icons.delete_rounded,
                      label: 'Xóa',
                      color: AppColors.redAccent,
                      onTap: _isUploading ? () {} : _confirmDelete,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ControlButton(
                      icon: _isUploading ? Icons.hourglass_empty_rounded : Icons.send_rounded,
                      label: _isUploading ? 'Đang gửi...' : 'Gửi',
                      color: AppColors.warningOrange,
                      onTap: (_isUploading || _audioPath == null) ? () {} : _uploadVoiceMemo,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordingStatusCard extends StatelessWidget {
  const _RecordingStatusCard({
    required this.isRecording, 
    required this.isPaused,
    required this.durationFormatted,
    required this.hasRecorded,
  });

  final bool isRecording;
  final bool isPaused;
  final String durationFormatted;
  final bool hasRecorded;

  @override
  Widget build(BuildContext context) {
    String title = 'Chưa bắt đầu ghi âm';
    if (isRecording) {
      title = isPaused ? 'Đang tạm dừng' : 'Đang ghi âm';
    } else if (hasRecorded) {
      title = 'Bản ghi âm đã sẵn sàng';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: AppColors.black12,
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isRecording ? AppColors.primaryGreen : AppColors.warningOrange)
                  .withValues(alpha: 0.12),
            ),
            child: Icon(
              isRecording ? Icons.graphic_eq_rounded : (hasRecorded ? Icons.check_rounded : Icons.mic_none_rounded),
              color: isRecording ? AppColors.primaryGreen : AppColors.warningOrange,
              size: 34,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          if (isRecording || hasRecorded)
            Text(
              durationFormatted,
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryGreen,
              ),
            ),
          if (!isRecording && !hasRecorded)
            const Text(
              'Giữ nhịp thật chậm, cháu sẽ lắng nghe.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 13,
                height: 1.4,
                color: AppColors.neutralGrey,
              ),
            ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
