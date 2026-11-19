import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:eir/core/room_session.dart';

import '../../server/signaling_server.dart';

Future<bool> _waitFor(
  bool Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return condition();
}

/// A real [Player] whose reported state is controlled by the test. Only the
/// state snapshot is replaced; construction and streams stay real.
class _StatePlayer extends Player {
  _StatePlayer(this._state);

  PlayerState _state;

  set state(PlayerState value) => _state = value;

  @override
  PlayerState get state => _state;
}

/// Records the position handed to the existing [RoomSession.seek] entry point
/// instead of publishing a commit. Relative seek must route through that
/// single permission/sync path, not seek the local player directly.
class _RecordingSession extends RoomSession {
  _RecordingSession({super.player, super.identityStore});

  Duration? recorded;

  @override
  Future<void> seek(Duration position) async {
    recorded = position;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  group('relativeSeekTarget', () {
    test('anchors at the live position, not the commit anchor', () {
      // Live playback has moved past the commit anchor (0): a relative +10
      // from 2.42s must target 12.42s, not anchor+10 = 10s.
      final target = relativeSeekTarget(
        base: const Duration(milliseconds: 2420),
        offset: const Duration(seconds: 10),
        duration: const Duration(seconds: 60),
      );
      expect(target, const Duration(milliseconds: 12420));
      expect(target, isNot(const Duration(seconds: 10)));
    });

    test('clamps a forward seek to the known duration', () {
      expect(
        relativeSeekTarget(
          base: const Duration(seconds: 55),
          offset: const Duration(seconds: 10),
          duration: const Duration(seconds: 60),
        ),
        const Duration(seconds: 60),
      );
    });

    test('clamps a backward seek at zero', () {
      expect(
        relativeSeekTarget(
          base: const Duration(seconds: 3),
          offset: const Duration(seconds: -10),
          duration: const Duration(seconds: 60),
        ),
        Duration.zero,
      );
    });

    test('unknown duration keeps the target instead of collapsing to zero',
        () {
      expect(
        relativeSeekTarget(
          base: const Duration(seconds: 5),
          offset: const Duration(seconds: 10),
          duration: null,
        ),
        const Duration(seconds: 15),
      );
      expect(
        relativeSeekTarget(
          base: const Duration(seconds: 5),
          offset: const Duration(seconds: 10),
          duration: Duration.zero,
        ),
        const Duration(seconds: 15),
      );
      // Backward with unknown duration is still lower-bounded at zero.
      expect(
        relativeSeekTarget(
          base: const Duration(seconds: 2),
          offset: const Duration(seconds: -10),
          duration: null,
        ),
        Duration.zero,
      );
    });
  });

  group('RoomSession.seekRelative', () {
    late _StatePlayer player;
    late _RecordingSession session;

    setUp(() async {
      player = _StatePlayer(
        const PlayerState(
          position: Duration(milliseconds: 12420),
          duration: Duration(seconds: 60),
        ),
      );
      session = _RecordingSession(
        player: player,
        identityStore: DeviceIdentityStore(
          store: InMemorySecureKeyValueStore(),
        ),
      );
      await session.init();
    });

    tearDown(() {
      session.dispose();
    });

    test('uses the live player position and delegates to the existing seek',
        () async {
      // Commit anchor is 0 (no commit applied). The live position is 12.42s,
      // so +10 must produce 22.42s and go through seek(), the same entry the
      // permission and sync commit path uses.
      await session.seekRelative(const Duration(seconds: 10));
      expect(session.recorded, const Duration(milliseconds: 22420));
    });

    test('uses the player duration as the forward bound', () async {
      player.state = const PlayerState(
        position: Duration(milliseconds: 55000),
        duration: Duration(seconds: 60),
      );
      await session.seekRelative(const Duration(seconds: 10));
      expect(session.recorded, const Duration(seconds: 60));
    });

    test('unknown duration does not force the target back to zero', () async {
      player.state = const PlayerState(
        position: Duration(seconds: 5),
        duration: Duration.zero,
      );
      await session.seekRelative(const Duration(seconds: 10));
      expect(session.recorded, const Duration(seconds: 15));
    });
  });

  group('RoomSession.seekRelative authorization', () {
    test('an unauthorized member is denied through the shared seek path',
        () async {
      final server = SignalingServer();
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      final url = 'ws://127.0.0.1:${server.port}';

      final owner = RoomSession(
        identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
      );
      final member = RoomSession(
        identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
      );
      addTearDown(() async {
        try {
          owner.dispose();
        } catch (_) {}
        try {
          member.dispose();
        } catch (_) {}
        try {
          await server.stop();
        } catch (_) {}
      });

      await owner.init();
      await owner.setSignalingUrl(url);
      await owner.createRoom();
      expect(
        await _waitFor(
          () => owner.connectionState == RoomConnectionState.connected,
          timeout: const Duration(seconds: 10),
        ),
        isTrue,
        reason: 'owner must connect (err=${owner.lastErrorCode})',
      );
      final invite = owner.inviteText!;

      await member.init();
      await member.joinRoom(invite);
      expect(
        await _waitFor(
          () => member.connectionState == RoomConnectionState.connected,
          timeout: const Duration(seconds: 10),
        ),
        isTrue,
        reason: 'member must join (err=${member.lastErrorCode})',
      );
      expect(member.role, RoomRole.member);
      expect(member.lastErrorCode, isNull);

      // A member with no control grant must be rejected by exactly the same
      // permission gate that plain seek() uses; relative seek adds no bypass.
      await member.seekRelative(const Duration(seconds: 10));
      expect(member.lastErrorCode, 'permission_denied');
    });
  });
}
