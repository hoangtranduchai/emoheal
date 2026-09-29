import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:emoheal/main.dart';
import 'package:emoheal/presentation/widgets/sos_button.dart';
import 'package:emoheal/presentation/widgets/feature_card.dart';
import 'package:emoheal/presentation/screens/home_screen.dart';
import 'package:emoheal/presentation/screens/history_screen.dart';
import 'package:emoheal/presentation/screens/settings_screen.dart';
import 'package:emoheal/presentation/screens/radio_screen.dart';
import 'package:emoheal/presentation/screens/voice_memo_screen.dart';
import 'package:emoheal/presentation/screens/lotus_breathing_screen.dart';
import 'package:emoheal/presentation/screens/auth/login_screen.dart';
import 'package:emoheal/presentation/screens/auth/otp_screen.dart';
import 'package:emoheal/presentation/widgets/add_contact_bottom_sheet.dart';
import 'package:emoheal/presentation/widgets/global_draggable_assistant.dart';
import 'package:emoheal/presentation/widgets/assistant_bubble.dart';
import 'package:emoheal/presentation/widgets/breathing_lotus.dart';

void main() {
  testWidgets('EmoHealApp smoke test - renders onboarding',
      (WidgetTester tester) async {
    await tester.pumpWidget(const EmoHealApp());
    await tester.pump();

    // Verify Onboarding title and CTA button
    expect(find.text('HÀNH TRÌNH TRI ÂN & CHỮA LÀNH'), findsOneWidget);
    expect(find.text('BẮT ĐẦU NGAY'), findsOneWidget);
  });

  testWidgets('SOSButton renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SOSButton(size: 100),
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify SOS and 115 text
    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('115'), findsOneWidget);
  });

  testWidgets('FeatureCard renders title and handles tap',
      (WidgetTester tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeatureCard(
            title: 'Hồi ký Giọng nói',
            svgAsset: 'assets/icons/lotus.svg',
            onTap: () {
              tapped = true;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Hồi ký Giọng nói'), findsOneWidget);

    await tester.tap(find.text('Hồi ký Giọng nói'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets(
      'HomeScreen renders without overflow on 320px viewport with 1.3x font scale',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const HomeScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('Xin chào'), findsOneWidget);
    expect(find.text('Bác'), findsOneWidget);
  });

  testWidgets(
      'HistoryScreen renders without errors on 320px viewport with 1.3x font scale',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const HistoryScreen(),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Lịch sử Hồi ký'), findsOneWidget);
  });

  testWidgets(
      'SettingsScreen renders without errors on 320px viewport with 1.3x font scale',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const SettingsScreen(),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Cài đặt'), findsOneWidget);
  });

  testWidgets('RadioScreen renders without overflow on 360x640',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: RadioScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('Đài Radio Hoài Niệm'), findsOneWidget);
  });

  testWidgets(
      'VoiceMemoScreen renders without overflow on 320px narrow viewport with 1.3x font scale',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const VoiceMemoScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('Gợi ý chủ đề'), findsOneWidget);
    expect(find.text('Trợ lý EmoHeal'), findsWidgets);
  });

  testWidgets('BreathingLotus renders video card properly',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: BreathingLotus(
              scaleAnimation: AlwaysStoppedAnimation(1.0),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BreathingLotus), findsOneWidget);
  });

  testWidgets('LotusBreathingScreen renders properly without errors',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LotusBreathingScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('Nhịp thở Hoa Sen'), findsOneWidget);
    expect(find.text('Chu kỳ thở 4 - 4 - 6 (Thư giãn & Điều hòa)'), findsOneWidget);
    expect(find.byType(LotusBreathingScreen), findsOneWidget);
  });

  testWidgets('Auth Login, Otp screens render properly',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const LoginScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('Đăng ký & Đăng nhập'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const OtpScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('Xác thực mã OTP'), findsOneWidget);
  });

  testWidgets(
      'VoiceMemoScreen renders properly and handles voice recording controls',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VoiceMemoScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('Hồi ký Giọng nói'), findsOneWidget);
    expect(find.text('Gợi ý chủ đề'), findsOneWidget);
    expect(find.text('Chiến trường & Đồng đội'), findsOneWidget);
    expect(find.text('HỘI THOẠI'), findsOneWidget);
    expect(find.text('Bấm để trò chuyện'), findsOneWidget);

    // Test topic switching
    await tester.tap(find.text('Niềm vui & Con cháu'));
    await tester.pump();
    expect(find.text('Điều gì khiến Bác cảm thấy nhẹ lòng và vui vẻ nhất?'), findsOneWidget);
  });

  testWidgets('AddContactBottomSheet renders contact picker button and chips',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddContactBottomSheet(
            onSave: (name, phone) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Thêm liên hệ người thân'), findsOneWidget);
    expect(find.text('CHỌN TỪ DANH BẠ ĐIỆN THOẠI'), findsOneWidget);
    expect(find.text('Con gái'), findsOneWidget);
    expect(find.text('LƯU LIÊN HỆ NGƯỜI THÂN'), findsOneWidget);
  });

  test('AddContactBottomSheet normalizePhoneNumber tests', () {
    // Standard Vietnamese mobile formats
    expect(AddContactBottomSheet.normalizePhoneNumber('+84912345678'), '0912345678');
    expect(AddContactBottomSheet.normalizePhoneNumber('+84 912 345 678'), '0912345678');
    expect(AddContactBottomSheet.normalizePhoneNumber('84912345678'), '0912345678');
    expect(AddContactBottomSheet.normalizePhoneNumber('0912-345-678'), '0912345678');
    expect(AddContactBottomSheet.normalizePhoneNumber('(0912) 345.678'), '0912345678');
    expect(AddContactBottomSheet.normalizePhoneNumber('0987 654 321'), '0987654321');
    expect(AddContactBottomSheet.normalizePhoneNumber(''), '');
    expect(AddContactBottomSheet.normalizePhoneNumber('   '), '');
  });

  testWidgets('AddContactBottomSheet fills fields and calls onSave',
      (WidgetTester tester) async {
    String savedName = '';
    String savedPhone = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddContactBottomSheet(
            onSave: (name, phone) {
              savedName = name;
              savedPhone = phone;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    // Click chip "Con gái"
    await tester.tap(find.text('Con gái'));
    await tester.pump();

    // Enter phone number
    await tester.enterText(find.byType(TextField).last, '0912345678');
    await tester.pump();

    // Tap Save button
    await tester.tap(find.text('LƯU LIÊN HỆ NGƯỜI THÂN'));
    await tester.pump();

    expect(savedName, 'Con gái');
    expect(savedPhone, '0912345678');
  });

  testWidgets('GlobalDraggableAssistant renders across MaterialApp.builder',
      (WidgetTester tester) async {
    await tester.pumpWidget(const EmoHealApp());
    await tester.pump();

    // Verify GlobalDraggableAssistant, AssistantBubble and 'Bạn đồng hành' label are present globally
    expect(find.byType(GlobalDraggableAssistant), findsOneWidget);
    expect(find.byType(AssistantBubble), findsOneWidget);
    expect(find.text('Bạn đồng hành'), findsOneWidget);

    // Test dragging the assistant bubble
    final initialCenter = tester.getCenter(find.byType(AssistantBubble));
    await tester.drag(find.byType(AssistantBubble), const Offset(-100, -100));
    await tester.pump(const Duration(milliseconds: 300));
    final newCenter = tester.getCenter(find.byType(AssistantBubble));
    expect(newCenter, isNot(equals(initialCenter)));
  });
}
