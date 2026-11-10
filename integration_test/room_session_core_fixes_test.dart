import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ----------------------------------------------------------------- F1
  testWidgets('F1 async player error is surfaced and cleared on item switch',
      (tester) async {
    final sampleBytesData = await rootBundle.load('assets/sample.mp4');
    final sampleBytes = sampleBytesData.buffer.asUint8List();
    // A corrupt "video/mp4" that the probe (forced success) lets through but
    // the decoder cannot play -> drives the async player error stream.
    final corrupt = List<int>.generate(8192, (i) => (i * 7 + 3) & 0xFF);

    final mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) {
      final path = request.uri.path;
      if (path == '/corrupt.mp4') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set('content-type', 'video/mp4')
          ..contentLength = corrupt.length
          ..add(corrupt);
        unawaited(request.response.close());
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set('content-type', 'video/mp4')
        ..headers.set('accept-ranges', 'bytes')
        ..contentLength = sampleBytes.length
        ..add(sampleBytes);
      unawaited(request.response.close());
    });
    final goodUrl = 'http://127.0.0.1:${mediaServer.port}/sample.mp4';
    final badUrl = 'http://127.0.0.1:${mediaServer.port}/corrupt.mp4';

    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final signalingUrl = 'ws://127.0.0.1:${signaling.port}';

    // urlProbe override returns null (probe "succeeds") so the corrupt URL is
    // accepted into the playlist and reaches the real player, exercising the
    // async error path rather than the probe path.
    final sessionA = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
      urlProbe: (_) => null,
    );
    final sessionB = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    addTearDown(sessionA.dispose);
    addTearDown(sessionB.dispose);
    addTearDown(() async => mediaServer.close(force: true));
    addTearDown(signaling.stop);

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

    // Regression: a valid URL still plays.
    await sessionA.addUrl(goodUrl, title: 'good');
    await _waitFor(() => sessionB.playlist.length == 1,
        timeout: const Duration(seconds: 10));
    final goodItem = sessionA.playlist.single.itemId;
    await sessionA.switchItem(goodItem);
    await _waitFor(() => sessionA.playback.itemId == goodItem,
        timeout: const Duration(seconds: 10));
    expect(sessionA.lastErrorCode, isNull);

    // F1: corrupt media triggers the async player error, mapped to an existing
    // localized code.
    await sessionA.addUrl(badUrl, title: 'bad');
    await _waitFor(() => sessionA.playlist.length == 2,
        timeout: const Duration(seconds: 10));
    final badItem = sessionA.playlist
        .firstWhere((e) => e.title == 'bad')
        .itemId;
    await sessionA.switchItem(badItem);
    final errored = await _waitFor(
      () => sessionA.lastErrorCode == 'media_probe_failed',
      timeout: const Duration(seconds: 20),
    );
    expect(errored, isTrue,
        reason: 'async player error must surface as media_probe_failed '
            '(lastErrorCode=${sessionA.lastErrorCode})');

    // Switching back to a playable item clears the stale error (no pollution).
    await sessionA.switchItem(goodItem);
    final cleared = await _waitFor(
      () => sessionA.lastErrorCode == null,
      timeout: const Duration(seconds: 15),
    );
    expect(cleared, isTrue,
        reason: 'error must clear on successful load of a valid item');
  }, timeout: const Timeout(Duration(minutes: 2)));

  // ----------------------------------------------------------------- F3
  testWidgets('F3 invite epoch rotates on signaling restart, old invite invalid',
      (tester) async {
    final sampleBytesData = await rootBundle.load('assets/sample.mp4');
    final sampleBytes = sampleBytesData.buffer.asUint8List();
    final mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => mediaServer.close(force: true));
    mediaServer.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set('content-type', 'video/mp4')
        ..contentLength = sampleBytes.length
        ..add(sampleBytes);
      unawaited(request.response.close());
    });
    final mediaUrl = 'http://127.0.0.1:${mediaServer.port}/sample.mp4';

    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final port = signaling.port;
    final signalingUrl = 'ws://127.0.0.1:$port';

    final sessionA = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    final sessionB = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    addTearDown(sessionA.dispose);
    addTearDown(sessionB.dispose);
    addTearDown(signaling.stop);

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

    final oldInvite = sessionA.inviteText!;
    final dcSurvivedBefore = sessionA.peerVerified;

    // A15: the SAME signaling endpoint goes down and comes back. We drop peer
    // sockets WITHOUT a `disbanded` frame (abrupt crash/restart) and rebind the
    // SAME port; existing sessions keep their URL, room and identity, and must
    // auto-recover on their own. No setSignalingUrl / no new room.
    await signaling.stop(graceful: false);
    final signaling2 = await _startSamePort(port);
    addTearDown(signaling2.stop);

    // Owner auto-reconnects to the SAME url and recreates the room with a
    // rotated epoch.
    final reconnected = await _waitFor(
      () => sessionA.connectionState == RoomConnectionState.connected,
      timeout: const Duration(seconds: 30),
    );
    expect(reconnected, isTrue,
        reason: 'owner must recreate the room after same-URL restart');
    final rotated = await _waitFor(
      () => sessionA.inviteText != null && sessionA.inviteText != oldInvite,
      timeout: const Duration(seconds: 15),
    );
    expect(rotated, isTrue,
        reason: 'invite epoch must rotate so old invites are invalidated');
    // Data channel must survive the signaling drop (F3: do not break DC).
    expect(sessionA.peerVerified, isTrue);
    expect(dcSurvivedBefore, isTrue);

    // A third party using the OLD invite must be rejected now.
    final sessionC = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    addTearDown(sessionC.dispose);
    await sessionC.init();
    await sessionC.setSignalingUrl(signalingUrl);
    await sessionC.joinRoom(oldInvite);
    final rejected = await _waitFor(
      () => sessionC.lastErrorCode != null,
      timeout: const Duration(seconds: 15),
    );
    expect(rejected, isTrue,
        reason: 'old invite must be rejected after epoch rotation '
            '(lastErrorCode=${sessionC.lastErrorCode})');
    expect(sessionC.lastErrorCode, anyOf('invalid_invite', 'invite_consumed'));

    // The NEW invite still works for a fresh join at the signaling level.
    await sessionC.joinRoom(sessionA.inviteText!);
    final joinedNew = await _waitFor(
      () => sessionC.connectionState == RoomConnectionState.connected,
      timeout: const Duration(seconds: 15),
    );
    expect(joinedNew, isTrue,
        reason: 'newly issued invite must still allow joining');
    // The owner's room/identity survived the restart (no reset).
    expect(sessionA.role, RoomRole.owner);
    expect(sessionA.inviteText, isNotNull);
    // mediaUrl is still usable by the owner (media plane unaffected).
    await sessionA.addUrl(mediaUrl, title: 'clip');
    final added = await _waitFor(() => sessionA.playlist.length == 1,
        timeout: const Duration(seconds: 10));
    expect(added, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  // ----------------------------------------------------------------- F4
  testWidgets('F4 manual retry() recovers connectivity and preserves DC',
      (tester) async {
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final port = signaling.port;
    final signalingUrl = 'ws://127.0.0.1:$port';

    final sessionA = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    final sessionB = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    addTearDown(sessionA.dispose);
    addTearDown(sessionB.dispose);
    addTearDown(signaling.stop);

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

    // A16: kill the SAME endpoint abruptly (no disband) then bring it back on
    // the SAME URL. The session keeps its URL/room/identity; retry() must
    // recover without any address change.
    await signaling.stop(graceful: false);
    final dropped = await _waitFor(
      () => sessionA.connectionState == RoomConnectionState.reconnecting ||
          sessionA.connectionState == RoomConnectionState.disconnected,
      timeout: const Duration(seconds: 10),
    );
    expect(dropped, isTrue, reason: 'must detect signaling loss');

    final signaling2 = await _startSamePort(port);
    addTearDown(signaling2.stop);

    await sessionA.retry();
    final recovered = await _waitFor(
      () => sessionA.connectionState == RoomConnectionState.connected,
      timeout: const Duration(seconds: 30),
    );
    expect(recovered, isTrue, reason: 'retry() must re-establish connection');
    expect(sessionA.peerVerified, isTrue,
        reason: 'retry() must preserve the data channel');
    expect(sessionA.lastErrorCode, isNull,
        reason: 'retry() must not leave a spurious error');

    // Manual retry while already connected is a harmless no-op.
    await sessionA.retry();
    expect(sessionA.connectionState, RoomConnectionState.connected);
  }, timeout: const Timeout(Duration(minutes: 2)));

  // ------------------------------------ natural end / late join / replace
  testWidgets('late join, replace current, and natural-end auto-advance',
      (tester) async {
    final s1 = await _readFixtureBytes('/tmp/eir-short1.mp4', 'assets/eir_short1.mp4');
    final s2 = await _readFixtureBytes('/tmp/eir-short2.mp4', 'assets/eir_short2.mp4');
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
    addTearDown(signaling.stop);
    final signalingUrl = 'ws://127.0.0.1:${signaling.port}';

    final sessionA = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    final sessionB = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    addTearDown(sessionA.dispose);
    addTearDown(sessionB.dispose);

    await sessionA.init();
    await sessionB.init();
    await sessionA.setSignalingUrl(signalingUrl);
    await sessionB.setSignalingUrl(signalingUrl);

    await sessionA.createRoom();
    // Owner adds an item BEFORE the member joins.
    await sessionA.addUrl(s1Url, title: 'one');
    await _waitFor(() => sessionA.playlist.length == 1,
        timeout: const Duration(seconds: 10));

    // --- LATE JOIN: member joins after the playlist already exists and must
    // receive it via the post-handshake snapshot/resync.
    await sessionB.joinRoom(sessionA.inviteText!);
    final verified = await _waitFor(
      () => sessionA.peerVerified && sessionB.peerVerified,
      timeout: const Duration(seconds: 20),
    );
    expect(verified, isTrue);
    final lateJoin = await _waitFor(() => sessionB.playlist.length == 1,
        timeout: const Duration(seconds: 15));
    expect(lateJoin, isTrue,
        reason: 'late joiner must receive the existing playlist '
            '(B.playlist=${sessionB.playlist.length})');
    expect(sessionB.playlist.single.url, s1Url);

    // --- REPLACE CURRENT: replace the current item's URL; both sides follow.
    final item1 = sessionA.playlist.single.itemId;
    await sessionA.switchItem(item1);
    await _waitFor(() => sessionB.currentItemId == item1,
        timeout: const Duration(seconds: 10));
    await sessionA.replaceItem(item1, url: s2Url);
    final replaced = await _waitFor(
      () =>
          sessionA.playlist.single.url == s2Url &&
          sessionB.playlist.single.url == s2Url,
      timeout: const Duration(seconds: 15),
    );
    expect(replaced, isTrue,
        reason: 'replace of the current item must propagate to both peers');

    // --- NATURAL END: a second item exists; playing item1 (≈1.6 s) to its end
    // must auto-advance the owner to item2 and the member must follow.
    await sessionA.addUrl(s1Url, title: 'two');
    await _waitFor(() => sessionB.playlist.length == 2,
        timeout: const Duration(seconds: 15));
    final item2 = sessionA.playlist.firstWhere((e) => e.title == 'two').itemId;
    await sessionA.switchItem(item1);
    await _waitFor(() => sessionA.playback.itemId == item1,
        timeout: const Duration(seconds: 10));
    await sessionA.play();
    final advanced = await _waitFor(
      () => sessionA.currentItemId == item2,
      timeout: const Duration(seconds: 20),
    );
    expect(advanced, isTrue,
        reason: 'natural end must auto-advance to the next playlist item '
            '(current=${sessionA.currentItemId})');
    final guestFollowed = await _waitFor(
      () => sessionB.currentItemId == item2,
      timeout: const Duration(seconds: 15),
    );
    expect(guestFollowed, isTrue,
        reason: 'member must follow the natural-end auto-advance');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Starts a fresh [SignalingServer] on the SAME [port], retrying briefly to
/// absorb the transient TIME_WAIT / rebind contention that a real same-URL
/// restart can hit. This is test-fixture plumbing, not a product change.
Future<SignalingServer> _startSamePort(int port) async {
  Object? last;
  for (var i = 0; i < 40; i++) {
    final server = SignalingServer();
    try {
      await server.start(
          address: InternetAddress.loopbackIPv4, port: port);
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

/// Read a small MP4 fixture. Desktop uses the host file under /tmp; mobile
/// platforms (no /tmp) materialize the bundled asset instead. Test-only.
Future<List<int>> _readFixtureBytes(String hostPath, String assetKey) async {
  final host = File(hostPath);
  if (host.existsSync()) return host.readAsBytes();
  final data = await rootBundle.load(assetKey);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
