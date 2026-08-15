import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../router.dart';
import '../widgets/feature_card.dart';
import '../widgets/sos_button.dart';
import '../widgets/emergency_contact_chip.dart';
import '../widgets/add_contact_bottom_sheet.dart';
import '../widgets/assistant_bubble.dart';
import '../../core/theme.dart';
import '../../core/responsive_utils.dart';

/// Màn hình Trang chủ — render 100% pixel-perfect theo Frame "Home" (421:1289) trên Figma.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = ResponsiveUtils.isTablet(context);

    final horizontalPadding = ResponsiveUtils.getCardPadding(context);
    final topHeaderHeight = isTablet ? 200.0 : 177.0;
    final sosSize = screenWidth * (isTablet ? 0.2 : 0.32);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight, // Figma frame fill
      body: Stack(
        children: [
          // ── Main scrollable content ──
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. Top Header ──
                _TopHeader(
                  height: topHeaderHeight,
                  horizontalPadding: horizontalPadding,
                ),

                // ── 2. SOS Section ──
                Padding(
                  padding: EdgeInsets.fromLTRB(horizontalPadding, 32, horizontalPadding, 0),
                  child: Center(
                    child: _SOSSection(sosSize: sosSize),
                  ),
                ),

                const SizedBox(height: 32),

                // ── 3. Emergency Contacts ──
                _EmergencyContactsSection(horizontalPadding: horizontalPadding),

                const SizedBox(height: 32),

                // ── 4. Feature Cards ──
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: const _FeatureGrid(),
                ),

                // Bottom safe area padding
                SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
              ],
            ),
          ),

          // ── 5. Floating Assistant Bubble ──
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: AssistantBubble(
              onTap: () {
                // TODO: Mở trợ lý AI
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ════════════════════════════════════════════════════════════════════

/// Header xanh đậm ở trên cùng.
class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.height,
    required this.horizontalPadding,
  });

  final double height;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final totalHeight = height + statusBarHeight;

    return SizedBox(
      height: totalHeight,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Background Container ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: totalHeight,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              child: Container(
                color: AppColors.primaryGreenDark, // Figma: primaryGreenDark
              ),
            ),
          ),

          // ── Star (Bottom Left of Top Header) ──
          Positioned(
            bottom: 0,
            left: 0,
            child: SvgPicture.asset('assets/icons/star.svg'),
          ),

          // ── Ellipse (Bottom Right of Top Header) ──
          Positioned(
            bottom: 0,
            right: 0,
            child: SvgPicture.asset('assets/icons/ellipse.svg'),
          ),

          // ── Text content ──
          Positioned(
            top: 79.0 + statusBarHeight,
            left: horizontalPadding,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Xin chào',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    letterSpacing: 0.24,
                    color: AppColors.textOnDark,
                  ),
                ),
                Text(
                  'Bác',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 48,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: AppColors.textOnDark,
                  ),
                ),
              ],
            ),
          ),

          // ── Flagpole image ──
          Positioned(
            bottom: 0,
            right: horizontalPadding,
            child: Image.asset(
              'assets/images/flagpole_image.png',
              height: 130, // Đặt mức height an toàn vừa vặn trong frame 177/200
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

/// SOS Section: tiêu đề + mô tả + nút SOS + text nhấn giữ.
class _SOSSection extends StatelessWidget {
  const _SOSSection({required this.sosSize});

  final double sosSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Bác đang cảm thấy bất an?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 24,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Hãy nhấn gọi để được chuyên gia\ny tế hỗ trợ.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.5,
            color: AppColors.textSecondary, // 60% opacity
          ),
        ),
        const SizedBox(height: 16),
        SOSButton(size: sosSize),
        const SizedBox(height: 12),
        const Text(
          'Nhấn và giữ trong 3 giây',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _EmergencyContactsSection extends StatefulWidget {
  final double horizontalPadding;
  const _EmergencyContactsSection({required this.horizontalPadding});

  @override
  State<_EmergencyContactsSection> createState() => _EmergencyContactsSectionState();
}

class _EmergencyContactsSectionState extends State<_EmergencyContactsSection> {
  // Mock data for contacts
  final List<Map<String, String>> _contacts = [
    {'name': '115', 'initial': 'C'}
  ];

  void _showAddContactSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: AddContactBottomSheet(
          onSave: () {
            Navigator.pop(context);
            // Implement saving logic here
          },
          onPickContact: () {
            // Implement picking contact logic here
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
          child: const Text(
            'Liên hệ khẩn cấp',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100, // appropriate height for EmergencyContactChip
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
            scrollDirection: Axis.horizontal,
            itemCount: _contacts.length + 1,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index < _contacts.length) {
                final contact = _contacts[index];
                return EmergencyContactChip(
                  name: contact['name']!,
                  initial: contact['initial']!,
                  onTap: () {
                    // Implement tap logic
                  },
                  onLongPress: () {
                    // Implement long press logic
                  },
                );
              } else {
                return _AddContactButton(onTap: _showAddContactSheet);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _AddContactButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddContactButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minWidth: 120, minHeight: 80),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, color: AppColors.primaryGreen, size: 32),
              SizedBox(height: 8),
              Text(
                'Thêm mới',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primaryGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  @override
  Widget build(BuildContext context) {
    final cardHeight = ResponsiveUtils.getCardSize(context);
    final cardGap = ResponsiveUtils.getCardGap(context);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: cardHeight,
                child: FeatureCard(
                  title: 'Hồi ký\nGiọng nói',
                  svgAsset: 'assets/icons/microphone.svg',
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.voiceMemo),
                ),
              ),
            ),
            SizedBox(width: cardGap),
            Expanded(
              child: SizedBox(
                height: cardHeight,
                child: FeatureCard(
                  title: 'Nhịp thở',
                  svgAsset: 'assets/icons/lotus.svg',
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.lotusBreathing),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: cardGap),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: cardHeight,
                child: FeatureCard(
                  title: 'Đài Radio',
                  svgAsset: 'assets/icons/soundwave-0.svg',
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.radio),
                ),
              ),
            ),
            SizedBox(width: cardGap),
            Expanded(
              child: SizedBox(
                height: cardHeight,
                child: FeatureCard(
                  title: 'Cài đặt &\nHỗ trợ tiếp cận',
                  svgAsset: 'assets/icons/setting.svg',
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.settings),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
