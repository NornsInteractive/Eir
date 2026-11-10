import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

// Real two-client RoomSession paused-start verification (Linux harness:
// real Player, real WebRTC DataChannel, real loopback signaling/media).
// Validates the "new media _ensure with Media.copyWith(start: seekTo) +
// snapshot _expectedPositionNow" fix through public API only:
//   owner seeks to a mid-point and pauses BEFORE the guest joins ->
//   guest's first open must land at that mid-point (not 0, not EOF),
//   stay paused, then resume-advancing from the mid-point.
// Uses eir_media_fixture.mp4 (20s). Mid-point is 10s (suitable for fixture;
// the duplex 600s film's 173s case maps to the same code path).

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('paused snapshot mid-point start is kept then resumes',
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
        identityStore:
            DeviceIdentityStore(store: InMemorySecureKeyValueStore()));
    final sessionB = RoomSession(
        identityStore:
            DeviceIdentityStore(store: InMemorySecureKeyValueStore()));
    addTearDown(sessionA.dispose);
    addTearDown(sessionB.dispose);

    await sessionA.init();
    await sessionB.init();
    await sessionA.setSignalingUrl(signalingUrl);
    await sessionB.setSignalingUrl(signalingUrl);
    await sessionA.createRoom();

    // Owner loads + plays to a real position first (proves playability).
    await sessionA.addUrl(url, title: 'fix');
    expect(sessionA.lastErrorCode, isNull,
        reason: 'addUrl failed: ${sessionA.lastErrorCode}');
    final item = sessionA.playlist.single.itemId;
    await sessionA.switchItem(item);
    await sessionA.play();
    final playing = await _waitFor(
      () => sessionA.player.state.position >= const Duration(seconds: 2),
      timeout: const Duration(seconds: 20),
    );
    expect(playing, isTrue,
        reason: 'owner never advanced past 2s '
            '(pos=${sessionA.player.state.position} '
            'err=${sessionA.lastErrorCode})');

    // Owner seeks to mid-point 10s and pauses BEFORE any guest joins.
    const target = Duration(seconds: 10);
    await sessionA.seek(target);
    final landed = await _waitFor(
      () => (sessionA.player.state.position - target).abs() <
          const Duration(milliseconds: 800),
      timeout: const Duration(seconds: 10),
    );
    expect(landed, isTrue,
        reason: 'owner seek to 10s did not land '
            '(pos=${sessionA.player.state.position} err=${sessionA.lastErrorCode})');
    await sessionA.pause();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(sessionA.playback.mode, PlaybackMode.paused);
    final ownerPausedPos = sessionA.player.state.position;
    // debugPrint for forensics.
    debugPrint('OWNER_PAUSED pos=$ownerPausedPos mode=${sessionA.playback.mode}');

    // Guest joins late: snapshot carries paused mid-point. First open must
    // honour the non-zero start.
    await sessionB.joinRoom(sessionA.inviteText!);
    final verified = await _waitFor(
      () => sessionA.peerVerified && sessionB.peerVerified,
      timeout: const Duration(seconds: 20),
    );
    expect(verified, isTrue);

    final guestPausedAtMid = await _waitFor(
      () =>
          sessionB.currentItemId == item &&
          sessionB.playback.mode == PlaybackMode.paused &&
          sessionB.player.state.position >= const Duration(seconds: 9) &&
          sessionB.player.state.position <= const Duration(seconds: 11) &&
          sessionB.player.state.position >
              const Duration(seconds: 5) &&
          sessionB.player.state.position <
              const Duration(seconds: 15),
      timeout: const Duration(seconds: 25),
    );
    debugPrint('GUEST_START pos=${sessionB.player.state.position} '
        'mode=${sessionB.playback.mode} playbackPos=${sessionB.playback.position} '
        'err=${sessionB.lastErrorCode} dur=${sessionB.player.state.duration}');
    expect(guestPausedAtMid, isTrue,
        reason: 'guest did not open paused at mid-point '
            '(pos=${sessionB.player.state.position} '
            'playback=${sessionB.playback.position} '
            'mode=${sessionB.playback.mode} err=${sessionB.lastErrorCode})');

    // Stays paused: no drift back to 0 within a hold window.
    final guestBeforeHold = sessionB.player.state.position;
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final guestAfterHold = sessionB.player.state.position;
    debugPrint('GUEST_HOLD before=$guestBeforeHold after=$guestAfterHold');
    expect((guestAfterHold - guestBeforeHold).abs(),
        lessThan(const Duration(milliseconds: 400)),
        reason: 'paused guest drifted (before=$guestBeforeHold after=$guestAfterHold)');
    expect(guestAfterHold, greaterThan(const Duration(seconds: 8)),
        reason: 'paused guest fell back to 0 (pos=$guestAfterHold)');

    // Owner resumes: guest must advance FROM the mid-point, not restart at 0.
    await sessionA.play();
    final resumedFromMid = await _waitFor(
      () =>
          sessionB.playback.mode == PlaybackMode.playing &&
          sessionB.player.state.position >
              const Duration(seconds: 10) + const Duration(milliseconds: 300) &&
          sessionB.player.state.position <
              const Duration(seconds: 15),
      timeout: const Duration(seconds: 15),
    );
    debugPrint('GUEST_RESUME pos=${sessionB.player.state.position} '
        'mode=${sessionB.playback.mode} playback=${sessionB.playback.position}');
    expect(resumedFromMid, isTrue,
        reason: 'guest did not advance from mid-point after resume '
            '(pos=${sessionB.player.state.position} mode=${sessionB.playback.mode})');
    expect(sessionB.player.state.position,
        greaterThan(const Duration(seconds: 9)),
        reason: 'resume restarted at 0 instead of mid-point');

    await sessionA.closeRoom();
    final closed = await _waitFor(
      () =>
          sessionA.connectionState == RoomConnectionState.disconnected &&
          sessionB.connectionState == RoomConnectionState.disconnected,
      timeout: const Duration(seconds: 10),
    );
    expect(closed, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
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
          ..headers.set('content-range',
              'bytes $start-$end/${bytes.length}')
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
