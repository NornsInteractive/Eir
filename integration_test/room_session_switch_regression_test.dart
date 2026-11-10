import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

/// Regression for Android local playback sticking at 00:00 for large
/// tail-moov files (moov at the end, e.g. `assets/eir_media_fixture.mp4`).
///
/// Root cause (measured in the ADB diagnosis): the Dart loopback Range
/// bridge serves every Range correctly (verified: full-file probe, moov-tail
/// seek and data re-read all return correct bytes), but `RoomSession`
/// reopened media on the reused Player without a reset, leaving libmpv
/// demux/VO state dirty after a previous item. The new item then never
/// started (duration known, position frozen at 0, no error), and the wedge
/// polluted every later item on the same Player.
///
/// Fix: reset the player with `stop()` before each `open()` and clear the
/// loaded marker on open failure so a later switch really re-opens.
///
/// These tests use the shipped tail-moov fixture unmodified (not converted,
/// not replaced) and assert real player position advancement, not the
/// session projection.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<File> materialize(String asset, String name) async {
    final dir = await Directory.systemTemp.createTemp('eir_reg_');
    final out = File('${dir.path}/$name');
    final data = await rootBundle.load(asset);
    await out.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return out;
  }

  Future<bool> advances(RoomSession session,
      {Duration window = const Duration(seconds: 10)}) async {
    final start = session.player.state.position;
    final deadline = DateTime.now().add(window);
    while (DateTime.now().isBefore(deadline)) {
      if (session.player.state.position > start + const Duration(milliseconds: 800)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return session.player.state.position > start;
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

  testWidgets('solo tail-moov local playback advances', (tester) async {
    final tail = await materialize(
      'assets/eir_media_fixture.mp4',
      'eir_media_fixture.mp4',
    );
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final session = await soloSession(signaling);
    try {
      await session.addLocalFile(XFile(tail.path, name: 'tail.mp4'));
      expect(session.lastErrorCode, isNull);
      await session.switchItem(session.playlist.single.itemId);
      await session.play();
      final ok = await advances(session);
      expect(ok, isTrue,
          reason: 'tail-moov playback did not advance '
              '(pos=${session.player.state.position} '
              'dur=${session.player.state.duration} '
              'error=${session.lastErrorCode})');
    } finally {
      session.dispose();
      await signaling.stop();
      try {
        await tail.parent.delete(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('switch away and back to tail still advances',
      (tester) async {
    final tail = await materialize(
      'assets/eir_media_fixture.mp4',
      'eir_media_fixture.mp4',
    );
    final head = await materialize('assets/eir_long.mp4', 'eir_long.mp4');
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final session = await soloSession(signaling);
    try {
      await session.addLocalFile(XFile(tail.path, name: 'tail.mp4'));
      await session.addLocalFile(XFile(head.path, name: 'head.mp4'));
      expect(session.lastErrorCode, isNull);
      final tailId = session.playlist[0].itemId;
      final headId = session.playlist[1].itemId;

      await session.switchItem(tailId);
      await session.play();
      expect(await advances(session), isTrue,
          reason: 'first tail play did not advance');

      // complete-adjacent switch (previous item paused mid-play, new open
      // must still start cleanly)
      await session.switchItem(headId);
      await session.play();
      expect(await advances(session), isTrue,
          reason: 'head after tail did not advance');

      await session.switchItem(tailId);
      await session.play();
      expect(await advances(session), isTrue,
          reason: 'tail after head did not advance (player wedge)');
    } finally {
      session.dispose();
      await signaling.stop();
      try {
        await tail.parent.delete(recursive: true);
      } catch (_) {}
      try {
        await head.parent.delete(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
