import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

// EOF snapshot regression (Linux harness: real RoomSession x2, real
// media_kit Player, real WebRTC DataChannel, loopback signaling/media).
// Public APIs only; no product hooks, no source-text assertions.
//
// Background: a 1.6s member clip (22506B) reached EOF on the owner
// (1600ms) while the member stayed at 0 instead of the 180s film
// playing. Previously _apply('ended_stop') reused the start anchor
// (position 0) and the late-join snapshot arrived paused at 0.
// The fix makes the owner publish ended_stop with the real duration
// as positionMs, validates it as optional non-negative, and applies
// params position (old no-field commits stay compatible).
//
// This test uses the shipped 20s fixture (assets/eir_media_fixture.mp4)
// and seeks near the tail to reach a REAL EOF quickly without
// shortening the suspicious length: assertions demand positions near
// the full duration, never "within the whole clip".
//   1. Owner single-item play to real EOF: owner playback.position
//      must equal duration and mode paused. Guest late-joins: the
//      snapshot target (guest playback.position) and the guest's real
//      player position must both sit at the tail (not 0), paused.
//      If Media(start: duration) cannot load the tail on this host,
//      the failure dump reports duration/position/error verbatim.
//   2. Owner play() at EOF: both sides return to 0 and advance
//      (proves the start param cannot pin the position).
//   3. Paused snapshot opened at 10s, then seek to 2s (before the
//      start anchor): the guest's real player and public playback
//      state must both land near 2s. On Linux native this proves
//      mpv does not enforce Media.start as a lower bound; any clamp
//      here is a platform difference vs the web onTimeUpdate clamp
//      risk and must be reported, not hidden.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'EOF ended_stop snapshot lands guest at tail, replay restarts at 0',
    (tester) async {
      final fixtureBytes = await _fixtureBytes();
      final mediaServer = await _startRangeServer(fixtureBytes);
      addTearDown(() => mediaServer.close(force: true));
      final url = 'http://127.0.0.1:${mediaServer.port}/fix.mp4';

      final signaling = SignalingServer();
      await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
      addTearDown(signaling.stop);
      final signalingUrl = 'ws://127.0.0.1:${signaling.port}';

      final sessionA = RoomSession(
        identityStore: DeviceIdentityStore(
          store: InMemorySecureKeyValueStore(),
        ),
      );
      final sessionB = RoomSession(
        identityStore: DeviceIdentityStore(
          store: InMemorySecureKeyValueStore(),
        ),
      );
      addTearDown(sessionA.dispose);
      addTearDown(sessionB.dispose);

      await sessionA.init();
      await sessionB.init();
      await sessionA.setSignalingUrl(signalingUrl);
      await sessionB.setSignalingUrl(signalingUrl);
      await sessionA.createRoom();

      // Single playlist item: EOF must end the room, not switch.
      await sessionA.addUrl(url, title: 'fix');
      expect(
        sessionA.lastErrorCode,
        isNull,
        reason: 'addUrl failed: ${sessionA.lastErrorCode}',
      );
      final item = sessionA.playlist.single.itemId;
      await sessionA.switchItem(item);
      await sessionA.play();
      final advanced = await _waitFor(
        () => sessionA.player.state.position >= const Duration(seconds: 1),
        timeout: const Duration(seconds: 20),
      );
      expect(
        advanced,
        isTrue,
        reason:
            'owner never advanced '
            '(pos=${sessionA.player.state.position} '
            'err=${sessionA.lastErrorCode})',
      );

      final dur = sessionA.player.state.duration;
      expect(
        dur,
        greaterThan(const Duration(seconds: 15)),
        reason:
            'fixture duration unexpectedly short: dur=$dur '
            '(test would stop measuring the tail)',
      );
      _dump('OWNER_LOADED', sessionA);

      // Seek near the tail, then let it really play into EOF.
      final nearTail = dur - const Duration(milliseconds: 1500);
      await sessionA.seek(nearTail);
      final landed = await _waitFor(
        () =>
            (sessionA.player.state.position - nearTail).abs() <
            const Duration(milliseconds: 800),
        timeout: const Duration(seconds: 10),
      );
      expect(
        landed,
        isTrue,
        reason:
            'owner seek near tail did not land '
            '(pos=${sessionA.player.state.position} target=$nearTail '
            'err=${sessionA.lastErrorCode})',
      );

      final eof = await _waitFor(
        () =>
            sessionA.player.state.completed &&
            sessionA.playback.mode == PlaybackMode.paused &&
            sessionA.playback.position >=
                dur - const Duration(milliseconds: 700),
        timeout: const Duration(seconds: 15),
      );
      _dump('OWNER_EOF', sessionA);
      debugPrint(
        'OWNER_EOF dur=$dur playback.position='
        '${sessionA.playback.position} mode=${sessionA.playback.mode} '
        'playerPos=${sessionA.player.state.position} '
        'completed=${sessionA.player.state.completed}',
      );
      expect(
        eof,
        isTrue,
        reason:
            'owner did not reach paused EOF at duration '
            '(playerPos=${sessionA.player.state.position} dur=$dur '
            'playback.position=${sessionA.playback.position} '
            'mode=${sessionA.playback.mode} '
            'completed=${sessionA.player.state.completed} '
            'err=${sessionA.lastErrorCode})',
      );
      // ended_stop must carry the real duration, not the start anchor 0.
      expect(
        sessionA.playback.position >= dur - const Duration(milliseconds: 700) &&
            sessionA.playback.position <= dur,
        isTrue,
        reason:
            'owner playback.position is not near duration '
            '(pos=${sessionA.playback.position} dur=$dur)',
      );

      // Guest late-joins AFTER EOF: the snapshot must target the tail.
      await sessionB.joinRoom(sessionA.inviteText!);
      final verified = await _waitFor(
        () => sessionA.peerVerified && sessionB.peerVerified,
        timeout: const Duration(seconds: 20),
      );
      expect(
        verified,
        isTrue,
        reason:
            'peers never verified '
            '(aVerified=${sessionA.peerVerified} '
            'bVerified=${sessionB.peerVerified})',
      );

      final guestTargetAtTail = await _waitFor(
        () =>
            sessionB.currentItemId == item &&
            sessionB.playback.mode == PlaybackMode.paused &&
            sessionB.playback.position >=
                dur - const Duration(milliseconds: 700),
        timeout: const Duration(seconds: 20),
      );
      _dump('GUEST_SNAPSHOT_TARGET', sessionB);
      debugPrint(
        'GUEST_TARGET target=${sessionB.playback.position} '
        'mode=${sessionB.playback.mode} dur=$dur',
      );
      expect(
        guestTargetAtTail,
        isTrue,
        reason:
            'guest snapshot target is not near duration '
            '(target=${sessionB.playback.position} dur=$dur '
            'mode=${sessionB.playback.mode} err=${sessionB.lastErrorCode})',
      );

      // The guest's REAL player must also sit at the tail, paused.
      // Media(start: duration) is the risk: if mpv cannot open a
      // start==duration media, position stays 0 / errors below.
      final guestPlayerAtTail = await _waitFor(
        () =>
            sessionB.player.state.position >=
                dur - const Duration(milliseconds: 2000) &&
            !sessionB.player.state.playing,
        timeout: const Duration(seconds: 25),
      );
      _dump('GUEST_PLAYER_TAIL', sessionB);
      debugPrint(
        'GUEST_PLAYER pos=${sessionB.player.state.position} '
        'dur=${sessionB.player.state.duration} '
        'playing=${sessionB.player.state.playing} '
        'completed=${sessionB.player.state.completed} '
        'width=${sessionB.player.state.width} '
        'height=${sessionB.player.state.height} '
        'err=${sessionB.lastErrorCode}',
      );
      expect(
        guestPlayerAtTail,
        isTrue,
        reason:
            'guest real player did not load at the tail '
            '(pos=${sessionB.player.state.position} '
            'dur=${sessionB.player.state.duration} '
            'playing=${sessionB.player.state.playing} '
            'completed=${sessionB.player.state.completed} '
            'width=${sessionB.player.state.width} '
            'height=${sessionB.player.state.height} '
            'err=${sessionB.lastErrorCode}; '
            'snapshot target=${sessionB.playback.position})',
      );
      expect(
        sessionB.player.state.position,
        greaterThan(const Duration(seconds: 10)),
        reason:
            'guest player fell back toward 0 '
            '(pos=${sessionB.player.state.position} dur=$dur)',
      );
      // Target and real player agree at the tail (not 0, not mid).
      expect(
        (sessionB.player.state.position - sessionB.playback.position).abs(),
        lessThan(const Duration(seconds: 2500)),
        reason:
            'snapshot target ${sessionB.playback.position} disagrees '
            'with real player ${sessionB.player.state.position}',
      );

      // Owner play() at EOF: both sides return to 0 and advance.
      await sessionA.play();
      final bothRestarted = await _waitFor(
        () =>
            sessionA.playback.mode == PlaybackMode.playing &&
            sessionB.playback.mode == PlaybackMode.playing &&
            sessionA.playback.position == Duration.zero &&
            sessionB.playback.position == Duration.zero &&
            sessionA.player.state.position >
                const Duration(milliseconds: 400) &&
            sessionA.player.state.position < dur &&
            sessionB.player.state.position >
                const Duration(milliseconds: 400) &&
            sessionB.player.state.position < dur &&
            !sessionA.player.state.completed &&
            !sessionB.player.state.completed,
        timeout: const Duration(seconds: 20),
      );
      _dump('REPLAY_OWNER', sessionA);
      _dump('REPLAY_GUEST', sessionB);
      debugPrint(
        'REPLAY ownerPos=${sessionA.player.state.position} '
        'guestPos=${sessionB.player.state.position} '
        'ownerPb=${sessionA.playback.position} '
        'guestPb=${sessionB.playback.position} '
        'ownerPlaying=${sessionA.player.state.playing} '
        'guestPlaying=${sessionB.player.state.playing} '
        'guestCompleted=${sessionB.player.state.completed} '
        'guestErr=${sessionB.lastErrorCode}',
      );
      expect(
        bothRestarted,
        isTrue,
        reason:
            'EOF replay did not restart both sides from 0 '
            '(ownerPos=${sessionA.player.state.position} '
            'guestPos=${sessionB.player.state.position} '
            'ownerPb=${sessionA.playback.position} '
            'guestPb=${sessionB.playback.position} '
            'guestPlaying=${sessionB.player.state.playing} '
            'guestCompleted=${sessionB.player.state.completed} '
            'guestErr=${sessionB.lastErrorCode})',
      );

      await sessionA.closeRoom();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'paused snapshot seek before start anchor lands at 2s',
    (tester) async {
      final fixtureBytes = await _fixtureBytes();
      final mediaServer = await _startRangeServer(fixtureBytes);
      addTearDown(() => mediaServer.close(force: true));
      final url = 'http://127.0.0.1:${mediaServer.port}/fix.mp4';

      final signaling = SignalingServer();
      await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
      addTearDown(signaling.stop);
      final signalingUrl = 'ws://127.0.0.1:${signaling.port}';

      final sessionA = RoomSession(
        identityStore: DeviceIdentityStore(
          store: InMemorySecureKeyValueStore(),
        ),
      );
      final sessionB = RoomSession(
        identityStore: DeviceIdentityStore(
          store: InMemorySecureKeyValueStore(),
        ),
      );
      addTearDown(sessionA.dispose);
      addTearDown(sessionB.dispose);

      await sessionA.init();
      await sessionB.init();
      await sessionA.setSignalingUrl(signalingUrl);
      await sessionB.setSignalingUrl(signalingUrl);
      await sessionA.createRoom();

      await sessionA.addUrl(url, title: 'fix');
      final item = sessionA.playlist.single.itemId;
      await sessionA.switchItem(item);
      await sessionA.play();
      final playing = await _waitFor(
        () => sessionA.player.state.position >= const Duration(seconds: 2),
        timeout: const Duration(seconds: 20),
      );
      expect(
        playing,
        isTrue,
        reason:
            'owner never advanced '
            '(pos=${sessionA.player.state.position} '
            'err=${sessionA.lastErrorCode})',
      );

      // Owner paused at 10s BEFORE the guest joins: the guest's first
      // open uses Media(start: 10s).
      const startAnchor = Duration(seconds: 10);
      await sessionA.seek(startAnchor);
      final landed = await _waitFor(
        () =>
            (sessionA.player.state.position - startAnchor).abs() <
            const Duration(milliseconds: 800),
        timeout: const Duration(seconds: 10),
      );
      expect(
        landed,
        isTrue,
        reason:
            'owner seek to 10s did not land '
            '(pos=${sessionA.player.state.position} '
            'err=${sessionA.lastErrorCode})',
      );
      await sessionA.pause();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(sessionA.playback.mode, PlaybackMode.paused);

      await sessionB.joinRoom(sessionA.inviteText!);
      final verified = await _waitFor(
        () => sessionA.peerVerified && sessionB.peerVerified,
        timeout: const Duration(seconds: 20),
      );
      expect(verified, isTrue);

      final guestAtAnchor = await _waitFor(
        () =>
            sessionB.currentItemId == item &&
            sessionB.playback.mode == PlaybackMode.paused &&
            sessionB.player.state.position >=
                startAnchor - const Duration(seconds: 1) &&
            sessionB.player.state.position <=
                startAnchor + const Duration(seconds: 1),
        timeout: const Duration(seconds: 25),
      );
      _dump('GUEST_AT_START_ANCHOR', sessionB);
      expect(
        guestAtAnchor,
        isTrue,
        reason:
            'guest did not open paused at the 10s start anchor '
            '(pos=${sessionB.player.state.position} '
            'playback=${sessionB.playback.position} '
            'mode=${sessionB.playback.mode} err=${sessionB.lastErrorCode})',
      );

      // Seek BEFORE the start anchor (10s -> 2s). Media.start is a
      // playback lower bound on web (onTimeUpdate clamp); on Linux
      // native mpv this must be verified, not assumed.
      const beforeStart = Duration(seconds: 2);
      await sessionA.seek(beforeStart);
      final bothAtTwo = await _waitFor(
        () =>
            sessionA.playback.position == beforeStart &&
            sessionB.playback.position == beforeStart &&
            sessionA.player.state.position >=
                beforeStart - const Duration(milliseconds: 500) &&
            sessionA.player.state.position <=
                beforeStart + const Duration(milliseconds: 800) &&
            sessionB.player.state.position >=
                beforeStart - const Duration(milliseconds: 500) &&
            sessionB.player.state.position <=
                beforeStart + const Duration(milliseconds: 800),
        timeout: const Duration(seconds: 15),
      );
      _dump('SEEK_BEFORE_START_OWNER', sessionA);
      _dump('SEEK_BEFORE_START_GUEST', sessionB);
      debugPrint(
        'SEEK_BEFORE_START ownerPlayer='
        '${sessionA.player.state.position} guestPlayer='
        '${sessionB.player.state.position} ownerPb='
        '${sessionA.playback.position} guestPb=${sessionB.playback.position} '
        'guestErr=${sessionB.lastErrorCode} '
        'guestCompleted=${sessionB.player.state.completed}',
      );
      expect(
        bothAtTwo,
        isTrue,
        reason:
            'seek to 2s before the 10s start anchor did not land '
            '(ownerPlayer=${sessionA.player.state.position} '
            'guestPlayer=${sessionB.player.state.position} '
            'ownerPb=${sessionA.playback.position} '
            'guestPb=${sessionB.playback.position} '
            'guestErr=${sessionB.lastErrorCode} '
            'guestCompleted=${sessionB.player.state.completed})',
      );

      // And playback advances from 2s, not from the anchor.
      await sessionA.play();
      final advancedFromTwo = await _waitFor(
        () =>
            sessionB.playback.mode == PlaybackMode.playing &&
            sessionB.player.state.position >
                beforeStart + const Duration(milliseconds: 300) &&
            sessionB.player.state.position <
                startAnchor - const Duration(seconds: 5),
        timeout: const Duration(seconds: 12),
      );
      _dump('ADVANCE_FROM_TWO_GUEST', sessionB);
      expect(
        advancedFromTwo,
        isTrue,
        reason:
            'guest did not advance from 2s '
            '(pos=${sessionB.player.state.position} '
            'mode=${sessionB.playback.mode} '
            'err=${sessionB.lastErrorCode})',
      );

      await sessionA.closeRoom();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

void _dump(String label, RoomSession session) {
  final player = session.player;
  debugPrint(
    '$label pos=${player.state.position} '
    'dur=${player.state.duration} playing=${player.state.playing} '
    'completed=${player.state.completed} '
    'buffered=${player.state.buffer} '
    'width=${player.state.width} height=${player.state.height} '
    'playback.position=${session.playback.position} '
    'mode=${session.playback.mode} seq=${session.playback.seq} '
    'err=${session.lastErrorCode}',
  );
}

Future<List<int>> _fixtureBytes() async {
  final host = File('/tmp/eir-media-fixture.mp4');
  if (host.existsSync()) return host.readAsBytes();
  final data = await rootBundle.load('assets/eir_media_fixture.mp4');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<HttpServer> _startRangeServer(List<int> bytes) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null && range.startsWith('bytes=')) {
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
      if (match != null) {
        final start = int.parse(match.group(1)!);
        final endStr = match.group(2)!;
        final end = endStr.isEmpty
            ? bytes.length - 1
            : int.parse(endStr).clamp(0, bytes.length - 1);
        final chunk = bytes.sublist(start, end + 1);
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set('content-type', 'video/mp4')
          ..headers.set('accept-ranges', 'bytes')
          ..headers.set('content-range', 'bytes $start-$end/${bytes.length}')
          ..contentLength = chunk.length
          ..add(chunk);
        await request.response.close();
        return;
      }
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.set('content-type', 'video/mp4')
      ..headers.set('accept-ranges', 'bytes')
      ..contentLength = bytes.length
      ..add(bytes);
    await request.response.close();
  });
  return server;
}

Future<bool> _waitFor(
  bool Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  return condition();
}
