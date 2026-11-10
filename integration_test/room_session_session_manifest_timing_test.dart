import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

// Real two-client RoomSession timing tests (Linux harness: real Player,
// real WebRTC DataChannel, real loopback signaling/media servers).
// No product test hooks, no forged business state, no source-text checks.
//
// Coverage map (see regression report for honest limits):
// - F2 snapshot vs commit: late-join snapshot first, then live commits
//   must apply on top of the snapshot state (not be rolled back).
//   Stale-snapshot replay (seq < lastSeq) cannot be injected through the
//   public API (snapshots are owner-signed and only sent on resync), so
//   that sub-case is NOT proven here.
// - F3 leave/rejoin old-await: an in-flight slow load from the old room
//   must not overwrite the new room's product state after leave+recreate.
//   The generation gate protects product state; mpv backend cancellation
//   of the old open is not observable via the public API and is not
//   claimed.
// - F5 large manifest late autoplay: owner adds a >16000-byte-manifest
//   local file and switches+plays before the chunked manifest round-trip
//   completes; the guest must load and play without a second switch/play
//   (playing-branch loadedItemId gate: play before load is a no-op).

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('F2 late-join snapshot then live commits apply on top',
      (tester) async {
    final fixtureBytes = await _fixtureBytes();
    final mediaServer = await _startRangeServer(fixtureBytes);
    addTearDown(() => mediaServer.close(force: true));
    final urlA = 'http://127.0.0.1:${mediaServer.port}/a.mp4';
    final urlB = 'http://127.0.0.1:${mediaServer.port}/b.mp4';

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

    // Owner adds + switches BEFORE the guest joins: the guest can only
    // learn about item A through the post-handshake snapshot.
    await sessionA.addUrl(urlA, title: 'A');
    expect(sessionA.playlist, hasLength(1));
    final itemA = sessionA.playlist.single.itemId;
    await sessionA.switchItem(itemA);

    await sessionB.joinRoom(sessionA.inviteText!);
    final verified = await _waitFor(
      () => sessionA.peerVerified && sessionB.peerVerified,
      timeout: const Duration(seconds: 20),
    );
    expect(verified, isTrue);
    final snapshotted = await _waitFor(
      () => sessionB.playlist.length == 1 && sessionB.currentItemId == itemA,
      timeout: const Duration(seconds: 15),
    );
    expect(snapshotted, isTrue,
        reason: 'late joiner did not receive snapshot state '
            '(playlist=${sessionB.playlist.length}, '
            'current=${sessionB.currentItemId}, err=${sessionB.lastErrorCode})');
    // Snapshot playlist/current are set before the snapshot's media load
    // finishes, and that load still holds the unified apply queue. Wait
    // for the guest's player to actually have A loaded (duration known)
    // so the live commits below are not queued behind a slow open.
    final snapshotLoaded = await _waitFor(
      () => sessionB.player.state.duration > Duration.zero,
      timeout: const Duration(seconds: 30),
    );
    expect(snapshotLoaded, isTrue,
        reason: 'guest did not load snapshot item A '
            '(duration=${sessionB.player.state.duration}, '
            'err=${sessionB.lastErrorCode})');

    // Live commits after the snapshot must advance the guest past the
    // snapshot seq: add B, switch to B, play.
    await sessionA.addUrl(urlB, title: 'B');
    final itemB = sessionA.playlist
        .firstWhere((e) => e.title == 'B')
        .itemId;
    await sessionA.switchItem(itemB);
    await sessionA.play();

    final advanced = await _waitFor(
      () =>
          sessionB.playlist.length == 2 &&
          sessionB.currentItemId == itemB &&
          sessionB.playback.mode == PlaybackMode.playing,
      timeout: const Duration(seconds: 30),
    );
    expect(advanced, isTrue,
        reason: 'commits after snapshot did not apply on guest '
            '(playlist=${sessionB.playlist.length}, '
            'current=${sessionB.currentItemId}, '
            'mode=${sessionB.playback.mode}, err=${sessionB.lastErrorCode})');
    expect(sessionB.playlist.map((e) => e.title), ['A', 'B']);

    // Real decode on the guest, not just commit flags.
    final decoding = await _waitFor(
      () => sessionB.player.state.position >= const Duration(milliseconds: 300),
      timeout: const Duration(seconds: 30),
    );
    expect(decoding, isTrue,
        reason: 'guest player did not decode B '
            '(position=${sessionB.player.state.position})');

    await sessionA.closeRoom();
    final closed = await _waitFor(
      () =>
          sessionA.connectionState == RoomConnectionState.disconnected &&
          sessionB.connectionState == RoomConnectionState.disconnected,
      timeout: const Duration(seconds: 10),
    );
    expect(closed, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('F3 leave+recreate: in-flight slow load cannot pollute new room',
      (tester) async {
    final fixtureBytes = await _fixtureBytes();
    // Slow path delays every response by 5s so player.open stays in flight
    // across leave/recreate. urlProbe override (existing public API) keeps
    // addUrl from spending the same delay in the probe phase.
    final mediaServer = await _startRangeServer(
      fixtureBytes,
      slowPath: '/slow.mp4',
      slowDelay: const Duration(seconds: 5),
    );
    addTearDown(() => mediaServer.close(force: true));
    final slowUrl = 'http://127.0.0.1:${mediaServer.port}/slow.mp4';
    final fastUrl = 'http://127.0.0.1:${mediaServer.port}/fast.mp4';

    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    addTearDown(signaling.stop);
    final signalingUrl = 'ws://127.0.0.1:${signaling.port}';

    final session = RoomSession(
      identityStore:
          DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
      urlProbe: (_) => null,
    );
    addTearDown(session.dispose);

    await session.init();
    await session.setSignalingUrl(signalingUrl);
    await session.createRoom();
    final oldRoomId = session.roomId;
    expect(oldRoomId, isNotNull);

    await session.addUrl(slowUrl, title: 'slow');
    expect(session.playlist, hasLength(1));
    final slowItem = session.playlist.single.itemId;

    // Fire the slow switch without awaiting it: its player.open is now
    // in flight against the 5s-delayed server.
    final slowSwitch = session.switchItem(slowItem);
    addTearDown(() async {
      try {
        await slowSwitch;
      } catch (_) {}
    });
    // Give the apply queue a moment to enter the slow open, then leave.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await session.leaveRoom();
    expect(session.roomId, isNull);
    expect(session.connectionState, RoomConnectionState.disconnected);

    // New room on the same session object: fresh generation/playlist.
    await session.createRoom();
    expect(session.roomId, isNotNull);
    expect(session.roomId, isNot(oldRoomId));
    await session.addUrl(fastUrl, title: 'fast');
    expect(session.playlist, hasLength(1));
    final fastItem = session.playlist.single.itemId;
    await session.switchItem(fastItem);
    await session.play();
    final fastPlaying = await _waitFor(
      () =>
          session.currentItemId == fastItem &&
          session.playback.mode == PlaybackMode.playing &&
          session.player.state.position >=
              const Duration(milliseconds: 300),
      timeout: const Duration(seconds: 20),
    );
    expect(fastPlaying, isTrue,
        reason: 'new room did not load/play fast item '
            '(current=${session.currentItemId}, mode=${session.playback.mode}, '
            'position=${session.player.state.position}, '
            'err=${session.lastErrorCode})');

    // Let the old slow open settle (5s server delay + margin). Its
    // completion must not overwrite the new room's product state.
    await Future<void>.delayed(const Duration(seconds: 7));
    expect(session.playlist, hasLength(1));
    expect(session.playlist.single.itemId, fastItem);
    expect(session.playlist.single.url, fastUrl);
    expect(session.currentItemId, fastItem);
    expect(session.playback.itemId, fastItem);
    expect(session.playback.mode, PlaybackMode.playing);

    await session.closeRoom();
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('F5 large manifest late arrival autoplays current playing item',
      (tester) async {
    final fixture = File('/tmp/eir-streaming-large.mp4');
    if (!fixture.existsSync()) {
      fail('fixture missing: /tmp/eir-streaming-large.mp4 '
          '(this test must not skip)');
    }
    final fixtureSize = await fixture.length();
    expect(fixtureSize, greaterThan(32 * 1024 * 1024));

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
    await sessionB.joinRoom(sessionA.inviteText!);
    final verified = await _waitFor(
      () => sessionA.peerVerified && sessionB.peerVerified,
      timeout: const Duration(seconds: 20),
    );
    expect(verified, isTrue);

    // Owner registers the large file. Its manifest must exceed the 16000
    // snapshot inline threshold (40 MiB can still be inline in a snapshot),
    // so the body travels over the chunked manifest protocol.
    await sessionA.addLocalFile(
      XFile(fixture.path, name: 'eir-streaming-large.mp4'),
      title: 'large clip',
    );
    expect(sessionA.lastErrorCode, isNull,
        reason: 'addLocalFile failed: ${sessionA.lastErrorCode}');
    expect(sessionA.playlist, hasLength(1));
    final mediaId = sessionA.playlist.single.localMediaId;
    expect(mediaId, isNotNull);
    final ownerManifest =
        sessionA.debugMediaService?.manifestFor(mediaId!);
    expect(ownerManifest, isNotNull);
    final manifestBytes =
        utf8.encode(jsonEncode(ownerManifest!.toJson())).length;
    expect(manifestBytes, greaterThan(16000),
        reason: 'fixture manifestJSON $manifestBytes must exceed the '
            '16000 snapshot inline threshold');
    final itemId = sessionA.playlist.single.itemId;

    // Switch + play immediately, before the guest's chunked-manifest
    // round-trip (guest request -> owner chunks -> guest install) can
    // complete. DataChannel owner->guest order is add, switch, play, so
    // the guest processes switch/play while the manifest is still missing:
    // load fails source-offline and the playing gate is a no-op. The late
    // manifest must then trigger load+play with no further owner command.
    await sessionA.switchItem(itemId);
    await sessionA.play();

    final chunked = await _waitFor(
      () =>
          (sessionA.debugMediaService?.transferTelemetry.manifestBytesSent ??
                  0) >
          0,
      timeout: const Duration(seconds: 20),
    );
    expect(chunked, isTrue,
        reason: 'large manifest did not travel via chunked transfer');

    final guestManifest = await _waitFor(
      () => sessionB.debugMediaService?.manifestFor(mediaId!) != null,
      timeout: const Duration(seconds: 20),
    );
    expect(guestManifest, isTrue,
        reason: 'guest never installed the chunked manifest '
            '(err=${sessionB.lastErrorCode})');

    // No second switch/play is sent. The guest must reach playing and
    // actually decode (position advancing) from the late manifest alone.
    final autoplaying = await _waitFor(
      () =>
          sessionB.currentItemId == itemId &&
          sessionB.playback.mode == PlaybackMode.playing &&
          sessionB.player.state.position >= const Duration(seconds: 1),
      timeout: const Duration(seconds: 60),
    );
    expect(autoplaying, isTrue,
        reason: 'guest did not autoplay after late manifest '
            '(current=${sessionB.currentItemId}, '
            'mode=${sessionB.playback.mode}, '
            'position=${sessionB.player.state.position}, '
            'err=${sessionB.lastErrorCode})');

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

Future<HttpServer> _startRangeServer(
  List<int> bytes, {
  String? slowPath,
  Duration slowDelay = Duration.zero,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (slowPath != null && request.uri.path == slowPath) {
      await Future<void>.delayed(slowDelay);
    }
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
