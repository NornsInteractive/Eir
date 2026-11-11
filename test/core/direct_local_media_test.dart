import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:eir/core/room_session.dart';
import 'package:media_kit/media_kit.dart';
import '../../server/signaling_server.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized();
  });

  test('PlaylistItem serializes and deserializes localPath accurately', () {
    final item = PlaylistItem(
      itemId: 'item-123',
      title: 'movie.mp4',
      sourceType: 'local',
      localPath: '/storage/emulated/0/Movies/movie.mp4',
      url: '/storage/emulated/0/Movies/movie.mp4',
      sizeBytes: 2147483648,
    );

    final map = item.toMap();
    expect(map['localPath'], equals('/storage/emulated/0/Movies/movie.mp4'));
    expect(map['url'], equals('/storage/emulated/0/Movies/movie.mp4'));
    expect(map['sizeBytes'], equals(2147483648));

    final parsed = PlaylistItem.fromMap(map);
    expect(parsed.itemId, equals('item-123'));
    expect(parsed.title, equals('movie.mp4'));
    expect(parsed.sourceType, equals('local'));
    expect(parsed.localPath, equals('/storage/emulated/0/Movies/movie.mp4'));
    expect(parsed.url, equals('/storage/emulated/0/Movies/movie.mp4'));
    expect(parsed.sizeBytes, equals(2147483648));
  });

  test('Direct local media creates instant playlist entry in active room', () async {
    final server = SignalingServer();
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    final signalingUrl = 'ws://127.0.0.1:${server.port}';

    final store = InMemorySecureKeyValueStore();
    final idStore = DeviceIdentityStore(store: store);
    final session = RoomSession(identityStore: idStore);

    addTearDown(() async {
      try {
        session.dispose();
      } catch (_) {}
      try {
        await server.stop();
      } catch (_) {}
    });

    await session.init();
    await session.setSignalingUrl(signalingUrl);
    await session.createRoom();

    final tempDir = await Directory.systemTemp.createTemp('eir_direct_local_');
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
    final mediaFile = File('${tempDir.path}/big_movie.mp4');
    await mediaFile.writeAsBytes(List<int>.filled(4096, 0));

    final path = mediaFile.path;
    await session.addDirectLocalMedia(
      path: path,
      title: 'big_movie.mp4',
      sizeBytes: 3000000000,
    );

    expect(session.playlist.length, equals(1));
    final item = session.playlist.first;
    expect(item.title, equals('big_movie.mp4'));
    expect(item.sourceType, equals('local'));
    expect(item.localPath, equals(path));
    expect(item.sizeBytes, equals(await mediaFile.length()));
  });
}
