import 'package:flutter/material.dart';

import '../../core/theme.dart';

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

  bool _isRecording = false;
  bool _isPaused = false;

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
      setState(() {
        _isRecording = false;
        _isPaused = false;
      });
    }
  }

  void _toggleRecord() {
    setState(() {
      _isRecording = !_isRecording;
      if (_isRecording) {
        _isPaused = false;
      }
    });
  }

  void _togglePause() {
    if (!_isRecording) return;
    setState(() {
      _isPaused = !_isPaused;
    });
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
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _ControlButton(
                      icon: _isRecording ? Icons.mic_off_rounded : Icons.mic_rounded,
                      label: _isRecording ? 'Dừng' : 'Ghi âm',
                      color: AppColors.primaryGreen,
                      onTap: _toggleRecord,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ControlButton(
                      icon: Icons.pause_rounded,
                      label: 'Tạm dừng',
                      color: _isPaused ? AppColors.warningOrange : AppColors.ink,
                      onTap: _togglePause,
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
                      onTap: _confirmDelete,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ControlButton(
                      icon: Icons.send_rounded,
                      label: 'Gửi',
                      color: AppColors.warningOrange,
                      onTap: () {},
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
  const _RecordingStatusCard({required this.isRecording, required this.isPaused});

  final bool isRecording;
  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    final title = isRecording
        ? (isPaused ? 'Đang tạm dừng' : 'Đang ghi âm')
        : 'Chưa bắt đầu ghi âm';

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
              isRecording ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
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
          Text(
            isPaused
                ? 'Bác có thể bấm tiếp tục khi sẵn sàng.'
                : 'Giữ nhịp thật chậm, cháu sẽ lắng nghe.',
            textAlign: TextAlign.center,
            style: const TextStyle(
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
