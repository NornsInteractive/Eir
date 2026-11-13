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
  });
}
