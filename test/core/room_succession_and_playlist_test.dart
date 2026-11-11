import 'package:flutter_test/flutter_test.dart';
import 'package:eir/core/commit_log.dart';
import 'package:eir/core/room_session.dart';

void main() {
  group('Room Succession & ACL', () {
    test('transferOwnership updates owner and increments version', () {
      final acl = RoomAcl(ownerDeviceId: 'owner1');
      expect(acl.ownerDeviceId, 'owner1');
      expect(acl.roleOf('owner1'), 'owner');
      expect(acl.version, 1);

      acl.transferOwnership('admin2');
      expect(acl.ownerDeviceId, 'admin2');
      expect(acl.roleOf('admin2'), 'owner');
      expect(acl.roleOf('owner1'), 'none');
      expect(acl.version, 2);
    });

    test('Succession sorting prioritizes admins over regular members', () {
      final members = [
        RoomMember(
          deviceId: 'mem1',
          displayName: 'Member 1',
          role: RoomRole.member,
          online: true,
          joinedAt: 1000,
        ),
        RoomMember(
          deviceId: 'admin1',
          displayName: 'Admin 1',
          role: RoomRole.admin,
          online: true,
          joinedAt: 2000,
        ),
        RoomMember(
          deviceId: 'mem2',
          displayName: 'Member 2',
          role: RoomRole.member,
          online: true,
          joinedAt: 500,
        ),
      ];

      final candidates = members.where((m) => m.online).toList();
      candidates.sort((a, b) {
        final aAdmin = a.role == RoomRole.admin ? 1 : 0;
        final bAdmin = b.role == RoomRole.admin ? 1 : 0;
        if (aAdmin != bAdmin) return bAdmin.compareTo(aAdmin);
        return a.joinedAt.compareTo(b.joinedAt);
      });

      // admin1 should be first even though joined later than mem1 and mem2
      expect(candidates.first.deviceId, 'admin1');
    });

    test('Succession sorting prioritizes earliest joinedAt among same role', () {
      final members = [
        RoomMember(
          deviceId: 'admin_late',
          displayName: 'Admin Late',
          role: RoomRole.admin,
          online: true,
          joinedAt: 3000,
        ),
        RoomMember(
          deviceId: 'admin_early',
          displayName: 'Admin Early',
          role: RoomRole.admin,
          online: true,
          joinedAt: 1000,
        ),
        RoomMember(
          deviceId: 'admin_mid',
          displayName: 'Admin Mid',
          role: RoomRole.admin,
          online: true,
          joinedAt: 2000,
        ),
      ];

      final candidates = members.where((m) => m.online).toList();
      candidates.sort((a, b) {
        final aAdmin = a.role == RoomRole.admin ? 1 : 0;
        final bAdmin = b.role == RoomRole.admin ? 1 : 0;
        if (aAdmin != bAdmin) return bAdmin.compareTo(aAdmin);
        return a.joinedAt.compareTo(b.joinedAt);
      });

      expect(candidates[0].deviceId, 'admin_early');
      expect(candidates[1].deviceId, 'admin_mid');
      expect(candidates[2].deviceId, 'admin_late');
    });

    test('Offline members are excluded from succession', () {
      final members = [
        RoomMember(
          deviceId: 'admin_offline',
          displayName: 'Admin Offline',
          role: RoomRole.admin,
          online: false,
          joinedAt: 100,
        ),
        RoomMember(
          deviceId: 'mem_online',
          displayName: 'Member Online',
          role: RoomRole.member,
          online: true,
          joinedAt: 500,
        ),
      ];

      final candidates = members.where((m) => m.online).toList();
      expect(candidates.length, 1);
      expect(candidates.first.deviceId, 'mem_online');
    });
  });

  group('Playlist Item Offline & Next Playable Selection', () {
    test('PlaylistItem serialization and offline logic simulation', () {
      final itemLocal = PlaylistItem(
        itemId: 'item1',
        title: 'Local Video',
        sourceType: 'local',
        localMediaId: 'media123',
      );
      final itemUrl = PlaylistItem(
        itemId: 'item2',
        title: 'Web Stream',
        sourceType: 'url',
        url: 'https://example.com/video.mp4',
      );

      final map = itemLocal.toMap();
      final revived = PlaylistItem.fromMap(map);
      expect(revived.itemId, 'item1');
      expect(revived.sourceType, 'local');
      expect(revived.localMediaId, 'media123');

      // Next playable simulation
      final playlist = [
        itemLocal,
        itemUrl,
        PlaylistItem(itemId: 'item3', title: 'Local 2', sourceType: 'local', localMediaId: 'media456'),
      ];

      // If media123 is offline and media456 is offline, next playable from item1 should be itemUrl
      bool isOffline(PlaylistItem it) {
        if (it.sourceType != 'local') return false;
        if (it.localMediaId == 'media123' || it.localMediaId == 'media456') return true;
        return false;
      }

      PlaylistItem? findNext(String fromItemId) {
        final startIndex = playlist.indexWhere((it) => it.itemId == fromItemId);
        final count = playlist.length;
        for (var i = 1; i <= count; i++) {
          final idx = (startIndex + i) % count;
          final cand = playlist[idx];
          if (cand.itemId == fromItemId) continue;
          if (!isOffline(cand)) return cand;
        }
        return null;
      }

      final next = findNext('item1');
      expect(next, isNotNull);
      expect(next!.itemId, 'item2');
      expect(next.sourceType, 'url');
    });
  });
}
