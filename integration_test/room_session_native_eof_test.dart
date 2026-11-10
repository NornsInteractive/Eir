import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

/// Native EOF replay verification with real media_kit Player + RoomSession
/// loopback on Linux host. Uses only public session APIs (addLocalFile /
/// switchItem / play / pause / seek) and real player state; no private
/// method calls and no logic-model transcription.
///
/// Samples (all shipped unmodified, all contain a second `soun` audio
/// track, verified by box inspection):
/// - assets/sample.mp4: 3.0s, tail-moov, video+AAC audio.
/// - assets/eir_short1.mp4 / eir_short2.mp4: 1.6s, tail-moov, video+audio.
/// - assets/eir_media_fixture.mp4: 20s, tail-moov, video+audio (regression).
///
/// Host-only: `xvfb-run -a flutter test integration_test/room_session_native_eof_test.dart -d linux`
/// Does not use ADB / Android emulator.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<File> materialize(String asset, String name) async {
    final dir = await Directory.systemTemp.createTemp('eir_eof_');
    final out = File('${dir.path}/$name');
    final data = await rootBundle.load(asset);
    await out.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return out;
  }

  Future<List<int>> loadBytes(String asset) async {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
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

  Future<void> verifyDataIntact(RoomSession session, List<int> expected) async {
    final item = session.playlist.single;
    final mediaId = item.localMediaId;
    expect(mediaId, isNotNull, reason: 'playlist item has no localMediaId');
    final svc = session.debugMediaService;
    expect(svc, isNotNull, reason: 'media service missing after addLocalFile');
    expect(session.cacheUsedBytes, greaterThan(0),
        reason: 'media cache empty; data must not be unloaded/cleared');
    const head = 4096;
    final headBytes = await svc!.readRangeBytes(mediaId!, 0, head);
    expect(headBytes.length, head);
    expect(headBytes, expected.sublist(0, head),
        reason: 'head bytes changed after playback path');
    final tailLen = expected.length < 8192 ? expected.length : 8192;
    final tailStart = expected.length - tailLen;
    final tailBytes = await svc.readRangeBytes(
      mediaId,
      tailStart,
      expected.length,
    );
    expect(tailBytes, expected.sublist(tailStart),
        reason: 'tail bytes changed after playback path');
    debugPrint('DATA_OK cacheUsed=${session.cacheUsedBytes} '
        'mediaId=$mediaId len=${expected.length}');
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

  testWidgets('native EOF: public play submits 0 and re-advances',
      (tester) async {
    final clip = await materialize('assets/sample.mp4', 'sample.mp4');
    final expected = await loadBytes('assets/sample.mp4');
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final session = await soloSession(signaling);
    try {
      await session.addLocalFile(XFile(clip.path, name: 'sample.mp4'));
      expect(session.lastErrorCode, isNull,
          reason: 'addLocalFile failed: ${session.lastErrorCode}');
      await session.switchItem(session.playlist.single.itemId);
      await session.play();

      // Real advance first (proves the file is playable on this host).
      final started = await waitFor(
        () => session.player.state.position >
            const Duration(milliseconds: 200),
        const Duration(seconds: 10),
      );
      expect(started, isTrue,
          reason: 'sample did not advance at all '
              '(pos=${session.player.state.position} '
              'dur=${session.player.state.duration} '
              'completed=${session.player.state.completed} '
              'error=${session.lastErrorCode})');

      // Wait for real EOF: native completed flag.
      final eof = await waitFor(
        () => session.player.state.completed,
        const Duration(seconds: 20),
      );
      expect(eof, isTrue,
          reason: 'EOF never reached: pos=${session.player.state.position} '
              'dur=${session.player.state.duration} '
              'playing=${session.player.state.playing} '
              'completed=${session.player.state.completed} '
              'error=${session.lastErrorCode}');
      final dur = session.player.state.duration;
      final eofPos = session.player.state.position;
      final cacheBefore = session.cacheUsedBytes;
      debugPrint('EOF_REACHED pos=$eofPos dur=$dur '
          'completed=${session.player.state.completed} '
          'mode=${session.playback.mode} cache=$cacheBefore');
      expect(dur, greaterThan(Duration.zero));

      // Public play() at EOF must submit positionMs 0 (public play path
      // checks completed/atEnd) and, with the reopen fix in
      // _ensureMediaLoaded, must actually re-advance instead of staying
      // stuck at the end after a seek(0) cleared completed.
      await session.play();
      // Session commit projection: EOF replay anchors at 0.
      debugPrint('AFTER_EOF_PLAY playback.position=${session.playback.position} '
          'mode=${session.playback.mode} seq=${session.playback.seq}');
      expect(session.playback.position, Duration.zero,
          reason: 'public play() at EOF did not submit position 0 '
              '(playback.position=${session.playback.position})');
      expect(session.playback.mode, PlaybackMode.playing);

      final readvanced = await waitFor(
        () => session.player.state.position >
                const Duration(milliseconds: 300) &&
            !session.player.state.completed &&
            session.player.state.playing,
        const Duration(seconds: 8),
      );
      debugPrint('REPLAY_RESULT pos=${session.player.state.position} '
          'dur=${session.player.state.duration} '
          'playing=${session.player.state.playing} '
          'completed=${session.player.state.completed} '
          'error=${session.lastErrorCode}');
      expect(readvanced, isTrue,
          reason: 'EOF replay did not re-advance from 0 (stuck at end?) '
              'pos=${session.player.state.position} '
              'dur=${session.player.state.duration} '
              'completed=${session.player.state.completed} '
              'playing=${session.player.state.playing}');
      expect(session.player.state.position, lessThan(dur),
          reason: 'replayed position should be inside media, not pinned at EOF');

      await verifyDataIntact(session, expected);
    } finally {
      await takeByteAndFinish(session, signaling, [clip]);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('native EOF: explicit seek to middle then play retains position',
      (tester) async {
    final clip = await materialize('assets/sample.mp4', 'sample.mp4');
    final expected = await loadBytes('assets/sample.mp4');
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final session = await soloSession(signaling);
    try {
      await session.addLocalFile(XFile(clip.path, name: 'sample.mp4'));
      expect(session.lastErrorCode, isNull);
      await session.switchItem(session.playlist.single.itemId);
      await session.play();

      final eof = await waitFor(
        () => session.player.state.completed,
        const Duration(seconds: 20),
      );
      expect(eof, isTrue,
          reason: 'EOF never reached for seek-retain test '
              '(pos=${session.player.state.position} '
              'dur=${session.player.state.duration} '
              'error=${session.lastErrorCode})');
      debugPrint('SEEK_TEST_EOF pos=${session.player.state.position} '
          'dur=${session.player.state.duration} '
          'mode=${session.playback.mode}');

      const target = Duration(milliseconds: 1500);
      await session.seek(target);
      final landed = await waitFor(
        () => (session.player.state.position - target).abs() <
            const Duration(milliseconds: 500),
        const Duration(seconds: 10),
      );
      debugPrint('AFTER_EOF_SEEK pos=${session.player.state.position} '
          'target=$target completed=${session.player.state.completed} '
          'playback.position=${session.playback.position}');
      expect(landed, isTrue,
          reason: 'explicit seek after EOF did not land near middle '
              '(pos=${session.player.state.position} target=$target)');

      await session.play();
      debugPrint('AFTER_SEEK_PLAY playback.position=${session.playback.position} '
          'mode=${session.playback.mode} playerPos=${session.player.state.position}');
      expect(session.playback.position, target,
          reason: 'play() after seek-to-middle must retain position '
              '(got ${session.playback.position}, want $target)');

      final advancedFromMiddle = await waitFor(
        () => session.player.state.position >
                target + const Duration(milliseconds: 250) &&
            !session.player.state.completed,
        const Duration(seconds: 6),
      );
      debugPrint('SEEK_RETAIN_RESULT pos=${session.player.state.position} '
          'playing=${session.player.state.playing} '
          'completed=${session.player.state.completed}');
      expect(advancedFromMiddle, isTrue,
          reason: 'play after seek-to-middle did not advance from middle '
              '(pos=${session.player.state.position} target=$target)');
      // Must not have restarted at 0.
      expect(session.player.state.position,
          greaterThan(const Duration(milliseconds: 1000)),
          reason: 'position restarted at 0 instead of retaining middle');

      await verifyDataIntact(session, expected);
    } finally {
      await takeByteAndFinish(session, signaling, [clip]);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('native pause/resume keeps position and advances',
      (tester) async {
    final clip = await materialize('assets/sample.mp4', 'sample.mp4');
    final expected = await loadBytes('assets/sample.mp4');
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final session = await soloSession(signaling);
    try {
      await session.addLocalFile(XFile(clip.path, name: 'sample.mp4'));
      expect(session.lastErrorCode, isNull);
      await session.switchItem(session.playlist.single.itemId);
      await session.play();

      final playing = await waitFor(
        () => session.player.state.position >
            const Duration(milliseconds: 400),
        const Duration(seconds: 10),
      );
      expect(playing, isTrue,
          reason: 'did not advance before pause '
              '(pos=${session.player.state.position} err=${session.lastErrorCode})');

      final beforePause = session.player.state.position;
      await session.pause();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final pausedPos = session.player.state.position;
      debugPrint('PAUSE posBefore=$beforePause posAfter=$pausedPos '
          'mode=${session.playback.mode} playing=${session.player.state.playing}');
      expect(session.playback.mode, PlaybackMode.paused);
      expect((pausedPos - beforePause).abs(),
          lessThan(const Duration(milliseconds: 300)),
          reason: 'position moved while paused: before=$beforePause after=$pausedPos');

      await session.play();
      debugPrint('AFTER_RESUME playback.position=${session.playback.position} '
          'mode=${session.playback.mode}');
      expect(session.playback.mode, PlaybackMode.playing);
      // Resume must anchor near the paused position, not at 0.
      expect(
        (session.playback.position - pausedPos).abs(),
        lessThan(const Duration(milliseconds: 600)),
        reason: 'resume did not retain pause position '
            '(playback=${session.playback.position} paused=$pausedPos)',
      );
      final resumed = await waitFor(
        () => session.player.state.position >
            pausedPos + const Duration(milliseconds: 300),
        const Duration(seconds: 6),
      );
      debugPrint('RESUME_RESULT pos=${session.player.state.position} '
          'pausedPos=$pausedPos');
      expect(resumed, isTrue,
          reason: 'resume did not advance from pause position '
              '(pos=${session.player.state.position} paused=$pausedPos)');

      await verifyDataIntact(session, expected);
    } finally {
      await takeByteAndFinish(session, signaling, [clip]);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('native fast-switch and tail-moov advance, data retained',
      (tester) async {
    final short = await materialize('assets/eir_short1.mp4', 'short1.mp4');
    final tail = await materialize(
      'assets/eir_media_fixture.mp4',
      'eir_media_fixture.mp4',
    );
    final shortExpected = await loadBytes('assets/eir_short1.mp4');
    final tailExpected = await loadBytes('assets/eir_media_fixture.mp4');
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final session = await soloSession(signaling);
    try {
      await session.addLocalFile(XFile(short.path, name: 'short1.mp4'));
      await session.addLocalFile(
        XFile(tail.path, name: 'eir_media_fixture.mp4'),
      );
      expect(session.lastErrorCode, isNull,
          reason: 'addLocalFile failed: ${session.lastErrorCode}');
      expect(session.playlist, hasLength(2));
      final shortId = session.playlist[0].itemId;
      final tailId = session.playlist[1].itemId;

      Future<void> switchAndAdvance(
        String itemId,
        String label, {
        required Duration threshold,
        required Duration window,
      }) async {
        await session.switchItem(itemId);
        await session.play();
        final ok = await waitFor(
          () => session.player.state.position > threshold &&
              !session.player.state.completed,
          window,
        );
        debugPrint('SWITCH_$label pos=${session.player.state.position} '
            'dur=${session.player.state.duration} cur=${session.currentItemId} '
            'error=${session.lastErrorCode}');
        expect(ok, isTrue,
            reason: 'switch to $label did not advance '
                '(pos=${session.player.state.position} '
                'dur=${session.player.state.duration} '
                'threshold=$threshold error=${session.lastErrorCode})');
        expect(session.currentItemId, itemId);
      }

      await switchAndAdvance(shortId, 'short_first',
          threshold: const Duration(milliseconds: 300),
          window: const Duration(seconds: 8));
      // Fast switch before EOF: 3s sample window is not used here; the
      // 1.6s short must still have advanced, switch to tail fixture.
      await switchAndAdvance(tailId, 'tail_after_short',
          threshold: const Duration(milliseconds: 800),
          window: const Duration(seconds: 12));
      // Back to short: proves the player is not wedged after tail open.
      await switchAndAdvance(shortId, 'short_back',
          threshold: const Duration(milliseconds: 300),
          window: const Duration(seconds: 8));

      expect(session.cacheUsedBytes, greaterThan(0),
          reason: 'cache cleared by fast switch');
      // Tail data must still be byte-exact through the service.
      final tailSvc = session.debugMediaService;
      expect(tailSvc, isNotNull);
      final tailMediaId = session.playlist[1].localMediaId;
      expect(tailMediaId, isNotNull);
      final headBytes = await tailSvc!.readRangeBytes(tailMediaId!, 0, 4096);
      expect(headBytes, tailExpected.sublist(0, 4096),
          reason: 'tail head bytes changed after fast switch');
      debugPrint('FAST_SWITCH_DATA_OK cacheUsed=${session.cacheUsedBytes}');
      expect(shortExpected.length, greaterThan(0));
    } finally {
      await takeByteAndFinish(session, signaling, [short, tail]);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
