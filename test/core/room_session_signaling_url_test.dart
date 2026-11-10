import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:eir/core/room_session.dart';
import 'package:eir/core/invite.dart';

import '../../server/signaling_server.dart';

Future<bool> _waitFor(
  bool Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return condition();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized();
  });

  test(
    'in-room save keeps old reconnect and invite, new create adopts configured',
    () async {
      final serverA = SignalingServer();
      await serverA.start(address: InternetAddress.loopbackIPv4, port: 0);
      final urlA = 'ws://127.0.0.1:${serverA.port}';

      final serverB = SignalingServer();
      await serverB.start(address: InternetAddress.loopbackIPv4, port: 0);
      final urlB = 'ws://127.0.0.1:${serverB.port}';

      final store = InMemorySecureKeyValueStore();
      final identityStore = DeviceIdentityStore(store: store);
      final session = RoomSession(identityStore: identityStore);

      addTearDown(() async {
        try {
          session.dispose();
        } catch (_) {}
        try {
          await serverA.stop();
        } catch (_) {}
        try {
          await serverB.stop();
        } catch (_) {}
      });

      await session.init();
      await session.setSignalingUrl(urlA);
      await session.createRoom();

      expect(
        await _waitFor(
          () => session.connectionState == RoomConnectionState.connected,
          timeout: const Duration(seconds: 10),
        ),
        isTrue,
        reason: 'owner must connect to A (state=${session.connectionState}, '
            'err=${session.lastErrorCode})',
      );
      final roomIdOld = session.roomId!;
      final inviteOld = session.inviteText!;
      final decodedBefore = await decodeAndVerifyInvite(
        inviteOld,
        identityStore: identityStore,
      );
      expect(decodedBefore.signalingUrl, urlA);

      await session.setSignalingUrl('  $urlB  ');
      expect(session.roomId, roomIdOld);
      expect(session.connectionState, RoomConnectionState.connected);
      expect(session.inviteText, inviteOld);
      final decodedAfterSave = await decodeAndVerifyInvite(
        session.inviteText!,
        identityStore: identityStore,
      );
      expect(decodedAfterSave.signalingUrl, urlA);
      expect(serverB.roomCount, 0);

      await expectLater(
        session.setSignalingUrl('http://127.0.0.1:9999'),
        throwsArgumentError,
      );
      expect(session.lastErrorCode, 'signaling_unavailable');
      expect(session.roomId, roomIdOld);
      expect(session.connectionState, RoomConnectionState.connected);
      final decodedAfterInvalid = await decodeAndVerifyInvite(
        session.inviteText!,
        identityStore: identityStore,
      );
      expect(decodedAfterInvalid.signalingUrl, urlA);

      await serverA.stop(graceful: false);
      expect(
        await _waitFor(
          () => session.connectionState != RoomConnectionState.connected,
          timeout: const Duration(seconds: 5),
        ),
        isTrue,
        reason: 'abrupt A loss must move session out of connected '
            '(state=${session.connectionState})',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await session.retry();
      expect(
        session.connectionState,
        RoomConnectionState.disconnected,
        reason: 'retry must keep targeting old A and fail, not repoint to B '
            '(state=${session.connectionState}, err=${session.lastErrorCode})',
      );
      expect(session.roomId, roomIdOld);
      expect(serverB.roomCount, 0,
          reason: 'retry must not create a room on B');
      expect(session.inviteText, inviteOld);
      final decodedAfterRetry = await decodeAndVerifyInvite(
        session.inviteText!,
        identityStore: identityStore,
      );
      expect(decodedAfterRetry.signalingUrl, urlA);

      await session.leaveRoom();
      expect(session.roomId, isNull);
      expect(session.connectionState, RoomConnectionState.disconnected);

      await session.createRoom();
      expect(
        await _waitFor(
          () => session.connectionState == RoomConnectionState.connected,
          timeout: const Duration(seconds: 10),
        ),
        isTrue,
        reason: 'new create must adopt configured B and connect '
            '(state=${session.connectionState}, err=${session.lastErrorCode})',
      );
      expect(session.roomId, isNotNull);
      expect(session.roomId, isNot(roomIdOld));
      final decodedNew = await decodeAndVerifyInvite(
        session.inviteText!,
        identityStore: identityStore,
      );
      expect(decodedNew.signalingUrl, urlB);
      expect(serverB.roomCount, 1);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
