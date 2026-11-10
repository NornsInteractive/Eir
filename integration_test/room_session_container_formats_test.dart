import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

/// Real two-client end-to-end for a non-MP4 container: a Matroska (.mkv) file
/// is registered with its real MIME (`video/x-matroska`), shared through a
/// signed manifest, fetched chunk-by-chunk over the live DataChannel, and
/// decoded by the guest player. A non-media file registers with its own safe
/// MIME (no fixed whitelist) and playback surfaces the player's verdict as a
/// stable error code.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two clients: Matroska share + decode, non-media playback fails',
      (tester) async {
    final bytesData = await rootBundle.load('assets/eir_container.mkv');
    final mkvBytes = bytesData.buffer
        .asUint8List(bytesData.offsetInBytes, bytesData.lengthInBytes);

    final tempDir = await Directory.systemTemp.createTemp('eir_container_');
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
    final file = File('${tempDir.path}/clip.mkv');
    await file.writeAsBytes(mkvBytes, flush: true);

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
    await sessionB.joinRoom(sessionA.inviteText!);
    expect(
      await _waitFor(
          () => sessionA.peerVerified && sessionB.peerVerified,
          const Duration(seconds: 20)),
      isTrue,
    );

    // --- a non-media file is still registered (no fixed whitelist) ---
    // The player decides playability: this text file becomes a playlist item
    // and is expected to fail playback later with a stable error.
    final txtBytes = Uint8List.fromList(
        utf8.encode('eir-not-media: plain text, no container magic\n'));
    await sessionA.addLocalFile(
      XFile.fromData(txtBytes, name: 'notes.txt', mimeType: 'text/plain'),
    );
    expect(sessionA.lastErrorCode, isNull,
        reason: 'non-media registration is allowed, '
            'got: ${sessionA.lastErrorCode}');
    expect(sessionA.playlist, hasLength(1));
    final txtItemId = sessionA.playlist.single.itemId;

    // --- the MKV is registered with its real MIME and shared ---
    await sessionA.addLocalFile(XFile(file.path), title: 'mkv clip');
    expect(sessionA.lastErrorCode, isNull,
        reason: 'addLocalFile failed: ${sessionA.lastErrorCode}');
    expect(sessionA.playlist, hasLength(2));

    expect(
      await _waitFor(() => sessionB.playlist.length == 2,
          const Duration(seconds: 15)),
      isTrue,
      reason: 'guest did not receive the add_local commits '
          '(lastErrorCode=${sessionB.lastErrorCode})',
    );
    final mediaId = sessionB.playlist.last.localMediaId;
    expect(mediaId, isNotNull);

    // The receiving side sees the container MIME, not a hard-coded MP4.
    final serviceB = sessionB.debugMediaService;
    expect(serviceB, isNotNull);
    final manifest = serviceB!.manifestFor(mediaId!);
    expect(manifest, isNotNull);
    expect(manifest!.mime, 'video/x-matroska');
    expect(serviceB.uriFor(mediaId), endsWith('.mkv'));

    // --- byte ranges cross the real DataChannel intact ---
    const head = 4096;
    final headBytes = await serviceB.readRangeBytes(mediaId, 0, head);
    expect(headBytes, mkvBytes.sublist(0, head));
    final tailLength = mkvBytes.length < 8192 ? mkvBytes.length : 8192;
    final tailStart = mkvBytes.length - tailLength;
    final tailBytes =
        await serviceB.readRangeBytes(mediaId, tailStart, mkvBytes.length);
    expect(tailBytes, mkvBytes.sublist(tailStart));
    expect(sessionA.debugMediaService?.transferTelemetry.sentFrames,
        greaterThan(0));

    // --- the guest really decodes the shared MKV ---
    final itemId = sessionA.playlist.last.itemId;
    await sessionA.switchItem(itemId);
    expect(
      await _waitFor(
          () => sessionB.currentItemId == itemId, const Duration(seconds: 10)),
      isTrue,
    );
    await sessionA.play();
    expect(
      await _waitFor(
          () => sessionB.player.state.position.inMilliseconds > 200,
          const Duration(seconds: 40)),
      isTrue,
      reason: 'guest did not decode the MKV '
          '(mode=${sessionB.playback.mode}, '
          'pos=${sessionB.player.state.position.inMilliseconds}ms, '
          'err=${sessionB.lastErrorCode})',
    );

    // --- playing the non-media item surfaces the player verdict ---
    await sessionA.switchItem(txtItemId);
    expect(
      await _waitFor(
          () =>
              sessionA.lastErrorCode == 'media_probe_failed' ||
              sessionB.lastErrorCode == 'media_probe_failed',
          const Duration(seconds: 30)),
      isTrue,
      reason: 'unplayable registration did not surface a playback error '
          '(A=${sessionA.lastErrorCode}, B=${sessionB.lastErrorCode})',
    );

    await sessionA.closeRoom();
    expect(
      await _waitFor(
          () =>
              sessionA.connectionState == RoomConnectionState.disconnected &&
              sessionB.connectionState == RoomConnectionState.disconnected,
          const Duration(seconds: 10)),
      isTrue,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
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
