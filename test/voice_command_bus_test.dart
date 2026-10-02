import 'package:flutter_test/flutter_test.dart';
import 'package:emoheal/core/voice_command_bus.dart';
import 'package:emoheal/router.dart';

void main() {
  group('VoiceCommandBus Tests', () {
    late VoiceCommandBus bus;

    setUp(() {
      bus = VoiceCommandBus();
    });

    test('dispatchToolCall parses control_radio correctly', () async {
      final future = bus.radioCommands.first;
      bus.dispatchToolCall('control_radio', {'action': 'next'});
      final cmd = await future;
      expect(cmd.action, VoiceRadioAction.next);
    });

    test('dispatchToolCall parses control_breathing correctly', () async {
      final future = bus.breathingCommands.first;
      bus.dispatchToolCall('control_breathing', {'action': 'start'});
      final cmd = await future;
      expect(cmd.action, VoiceBreathingAction.start);
    });

    test('dispatchToolCall parses control_voice_memo correctly', () async {
      final future = bus.memoCommands.first;
      bus.dispatchToolCall('control_voice_memo', {'action': 'changeTopic', 'topic': 'đồng đội'});
      final cmd = await future;
      expect(cmd.action, VoiceMemoAction.changeTopic);
      expect(cmd.topic, 'đồng đội');
    });

    test('dispatchToolCall parses adjust_settings correctly', () async {
      final future = bus.settingsCommands.first;
      bus.dispatchToolCall('adjust_settings', {
        'font_delta': 0.15,
        'voice_type': 'puck',
        'sound_enabled': true,
      });
      final cmd = await future;
      expect(cmd.fontDelta, 0.15);
      expect(cmd.voiceType, 'puck');
      expect(cmd.soundEnabled, true);
    });

    test('dispatchToolCall parses trigger_sos_emergency correctly', () async {
      final future = bus.sosCommands.first;
      bus.dispatchToolCall('trigger_sos_emergency', {
        'reason': 'Bác bị chóng mặt',
        'countdown_seconds': 3,
      });
      final cmd = await future;
      expect(cmd.reason, 'Bác bị chóng mặt');
      expect(cmd.countdownSeconds, 3);
    });

    test('dispatchToolCall parses navigate_to_screen correctly', () async {
      final future = bus.navigationCommands.first;
      bus.dispatchToolCall('navigate_to_screen', {'screen_name': 'lotus_breathing'});
      final cmd = await future;
      expect(cmd.targetRoute, AppRoutes.lotusBreathing);
      expect(cmd.screenName, 'breathing');
    });

    test('dispatchToolCall parses convenience navigation tool names', () async {
      final future = bus.navigationCommands.first;
      bus.dispatchToolCall('open_radio', {});
      final cmd = await future;
      expect(cmd.targetRoute, AppRoutes.radio);
    });
  });
}
