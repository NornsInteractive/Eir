// Eir signaling server.
//
// Memory-only: room state lives in this process and is wiped on restart.
// The server is NOT trusted for content; it only enforces membership,
// capacity, size, rate and room-scoping rules. Authorization is enforced
// by the peers via signed messages (see lib/core/protocol.dart).
//
// Guarantees:
//  * one room per roomId; creating over an existing roomId is rejected
//    (except the idempotent same-owner/same-genesis retry);
//  * invites are consumed atomically: the first joiner under a token binds
//    it; a different deviceId re-using the token is rejected; the same
//    deviceId re-joining is idempotent;
//  * at most 2 peers per room;
//  * signaling frames are size-capped, JSON-only and rate-limited per
//    connection; `signal` frames are forwarded only to the *other* peers
//    of the same room, never across rooms, and only whitelisted fields;
//  * the owner (connection that created the room) may disband it, which
//    closes the room and notifies the member;
//  * no tokens, SDPs or invite contents are logged.
//
// Run: dart server/signaling_server.dart [port] [host]
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;

const int kProtocolVersion = 1;
const int kMaxMessageBytes = 32 * 1024;
const int kMaxSdpBytes = 16 * 1024;
const int kMaxCandidateBytes = 2 * 1024;
const int kMaxIceCandidatesPerPeer = 96;
const int kMaxRooms = 256;
const int kMaxPeersPerRoom = 2;
const int kRateBurst = 60;
const int kRateRefillPerSecond = 20;
const int kMaxDisplayNameBytes = 64;
const int kMaxAvatarBytes = 128;

final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');
final RegExp _deviceIdPattern = RegExp(r'^[0-9a-f]{64}$');

class SignalingServer {
  HttpServer? _http;
  final Map<String, _Room> _rooms = <String, _Room>{};
  final Map<String, String> _codeToRoomId = <String, String>{};
  final Map<String, String> _roomIdToCode = <String, String>{};
  final Map<String, Timer> _roomReapTimers = <String, Timer>{};
  static const Duration kReapGracePeriod = Duration(minutes: 5);
  bool _stopping = false;
  String? webRoot;

  int get port => _http?.port ?? 0;
  int get roomCount => _rooms.length;

  void _scheduleRoomReap(String roomId) {
    _cancelRoomReap(roomId);
    _roomReapTimers[roomId] = Timer(kReapGracePeriod, () {
      _roomReapTimers.remove(roomId);
      final room = _rooms[roomId];
      if (room != null && room.peers.isEmpty) {
        _removeRoom(roomId);
      }
    });
  }

  void _cancelRoomReap(String roomId) {
    _roomReapTimers.remove(roomId)?.cancel();
  }

  String _generateRoomCode() {
    final rnd = math.Random();
    for (var i = 0; i < 10000; i++) {
      final code = (100000 + rnd.nextInt(900000)).toString();
      if (!_codeToRoomId.containsKey(code)) {
        return code;
      }
    }
    return (100000 + rnd.nextInt(900000)).toString();
  }

  static final Map<String, String> _mimeTypes = <String, String>{
    '.html': 'text/html; charset=utf-8',
    '.htm': 'text/html; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.mjs': 'application/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.wasm': 'application/wasm',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.mp4': 'video/mp4',
    '.ogg': 'audio/ogg',
    '.otf': 'font/otf',
    '.ttf': 'font/ttf',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
  };

  Future<void> start({
    InternetAddress? address,
    int port = 8080,
    String? webRoot,
  }) async {
    this.webRoot = webRoot;
    final addr = address ?? InternetAddress.anyIPv4;
    _http = await HttpServer.bind(addr, port);
    _stopping = false;
    _http!.listen(_onRequest, onError: (_) {}, cancelOnError: false);
  }

