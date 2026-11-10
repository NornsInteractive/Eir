import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

/// Leave-playback reproduction (real Linux RoomSession + real media_kit
/// Player, public APIs only, no product-lib changes, no fake playback).
///
/// Host-only: `xvfb-run -a flutter test integration_test/room_session_leave_playback_test.dart -d linux`
///
/// What it does:
/// 1. Materializes the shipped 20s fixture asset (`assets/eir_media_fixture.mp4`)
///    to a real temp file; adds it via `addLocalFile`, `switchItem`, `play`.
/// 2. Proves real advance: waits until `session.player.state.position > 1s`
///    and `playing == true` (real player state, not room projection).
/// 3. Captures pre-leave player state, calls public `session.leaveRoom()`.
/// 4. Captures immediate post-leave player state (same `session.player` —
///    leaveRoom must not dispose it) plus room fields (roomId / connection /
///    playback projection) to contrast "room reset" vs actual playback.
/// 5. Waits exactly 1s and captures `player.state.playing` + `position` again.
///    Correct behavior after leave is stopped: `playing == false` and
///    position no longer advances (small pause-settling tolerance only).
///
/// 20s fixture is used so the 1s post-leave window cannot be confounded by
/// EOF / completed state (duration >> position + 1s). Does not use ADB,
/// the current 8080 AppWeb serving nor signaling servers (random loopback
/// port 0), does not build Web/APK, does not clear data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<File> materialize(String asset, String name) async {
    final dir = await Directory.systemTemp.createTemp('eir_leave_');
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
    expect(session.lastErrorCode, isNull,
        reason: 'createRoom failed: ${session.lastErrorCode}');
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

  Future<void> takeByteAndFinish(
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

  testWidgets('leaveRoom stops real player playback within 1s',
      (tester) async {
    final clip = await materialize(
      'assets/eir_media_fixture.mp4',
      'eir_media_fixture.mp4',
    );
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final session = await soloSession(signaling);
    try {
      await session.addLocalFile(
        XFile(clip.path, name: 'eir_media_fixture.mp4'),
      );
      expect(session.lastErrorCode, isNull,
          reason: 'addLocalFile failed: ${session.lastErrorCode}');
      await session.switchItem(session.playlist.single.itemId);
      await session.play();

      // Real advance first (proves the 20s file is really playing on host).
      final started = await waitFor(
        () => session.player.state.position > const Duration(seconds: 1) &&
            session.player.state.playing,
        const Duration(seconds: 15),
      );
      final prePos = session.player.state.position;
      final prePlaying = session.player.state.playing;
      final preDur = session.player.state.duration;
      final preCompleted = session.player.state.completed;
      final preRoomId = session.roomId;
      debugPrint('LEAVE_PRE pos=$prePos dur=$preDur playing=$prePlaying '
          'completed=$preCompleted roomId=$preRoomId '
          'conn=${session.connectionState} playbackMode=${session.playback.mode} '
          'playbackPos=${session.playback.position} err=${session.lastErrorCode}');
      expect(started, isTrue,
          reason: 'fixture did not really advance before leave '
              '(pos=$prePos dur=$preDur playing=$prePlaying '
              'completed=$preCompleted err=${session.lastErrorCode})');
      expect(preDur > const Duration(seconds: 15), isTrue,
          reason: 'fixture is not the 20s clip (dur=$preDur)');

      await session.leaveRoom();

      // Immediate post-leave sample on the SAME Player instance. Room fields
      // alone must not be used as playback evidence.
      final t0Pos = session.player.state.position;
      final t0Playing = session.player.state.playing;
      debugPrint('LEAVE_T0 pos=$t0Pos playing=$t0Playing '
          'roomId=${session.roomId} conn=${session.connectionState} '
          'playbackMode=${session.playback.mode} '
          'playbackPos=${session.playback.position} '
          'item=${session.currentItemId} err=${session.lastErrorCode}');

      await Future<void>.delayed(const Duration(milliseconds: 1000));

      final t1Pos = session.player.state.position;
      final t1Playing = session.player.state.playing;
      final t1Dur = session.player.state.duration;
      final t1Completed = session.player.state.completed;
      final deltaMs = t1Pos.inMilliseconds - t0Pos.inMilliseconds;
      final deltaFromPreMs = t1Pos.inMilliseconds - prePos.inMilliseconds;
      debugPrint('LEAVE_T1 pos=$t1Pos playing=$t1Playing dur=$t1Dur '
          'completed=$t1Completed deltaMs=$deltaMs deltaFromPreMs=$deltaFromPreMs '
          'roomId=${session.roomId} conn=${session.connectionState} '
          'playbackMode=${session.playback.mode} '
          'playbackPos=${session.playback.position} '
          'item=${session.currentItemId} err=${session.lastErrorCode}');
      debugPrint('LEAVE_VERDICT playingBefore=$prePlaying posBefore=$prePos '
          'posT0=$t0Pos posT1=$t1Pos deltaMs=$deltaMs playingT1=$t1Playing');

      expect(session.roomId, isNull,
          reason: 'leaveRoom must clear roomId (got ${session.roomId})');
      expect(session.connectionState, RoomConnectionState.disconnected);
      // The bug this reproduces: leaveRoom currently does not pause the
      // underlying Player, so playing stays true and position advances.
      // These expectations state correct behavior; running against current
      // source they should fail with the exact values above.
      expect(t1Playing, isFalse,
          reason: 'player still playing 1s after leaveRoom '
              '(posBefore=$prePos posT0=$t0Pos posT1=$t1Pos deltaMs=$deltaMs)');
      expect(deltaMs, lessThan(200),
          reason: 'position still advanced 1s after leaveRoom '
              '(posBefore=$prePos posT0=$t0Pos posT1=$t1Pos deltaMs=$deltaMs)');
      expect(t1Pos, Duration.zero, reason: 'old position must not leak into a new room');
      expect(t1Dur, Duration.zero, reason: 'old duration must not leak into a new room');
      expect(session.player.state.playlist.medias, isEmpty);
      await session.createRoom();
      expect(session.playlist, isEmpty);
      expect(session.player.state.duration, Duration.zero);
    } finally {
      await takeByteAndFinish(session, signaling, [clip]);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
