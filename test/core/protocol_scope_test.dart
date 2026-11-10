import 'package:flutter_test/flutter_test.dart';

import 'package:eir/core/protocol.dart';

Map<String, Object?> scoped({
  Object? protocolVersion = 1,
  Object? roomId = 'room-1',
  Object? sessionId = 'session-1',
  Object? senderId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  Object? type = 'media_range_request',
}) {
  return <String, Object?>{
    'protocolVersion': protocolVersion,
    'roomId': roomId,
    'sessionId': sessionId,
    'senderId': senderId,
    'type': type,
    'requestId': 1,
  };
}

void main() {
  group('isRoomScopedMessage (media route gate)', () {
    const room = 'room-1';
    const session = 'session-1';
    const peer = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    test('valid media message from the verified peer passes', () {
      expect(
        isRoomScopedMessage(
          scoped(),
          roomId: room,
          sessionId: session,
          expectedSenderId: peer,
        ),
        isTrue,
      );
    });

    test('media message without roomId/sessionId is dropped', () {
      final msg = scoped(roomId: null, sessionId: null);
      expect(
        isRoomScopedMessage(msg,
            roomId: room, sessionId: session, expectedSenderId: peer),
        isFalse,
      );
    });

    test('wrong roomId / sessionId / protocolVersion are dropped', () {
      for (final bad in [
        scoped(roomId: 'room-2'),
        scoped(sessionId: 'session-2'),
        scoped(protocolVersion: 2),
      ]) {
        expect(
          isRoomScopedMessage(bad,
              roomId: room, sessionId: session, expectedSenderId: peer),
          isFalse,
        );
      }
    });

    test('media message from an unverified/different sender is dropped', () {
      expect(
        isRoomScopedMessage(
          scoped(senderId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
          roomId: room,
          sessionId: session,
          expectedSenderId: peer,
        ),
        isFalse,
      );
    });

    test('sender is not enforced when expectedSenderId is null (handshake path)',
        () {
      expect(
        isRoomScopedMessage(
          scoped(senderId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
          roomId: room,
          sessionId: session,
          expectedSenderId: null,
        ),
        isTrue,
      );
    });

    test('sender required but missing is dropped', () {
      final msg = scoped()..remove('senderId');
      expect(
        isRoomScopedMessage(msg,
            roomId: room, sessionId: session, expectedSenderId: peer),
        isFalse,
      );
    });
  });
}
