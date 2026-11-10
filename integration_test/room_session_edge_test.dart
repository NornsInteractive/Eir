import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

/// A13 / A14 edge acceptance with REAL fault injection only:
///  - A13: the source device (owner) is genuinely torn down (`dispose`), which
///    closes the real DataChannel and stops its media service. We do NOT mutate
///    business fields. The surviving peer must keep its room state (DC-close
///    does not reset), keep playing already-cached local media, and surface
///    `source_offline`/`media_probe_failed` or wait when it needs a missing
///    chunk — never fake-play.
///  - A14: the owner/control channel is genuinely down (owner disposed). A
///    member (even admin) must not produce a new shared commit, must not advance
///    natural-end on its own, and a manual `retry()` must end in an explicit
///    bounded outcome with no fabricated authority.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ----------------------------------------------------------------- A13a
  testWidgets('A13 source drop: cached local media keeps playing, room not reset',
      (tester) async {
    final small = File('/tmp/eir-short1.mp4');
    if (!small.existsSync()) {
      fail('fixture /tmp/eir-short1.mp4 missing (ffmpeg fixture)');
    }

    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    addTearDown(signaling.stop);
    final signalingUrl = 'ws://127.0.0.1:${signaling.port}';

    final sessionA = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    final sessionB = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    addTearDown(sessionB.dispose);

    await sessionA.init();
    await sessionB.init();
    await sessionA.setSignalingUrl(signalingUrl);
    await sessionB.setSignalingUrl(signalingUrl);
    await sessionA.createRoom();
    await sessionB.joinRoom(sessionA.inviteText!);
    final verified = await _waitFor(
      () => sessionA.peerVerified && sessionB.peerVerified,
      timeout: const Duration(seconds: 20),
    );
    expect(verified, isTrue);

    // Owner registers a small LOCAL file (P2P source = owner).
    await sessionA.addLocalFile(XFile('/tmp/eir-short1.mp4'), title: 'clip');
    expect(sessionA.lastErrorCode, isNull,
        reason: 'addLocalFile failed: ${sessionA.lastErrorCode}');
    final gotItem = await _waitFor(
      () => sessionB.playlist.length == 1 &&
          sessionB.playlist.single.localMediaId != null,
      timeout: const Duration(seconds: 20),
    );
    expect(gotItem, isTrue, reason: 'guest must receive the local item');
    final itemId = sessionA.playlist.single.itemId;

    await sessionA.switchItem(itemId);
    await sessionA.play();
    // Use the LIVE player clock (not the anchored commit position).
    final playing = await _waitFor(
      () =>
          sessionB.playback.mode == PlaybackMode.playing &&
          sessionB.player.state.position.inMilliseconds > 300,
      timeout: const Duration(seconds: 20),
    );
    expect(playing, isTrue,
        reason: 'guest must be playing from its cache '
            '(mode=${sessionB.playback.mode}, '
            'pos=${sessionB.player.state.position.inMilliseconds}ms, '
            'err=${sessionB.lastErrorCode})');
    expect(sessionB.cacheUsedBytes, greaterThan(0),
        reason: 'guest must have cached chunks before the source leaves');
    final posBefore = sessionB.player.state.position;

    // REAL FAULT: tear down the source device (closes DC + its media service).
    sessionA.dispose();
    final gone = await _waitFor(() => sessionB.peerVerified == false,
        timeout: const Duration(seconds: 15));
    expect(gone, isTrue, reason: 'source loss must be observed');

    // Room state must NOT be reset by a DC close.
    expect(sessionB.playlist.length, 1,
        reason: 'surviving peer must keep its playlist after source drop');
    expect(sessionB.currentItemId, itemId,
        reason: 'current item must be retained after source drop');

    // Cached playback must continue (guest reads its own cache, no relay).
    final advanced = await _waitFor(
      () => sessionB.player.state.position > posBefore,
      timeout: const Duration(seconds: 10),
    );
    expect(advanced, isTrue,
        reason: 'already-cached local media must keep playing after source drop '
            '(posBefore=${posBefore.inMilliseconds}ms, '
            'now=${sessionB.player.state.position.inMilliseconds}ms, '
            'err=${sessionB.lastErrorCode})');
  }, timeout: const Timeout(Duration(minutes: 2)));

  // ----------------------------------------------------------------- A13b
  testWidgets('A13 missing chunk after source drop: source_offline or wait (no fake)',
      (tester) async {
    final large = File('/tmp/eir-streaming-large.mp4');
    if (!large.existsSync()) {
      fail('fixture /tmp/eir-streaming-large.mp4 missing');
    }
    final fileSize = large.lengthSync();

    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    addTearDown(signaling.stop);
    final signalingUrl = 'ws://127.0.0.1:${signaling.port}';

    final sessionA = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    final sessionB = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    addTearDown(sessionB.dispose);

    await sessionA.init();
    await sessionB.init();
    await sessionA.setSignalingUrl(signalingUrl);
    await sessionB.setSignalingUrl(signalingUrl);
    await sessionA.createRoom();
    await sessionB.joinRoom(sessionA.inviteText!);
    await _waitFor(() => sessionA.peerVerified && sessionB.peerVerified,
        timeout: const Duration(seconds: 20));

    await sessionA.addLocalFile(XFile('/tmp/eir-streaming-large.mp4'),
        title: 'big');
    expect(sessionA.lastErrorCode, isNull);
    final gotItem = await _waitFor(
      () => sessionB.playlist.length == 1 &&
          sessionB.playlist.single.localMediaId != null,
      timeout: const Duration(seconds: 30),
    );
    expect(gotItem, isTrue);
    final itemId = sessionA.playlist.single.itemId;
    await sessionA.switchItem(itemId);
    await sessionA.play();
    // Let the guest cache only a small prefix, then cut the source.
    final partial = await _waitFor(
      () =>
          sessionB.player.state.position.inMilliseconds > 500 &&
          sessionB.cacheUsedBytes > 0 &&
          sessionB.cacheUsedBytes < fileSize,
      timeout: const Duration(seconds: 40),
    );
    expect(partial, isTrue,
        reason: 'guest must have a partial cache before the source leaves '
            '(pos=${sessionB.player.state.position.inMilliseconds}ms, '
            'cache=${sessionB.cacheUsedBytes}/$fileSize, '
            'err=${sessionB.lastErrorCode})');

    sessionA.dispose();
    await _waitFor(() => sessionB.peerVerified == false,
        timeout: const Duration(seconds: 15));
    expect(sessionB.playlist.length, 1);
    expect(sessionB.currentItemId, itemId);

    // Once the prefix is exhausted the guest must either surface a real error
    // or stall (wait) — it must NOT fake-play the remaining 65 MiB.
    var lastPos = sessionB.player.state.position;
    var stalledSamples = 0;
    var sawError = false;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final err = sessionB.lastErrorCode;
      if (err == 'source_offline' || err == 'media_probe_failed') {
        sawError = true;
        break;
      }
      final pos = sessionB.player.state.position;
      if (pos <= lastPos) {
        stalledSamples += 1;
        if (stalledSamples >= 4) break; // ~2s without progress => waiting
      } else {
        stalledSamples = 0;
      }
      lastPos = pos;
    }
    expect(sawError || stalledSamples >= 4, isTrue,
        reason: 'after source drop, a missing chunk must yield source_offline/'
            'media_probe_failed or a stall, never fake playback '
            '(err=${sessionB.lastErrorCode}, '
            'pos=${sessionB.player.state.position.inMilliseconds}ms, '
            'stalledSamples=$stalledSamples)');
    expect(sessionB.player.state.position.inMilliseconds, lessThan(60000),
        reason: 'must not appear to play the whole 65 MiB file without the source');
  }, timeout: const Timeout(Duration(minutes: 3)));

  // ----------------------------------------------------------------- A14
  testWidgets('A14 owner/control channel down: member cannot commit or auto-advance',
      (tester) async {
    final s1 = await File('/tmp/eir-mid.mp4').readAsBytes(); // 6s for item1
    final s2 = await File('/tmp/eir-short2.mp4').readAsBytes();
    final mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => mediaServer.close(force: true));
    mediaServer.listen((request) {
      final bytes = request.uri.path.contains('s2') ? s2 : s1;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set('content-type', 'video/mp4')
        ..headers.set('accept-ranges', 'bytes')
        ..contentLength = bytes.length
        ..add(bytes);
      unawaited(request.response.close());
    });
    final s1Url = 'http://127.0.0.1:${mediaServer.port}/s1.mp4';
    final s2Url = 'http://127.0.0.1:${mediaServer.port}/s2.mp4';

    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final port = signaling.port;
    final signalingUrl = 'ws://127.0.0.1:$port';
    addTearDown(signaling.stop);

    final sessionA = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    final sessionB = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    addTearDown(sessionB.dispose);

    await sessionA.init();
    await sessionB.init();
    await sessionA.setSignalingUrl(signalingUrl);
    await sessionB.setSignalingUrl(signalingUrl);
    await sessionA.createRoom();
    await sessionB.joinRoom(sessionA.inviteText!);
    await _waitFor(() => sessionA.peerVerified && sessionB.peerVerified,
        timeout: const Duration(seconds: 20));

    // Member becomes admin so control is blocked by *reachability*, not role.
    await sessionA.grantAdmin(sessionB.identity.deviceId);
    await _waitFor(() => sessionB.role == RoomRole.admin,
        timeout: const Duration(seconds: 10));

    await sessionA.addUrl(s1Url, title: 'one');
    await sessionA.addUrl(s2Url, title: 'two');
    await _waitFor(() => sessionB.playlist.length == 2,
        timeout: const Duration(seconds: 15));
    final item1 = sessionA.playlist.firstWhere((e) => e.title == 'one').itemId;
    await sessionA.switchItem(item1);
    await sessionA.play();
    // Wait until the guest is actually decoding (live player clock), then cut
    // the owner well before the 6 s item ends.
    final playing = await _waitFor(
        () =>
            sessionB.currentItemId == item1 &&
            sessionB.player.state.position.inMilliseconds > 50,
        timeout: const Duration(seconds: 15));
    expect(playing, isTrue,
        reason: 'guest must be playing item1 before the owner leaves '
            '(current=${sessionB.currentItemId}, '
            'pos=${sessionB.player.state.position.inMilliseconds}ms)');
    final seq0 = sessionB.playback.seq;

    // REAL FAULT: owner/control channel goes down (owner disposed).
    sessionA.dispose();
    final down = await _waitFor(() => sessionB.peerVerified == false,
        timeout: const Duration(seconds: 15));
    expect(down, isTrue, reason: 'control channel down must be observed');
    expect(sessionB.playlist.length, 2,
        reason: 'member keeps room state but has no authority');

    // Member (admin) attempts a control action: no new shared commit.
    await sessionB.seek(const Duration(seconds: 1));
    await _waitFor(() => sessionB.lastErrorCode != null,
        timeout: const Duration(seconds: 10));
    expect(sessionB.playback.seq, seq0,
        reason: 'member must not produce a new shared commit when owner is down');
    expect(sessionB.playlist.length, 2,
        reason: 'member must not fabricate playlist state');
    expect(sessionB.lastErrorCode, isNotNull,
        reason: 'failure must be explicit, not silent');

    // Natural end must NOT be advanced by the member: let item1 (6 s) finish;
    // the member's own completion callback is owner-gated.
    final finished = await _waitFor(
      () =>
          sessionB.player.state.completed ||
          sessionB.player.state.position >= const Duration(seconds: 5),
      timeout: const Duration(seconds: 20),
    );
    expect(finished, isTrue, reason: 'guest player should reach item1 end');
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(sessionB.currentItemId, item1,
        reason: 'member must not auto-advance natural end to the next item '
            '(current=${sessionB.currentItemId})');

    // Recovery: restart signalling on the SAME url; manual retry must end in an
    // explicit bounded outcome with no fabricated authority.
    await signaling.stop(graceful: false);
    final signaling2 = await _startSamePort(port);
    addTearDown(signaling2.stop);
    await sessionB.retry();
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(sessionB.peerVerified, isFalse,
        reason: 'retry must not fabricate a verified peer without the owner');
    expect(sessionB.playback.seq, seq0,
        reason: 'retry must not fabricate shared commits');
    expect(
        sessionB.lastErrorCode,
        anyOf('room_not_found', 'signaling_unavailable', 'invalid_invite'),
        reason: 'retry after the owner is gone must fail in a bounded, explicit '
            'way (lastErrorCode=${sessionB.lastErrorCode})');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<SignalingServer> _startSamePort(int port) async {
  Object? last;
  for (var i = 0; i < 40; i++) {
    final server = SignalingServer();
    try {
      await server.start(address: InternetAddress.loopbackIPv4, port: port);
      return server;
    } catch (e) {
      last = e;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  throw StateError('could not rebind signaling port $port: $last');
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