  /// Stops the server.
  ///
  /// With [graceful] true (default) peers are notified with a `disbanded`
  /// frame before their sockets close (normal shutdown). With [graceful] false
  /// peer sockets are dropped **without** a `disbanded` frame, simulating an
  /// abrupt crash/restart: clients keep their room/identity state and can
  /// reconnect to the same URL, which is exactly the A15 restart scenario.
  Future<void> stop({bool graceful = true}) async {
    _stopping = true;
    final rooms = List<_Room>.from(_rooms.values);
    if (graceful) {
      for (final room in rooms) {
        await _closeRoom(room, 'server_stopping');
      }
    } else {
      for (final room in rooms) {
        for (final peer in room.peers.values.toList()) {
          try {
            await peer.conn.close(1001, 'server_restart');
          } catch (_) {}
        }
        room.peers.clear();
      }
      _rooms.clear();
    }
    final http = _http;
    _http = null;
    if (http != null) {
      await http.close(force: true);
    }
  }

  Future<void> _onRequest(HttpRequest req) async {
    if (_stopping) {
      await _reject(req, HttpStatus.serviceUnavailable, 'server_stopping');
      return;
    }
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      if (_rooms.length >= kMaxRooms) {
        await _reject(req, HttpStatus.tooManyRequests, 'server_full');
        return;
      }
      final socket = await WebSocketTransformer.upgrade(req);
      _PeerConnection(this, socket).start();
      return;
    }
    final root = webRoot;
    if (root != null) {
      await _serveStatic(req, root);
      return;
    }
    await _reject(req, HttpStatus.notFound, 'not_found');
  }

  void _applyCommonHeaders(HttpResponse res) {
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', '*');
    res.headers.set('Cross-Origin-Opener-Policy', 'same-origin');
    res.headers.set('Cross-Origin-Embedder-Policy', 'credentialless');
    res.headers.set('Cache-Control', 'no-cache');
  }

  Future<void> _serveStatic(HttpRequest req, String root) async {
    final res = req.response;
    _applyCommonHeaders(res);

    if (req.method == 'OPTIONS') {
      res.statusCode = HttpStatus.ok;
      await res.close();
      return;
    }

    if (req.method != 'GET' && req.method != 'HEAD') {
      res.statusCode = HttpStatus.methodNotAllowed;
      await res.close();
      return;
    }

    // Resolve and sanitize path (prevent path traversal like '..')
    final decodedPath = Uri.decodeFull(req.uri.path);
    if (decodedPath.contains('..') || req.uri.pathSegments.any((s) => s.contains('..'))) {
      res.statusCode = HttpStatus.forbidden;
      await res.close();
      return;
    }

    final normalizedSegments = <String>[];
    for (final seg in req.uri.pathSegments) {
      if (seg.isEmpty || seg == '.') continue;
      normalizedSegments.add(seg);
    }

    String relPath = normalizedSegments.join(Platform.pathSeparator);
    if (relPath.isEmpty) {
      relPath = 'index.html';
    }

    final rootDir = Directory(root).absolute;
    var targetFile = File('${rootDir.path}${Platform.pathSeparator}$relPath').absolute;
    if (!targetFile.path.startsWith(rootDir.path)) {
      res.statusCode = HttpStatus.forbidden;
      await res.close();
      return;
    }
    if (await FileSystemEntity.isDirectory(targetFile.path)) {
      targetFile = File('${targetFile.path}${Platform.pathSeparator}index.html');
    }

    if (!await targetFile.exists()) {
      // Single Page Application (SPA) fallback: serve index.html for extensionless routes
      final lastSegment = normalizedSegments.isNotEmpty ? normalizedSegments.last : '';
      if (!lastSegment.contains('.')) {
        final indexFile = File('${rootDir.path}${Platform.pathSeparator}index.html');
        if (await indexFile.exists()) {
          targetFile = indexFile;
        } else {
          res.statusCode = HttpStatus.notFound;
          await res.close();
          return;
        }
      } else {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
    }

    final ext = targetFile.path.contains('.')
        ? targetFile.path.substring(targetFile.path.lastIndexOf('.')).toLowerCase()
        : '';
    final mime = _mimeTypes[ext] ?? 'application/octet-stream';
    res.headers.set(HttpHeaders.contentTypeHeader, mime);

    final length = await targetFile.length();
    res.headers.set(HttpHeaders.contentLengthHeader, length);

    if (req.method == 'HEAD') {
      await res.close();
      return;
    }

    await targetFile.openRead().pipe(res);
  }

  Future<void> _reject(HttpRequest req, int status, String code) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(<String, Object?>{'error': code}));
    await req.response.close();
  }

  void _handleCreateRoom(_PeerConnection conn, Map<String, Object?> msg) {
    final err = _checkCreateRoom(conn, msg);
    if (err != null) {
      conn.sendError(err);
      return;
    }
    final roomId = msg['roomId']! as String;
    final token = msg['token']! as String;
    final deviceId = msg['deviceId']! as String;
    final existing = _rooms[roomId];
    if (existing != null) {
      // Idempotent retry for the same owner + genesis; anything else is a takeover.
      if (existing.ownerDeviceId == deviceId &&
          existing.genesisHash == msg['genesisHash'] &&
          existing.sessionId == msg['sessionId']) {
        _cancelRoomReap(roomId);
        existing.attach(conn, deviceId);
        conn.roomId = roomId;
        conn.deviceId = deviceId;
        conn.send(<String, Object?>{
          'type': 'room_created',
          'roomId': roomId,
          'roomCode': existing.roomCode ?? _roomIdToCode[roomId],
          'sessionId': existing.sessionId,
          'inviteEpoch': existing.inviteEpoch,
          'rejoined': true,
        });
        return;
      }
      conn.sendError('room_exists');
      return;
    }
    if (_rooms.length >= kMaxRooms) {
      conn.sendError('server_full');
      return;
    }
    final digest = _sha256Hex(token);
    final requestedCode = (msg['roomCode'] as String?)?.trim();
    final roomCode = (requestedCode != null &&
            RegExp(r'^\d{6}$').hasMatch(requestedCode) &&
            !_codeToRoomId.containsKey(requestedCode))
        ? requestedCode
        : _generateRoomCode();
    _codeToRoomId[roomCode] = roomId;
    _roomIdToCode[roomId] = roomCode;

    final room = _Room(
      roomId: roomId,
      tokenDigest: digest,
      ownerDeviceId: deviceId,
      ownerPublicKey: msg['ownerPublicKey']! as String,
      sessionId: msg['sessionId']! as String,
      genesisHash: msg['genesisHash']! as String,
      inviteEpoch: (msg['inviteEpoch'] as int?) ?? 1,
      roomCode: roomCode,
      rawToken: token,
    );
    _rooms[roomId] = room;
    final displayName = _cleanDisplayName(msg['displayName']);
    final avatar = _cleanAvatar(msg['avatar']);
    room.attach(conn, deviceId, displayName: displayName, avatar: avatar);
    conn.roomId = roomId;
    conn.deviceId = deviceId;
    conn.role = 'owner';
    conn.publicKey = msg['ownerPublicKey'] as String?;
    conn.displayName = displayName;
    conn.avatar = avatar;
    conn.joinedAt = DateTime.now().millisecondsSinceEpoch;
    conn.send(<String, Object?>{
      'type': 'room_created',
      'roomId': roomId,
      'roomCode': roomCode,
      'sessionId': room.sessionId,
      'inviteEpoch': room.inviteEpoch,
    });
  }

  void _handleQueryRoomCode(_PeerConnection conn, Map<String, Object?> msg) {
    final code = (msg['roomCode'] as String?)?.trim();
    if (code == null || code.isEmpty) {
      conn.sendError('invalid_message');
      return;
    }
    final roomId = _codeToRoomId[code];
    if (roomId == null) {
      conn.sendError('room_not_found');
      return;
    }
    final room = _rooms[roomId];
    if (room == null) {
      conn.sendError('room_not_found');
      return;
    }
    conn.send(<String, Object?>{
      'type': 'room_code_info',
      'roomCode': code,
      'roomId': roomId,
      'sessionId': room.sessionId,
      'ownerPublicKey': room.ownerPublicKey,
      'genesisHash': room.genesisHash,
      'inviteEpoch': room.inviteEpoch,
      'token': room.rawToken,
    });
  }

  void _handleJoinRoom(_PeerConnection conn, Map<String, Object?> msg) {
    var roomId = msg['roomId'] as String?;
    if ((roomId == null || roomId.isEmpty) && msg['roomCode'] is String) {
      final code = (msg['roomCode'] as String).trim();
      roomId = _codeToRoomId[code];
    }
    var token = msg['token'] as String?;
    if (token == null && roomId != null && _rooms.containsKey(roomId)) {
      token = _rooms[roomId]?.rawToken;
    }
    final deviceId = msg['deviceId'] as String?;
    final publicKey = msg['publicKey'] as String?;
    final epoch = (msg['inviteEpoch'] as int?) ?? (roomId != null ? _rooms[roomId]?.inviteEpoch : 1);
    final protocolVersion = msg['protocolVersion'] as int?;
    if (protocolVersion != kProtocolVersion) {
      conn.sendError('protocol_version');
      return;
    }
    if (roomId == null || !_uuidV4.hasMatch(roomId)) {
      conn.sendError('invalid_message');
      return;
    }
    if (token == null || !_tokenPattern.hasMatch(token)) {
      conn.sendError('invalid_invite');
      return;
    }
    if (deviceId == null || !_deviceIdPattern.hasMatch(deviceId)) {
      conn.sendError('invalid_message');
      return;
    }
    if (publicKey == null || !_publicKeyMatches(publicKey, deviceId)) {
      conn.sendError('invalid_message');
      return;
    }
    final room = _rooms[roomId];
    if (room == null) {
      conn.sendError('room_not_found');
      return;
    }
    _cancelRoomReap(roomId);
    if (epoch != room.inviteEpoch) {
      conn.sendError('invite_stale');
      return;
    }
    if (!_ctEqualHex(room.tokenDigest, _sha256Hex(token))) {
      conn.sendError('invalid_invite');
      return;
    }
    if (room.peers.containsKey(deviceId)) {
      // Same identity re-joining (e.g. after a network drop): idempotent.
      final displayName = _cleanDisplayName(msg['displayName']);
      final avatar = _cleanAvatar(msg['avatar']);
      room.attach(conn, deviceId, displayName: displayName, avatar: avatar);
      conn.roomId = roomId;
      conn.deviceId = deviceId;
      conn.displayName = displayName ?? conn.displayName;
      conn.avatar = avatar ?? conn.avatar;
      conn.send(<String, Object?>{
        'type': 'join_accepted',
        'roomId': roomId,
        'sessionId': room.sessionId,
        'genesisHash': room.genesisHash,
        'ownerPublicKey': room.ownerPublicKey,
        'inviteEpoch': room.inviteEpoch,
        'rejoined': true,
        'members': room.membersList(),
      });
      room.broadcast(<String, Object?>{
        'type': 'member_joined',
        'roomId': roomId,
        'deviceId': deviceId,
        'publicKey': conn.publicKey,
        'displayName': conn.displayName ?? '',
        'avatar': conn.avatar ?? '',
        'joinedAt': conn.joinedAt,
        'rejoined': true,
      }, exceptDeviceId: deviceId);
      return;
    }
    if (room.inviteConsumedBy != null && room.inviteConsumedBy != deviceId) {
      conn.sendError('invite_consumed');
      return;
    }
    if (room.peers.length >= kMaxPeersPerRoom) {
      conn.sendError('room_full');
      return;
    }
    // Atomically consume the invite for this identity.
    room.inviteConsumedBy ??= deviceId;
    final displayName = _cleanDisplayName(msg['displayName']);
    final avatar = _cleanAvatar(msg['avatar']);
    room.attach(conn, deviceId, displayName: displayName, avatar: avatar);
    conn.roomId = roomId;
    conn.deviceId = deviceId;
    conn.role = (deviceId == room.ownerDeviceId) ? 'owner' : 'member';
    conn.publicKey = msg['publicKey'] as String?;
    conn.displayName = displayName;
    conn.avatar = avatar;
    conn.joinedAt = DateTime.now().millisecondsSinceEpoch;
    final wasConsumedBySelf = room.inviteConsumedBy == deviceId;
    conn.send(<String, Object?>{
      'type': 'join_accepted',
      'roomId': roomId,
      'sessionId': room.sessionId,
      'genesisHash': room.genesisHash,
      'ownerPublicKey': room.ownerPublicKey,
      'inviteEpoch': room.inviteEpoch,
      'rejoined': wasConsumedBySelf,
      'members': room.membersList(),
    });
    room.broadcast(<String, Object?>{
      'type': 'member_joined',
      'roomId': roomId,
      'deviceId': deviceId,
      'publicKey': conn.publicKey,
      'displayName': conn.displayName ?? '',
      'avatar': conn.avatar ?? '',
      'joinedAt': conn.joinedAt,
      'rejoined': false,
    }, exceptDeviceId: deviceId);
  }

  void _handleSignal(_PeerConnection conn, Map<String, Object?> msg) {
    final room = _roomOf(conn);
    if (room == null || conn.deviceId == null) {
      conn.sendError('not_in_room');
      return;
    }
    final kind = msg['kind'];
    if (kind != 'offer' && kind != 'answer' && kind != 'ice' && kind != 'room_msg' && kind != 'tailcat_addr') {
      conn.sendError('invalid_message');
      return;
    }
    Map<String, Object?> outbound;
    if (kind == 'offer' || kind == 'answer') {
      final sdp = msg['sdp'];
      if (sdp is! Map) {
        conn.sendError('invalid_message');
        return;
      }
      final type = sdp['type'];
      final body = sdp['sdp'];
      if (type is! String ||
          type != kind ||
          body is! String ||
          body.isEmpty ||
          body.length > kMaxSdpBytes) {
        conn.sendError('invalid_message');
        return;
      }
      outbound = <String, Object?>{
        'type': 'signal',
        'roomId': room.roomId,
        'from': conn.deviceId,
        'kind': kind,
        'sdp': <String, Object?>{'type': type, 'sdp': body},
      };
    } else if (kind == 'tailcat_addr') {
      final addr = msg['addr'];
      if (addr is! String || addr.isEmpty || addr.length > 2048) {
        conn.sendError('invalid_message');
        return;
      }
      outbound = <String, Object?>{
        'type': 'signal',
        'roomId': room.roomId,
        'from': conn.deviceId,
        'kind': 'tailcat_addr',
        'addr': addr,
      };
    } else if (kind == 'room_msg') {
      final payload = msg['payload'];
      if (payload is! Map) {
        conn.sendError('invalid_message');
        return;
      }
      outbound = <String, Object?>{
        'type': 'signal',
        'roomId': room.roomId,
        'from': conn.deviceId,
        'kind': 'room_msg',
        'payload': payload,
      };
    } else {
      // ice
      final cand = msg['candidate'];
      if (cand is! Map) {
        conn.sendError('invalid_message');
        return;
      }
      conn.iceCount += 1;
      if (conn.iceCount > kMaxIceCandidatesPerPeer) {
        conn.sendError('rate_limited');
        return;
      }
      final candidate = cand['candidate'];
      if (candidate is! String || candidate.length > kMaxCandidateBytes) {
        conn.sendError('invalid_message');
        return;
      }
      final sdpMid = cand['sdpMid'];
      final sdpMLineIndex = cand['sdpMLineIndex'];
      if (sdpMid != null && sdpMid is! String) {
        conn.sendError('invalid_message');
        return;
      }
      if (sdpMLineIndex != null && sdpMLineIndex is! int && sdpMLineIndex is! double) {
        conn.sendError('invalid_message');
        return;
      }
      outbound = <String, Object?>{
        'type': 'signal',
        'roomId': room.roomId,
        'from': conn.deviceId,
        'kind': 'ice',
        'candidate': <String, Object?>{
          'candidate': candidate,
          'sdpMid': sdpMid,
          'sdpMLineIndex': sdpMLineIndex,
        },
      };
    }
    // Forward only within the room, never echo, never across rooms.
    room.broadcast(outbound, exceptDeviceId: conn.deviceId);
  }

  void _handleLeave(_PeerConnection conn) {
    final room = _roomOf(conn);
    final deviceId = conn.deviceId;
    conn.roomId = null;
    conn.deviceId = null;
    if (room == null || deviceId == null) return;
    final wasOwner = room.ownerDeviceId == deviceId;
    room.remove(deviceId, conn);
    room.broadcast(<String, Object?>{
      'type': 'member_left',
      'roomId': room.roomId,
      'deviceId': deviceId,
    });
    if (wasOwner && room.peers.isNotEmpty) {
      final candidates = room.peers.values.toList();
      candidates.sort((a, b) {
        final aAdmin = a.conn.role == 'admin' ? 1 : 0;
        final bAdmin = b.conn.role == 'admin' ? 1 : 0;
        if (aAdmin != bAdmin) return bAdmin.compareTo(aAdmin);
        return a.conn.joinedAt.compareTo(b.conn.joinedAt);
      });
      final successor = candidates.first;
      successor.conn.role = 'owner';
      room.ownerDeviceId = successor.conn.deviceId!;
      if (successor.conn.publicKey != null) {
        room.ownerPublicKey = successor.conn.publicKey!;
      }
      room.broadcast(<String, Object?>{
        'type': 'owner_changed',
        'roomId': room.roomId,
        'newOwnerDeviceId': successor.conn.deviceId,
        'previousOwnerDeviceId': deviceId,
      });
    }
    _maybeReapRoom(room);
  }

  void _handleDisband(_PeerConnection conn) {
    final room = _roomOf(conn);
    if (room == null || conn.deviceId == null) {
      conn.sendError('not_in_room');
      return;
    }
    if (room.ownerDeviceId != conn.deviceId) {
      conn.sendError('permission_denied');
      return;
    }
    _closeRoom(room, 'disbanded');
  }

  _Room? _roomOf(_PeerConnection conn) {
    final id = conn.roomId;
    if (id == null) return null;
    return _rooms[id];
  }

  void _removeRoom(String roomId) {
    _cancelRoomReap(roomId);
    _rooms.remove(roomId);
    final code = _roomIdToCode.remove(roomId);
    if (code != null) _codeToRoomId.remove(code);
  }

  void _maybeReapRoom(_Room room) {
    if (room.peers.isEmpty) {
      _scheduleRoomReap(room.roomId);
    }
  }

  Future<void> _closeRoom(_Room room, String reason) async {
    _removeRoom(room.roomId);
    for (final peer in room.peers.values.toList()) {
      try {
        peer.conn.send(<String, Object?>{
          'type': 'disbanded',
          'roomId': room.roomId,
          'reason': reason,
        });
        await peer.conn.close(1000, reason);
      } catch (_) {}
    }
    room.peers.clear();
  }

  void _onPeerClosed(_PeerConnection conn) {
    _handleLeave(conn);
  }

  String? _checkCreateRoom(_PeerConnection conn, Map<String, Object?> msg) {
    final protocolVersion = msg['protocolVersion'] as int?;
    if (protocolVersion != kProtocolVersion) return 'protocol_version';
    final roomId = msg['roomId'];
    if (roomId is! String || !_uuidV4.hasMatch(roomId)) {
      return 'invalid_message';
    }
    final token = msg['token'];
    if (token is! String || !_tokenPattern.hasMatch(token)) {
      return 'invalid_message';
    }
    final deviceId = msg['deviceId'];
    if (deviceId is! String || !_deviceIdPattern.hasMatch(deviceId)) {
      return 'invalid_message';
    }
    final publicKey = msg['ownerPublicKey'];
    if (publicKey is! String || !_publicKeyMatches(publicKey, deviceId)) {
      return 'invalid_message';
    }
    final sessionId = msg['sessionId'];
    if (sessionId is! String || !_uuidV4.hasMatch(sessionId)) {
      return 'invalid_message';
    }
    final genesisHash = msg['genesisHash'];
    if (genesisHash is! String || !_hex64.hasMatch(genesisHash)) {
      return 'invalid_message';
    }
    final epoch = msg['inviteEpoch'];
    if (epoch != null && (epoch is! int || epoch < 1 || epoch > (1 << 31))) {
      return 'invalid_message';
    }
    return null;
  }
}

