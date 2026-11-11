import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../server/signaling_server.dart';

class TestIdentity {
  TestIdentity({
    required this.deviceId,
    required this.publicKeyBase64,
  });
  final String deviceId;
  final String publicKeyBase64;
}

Future<TestIdentity> newTestIdentity() async {
  final keyPair = await Ed25519().newKeyPair();
  final pub = (await keyPair.extractPublicKey()).bytes;
  final digest = crypto.sha256.convert(pub).toString();
  return TestIdentity(deviceId: digest, publicKeyBase64: base64Encode(pub));
}

class WsClient {
  WsClient(this.channel);
  final WebSocketChannel channel;
  final List<Map<String, dynamic>> received = <Map<String, dynamic>>[];
  final List<(String, Completer<Map<String, dynamic>>)> _waiters =
      <(String, Completer<Map<String, dynamic>>)>[];

  static Future<WsClient> connect(int port) async {
    final channel = WebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:$port'),
    );
    await channel.ready;
    final client = WsClient(channel);
    channel.stream.listen((data) {
      final decoded = jsonDecode(data as String) as Map<String, dynamic>;
      final type = decoded['type'] as String?;
      (String, Completer<Map<String, dynamic>>)? match;
      for (final w in client._waiters) {
        if (w.$1 == type) {
          match = w;
          break;
        }
      }
      if (match != null) {
        client._waiters.remove(match);
        if (!match.$2.isCompleted) match.$2.complete(decoded);
      } else {
        client.received.add(decoded);
      }
    });
    return client;
  }

  Future<void> send(Map<String, Object?> message) async {
    channel.sink.add(jsonEncode(message));
  }

  Future<void> sendRaw(String raw) async {
    channel.sink.add(raw);
  }

  /// Waits for the next message of [type]; fails after [timeout].
  Future<Map<String, dynamic>> waitFor(
    String type, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    for (final m in List<Map<String, dynamic>>.from(received)) {
      if (m['type'] == type) {
        received.remove(m);
        return m;
      }
    }
    final completer = Completer<Map<String, dynamic>>();
    _waiters.add((type, completer));
    try {
      return await completer.future.timeout(timeout);
    } finally {
      _waiters.removeWhere((w) => w.$2 == completer);
    }
  }

  Future<void> close() async {
    await channel.sink.close();
  }
}

Map<String, Object?> createRoomMsg({
  required String roomId,
  required String token,
  required TestIdentity identity,
  String sessionId = '11111111-2222-3333-4444-555555555555',
  String genesisHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  int inviteEpoch = 1,
  int protocolVersion = 1,
}) {
  return {
    'type': 'create_room',
    'protocolVersion': protocolVersion,
    'roomId': roomId,
    'token': token,
    'deviceId': identity.deviceId,
    'ownerPublicKey': identity.publicKeyBase64,
    'sessionId': sessionId,
    'genesisHash': genesisHash,
    'inviteEpoch': inviteEpoch,
  };
}

Map<String, Object?> joinRoomMsg({
  required String roomId,
  required String token,
  required TestIdentity identity,
  int inviteEpoch = 1,
  int protocolVersion = 1,
}) {
  return {
    'type': 'join_room',
    'protocolVersion': protocolVersion,
    'roomId': roomId,
    'token': token,
    'deviceId': identity.deviceId,
    'publicKey': identity.publicKeyBase64,
    'inviteEpoch': inviteEpoch,
  };
}

const roomId = 'cccccccc-2222-3333-4444-555555555555';
const token = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq'; // exactly 43 chars

