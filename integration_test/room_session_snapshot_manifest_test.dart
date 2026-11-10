import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

/// Regression: a guest joining AFTER the owner added a local file receives
/// the playlist via `room_snapshot`. The snapshot must bind each local
/// item to its source device (`manifestSource`, covered by the snapshot
/// signature); without it the guest can never authorize the manifest
/// (inline or chunked pull) and the item stays source-offline forever.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('late joiner installs snapshot manifest and reads ranges',
      (tester) async {
    final sampleBytesData = await rootBundle.load('assets/sample.mp4');
    final sampleBytes = sampleBytesData.buffer.asUint8List();

    final tempDir = await Directory.systemTemp.createTemp('eir_snapshot_');
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
    final file = File('${tempDir.path}/sample.mp4');
    await file.writeAsBytes(sampleBytes, flush: true);

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

    // Owner adds the local file BEFORE the guest joins (snapshot path).
    await sessionA.addLocalFile(
        XFile(file.path, name: 'sample.mp4'), title: 'late join clip');
    expect(sessionA.lastErrorCode, isNull,
        reason: 'addLocalFile failed: ${sessionA.lastErrorCode}');
    expect(sessionA.playlist, hasLength(1));
    final mediaId = sessionA.playlist.single.localMediaId;
    expect(mediaId, isNotNull);
    final itemId = sessionA.playlist.single.itemId;
    await sessionA.switchItem(itemId);

    // Guest joins late: state must arrive via snapshot, including the
    // source binding for the local item's manifest.
    final invite = sessionA.inviteText;
    expect(invite, isNotNull);
    await sessionB.joinRoom(invite!);
    final verified = await _waitFor(
      () => sessionA.peerVerified && sessionB.peerVerified,
      timeout: const Duration(seconds: 20),
    );
    expect(verified, isTrue);

    final synced = await _waitFor(
      () => sessionB.playlist.length == 1,
      timeout: const Duration(seconds: 15),
    );
    expect(synced, isTrue,
        reason: 'guest did not receive snapshot playlist '
            '(lastErrorCode=${sessionB.lastErrorCode})');
    expect(sessionB.playlist.single.sourceType, 'local');
    expect(sessionB.playlist.single.localMediaId, mediaId);

    // The manifest must be installed (inline from snapshot or chunked
    // pull authorized by the snapshot's source binding).
    final serviceB = sessionB.debugMediaService;
    expect(serviceB, isNotNull);
    final installed = await _waitFor(
      () => serviceB!.manifestFor(mediaId!) != null,
      timeout: const Duration(seconds: 15),
    );
    expect(installed, isTrue,
        reason: 'snapshot manifest was not installed '
            '(lastErrorCode=${sessionB.lastErrorCode})');

    // Guest reads byte ranges back over the live DataChannel.
    const head = 4096;
    final headBytes = await serviceB!.readRangeBytes(mediaId!, 0, head);
    expect(headBytes.length, head);
    expect(headBytes, sampleBytes.sublist(0, head));

    final tailLength = sampleBytes.length < 8192 ? sampleBytes.length : 8192;
    final tailStart = sampleBytes.length - tailLength;
    final tailBytes = await serviceB.readRangeBytes(
      mediaId,
      tailStart,
      sampleBytes.length,
    );
    expect(tailBytes, sampleBytes.sublist(tailStart));

    await sessionA.closeRoom();
    final closed = await _waitFor(
      () =>
          sessionA.connectionState == RoomConnectionState.disconnected &&
          sessionB.connectionState == RoomConnectionState.disconnected,
      timeout: const Duration(seconds: 10),
    );
    expect(closed, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
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