String _sha256Hex(String input) =>
    crypto.sha256.convert(utf8.encode(input)).toString();

bool _ctEqualHex(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

bool _publicKeyMatches(String publicKeyBase64, String deviceId) {
  try {
    final pub = base64Decode(publicKeyBase64);
    if (pub.length != 32) return false;
    return crypto.sha256.convert(pub).toString() == deviceId;
  } catch (_) {
    return false;
  }
}

String? _cleanDisplayName(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final bytes = utf8.encode(trimmed);
  if (bytes.length > kMaxDisplayNameBytes) return null;
  if (trimmed.codeUnits.any((u) => u < 0x20 || u == 0x7f)) return null;
  return trimmed;
}

String? _cleanAvatar(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final bytes = utf8.encode(trimmed);
  if (bytes.length > kMaxAvatarBytes) return null;
  if (trimmed.codeUnits.any((u) => u < 0x20 || u == 0x7f)) return null;
  return trimmed;
}

class _Room {
  _Room({
    required this.roomId,
    required this.tokenDigest,
    required this.ownerDeviceId,
    required this.ownerPublicKey,
    required this.sessionId,
    required this.genesisHash,
    this.inviteEpoch = 1,
    this.roomCode,
    this.rawToken,
  });

  final String roomId;
  final String tokenDigest;
  String ownerDeviceId;
  String ownerPublicKey;
  final String sessionId;
  final String genesisHash;
  int inviteEpoch;
  String? roomCode;
  String? rawToken;
  /// Identity that consumed the single-use invite, if any.
  String? inviteConsumedBy;
  final Map<String, _RoomPeer> peers = <String, _RoomPeer>{};

  void attach(_PeerConnection conn, String deviceId, {String? displayName, String? avatar}) {
    final existing = peers[deviceId];
    if (existing != null && !identical(existing.conn, conn)) {
      // Replace a dropped connection held by the same identity.
      try {
        existing.conn.close(1000, 'replaced_by_new_connection');
      } catch (_) {}
    }
    peers[deviceId] = _RoomPeer(conn, displayName, avatar: avatar);
  }

  void remove(String deviceId, _PeerConnection conn) {
    final peer = peers[deviceId];
    if (peer != null && identical(peer.conn, conn)) {
      peers.remove(deviceId);
    }
  }

  List<Map<String, Object?>> membersList() => peers.entries
      .map((e) => <String, Object?>{
            'deviceId': e.key,
            'role': e.value.conn.role,
            'displayName': e.value.displayName ?? '',
            'avatar': e.value.avatar ?? '',
            'joinedAt': e.value.conn.joinedAt,
          })
      .toList();

  void broadcast(Map<String, Object?> message, {String? exceptDeviceId}) {
    final wire = jsonEncode(message);
    for (final entry in peers.entries) {
      if (entry.key == exceptDeviceId) continue;
      try {
        entry.value.conn.sendWire(wire);
      } catch (_) {}
    }
  }
}

class _RoomPeer {
  _RoomPeer(this.conn, this.displayName, {this.avatar});
  final _PeerConnection conn;
  final String? displayName;
  final String? avatar;
}

class _PeerConnection {
  _PeerConnection(this.server, this.socket);

  final SignalingServer server;
  final WebSocket socket;

  String? roomId;
  String? deviceId;
  int iceCount = 0;
  int joinedAt = DateTime.now().millisecondsSinceEpoch;
  String role = 'member';
  String? publicKey;
  String? displayName;
  String? avatar;

  int _tokens = kRateBurst;
  DateTime _lastRefill = DateTime.now();
  int _rateLimitStrikes = 0;

  void start() {
    socket.pingInterval = const Duration(seconds: 25);
    socket.listen(
      _onData,
      onDone: _onDone,
      onError: (_) => _onDone(),
      cancelOnError: true,
    );
  }

  void _onData(dynamic data) {
    if (data is! String) {
      sendError('invalid_message');
      return;
    }
    if (!_allowRequest()) {
      sendError('rate_limited');
      _rateLimitStrikes += 1;
      if (_rateLimitStrikes >= 3) {
        close(1008, 'rate_limited');
      }
      return;
    }
    _rateLimitStrikes = 0;
    if (data.length > kMaxMessageBytes) {
      sendError('message_too_large');
      return;
    }
    final Map<String, Object?> msg;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) {
        sendError('invalid_message');
        return;
      }
      msg = Map<String, Object?>.from(decoded);
    } catch (_) {
      sendError('invalid_message');
      return;
    }
    final type = msg['type'];
    if (type is! String) {
      sendError('invalid_message');
      return;
    }
    switch (type) {
      case 'create_room':
        server._handleCreateRoom(this, msg);
        break;
      case 'query_room_code':
        server._handleQueryRoomCode(this, msg);
        break;
      case 'join_room':
        server._handleJoinRoom(this, msg);
        break;
      case 'signal':
        server._handleSignal(this, msg);
        break;
      case 'leave':
        server._handleLeave(this);
        break;
      case 'disband':
        server._handleDisband(this);
        break;
      case 'ping':
        send(<String, Object?>{'type': 'pong'});
        break;
      default:
        sendError('invalid_message');
    }
  }

  bool _allowRequest() {
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastRefill).inMilliseconds;
    if (elapsedMs >= 1000) {
      final refill = (elapsedMs ~/ 1000) * kRateRefillPerSecond;
      _tokens = (_tokens + refill).clamp(0, kRateBurst);
      _lastRefill = now;
    }
    if (_tokens <= 0) return false;
    _tokens -= 1;
    return true;
  }

  void send(Map<String, Object?> message) {
    sendWire(jsonEncode(message));
  }

  void sendWire(String wire) {
    try {
      socket.add(wire);
    } catch (_) {}
  }

  void sendError(String code) {
    send(<String, Object?>{'type': 'error', 'code': code});
  }

  void _onDone() {
    server._onPeerClosed(this);
  }

  Future<void> close(int code, String reason) async {
    try {
      await socket.close(code, reason);
    } catch (_) {}
  }
}

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args[0]) : 8080;
  if (port == null || port < 0 || port > 65535) {
    stderr.writeln('usage: signaling_server.dart [port] [host] [webRoot]');
    exitCode = 64;
    return;
  }
  final host = args.length > 1 ? args[1] : null;
  final webRoot = args.length > 2
      ? args[2]
      : (Directory('build/web').existsSync()
          ? 'build/web'
          : (Directory('/tmp/eir-web-latest-20261108').existsSync()
              ? '/tmp/eir-web-latest-20261108'
              : null));
  final server = SignalingServer();
  InternetAddress bindAddr;
  if (host == null || host == '::' || host == 'anyIPv6') {
    bindAddr = InternetAddress.anyIPv6;
  } else if (host == 'anyIPv4' || host == '0.0.0.0') {
    bindAddr = InternetAddress.anyIPv4;
  } else {
    bindAddr = InternetAddress(host);
  }
  await server.start(
    address: bindAddr,
    port: port,
    webRoot: webRoot,
  );
  if (webRoot != null) {
    stdout.writeln('eir unified server (web + signaling) listening on ${server.port} (webRoot: $webRoot)');
  } else {
    stdout.writeln('eir signaling server listening on ${server.port}');
  }
}
