import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<File> materialize(String asset, String name) async {
    final dir = await Directory.systemTemp.createTemp('eir_exact_');
    final out = File('${dir.path}/$name');
    final data = await rootBundle.load(asset);
    await out.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return out;
  }

  Future<RoomSession> soloSession(SignalingServer signaling) async {
    final session = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    await session.init();
    await session.setSignalingUrl('ws://127.0.0.1:${signaling.port}');
    await session.createRoom();
    expect(session.lastErrorCode, isNull);
    return session;
  }

  Future<bool> waitFor(bool Function() cond, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (cond()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return cond();
  }

  Future<void> cleanup(
    RoomSession session,
    SignalingServer signaling,
    List<File> files,
  ) async {
    session.dispose();
    try {
      await signaling.stop();
    } catch (_) {}
    for (final f in files) {
      try {
        await f.parent.delete(recursive: true);
      } catch (_) {}
    }
  }

  testWidgets('exact seek duration then play replays from 0', (tester) async {
    final clip = await materialize('assets/sample.mp4', 'sample.mp4');
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final session = await soloSession(signaling);
    try {
      await session.addLocalFile(XFile(clip.path, name: 'sample.mp4'));
      expect(session.lastErrorCode, isNull);
      await session.switchItem(session.playlist.single.itemId);
      await session.play();

      final started = await waitFor(
        () => session.player.state.position >
            const Duration(milliseconds: 300),
        const Duration(seconds: 10),
      );
      expect(started, isTrue,
          reason: 'did not advance (pos=${session.player.state.position} '
              'dur=${session.player.state.duration})');
      final dur = session.player.state.duration;
      expect(dur, greaterThan(Duration.zero));

      // Drive to real EOF first (paused ended_stop), then seek exactly to
      // duration while paused. This mirrors the UI case: slider dragged to
      // the end, then Play. mpv may report last frame slightly < duration
      // and seek clears completed; fix must consult _playback.position.
      final eof = await waitFor(
        () => session.player.state.completed,
        const Duration(seconds: 20),
      );
      expect(eof, isTrue,
          reason: 'EOF never reached (pos=${session.player.state.position} dur=$dur)');
      await session.seek(dur);
      final landed = await waitFor(
        () => (session.player.state.position - dur).abs() <
            const Duration(milliseconds: 400),
        const Duration(seconds: 10),
      );
      debugPrint('EXACT_SEEK dur=$dur pos=${session.player.state.position} '
          'completed=${session.player.state.completed} '
          'playback=${session.playback.position} mode=${session.playback.mode}');
      expect(landed, isTrue,
          reason: 'exact seek to duration did not land (pos=${session.player.state.position} dur=$dur)');
      expect(session.playback.position, dur,
          reason: 'playback.position should be dur after exact seek (got ${session.playback.position})');

      await session.play();
      debugPrint('EXACT_AFTER_PLAY playback=${session.playback.position} '
          'mode=${session.playback.mode} playerPos=${session.player.state.position} '
          'completed=${session.player.state.completed}');
      expect(session.playback.position, Duration.zero,
          reason: 'play after exact seek to duration must submit 0 (got ${session.playback.position})');
      expect(session.playback.mode, PlaybackMode.playing);

      final readvanced = await waitFor(
        () => session.player.state.position >
                const Duration(milliseconds: 300) &&
            session.player.state.position < dur &&
            session.player.state.playing,
        const Duration(seconds: 8),
      );
      debugPrint('EXACT_REPLAY_RESULT pos=${session.player.state.position} '
          'dur=${session.player.state.duration} playing=${session.player.state.playing} '
          'completed=${session.player.state.completed}');
      expect(readvanced, isTrue,
          reason: 'exact-seek replay did not advance from 0 (pos=${session.player.state.position} dur=$dur)');
    } finally {
      await cleanup(session, signaling, [clip]);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('mid seek then play retains position', (tester) async {
    final clip = await materialize('assets/sample.mp4', 'sample.mp4');
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final session = await soloSession(signaling);
    try {
      await session.addLocalFile(XFile(clip.path, name: 'sample.mp4'));
      expect(session.lastErrorCode, isNull);
      await session.switchItem(session.playlist.single.itemId);
      await session.play();

      final started = await waitFor(
        () => session.player.state.position >
            const Duration(milliseconds: 300),
        const Duration(seconds: 10),
      );
      expect(started, isTrue);
      final dur = session.player.state.duration;
      final eof = await waitFor(
        () => session.player.state.completed,
        const Duration(seconds: 20),
      );
      expect(eof, isTrue);
      const target = Duration(milliseconds: 1500);
      await session.seek(target);
      final landed = await waitFor(
        () => (session.player.state.position - target).abs() <
            const Duration(milliseconds: 500),
        const Duration(seconds: 10),
      );
      expect(landed, isTrue,
          reason: 'mid seek did not land (pos=${session.player.state.position})');
      await session.play();
      expect((session.playback.position - target).abs(),
          lessThan(const Duration(milliseconds: 600)),
          reason: 'play after mid seek must retain target (got ${session.playback.position} want $target)');
      final advanced = await waitFor(
        () => session.player.state.position >
                target + const Duration(milliseconds: 250) &&
            session.player.state.position < dur,
        const Duration(seconds: 6),
      );
      expect(advanced, isTrue,
          reason: 'did not advance from mid (pos=${session.player.state.position})');
      expect(session.player.state.position,
          greaterThan(const Duration(milliseconds: 1000)),
          reason: 'restarted at 0 instead of retaining mid');
    } finally {
      await cleanup(session, signaling, [clip]);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('near-end slider seek replays instead of stalling', (tester) async {
    final clip = await materialize('assets/sample.mp4', 'sample.mp4');
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final session = await soloSession(signaling);
    try {
      await session.addLocalFile(XFile(clip.path, name: 'sample.mp4'));
      await session.switchItem(session.playlist.single.itemId);
      expect(await waitFor(() => session.player.state.duration > Duration.zero,
          const Duration(seconds: 10)), isTrue);
      final duration = session.player.state.duration;
      await session.seek(duration - const Duration(milliseconds: 100));
      await session.play();
      expect(session.playback.position, Duration.zero);
      expect(await waitFor(
          () => session.player.state.playing &&
              session.player.state.position > const Duration(milliseconds: 300) &&
              session.player.state.position < duration - const Duration(seconds: 1),
          const Duration(seconds: 8)), isTrue);
    } finally {
      await cleanup(session, signaling, [clip]);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
