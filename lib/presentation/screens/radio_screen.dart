import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/logger.dart';
import '../../core/sound_coordinator.dart';
import '../../core/theme.dart';
import '../../core/voice_guide.dart';
import '../../data/supabase_service.dart';

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final SupabaseService _supabaseService = SupabaseService();

  double _progress = 0.0;
  bool _isPlaying = false;
  bool _isShuffled = false;
  int _currentTrackIndex = 0;
  String _currentTitle = 'Dân ca quan họ Bắc Ninh';
  String _currentSubtitle = 'Giai điệu quê hương mộc mạc, gần gũi';

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  List<Map<String, dynamic>> _stations = [];
  bool _isLoading = true;

  final List<_RadioCategory> _categories = const [
    _RadioCategory(
      title: 'Dân ca',
      subtitle: 'Bản nhạc mộc mạc, gần gũi',
      duration: '3 giờ 20 phút',
      color: AppColors.golden,
      icon: Icons.music_note_rounded,
    ),
    _RadioCategory(
      title: 'Đờn ca tài tử',
      subtitle: 'Không gian hoài niệm nhẹ nhàng',
      duration: '2 giờ 05 phút',
      color: AppColors.primaryGreen,
      icon: Icons.library_music_rounded,
    ),
    _RadioCategory(
      title: 'Nhạc thư giãn',
      subtitle: 'Chậm rãi, ấm áp, bình yên',
      duration: '1 giờ 40 phút',
      color: AppColors.mediumGrey,
      icon: Icons.spa_rounded,
    ),
  ];

  final List<_Track> _tracks = const [
    _Track(
      title: 'Dân ca quan họ Bắc Ninh',
      artist: 'Nghệ nhân Quan họ',
      length: '15:20',
      url: 'https://archive.org/download/vietnamese-traditional-music/danca_bacninh.mp3',
    ),
    _Track(
      title: 'Đờn ca tài tử Nam Bộ',
      artist: 'Giai điệu Phương Nam',
      length: '18:45',
      url: 'https://archive.org/download/vietnamese-traditional-music/doncataitu.mp3',
    ),
    _Track(
      title: 'Khúc hát tri ân & Nhạc cách mạng',
      artist: 'Đoàn Văn công Quân đội',
      length: '12:30',
      url: 'https://archive.org/download/vietnamese-traditional-music/nhaccachmang.mp3',
    ),
    _Track(
      title: 'Đọc thơ: Đất Nước (Nguyễn Khoa Điềm)',
      artist: 'Giọng đọc Truyền cảm',
      length: '08:50',
      url: 'https://archive.org/download/vietnamese-traditional-music/doctho_datnuoc.mp3',
    ),
  ];

  List<_Track> get _activeTracks {
    if (_stations.isNotEmpty) {
      return _stations.map((s) {
        final genre = s['genre']?.toString();
        String artist = 'Giai điệu quê hương';
        if (genre == 'tho') {
          artist = 'Giọng đọc Truyền cảm';
        } else if (genre == 'nhac_cach_mang') {
          artist = 'Đoàn Văn công Quân đội';
        } else if (genre == 'dan_ca') {
          artist = 'Nghệ nhân Dân gian';
        }
        return _Track(
          title: s['name']?.toString() ?? 'Đài Radio',
          artist: artist,
          length: '15:00',
          url: s['stream_url']?.toString() ?? 'https://archive.org/download/vietnamese-traditional-music/danca_bacninh.mp3',
        );
      }).toList();
    }
    return _tracks;
  }

  @override
  void initState() {
    super.initState();
    SoundCoordinator.registerRadioPlayer(_audioPlayer);
    _loadStations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VoiceGuide.play(VoiceScripts.radio);
    });

    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) {
        setState(() {
          _position = p;
          if (_duration.inMilliseconds > 0) {
            _progress = (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
          }
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) {
        setState(() => _duration = d);
      }
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });
  }

  Future<void> _loadStations() async {
    AppLogger.d('Bắt đầu tải danh sách đài Radio từ Supabase', tag: 'RADIO');
    try {
      final stations = await _supabaseService.getRadioStations();
      if (stations.isNotEmpty && mounted) {
        AppLogger.i('Tải thành công ${stations.length} kênh radio từ Supabase', tag: 'RADIO');
        setState(() {
          _stations = stations;
          _currentTitle = stations[0]['name']?.toString() ?? _tracks[0].title;
          _isLoading = false;
        });
      } else {
        AppLogger.d('Sử dụng danh sách bài phát mặc định', tag: 'RADIO');
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e, st) {
      AppLogger.w('Không thể tải kênh từ DB, chuyển sang danh sách bài hát mặc định', tag: 'RADIO', error: e, stackTrace: st);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    AppLogger.d('Hủy trình phát Radio', tag: 'RADIO');
    SoundCoordinator.registerRadioPlayer(null);
    VoiceGuide.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playTrackAt(int index) async {
    VoiceGuide.stop();
    final trackList = _activeTracks;
    if (index < 0 || index >= trackList.length) return;
    _currentTrackIndex = index;
    final track = trackList[index];

    AppLogger.i('Phát bài Radio: "${track.title}" - ${track.artist} ($index)', tag: 'RADIO');
    AppLogger.event('RADIO_PLAY_TRACK', params: {'title': track.title, 'url': track.url});

    if (mounted) {
      setState(() {
        _currentTitle = track.title;
        _currentSubtitle = track.artist;
      });
    }

    try {
      await _audioPlayer.stop();
      if (!mounted) return;
      await _audioPlayer.play(UrlSource(track.url));
    } catch (e, st) {
      AppLogger.e('Lỗi khi phát luồng Radio: ${track.url}', tag: 'RADIO', error: e, stackTrace: st);
      // Fallback state if URL stream offline
      if (mounted) {
        setState(() => _isPlaying = true);
      }
    }
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      AppLogger.d('Tạm dừng Radio', tag: 'RADIO');
      AppLogger.event('RADIO_PAUSE');
      await _audioPlayer.pause();
    } else {
      AppLogger.d('Tiếp tục phát Radio', tag: 'RADIO');
      AppLogger.event('RADIO_RESUME');
      if (_position > Duration.zero) {
        await _audioPlayer.resume();
      } else {
        await _playTrackAt(_currentTrackIndex);
      }
    }
  }

  Future<void> _nextTrack() async {
    final trackList = _activeTracks;
    final nextIndex = (_currentTrackIndex + 1) % trackList.length;
    await _playTrackAt(nextIndex);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundLight, AppColors.lightGrey],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Thanh tiêu đề có nút Quay lại ──
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.ink, size: 24),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Quay lại',
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Đài Radio Hoài Niệm',
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Chọn thể loại, phát nhạc và thư giãn chậm rãi',
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: AppColors.neutralGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      _PlayerCard(
                        title: _currentTitle,
                        subtitle: _currentSubtitle,
                        isPlaying: _isPlaying,
                        isShuffled: _isShuffled,
                        progress: _progress,
                        currentPositionText: _formatDuration(_position),
                        durationText: _duration.inSeconds > 0 ? _formatDuration(_duration) : '15:00',
                        onProgressChanged: (value) {
                          setState(() => _progress = value);
                          if (_duration.inMilliseconds > 0) {
                            final seekMs = (value * _duration.inMilliseconds).round();
                            _audioPlayer.seek(Duration(milliseconds: seekMs));
                          }
                        },
                        onPlayPause: _togglePlayPause,
                        onShuffle: () {
                          setState(() => _isShuffled = !_isShuffled);
                        },
                        onNext: _nextTrack,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Thể loại nổi bật',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 245,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _categories.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final item = _categories[index];
                            return _CategoryCard(
                              category: item,
                              onTap: () => _playTrackAt(index % _tracks.length),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Danh sách phát gợi ý',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: CircularProgressIndicator(color: AppColors.primaryGreen),
                          ),
                        )
                      else
                        ListView.separated(
                          itemCount: _activeTracks.length,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final track = _activeTracks[index];
                            final isSelected = index == _currentTrackIndex;
                            return _TrackTile(
                              track: track,
                              index: index + 1,
                              isSelected: isSelected,
                              onTap: () => _playTrackAt(index),
                            );
                          },
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.title,
    required this.subtitle,
    required this.isPlaying,
    required this.isShuffled,
    required this.progress,
    required this.currentPositionText,
    required this.durationText,
    required this.onProgressChanged,
    required this.onPlayPause,
    required this.onShuffle,
    required this.onNext,
  });

  final String title;
  final String subtitle;
  final bool isPlaying;
  final bool isShuffled;
  final double progress;
  final String currentPositionText;
  final String durationText;
  final ValueChanged<double> onProgressChanged;
  final VoidCallback onPlayPause;
  final VoidCallback onShuffle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: AppColors.black12,
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.radio_rounded, color: AppColors.primaryGreen, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Đang phát',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: AppColors.neutralGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: AppColors.primaryGreen,
              inactiveTrackColor: AppColors.surfaceLight,
              thumbColor: AppColors.primaryGreen,
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: onProgressChanged,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                currentPositionText,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.neutralGrey,
                ),
              ),
              Text(
                durationText,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.neutralGrey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _ControlButton(
                icon: Icons.shuffle_rounded,
                isActive: isShuffled,
                onPressed: onShuffle,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onPlayPause,
                  icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28),
                  label: Text(
                    isPlaying ? 'Tạm dừng' : 'Phát nhạc',
                    style: const TextStyle(fontFamily: 'Roboto', fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: AppColors.white,
                    minimumSize: const Size(0, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _ControlButton(
                icon: Icons.skip_next_rounded,
                onPressed: onNext,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: isActive ? AppColors.sosOrange : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(
          icon,
          color: isActive ? AppColors.white : AppColors.primaryGreen,
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    this.onTap,
  });

  final _RadioCategory category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 185,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: AppColors.black0F,
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(category.icon, color: category.color),
                ),
                const SizedBox(height: 10),
                Text(
                  category.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  category.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: AppColors.neutralGrey,
                    height: 1.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              category.duration,
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.index,
    this.isSelected = false,
    this.onTap,
  });

  final _Track track;
  final int index;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceLight : AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.primaryGreen : AppColors.surfaceLight,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isSelected ? AppColors.primaryGreen : AppColors.surfaceLight,
              child: Text(
                '$index',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppColors.primaryGreen,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 16,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.artist,
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: AppColors.neutralGrey,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              track.length,
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadioCategory {
  const _RadioCategory({
    required this.title,
    required this.subtitle,
    required this.duration,
    required this.color,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String duration;
  final Color color;
  final IconData icon;
}

class _Track {
  const _Track({
    required this.title,
    required this.artist,
    required this.length,
    required this.url,
  });

  final String title;
  final String artist;
  final String length;
  final String url;
}
