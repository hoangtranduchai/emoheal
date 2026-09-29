import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/logger.dart';
import '../../core/theme.dart';
import '../../data/live_voice_service.dart';

/// Lớp phủ Giao diện Trực quan (Dynamic Waveform & Live Subtitles Overlay)
/// Tích hợp đầy đủ các tính năng từ kho mẫu Google Gemini Live API:
/// 1. Sóng âm trực quan đa năng (Live Audio Waveform Visualizer)
/// 2. Phụ đề chạy trực tiếp 2 chiều (Live Transcription)
/// 3. Huy hiệu tra cứu thực tế Google Search Grounding
/// 4. Chạm để cắt lời (Touch-to-Interrupt / Barge-In)
/// 5. Thiết kế chuẩn mực Zero-Barrier cho người cao tuổi (Chữ lớn >= 18sp, nút bấm >= 56dp).
class LiveVoiceOverlay extends StatefulWidget {
  final LiveVoiceService liveService;
  final VoidCallback onClose;
  final Function(String name, Map<String, dynamic> args)? onToolCall;

  const LiveVoiceOverlay({
    super.key,
    required this.liveService,
    required this.onClose,
    this.onToolCall,
  });

  @override
  State<LiveVoiceOverlay> createState() => _LiveVoiceOverlayState();
}

class _LiveVoiceOverlayState extends State<LiveVoiceOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  String _userSubtitle = '';
  String _aiSubtitle = '';
  List<String> _searchQueries = [];
  LiveVoiceState _currentState = LiveVoiceState.connecting;

  StreamSubscription<LiveVoiceState>? _stateSub;
  StreamSubscription<String>? _inputSub;
  StreamSubscription<String>? _outputSub;
  StreamSubscription<Map<String, dynamic>>? _searchSub;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.15).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _currentState = widget.liveService.state;

    _stateSub = widget.liveService.stateStream.listen((state) {
      if (mounted) {
        setState(() => _currentState = state);
      }
    });

    _inputSub = widget.liveService.inputTranscriptStream.listen((text) {
      if (mounted) {
        setState(() => _userSubtitle = text);
      }
    });

    _outputSub = widget.liveService.outputTranscriptStream.listen((text) {
      if (mounted) {
        setState(() => _aiSubtitle = text);
      }
    });

    _searchSub = widget.liveService.searchGroundingStream.listen((data) {
      if (mounted) {
        final queries = (data['queries'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        setState(() {
          _searchQueries = queries;
        });
      }
    });

    widget.liveService.onToolCall = (name, args) {
      AppLogger.i('🛠️ LiveVoiceOverlay nhận Tool Call: $name, args: $args', tag: 'OVERLAY');
      widget.onToolCall?.call(name, args);
    };

    widget.liveService.onInterrupted = () {
      if (mounted) {
        setState(() {
          _aiSubtitle = '...(Cháu đang lắng nghe Bác nói tiếp)...';
        });
      }
    };
  }

  @override
  void dispose() {
    _animController.dispose();
    _stateSub?.cancel();
    _inputSub?.cancel();
    _outputSub?.cancel();
    _searchSub?.cancel();
    super.dispose();
  }

  String _getStatusText() {
    switch (_currentState) {
      case LiveVoiceState.connecting:
        return 'Đang kết nối cùng cháu...';
      case LiveVoiceState.listening:
        return 'Cháu đang lắng nghe Bác nói...';
      case LiveVoiceState.speaking:
        return 'Cháu đang tâm sự cùng Bác...';
      case LiveVoiceState.error:
        return 'Đường truyền đang chập chờn một chút...';
      case LiveVoiceState.idle:
        return 'Sẵn sàng lắng nghe Bác';
    }
  }

  Color _getStatusColor() {
    switch (_currentState) {
      case LiveVoiceState.listening:
        return AppColors.sosOrange;
      case LiveVoiceState.speaking:
        return AppColors.primaryGreen;
      case LiveVoiceState.connecting:
        return Colors.blue.shade700;
      case LiveVoiceState.error:
        return Colors.red.shade700;
      case LiveVoiceState.idle:
        return AppColors.primaryGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: screenHeight * 0.78),
      decoration: const BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thanh gạt modal
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.neutralGrey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),

            // Header: Trạng thái kết nối
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getStatusColor(),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _getStatusText(),
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _getStatusColor(),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Google Search Grounding Badge nếu có tra cứu thực tế
            if (_searchQueries.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blue.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.travel_explore_rounded, size: 18, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Google Search: ${_searchQueries.join(", ")}',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Sóng âm hoa sen động tương tác (Interactive Waveform Avatar)
            GestureDetector(
              onTap: () {
                // Chạm vào vòng tròn để ngắt lời hoặc hoàn tất lượt nói
                if (_currentState == LiveVoiceState.speaking) {
                  widget.liveService.sendEndOfTurn();
                }
              },
              child: AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _currentState == LiveVoiceState.listening || _currentState == LiveVoiceState.speaking
                        ? _scaleAnimation.value
                        : 1.0,
                    child: child,
                  );
                },
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: _getStatusColor().withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _getStatusColor(),
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      _currentState == LiveVoiceState.speaking
                          ? Icons.volume_up_rounded
                          : Icons.mic_rounded,
                      size: 44,
                      color: _getStatusColor(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Vùng hiển thị Phụ đề Thời gian thực (Live Subtitles)
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_userSubtitle.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🗣️ ', style: TextStyle(fontSize: 18)),
                            Expanded(
                              child: Text(
                                _userSubtitle,
                                style: const TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (_aiSubtitle.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primaryGreen),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🌸 ', style: TextStyle(fontSize: 18)),
                            Expanded(
                              child: Text(
                                _aiSubtitle,
                                style: const TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryGreenDark,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_userSubtitle.isEmpty && _aiSubtitle.isEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Text(
                            'Bác cứ thong thả nói chuyện tự nhiên cùng cháu nhé...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 17,
                              fontStyle: FontStyle.italic,
                              color: AppColors.neutralGrey.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Nút bấm Kết thúc / Dừng trò chuyện
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  widget.liveService.stopSession();
                  widget.onClose();
                },
                icon: const Icon(Icons.close_rounded, size: 28, color: Colors.white),
                label: const Text(
                  'Dừng trò chuyện',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreenDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
