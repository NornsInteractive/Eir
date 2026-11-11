import 'package:flutter_test/flutter_test.dart';
import 'package:eir/core/room_session.dart';

void main() {
  group('Loop Mode & Danmaku Tests', () {
    test('PlaybackLoopMode enum values and transitions', () {
      expect(PlaybackLoopMode.values.length, 3);
      expect(PlaybackLoopMode.loopAll.name, 'loopAll');
      expect(PlaybackLoopMode.loopOne.name, 'loopOne');
      expect(PlaybackLoopMode.sequential.name, 'sequential');
    });

    test('DanmakuMessage carries sender, text, timestamp and color', () {
      final timestamp = DateTime.utc(2026, 11, 11, 12, 34, 56);
      final msg = DanmakuMessage(
        id: 'msg-1',
        sender: 'Alice',
        text: 'Hello Eir Sync',
        timestamp: timestamp,
        colorHex: '#FF0000',
      );

      expect(msg.id, 'msg-1');
      expect(msg.sender, 'Alice');
      expect(msg.text, 'Hello Eir Sync');
      expect(msg.timestamp, timestamp);
      expect(msg.colorHex, '#FF0000');
    });
  });
}
