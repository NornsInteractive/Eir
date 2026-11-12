import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eir/app_settings.dart';
import 'package:eir/core/room_session.dart';
import 'package:eir/core/transport/room_transport.dart';
import 'package:eir/core/transport/tailcat_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Transport Dual Engine & Traversal Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.instance.init();
    });

    test('TURN Server Configuration & effectiveIceServers', () async {
      expect(RoomSession.effectiveIceServers.length, 1);
      expect(RoomSession.effectiveIceServers.first['urls'], RoomSession.iceServers);

      await AppSettings.instance.setTurnConfig(
        server: 'turn.example.com:3478',
        username: 'alice',
        credential: 'secretpassword',
      );

      expect(AppSettings.instance.turnServer, 'turn.example.com:3478');
      expect(AppSettings.instance.turnUsername, 'alice');
      expect(AppSettings.instance.turnCredential, 'secretpassword');

      final servers = RoomSession.effectiveIceServers;
      expect(servers.length, 2);
      expect(servers[1]['urls'], 'turn:turn.example.com:3478');
      expect(servers[1]['username'], 'alice');
      expect(servers[1]['credential'], 'secretpassword');
    });

    test('Transport Engine Preference (webrtc vs tailcat)', () async {
      expect(AppSettings.instance.transportEngine, 'webrtc');
      expect(AppSettings.instance.isTailcatEngine, false);

      await AppSettings.instance.setTransportEngine('tailcat');
      expect(AppSettings.instance.transportEngine, 'tailcat');
      expect(AppSettings.instance.isTailcatEngine, true);

      await AppSettings.instance.setTransportEngine('invalid');
      expect(AppSettings.instance.transportEngine, 'webrtc');
      expect(AppSettings.instance.isTailcatEngine, false);
    });

    test('AppSettings wait for peer buffering setting', () async {
      expect(AppSettings.instance.waitForPeerBuffering, true);
      await AppSettings.instance.setWaitForPeerBuffering(false);
      expect(AppSettings.instance.waitForPeerBuffering, false);
      await AppSettings.instance.setWaitForPeerBuffering(true);
      expect(AppSettings.instance.waitForPeerBuffering, true);
    });

    test('RoomTransport enum and TailcatTransport availability', () {
      expect(TransportEngineType.values.length, 2);
      expect(TransportEngineType.webrtc.name, 'webrtc');
      expect(TransportEngineType.tailcat.name, 'tailcat');

      final transport = TailcatTransport();
      expect(transport.type, TransportEngineType.tailcat);
      expect(transport.isOpen, false);
      expect(transport.isDirectP2p, false);
      expect(transport.onConnected, isNull);
      transport.onConnected = () {};
      expect(transport.onConnected, isNotNull);
    });

    test('RoomSession P2P states and retryP2p interface', () {
      final session = RoomSession();
      expect(session.isP2pConnected, false);
      expect(session.isP2pConnecting, false);
      expect(session.isP2pFailed, false);
      expect(session.waitForPeerBuffering, true);
      expect(session.isHostWaitingPeerBuffering, false);
      expect(session.isAnyPeerBuffering, false);

      session.waitForPeerBuffering = false;
      expect(session.waitForPeerBuffering, false);

      // retryP2p does not throw when room is not connected
      expect(() => session.retryP2p(), returnsNormally);
    });
  });
}
