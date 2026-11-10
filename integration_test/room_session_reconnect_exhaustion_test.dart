import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

/// W3 / A16 regression: the bounded automatic reconnect must END in a real
/// terminal state instead of looping or staying `reconnecting` forever.
///
/// Contract under test:
///  - same-URL abrupt signaling loss (no `disbanded`) -> at most 3 auto
///    attempts (1.1 s / 2.1 s / 4.2 s);
///  - exhaustion -> `connectionState == disconnected`,
///    `lastErrorCode == 'signaling_unavailable'`, no further automatic
///    attempts (a restarted server must NOT silently auto-recover);
///  - room / identity / playlist / playback / surviving data channel are kept;
///  - explicit `retry()` on the SAME URL recovers for real (no address
///    change, no room rebuild, invite epoch rotated).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'A16 auto-retry exhaustion is terminal; manual retry recovers same URL',
      (tester) async {
    final clip = await _resolveLongClip();
    final clipBytes = await clip.readAsBytes();

    final mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => mediaServer.close(force: true));
    mediaServer.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set('content-type', 'video/mp4')
        ..headers.set('accept-ranges', 'bytes')
        ..contentLength = clipBytes.length
        ..add(clipBytes);
      unawaited(request.response.close());
    });
    final mediaUrl = 'http://127.0.0.1:${mediaServer.port}/clip.mp4';

    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final port = signaling.port;
    final signalingUrl = 'ws://127.0.0.1:$port';
    addTearDown(signaling.stop);

    final owner = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    final guest = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
    );
    addTearDown(owner.dispose);
    addTearDown(guest.dispose);

    await owner.init();
    await guest.init();
    await owner.setSignalingUrl(signalingUrl);
    await guest.setSignalingUrl(signalingUrl);
    await owner.createRoom();
    await guest.joinRoom(owner.inviteText!);
    expect(
      await _waitFor(
          () => owner.peerVerified && guest.peerVerified,
          const Duration(seconds: 20)),
      isTrue,
      reason: 'both peers must complete the DTLS-bound handshake',
    );

    final roomId = owner.roomId;
    final deviceId = owner.identity.deviceId;
    final oldInvite = owner.inviteText;

    await owner.addUrl(mediaUrl, title: 'clip');
    expect(owner.lastErrorCode, isNull,
        reason: 'addUrl failed: ${owner.lastErrorCode}');
    expect(
      await _waitFor(
          () => guest.playlist.length == 1,
          const Duration(seconds: 15)),
      isTrue,
    );
    final itemId = owner.playlist.single.itemId;
    await owner.switchItem(itemId);
    await owner.play();
    expect(
      await _waitFor(
          () => guest.player.state.position.inMilliseconds > 200,
          const Duration(seconds: 30)),
      isTrue,
      reason: 'guest must be decoding before the signaling cut '
          '(mode=${guest.playback.mode}, cur=${guest.currentItemId}, '
          'pos=${guest.player.state.position.inMilliseconds}ms, '
          'err=${guest.lastErrorCode}, '
          'ownerPos=${owner.player.state.position.inMilliseconds}ms, '
          'ownerErr=${owner.lastErrorCode})',
    );
    final seqBefore = owner.playback.seq;

    // REAL FAULT: kill the SAME endpoint abruptly (no `disbanded` frame).
    await signaling.stop(graceful: false);

    // Bounded auto-retry (1.1 + 2.1 + 4.2 s) must terminate.
    final exhausted = await _waitFor(
      () =>
          owner.connectionState == RoomConnectionState.disconnected &&
          guest.connectionState == RoomConnectionState.disconnected,
      const Duration(seconds: 40),
    );
    expect(exhausted, isTrue,
        reason: 'bounded auto-retry must end in disconnected '
            '(owner=${owner.connectionState}/${owner.lastErrorCode}, '
            'guest=${guest.connectionState}/${guest.lastErrorCode})');
    expect(owner.lastErrorCode, 'signaling_unavailable');
    expect(guest.lastErrorCode, 'signaling_unavailable');

    // Room, identity, playlist, playback and the surviving DC are retained.
    expect(owner.roomId, roomId);
    expect(owner.identity.deviceId, deviceId);
    expect(owner.playlist.length, 1);
    expect(owner.currentItemId, itemId);
    expect(owner.playback.seq, seqBefore);
    expect(owner.peerVerified, isTrue,
        reason: 'signaling loss must not tear down the data channel');
    expect(guest.peerVerified, isTrue);

    // URL playback does not depend on signaling: it keeps advancing.
    final posAtCut = owner.player.state.position;
    expect(
      await _waitFor(
          () => owner.player.state.position > posAtCut,
          const Duration(seconds: 10)),
      isTrue,
      reason: 'playback must keep running after signaling exhaustion',
    );

    // Exhaustion is terminal: the SAME endpoint returns, but the session must
    // NOT silently auto-recover. Only an explicit retry may reconnect.
    final signaling2 = await _startSamePort(port);
    addTearDown(signaling2.stop);
    await Future<void>.delayed(const Duration(seconds: 8));
    expect(owner.connectionState, RoomConnectionState.disconnected,
        reason: 'exhausted auto-retry must not restart on its own');
    expect(guest.connectionState, RoomConnectionState.disconnected);
    expect(owner.roomId, roomId);
    expect(owner.lastErrorCode, 'signaling_unavailable');

    // Explicit manual retry on the SAME URL.
    await owner.retry();
    expect(
      await _waitFor(
          () => owner.connectionState == RoomConnectionState.connected,
          const Duration(seconds: 30)),
      isTrue,
      reason: 'retry() must recover the same session '
          '(state=${owner.connectionState}, err=${owner.lastErrorCode})',
    );
    // No repointing, no room rebuild: same room/identity/playlist/DC.
    expect(owner.roomId, roomId);
    expect(owner.identity.deviceId, deviceId);
    expect(owner.playlist.length, 1);
    expect(owner.peerVerified, isTrue);
    expect(owner.lastErrorCode, isNull,
        reason: 'a successful retry must clear the stale connectivity error');

    // The owner re-registered on the same URL and rotated the invite epoch.
    expect(
      await _waitFor(
          () => owner.inviteText != null && owner.inviteText != oldInvite,
          const Duration(seconds: 15)),
      isTrue,
      reason: 'same-URL re-registration must rotate the invite epoch',
    );

    // The guest has no fabricated authority while its signaling is down.
    expect(guest.connectionState, RoomConnectionState.disconnected);
    expect(guest.playback.seq, seqBefore);
  }, timeout: const Timeout(Duration(minutes: 3)));
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

/// Resolve the 60 s / ~2.2 MiB clip. Desktop uses the pre-generated host file;
/// mobile platforms (no /tmp) materialize the bundled copy into the app temp dir.
Future<File> _resolveLongClip() async {
  final host = File('/tmp/eir-long.mp4');
  if (host.existsSync()) return host;
  final dir = await Directory.systemTemp.createTemp('eir_long_clip_');
  final out = File('${dir.path}/eir-long.mp4');
  final data = await rootBundle.load('assets/eir_long.mp4');
  await out.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return out;
}

Future<bool> _waitFor(
  bool Function() condition,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  return condition();
}
