import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

/// Real two-client large-file streaming proof.
///
/// Uses a ~65 MiB, 120 s H.264/AAC faststart MP4 (`/tmp/eir-streaming-large.mp4`)
/// registered as P2P local media by the source device. The guest must begin
/// real playback (decoded position advancing) BEFORE the full unique file bytes
/// have crossed the WebRTC DataChannel. With a 65 MiB file no sane player
/// buffers the entire file to play the first seconds, so asserting
/// `position >= 1s` while `sentBytes < fixtureSize` is a genuine
/// first-play-before-full-transfer proof (the 3 MB sample used elsewhere is
/// eagerly prefetched end-to-end and is explicitly NOT such a proof).
///
/// The 65 MiB manifest exceeds the inline envelope, exercising the compact
/// source-signed root + bounded `media_manifest_chunk` transfer; the source's
/// `manifestBytesSent > 0` confirms the body arrived over that chunked path.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('65 MiB local file streams before full transfer (real proof)',
      (tester) async {
    final fixture = File('/tmp/eir-streaming-large.mp4');
    if (!fixture.existsSync()) {
      fail('fixture missing: /tmp/eir-streaming-large.mp4 '
          '(generate a 120s H.264/AAC faststart 640x360 MP4; this test must '
          'not skip)');
    }
    final fixtureSize = await fixture.length();
    // Sanity: the fixture must be large enough that a real player cannot have
    // fully transferred it merely to start playback.
    expect(fixtureSize, greaterThan(32 * 1024 * 1024),
        reason: 'fixture must be larger than the default player buffer');

    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    addTearDown(signaling.stop);
    final signalingUrl = 'ws://127.0.0.1:${signaling.port}';

    final sessionA =
        RoomSession(identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()));
    final sessionB =
        RoomSession(identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()));
    addTearDown(sessionA.dispose);
    addTearDown(sessionB.dispose);

    await sessionA.init();
    await sessionB.init();
    await sessionA.setSignalingUrl(signalingUrl);
    await sessionB.setSignalingUrl(signalingUrl);
    await sessionA.createRoom();
    final invite = sessionA.inviteText;
    expect(invite, isNotNull);
    await sessionB.joinRoom(invite!);
    final verified = await _waitFor(
      () => sessionA.peerVerified && sessionB.peerVerified,
      timeout: const Duration(seconds: 20),
    );
    expect(verified, isTrue, reason: 'DTLS-fingerprint-bound handshake');

    // --- owner registers the 65 MiB local file as shared P2P media ---
    await sessionA.addLocalFile(
      XFile(fixture.path, name: 'eir-streaming-large.mp4'),
      title: 'large clip',
    );
    expect(sessionA.lastErrorCode, isNull,
        reason: 'addLocalFile failed: ${sessionA.lastErrorCode}');
    final added = await _waitFor(
      () => sessionB.playlist.length == 1,
      timeout: const Duration(seconds: 30),
    );
    expect(added, isTrue,
        reason: 'guest did not receive the add_local commit '
            '(lastErrorCode=${sessionB.lastErrorCode})');
    expect(sessionB.playlist.single.sourceType, 'local');
    final mediaId = sessionB.playlist.single.localMediaId;
    expect(mediaId, isNotNull);

    // The 65 MiB manifest exceeds the inline threshold, so it is pulled over
    // the bounded chunked protocol; the source must have sent manifest bytes.
    final manifestChunked = await _waitFor(
      () => (sessionA.debugMediaService?.transferTelemetry.manifestBytesSent ?? 0) > 0,
      timeout: const Duration(seconds: 20),
    );
    expect(manifestChunked, isTrue,
        reason: 'large manifest must travel via bounded chunked transfer');

    // Guest must have the manifest before it can open the media URI.
    final manifestReady = await _waitFor(
      () => sessionB.debugMediaService?.manifestFor(mediaId!) != null,
      timeout: const Duration(seconds: 20),
    );
    expect(manifestReady, isTrue,
        reason: 'guest never received the chunked manifest');

    // --- switch + play; both sides follow the commit ---
    final itemId = sessionA.playlist.single.itemId;
    await sessionA.switchItem(itemId);
    final switched = await _waitFor(
      () => sessionB.currentItemId == itemId,
      timeout: const Duration(seconds: 10),
    );
    expect(switched, isTrue);

    await sessionA.play();
    final playing = await _waitFor(
      () => sessionB.playback.mode == PlaybackMode.playing,
      timeout: const Duration(seconds: 10),
    );
    expect(playing, isTrue);

    // --- THE PROOF: guest is actually decoding and advancing while the full
    /// unique file has NOT yet crossed the DataChannel. Poll for the window
    /// where position >= 1s AND sentBytes < fixtureSize.
    var proofPositionMs = 0;
    var proofSentBytes = 0;
    final proved = await _waitFor(() {
      final pos = sessionB.player.state.position;
      final sent = sessionA.debugMediaService?.transferTelemetry.sentBytes ?? 0;
      proofPositionMs = pos.inMilliseconds;
      proofSentBytes = sent;
      return pos >= const Duration(seconds: 1) && sent < fixtureSize;
    }, timeout: const Duration(seconds: 90));
    expect(proved, isTrue,
        reason: 'guest did not start playback before the full file transferred '
            '(positionMs=$proofPositionMs, sentBytes=$proofSentBytes, '
            'fixtureSize=$fixtureSize)');
    // The transfer was real and net-positive, not a no-op.
    expect(proofSentBytes, greaterThan(0),
        reason: 'no media bytes were actually transferred');

    // --- seek propagates through the commit chain; guest lands there with
    /// real decoded bytes behind it ---
    await sessionA.seek(const Duration(seconds: 12));
    final seeked = await _waitFor(
      () => sessionB.player.state.position >= const Duration(seconds: 10),
      timeout: const Duration(seconds: 30),
    );
    expect(seeked, isTrue,
        reason: 'guest player did not seek near 12s '
            '(position=${sessionB.player.state.position})');

    // --- cache occupancy API is wired and safe-clear is callable ---
    final telemetry = sessionB.cacheTelemetry;
    expect(telemetry, isNotNull);
    expect(telemetry!.maxBytes, greaterThan(0));
    final freed = await sessionB.clearUnprotectedCache();
    expect(freed, isA<int>());

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

Future<bool> _waitFor(
  bool Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return condition();
}
