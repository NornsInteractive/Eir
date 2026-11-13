import 'package:flutter_test/flutter_test.dart';
import 'package:eir/core/screen_share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScreenShareService Unit Tests', () {
    test('initializes with idle state and default properties', () {
      final signals = <Map<String, dynamic>>[];
      final service = ScreenShareService(
        sendSignal: (sig) async => signals.add(sig),
        getCurrentDeviceId: () => 'dev-test-123',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => 'preset:aurora',
      );

      expect(service.state, ScreenShareState.idle);
      expect(service.role, ScreenShareRole.none);
      expect(service.isActive, isFalse);
      expect(service.isBroadcasting, isFalse);
      expect(service.isViewing, isFalse);
      expect(service.targetFps, 60);
      expect(service.volume, 1.0);
      expect(service.isMuted, isFalse);
      expect(service.duration, Duration.zero);

      service.dispose();
    });

    test('volume adjustment and muting work as expected', () {
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Bob',
        getCurrentAvatar: () => null,
      );

      service.setVolume(0.5);
      expect(service.volume, 0.5);
      expect(service.isMuted, isFalse);

      service.setVolume(0.0);
      expect(service.isMuted, isTrue);

      service.setVolume(0.8);
      expect(service.isMuted, isFalse);

      service.toggleMute();
      expect(service.isMuted, isTrue);

      service.toggleMute();
      expect(service.isMuted, isFalse);

      service.dispose();
    });

    test('handles incoming screen_share_started signal', () async {
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-viewer',
        getCurrentDisplayName: () => 'Viewer',
        getCurrentAvatar: () => null,
      );

      await service.handleSignal({
        'type': 'screen_share_started',
        'sourceTitle': '抖音 - 发现美好',
        'sourceType': 'window',
        'targetFps': 60,
      });

      expect(service.sourceTitle, '抖音 - 发现美好');
      expect(service.sourceType, 'window');
      expect(service.targetFps, 60);

      service.dispose();
    });

    test('handles incoming screen_share_stop signal', () async {
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-test',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
      );

      await service.handleSignal({
        'type': 'screen_share_stop',
        'reason': 'remote_closed',
      });

      expect(service.state, ScreenShareState.idle);
      expect(service.role, ScreenShareRole.none);
      expect(service.isActive, isFalse);

      service.dispose();
    });

    test('dual-channel volume and smart audio ducking', () {
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
      );

      expect(service.companionVolume, 1.0);
      expect(service.voiceVolume, 1.0);
      expect(service.isAudioDuckingEnabled, isTrue);

      service.setCompanionVolume(0.7);
      service.setVoiceVolume(1.4);
      service.setAudioDucking(false);

      expect(service.companionVolume, 0.7);
      expect(service.voiceVolume, 1.4);
      expect(service.isAudioDuckingEnabled, isFalse);

      service.dispose();
    });

    test('aspect ratio mode toggle (cover vs contain)', () {
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
      );

      expect(service.isCoverMode, isFalse);
      service.toggleAspectMode();
      expect(service.isCoverMode, isTrue);
      service.toggleAspectMode();
      expect(service.isCoverMode, isFalse);

      service.dispose();
    });

    test('reaction emoji streaming and signaling', () async {
      final sentSignals = <Map<String, dynamic>>[];
      final receivedReactions = <String>[];

      final service = ScreenShareService(
        sendSignal: (sig) async => sentSignals.add(sig),
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
      );

      final sub = service.onReaction.listen(receivedReactions.add);

      await service.sendReaction('🔥');
      expect(sentSignals.length, 1);
      expect(sentSignals.first['type'], 'screen_share_reaction');
      expect(sentSignals.first['emoji'], '🔥');

      await service.handleSignal({
        'type': 'screen_share_reaction',
        'emoji': '❤️',
      });
      expect(receivedReactions, contains('❤️'));

      await sub.cancel();
      service.dispose();
    });

    test('stream health diagnostics report defaults', () {
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
      );

      expect(service.rttMs, 0);
      expect(service.bitrateMbps, 0.0);
      expect(service.packetLoss, 0.0);

      service.dispose();
    });
  });
}