void main() {
  late SignalingServer server;
  late int port;

  setUp(() async {
    server = SignalingServer();
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    port = server.port;
  });

  tearDown(() async {
    await server.stop();
  });

  test('create_room succeeds and returns room_created', () async {
    final owner = await newTestIdentity();
    final client = await WsClient.connect(port);
    await client.send(createRoomMsg(
      roomId: roomId,
      token: token,
      identity: owner,
    ));
    final reply = await client.waitFor('room_created');
    expect(reply['roomId'], roomId);
    await client.close();
  });

  test('create_room rejects malformed roomId and pubkey/device mismatch',
      () async {
    final owner = await newTestIdentity();
    final client = await WsClient.connect(port);
    await client.send(createRoomMsg(
      roomId: 'not-a-uuid',
      token: token,
      identity: owner,
    ));
    expect((await client.waitFor('error'))['code'], 'invalid_message');

    final other = await newTestIdentity();
    await client.send(createRoomMsg(
      roomId: roomId,
      token: token,
      identity: TestIdentity(
        deviceId: other.deviceId,
        publicKeyBase64: owner.publicKeyBase64, // mismatched pair
      ),
    ));
    expect((await client.waitFor('error'))['code'], 'invalid_message');
    await client.close();
  });

  test('create_room enforces protocol version', () async {
    final owner = await newTestIdentity();
    final client = await WsClient.connect(port);
    await client.send(createRoomMsg(
      roomId: roomId,
      token: token,
      identity: owner,
      protocolVersion: 2,
    ));
    expect((await client.waitFor('error'))['code'], 'protocol_version');
    await client.close();
  });

  test('room creation is not takeable: different owner/genesis gets room_exists',
      () async {
    final owner = await newTestIdentity();
    final thief = await newTestIdentity();
    final c1 = await WsClient.connect(port);
    await c1.send(createRoomMsg(roomId: roomId, token: token, identity: owner));
    await c1.waitFor('room_created');

    final c2 = await WsClient.connect(port);
    await c2.send(createRoomMsg(roomId: roomId, token: token, identity: thief));
    expect((await c2.waitFor('error'))['code'], 'room_exists');

    // Idempotent retry by the same owner with same genesis succeeds.
    final c3 = await WsClient.connect(port);
    await c3.send(createRoomMsg(roomId: roomId, token: token, identity: owner));
    final rejoined = await c3.waitFor('room_created');
    expect(rejoined['roomId'], roomId);
    await c1.close();
    await c2.close();
    await c3.close();
  });

  test('invite is single-use and bound to one identity', () async {
    final owner = await newTestIdentity();
    final guestA = await newTestIdentity();
    final guestB = await newTestIdentity();
    final ownerClient = await WsClient.connect(port);
    await ownerClient.send(
        createRoomMsg(roomId: roomId, token: token, identity: owner));
    await ownerClient.waitFor('room_created');

    final a = await WsClient.connect(port);
    await a.send(joinRoomMsg(roomId: roomId, token: token, identity: guestA));
    expect((await a.waitFor('join_accepted'))['roomId'], roomId);

    final b = await WsClient.connect(port);
    await b.send(joinRoomMsg(roomId: roomId, token: token, identity: guestB));
    expect((await b.waitFor('error'))['code'], 'invite_consumed');

    await ownerClient.close();
    await a.close();
    await b.close();
  });

  test('same identity can rejoin idempotently after dropping', () async {
    final owner = await newTestIdentity();
    final guest = await newTestIdentity();
    final ownerClient = await WsClient.connect(port);
    await ownerClient.send(
        createRoomMsg(roomId: roomId, token: token, identity: owner));
    await ownerClient.waitFor('room_created');

    final first = await WsClient.connect(port);
    await first.send(joinRoomMsg(roomId: roomId, token: token, identity: guest));
    await first.waitFor('join_accepted');
    await first.close();

    final second = await WsClient.connect(port);
    await second.send(joinRoomMsg(roomId: roomId, token: token, identity: guest));
    final reply = await second.waitFor('join_accepted');
    expect(reply['rejoined'], isTrue);
    await ownerClient.close();
    await second.close();
  });

  test('third device cannot join a full room', () async {
    final owner = await newTestIdentity();
    final guestA = await newTestIdentity();
    final guestB = await newTestIdentity();
    final ownerClient = await WsClient.connect(port);
    await ownerClient.send(
        createRoomMsg(roomId: roomId, token: token, identity: owner));
    await ownerClient.waitFor('room_created');

    final a = await WsClient.connect(port);
    await a.send(joinRoomMsg(roomId: roomId, token: token, identity: guestA));
    await a.waitFor('join_accepted');

    // B presents a *different* token would be a different room; B here reuses
    // the same invite (consumed) or another room's invite; both must fail.
    final b = await WsClient.connect(port);
    await b.send(joinRoomMsg(roomId: roomId, token: token, identity: guestB));
    final err = (await b.waitFor('error'))['code'];
    expect(err == 'invite_consumed' || err == 'room_full', isTrue);
    await ownerClient.close();
    await a.close();
    await b.close();
  });

  test('join with wrong token is rejected', () async {
    final owner = await newTestIdentity();
    final guest = await newTestIdentity();
    final ownerClient = await WsClient.connect(port);
    await ownerClient.send(
        createRoomMsg(roomId: roomId, token: token, identity: owner));
    await ownerClient.waitFor('room_created');

    final g = await WsClient.connect(port);
    await g.send(joinRoomMsg(
      roomId: roomId,
      token: 'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz',
      identity: guest,
    ));
    expect((await g.waitFor('error'))['code'], 'invalid_invite');
    await ownerClient.close();
    await g.close();
  });

  test('join with stale invite epoch is rejected', () async {
    final owner = await newTestIdentity();
    final guest = await newTestIdentity();
    final ownerClient = await WsClient.connect(port);
    await ownerClient.send(createRoomMsg(
      roomId: roomId,
      token: token,
      identity: owner,
      inviteEpoch: 2,
    ));
    await ownerClient.waitFor('room_created');
    final g = await WsClient.connect(port);
    await g.send(joinRoomMsg(
      roomId: roomId,
      token: token,
      identity: guest,
      inviteEpoch: 1,
    ));
    expect((await g.waitFor('error'))['code'], 'invite_stale');
    await ownerClient.close();
    await g.close();
  });

  test('signals are forwarded only to the other peer of the same room',
      () async {
    final ownerA = await newTestIdentity();
    const roomA = 'dddddddd-2222-3333-4444-555555555555';
    const roomB = 'eeeeeeee-2222-3333-4444-555555555555';
    final guestA = await newTestIdentity();
    final ownerB = await newTestIdentity();
    final guestB = await newTestIdentity();
    const tokenA = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    const tokenB = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

    final aOwner = await WsClient.connect(port);
    await aOwner.send(
        createRoomMsg(roomId: roomA, token: tokenA, identity: ownerA));
    await aOwner.waitFor('room_created');
    final aGuest = await WsClient.connect(port);
    await aGuest.send(
        joinRoomMsg(roomId: roomA, token: tokenA, identity: guestA));
    await aGuest.waitFor('join_accepted');

    final bOwner = await WsClient.connect(port);
    await bOwner.send(
        createRoomMsg(roomId: roomB, token: tokenB, identity: ownerB));
    await bOwner.waitFor('room_created');
    final bGuest = await WsClient.connect(port);
    await bGuest.send(
        joinRoomMsg(roomId: roomB, token: tokenB, identity: guestB));
    await bGuest.waitFor('join_accepted');

    // Owner of room A sends an SDP offer.
    await aOwner.send({
      'type': 'signal',
      'kind': 'offer',
      'sdp': {'type': 'offer', 'sdp': 'v=0 o=- 1 1 IN IP4 127.0.0.1'},
    });
    final received =
        await aGuest.waitFor('signal', timeout: const Duration(seconds: 2));
    expect(received['kind'], 'offer');
    expect(received['from'], ownerA.deviceId);

    // Room B peers must receive nothing.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(bOwner.received.where((m) => m['type'] == 'signal'), isEmpty);
    expect(bGuest.received.where((m) => m['type'] == 'signal'), isEmpty);

    await aOwner.close();
    await aGuest.close();
    await bOwner.close();
    await bGuest.close();
  });

  test('cross-room signal injection cannot reach another room', () async {
    final ownerA = await newTestIdentity();
    const roomA = 'ffffffff-2222-3333-4444-555555555555';
    const roomB = '99999999-2222-3333-4444-555555555555';
    final ownerB = await newTestIdentity();
    const tokenA = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
    const tokenB = 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';

    final aOwner = await WsClient.connect(port);
    await aOwner.send(
        createRoomMsg(roomId: roomA, token: tokenA, identity: ownerA));
    await aOwner.waitFor('room_created');
    final bOwner = await WsClient.connect(port);
    await bOwner.send(
        createRoomMsg(roomId: roomB, token: tokenB, identity: ownerB));
    await bOwner.waitFor('room_created');

    // Owner A claims roomId of room B in the signal; server must not forward
    // it there (it is not a peer of room B anyway).
    await aOwner.send({
      'type': 'signal',
      'roomId': roomB,
      'kind': 'offer',
      'sdp': {'type': 'offer', 'sdp': 'v=0 fake'},
    });
    await aOwner.close();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(bOwner.received.where((m) => m['type'] == 'signal'), isEmpty);
    await bOwner.close();
  });

  test('signal before joining a room is rejected', () async {
    final c = await WsClient.connect(port);
    await c.send({
      'type': 'signal',
      'roomId': roomId,
      'kind': 'offer',
      'sdp': {'type': 'offer', 'sdp': 'v=0'},
    });
    expect((await c.waitFor('error'))['code'], 'not_in_room');
    await c.close();
  });

  test('signal with oversized SDP is rejected', () async {
    final owner = await newTestIdentity();
    final c = await WsClient.connect(port);
    await c.send(
        createRoomMsg(roomId: roomId, token: token, identity: owner));
    await c.waitFor('room_created');
    await c.send({
      'type': 'signal',
      'kind': 'offer',
      'sdp': {'type': 'offer', 'sdp': 'x' * 17000},
    });
    expect((await c.waitFor('error'))['code'], 'invalid_message');
    await c.close();
  });

  test('signal with mismatched kind/type is rejected', () async {
    final owner = await newTestIdentity();
    final c = await WsClient.connect(port);
    await c.send(
        createRoomMsg(roomId: roomId, token: token, identity: owner));
    await c.waitFor('room_created');
    await c.send({
      'type': 'signal',
      'kind': 'offer',
      'sdp': {'type': 'answer', 'sdp': 'v=0'},
    });
    expect((await c.waitFor('error'))['code'], 'invalid_message');
    await c.close();
  });

  test('malformed JSON is rejected without dropping the connection', () async {
    final c = await WsClient.connect(port);
    await c.sendRaw('{not json');
    expect((await c.waitFor('error'))['code'], 'invalid_message');
    // Connection still works.
    await c.send({'type': 'ping'});
    expect((await c.waitFor('pong'))['type'], 'pong');
    await c.close();
  });

  test('oversized raw frame is rejected as message_too_large', () async {
    final c = await WsClient.connect(port);
    await c.sendRaw('{"type":"ping","pad":"${'x' * 40000}"}');
    expect((await c.waitFor('error'))['code'], 'message_too_large');
    await c.close();
  });

  test('rate limiting kicks in under flood', () async {
    final c = await WsClient.connect(port);
    for (var i = 0; i < 80; i++) {
      await c.send({'type': 'ping'});
    }
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var sawRateLimited = false;
    while (DateTime.now().isBefore(deadline) && !sawRateLimited) {
      try {
        final m = await c.waitFor('error', timeout: const Duration(seconds: 5));
        if (m['code'] == 'rate_limited') sawRateLimited = true;
      } on TimeoutException {
        break;
      }
    }
    expect(sawRateLimited, isTrue);
    await c.close();
  });

  test('disband by owner closes the room and notifies members', () async {
    final owner = await newTestIdentity();
    final guest = await newTestIdentity();
    final ownerClient = await WsClient.connect(port);
    await ownerClient.send(
        createRoomMsg(roomId: roomId, token: token, identity: owner));
    await ownerClient.waitFor('room_created');
    final g = await WsClient.connect(port);
    await g.send(joinRoomMsg(roomId: roomId, token: token, identity: guest));
    await g.waitFor('join_accepted');

    await ownerClient.send({'type': 'disband', 'roomId': roomId});
    final disbanded = await g.waitFor('disbanded');
    expect(disbanded['roomId'], roomId);
    expect(server.roomCount, 0);
    await ownerClient.close();
    await g.close();
  });

  test('disband by non-owner is rejected', () async {
    final owner = await newTestIdentity();
    final guest = await newTestIdentity();
    final ownerClient = await WsClient.connect(port);
    await ownerClient.send(
        createRoomMsg(roomId: roomId, token: token, identity: owner));
    await ownerClient.waitFor('room_created');
    final g = await WsClient.connect(port);
    await g.send(joinRoomMsg(roomId: roomId, token: token, identity: guest));
    await g.waitFor('join_accepted');

    await g.send({'type': 'disband', 'roomId': roomId});
    expect((await g.waitFor('error'))['code'], 'permission_denied');
    expect(server.roomCount, 1);
    await ownerClient.close();
    await g.close();
  });

  test('member_left is broadcast when a peer drops', () async {
    final owner = await newTestIdentity();
    final guest = await newTestIdentity();
    final ownerClient = await WsClient.connect(port);
    await ownerClient.send(
        createRoomMsg(roomId: roomId, token: token, identity: owner));
    await ownerClient.waitFor('room_created');
    final g = await WsClient.connect(port);
    await g.send(joinRoomMsg(roomId: roomId, token: token, identity: guest));
    await g.waitFor('join_accepted');
    // Owner may have member_joined for the guest buffered; drain it.
    await ownerClient.waitFor('member_joined');
    await g.close();
    final left = await ownerClient.waitFor('member_left');
    expect(left['deviceId'], guest.deviceId);
    await ownerClient.close();
  });

  test('join with wrong public key/device pairing fails', () async {
    final owner = await newTestIdentity();
    final guest = await newTestIdentity();
    final other = await newTestIdentity();
    final ownerClient = await WsClient.connect(port);
    await ownerClient.send(
        createRoomMsg(roomId: roomId, token: token, identity: owner));
    await ownerClient.waitFor('room_created');
    final g = await WsClient.connect(port);
    await g.send({
      'type': 'join_room',
      'protocolVersion': 1,
      'roomId': roomId,
      'token': token,
      'deviceId': guest.deviceId,
      'publicKey': other.publicKeyBase64, // not bound to guest.deviceId
      'inviteEpoch': 1,
    });
    expect((await g.waitFor('error'))['code'], 'invalid_message');
    await ownerClient.close();
    await g.close();
  });

  test('signaling forwards displayName and avatar to members', () async {
    final owner = await newTestIdentity();
    final guest = await newTestIdentity();
    final ownerClient = await WsClient.connect(port);
    await ownerClient.send({
      ...createRoomMsg(roomId: roomId, token: token, identity: owner),
      'displayName': 'AliceHost',
      'avatar': 'preset:cyber',
    });
    await ownerClient.waitFor('room_created');

    final guestClient = await WsClient.connect(port);
    await guestClient.send({
      ...joinRoomMsg(roomId: roomId, token: token, identity: guest),
      'displayName': 'BobFriend',
      'avatar': 'preset:rose',
    });

    final accepted = await guestClient.waitFor('join_accepted');
    final members = (accepted['members'] as List).cast<Map>();
    expect(members.length, 2);
    final ownerEntry = members.firstWhere((m) => m['deviceId'] == owner.deviceId);
    expect(ownerEntry['displayName'], 'AliceHost');
    expect(ownerEntry['avatar'], 'preset:cyber');

    final joined = await ownerClient.waitFor('member_joined');
    expect(joined['deviceId'], guest.deviceId);
    expect(joined['displayName'], 'BobFriend');
    expect(joined['avatar'], 'preset:rose');

    await ownerClient.close();
    await guestClient.close();
  });
}
