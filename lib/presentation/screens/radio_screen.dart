import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../widgets/sos_button.dart';

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  double _progress = 0.42;
  bool _isPlaying = false;
  bool _isShuffled = false;

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
    _Track(title: 'Mùa xuân trên quê hương', artist: 'Nghệ sĩ Hoài Niệm', length: '04:12'),
    _Track(title: 'Khúc hát tri ân', artist: 'Đội văn nghệ', length: '03:58'),
    _Track(title: 'Lối về bình yên', artist: 'Giai điệu xưa', length: '05:21'),
    _Track(title: 'Sông nước quê nhà', artist: 'Dân ca Việt', length: '04:45'),
  ];

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
                const Text(
                  'Đài Radio Hoài Niệm',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Chọn thể loại, phát nhạc và thư giãn chậm rãi',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.neutralGrey,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    children: [
                      _PlayerCard(
                        isPlaying: _isPlaying,
                        isShuffled: _isShuffled,
                        progress: _progress,
                        onProgressChanged: (value) {
                          setState(() {
                            _progress = value;
                          });
                        },
                        onPlayPause: () {
                          setState(() {
                            _isPlaying = !_isPlaying;
                          });
                        },
                        onShuffle: () {
                          setState(() {
                            _isShuffled = !_isShuffled;
                          });
                        },
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
                        height: 150,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _categories.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final item = _categories[index];
                            return _CategoryCard(category: item);
                          },
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Danh sách nhạc mẫu',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListView.separated(
                        itemCount: _tracks.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final track = _tracks[index];
                          return _TrackTile(track: track, index: index + 1);
                        },
                      ),
                      const SizedBox(height: 18),
                      const SizedBox(
                        width: 265,
                        height: 265,
                        child: SOSButton(),
                      ),
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
    required this.isPlaying,
    required this.isShuffled,
    required this.progress,
    required this.onProgressChanged,
    required this.onPlayPause,
    required this.onShuffle,
  });

  final bool isPlaying;
  final bool isShuffled;
  final double progress;
  final ValueChanged<double> onProgressChanged;
  final VoidCallback onPlayPause;
  final VoidCallback onShuffle;

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
                child: const Icon(Icons.radio_rounded, color: AppColors.primaryGreen),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đang phát',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Hoài niệm quê hương',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Giai điệu giúp thư giãn nhẹ nhàng',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 13,
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
              value: progress,
              onChanged: onProgressChanged,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(progress * 100).round()}% đã nghe',
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.neutralGrey,
                ),
              ),
              const Text(
                '08:24',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 12,
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
                  icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(isPlaying ? 'Tạm dừng' : 'Phát nhạc'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _ControlButton(
                icon: Icons.skip_next_rounded,
                onPressed: () {},
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
          color: isActive ? AppColors.warningOrange : AppColors.surfaceLight,
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
  const _CategoryCard({required this.category});

  final _RadioCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 156,
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 12),
          Text(
            category.title,
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
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.neutralGrey,
              height: 1.3,
            ),
          ),
          const Spacer(),
          Text(
            category.duration,
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track, required this.index});

  final _Track track;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.surfaceLight,
            child: Text(
              '$index',
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryGreen,
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
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  track.artist,
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 12,
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
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryGreen,
            ),
          ),
        ],
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
  });

  final String title;
  final String artist;
  final String length;
}
