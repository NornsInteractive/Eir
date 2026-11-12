import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eir/core/room_history_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RoomHistoryService.recentRoomsNotifier.value = [];
  });

  group('RoomHistoryService', () {
    test('recordRoom saves room and updates recentRoomsNotifier', () async {
      await RoomHistoryService.recordRoom(
        roomCode: '123456',
        roomId: 'uuid-1',
        roomName: 'Alice Cinema',
        isOwner: true,
      );

      final rooms = await RoomHistoryService.getRecentRooms();
      expect(rooms.length, 1);
      expect(rooms.first.roomCode, '123456');
      expect(rooms.first.roomId, 'uuid-1');
      expect(rooms.first.roomName, 'Alice Cinema');
      expect(rooms.first.isOwner, true);
      expect(RoomHistoryService.recentRoomsNotifier.value.length, 1);
    });

    test('recordRoom deduplicates and moves visited room to top', () async {
      await RoomHistoryService.recordRoom(
        roomCode: '111111',
        roomId: 'uuid-1',
        roomName: 'Room 1',
        isOwner: false,
      );
      await RoomHistoryService.recordRoom(
        roomCode: '222222',
        roomId: 'uuid-2',
        roomName: 'Room 2',
        isOwner: false,
      );

      var rooms = await RoomHistoryService.getRecentRooms();
      expect(rooms.first.roomCode, '222222');

      // Re-record Room 1
      await RoomHistoryService.recordRoom(
        roomCode: '111111',
        roomId: 'uuid-1',
        roomName: 'Room 1 Updated',
        isOwner: true,
      );

      rooms = await RoomHistoryService.getRecentRooms();
      expect(rooms.length, 2);
      expect(rooms.first.roomCode, '111111');
      expect(rooms.first.roomName, 'Room 1 Updated');
      expect(rooms.first.isOwner, true);
    });

    test('recordRoom caps at max 5 rooms', () async {
      for (int i = 1; i <= 7; i++) {
        await RoomHistoryService.recordRoom(
          roomCode: '00000$i',
          roomId: 'uuid-$i',
          roomName: 'Room $i',
          isOwner: false,
        );
      }

      final rooms = await RoomHistoryService.getRecentRooms();
      expect(rooms.length, 5);
      // Newest (Room 7) should be at top, oldest (Room 1, 2) dropped
      expect(rooms.first.roomCode, '000007');
      expect(rooms.last.roomCode, '000003');
    });

    test('removeRoom deletes specified room', () async {
      await RoomHistoryService.recordRoom(
        roomCode: '111111',
        roomId: 'uuid-1',
        roomName: 'Room 1',
        isOwner: false,
      );
      await RoomHistoryService.recordRoom(
        roomCode: '222222',
        roomId: 'uuid-2',
        roomName: 'Room 2',
        isOwner: false,
      );

      await RoomHistoryService.removeRoom('111111');
      final rooms = await RoomHistoryService.getRecentRooms();
      expect(rooms.length, 1);
      expect(rooms.first.roomCode, '222222');
      expect(RoomHistoryService.recentRoomsNotifier.value.length, 1);
    });

    test('clearHistory removes all recent rooms', () async {
      await RoomHistoryService.recordRoom(
        roomCode: '111111',
        roomId: 'uuid-1',
        roomName: 'Room 1',
        isOwner: false,
      );
      await RoomHistoryService.recordRoom(
        roomCode: '222222',
        roomId: 'uuid-2',
        roomName: 'Room 2',
        isOwner: false,
      );

      await RoomHistoryService.clearHistory();
      final rooms = await RoomHistoryService.getRecentRooms();
      expect(rooms.isEmpty, true);
      expect(RoomHistoryService.recentRoomsNotifier.value.isEmpty, true);
    });
  });
}
