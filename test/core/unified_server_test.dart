import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/signaling_server.dart';

Future<({String deviceId, String publicKeyBase64})> _createIdentity() async {
  final keyPair = await Ed25519().newKeyPair();
  final pub = (await keyPair.extractPublicKey()).bytes;
  final digest = crypto.sha256.convert(pub).toString();
  return (deviceId: digest, publicKeyBase64: base64Encode(pub));
}

void main() {
  group('Unified Web & Signaling Server (Single Port)', () {
    late Directory tempWebDir;
    late SignalingServer server;
    late int port;
    late HttpClient httpClient;

    setUp(() async {
      tempWebDir = await Directory.systemTemp.createTemp('eir_web_test_');
      final indexHtml = File('${tempWebDir.path}/index.html');
      await indexHtml.writeAsString('<!DOCTYPE html><html><body>Eir Web</body></html>');

      final appJs = File('${tempWebDir.path}/main.dart.js');
      await appJs.writeAsString('console.log("eir app");');

      server = SignalingServer();
      await server.start(
        address: InternetAddress.loopbackIPv4,
        port: 0,
        webRoot: tempWebDir.path,
      );
      port = server.port;
      httpClient = HttpClient();
    });

    tearDown(() async {
      httpClient.close(force: true);
      await server.stop();
      if (tempWebDir.existsSync()) {
        await tempWebDir.delete(recursive: true);
      }
    });

    test('serves static index.html with COOP and COEP headers on root GET', () async {
      final req = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/'));
      final resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.ok));
      expect(resp.headers.value('cross-origin-opener-policy'), equals('same-origin'));
      expect(resp.headers.value('cross-origin-embedder-policy'), equals('credentialless'));
      expect(resp.headers.contentType?.mimeType, equals('text/html'));

      final body = await utf8.decoder.bind(resp).join();
      expect(body, contains('Eir Web'));
    });

    test('serves js file with correct Content-Type and COOP/COEP headers', () async {
      final req = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/main.dart.js'));
      final resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.ok));
      expect(resp.headers.value('cross-origin-opener-policy'), equals('same-origin'));
      expect(resp.headers.value('cross-origin-embedder-policy'), equals('credentialless'));
      expect(resp.headers.contentType?.mimeType, equals('application/javascript'));

      final body = await utf8.decoder.bind(resp).join();
      expect(body, contains('console.log("eir app");'));
    });

    test('SPA fallback routes non-file paths to index.html', () async {
      final req = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/room/alpha-123'));
      final resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.ok));
      final body = await utf8.decoder.bind(resp).join();
      expect(body, contains('Eir Web'));
    });

    test('returns 404 Not Found for non-existent files', () async {
      final req = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/missing_file.css'));
      final resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.notFound));
    });

    test('connects WebSocket signaling on /ws on the exact same HTTP port', () async {
      final identity = await _createIdentity();
      final ws = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      addTearDown(() => ws.close());

      // Send create_room
      ws.add(jsonEncode({
        'type': 'create_room',
        'protocolVersion': 1,
        'roomId': '11111111-1111-4111-8111-111111111111',
        'token': 'abcdefghijklmnopqrstuvwxyz0123456789_-ABCDE',
        'deviceId': identity.deviceId,
        'ownerPublicKey': identity.publicKeyBase64,
        'sessionId': '22222222-2222-4222-8222-222222222222',
        'genesisHash': 'f' * 64,
        'inviteEpoch': 1,
      }));

      final replyRaw = await ws.first;
      final reply = jsonDecode(replyRaw as String) as Map<String, dynamic>;
      expect(reply['type'], equals('room_created'));
      expect(reply['roomId'], equals('11111111-1111-4111-8111-111111111111'));
    });

    test('connects WebSocket signaling on root / on the exact same HTTP port', () async {
      final identity = await _createIdentity();
      final ws = await WebSocket.connect('ws://127.0.0.1:$port/');
      addTearDown(() => ws.close());

      ws.add(jsonEncode({
        'type': 'create_room',
        'protocolVersion': 1,
        'roomId': '33333333-3333-4333-8333-333333333333',
        'token': 'abcdefghijklmnopqrstuvwxyz0123456789_-ABCDE',
        'deviceId': identity.deviceId,
        'ownerPublicKey': identity.publicKeyBase64,
        'sessionId': '44444444-4444-4444-8444-444444444444',
        'genesisHash': 'e' * 64,
        'inviteEpoch': 1,
      }));

      final replyRaw = await ws.first;
      final reply = jsonDecode(replyRaw as String) as Map<String, dynamic>;
      expect(reply['type'], equals('room_created'));
      expect(reply['roomId'], equals('33333333-3333-4333-8333-333333333333'));
    });
  });
}
