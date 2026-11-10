import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

import 'canonical.dart';
import 'identity.dart';
import 'protocol.dart';

/// Invite wire format: `eir:v1:<base64url(canonical(payload))>.<base64url(sig)>`
///
/// The payload pins the signaling endpoint, room/session ids, the owner's
/// public key (hence the owner device id), the genesis hash, the invite
/// epoch, the token digest and an expiry. The payload is signed by the
/// owner with domain purpose 'invite'; possession of the invite therefore
/// authorizes requesting admission, but never grants admin rights.
///
/// The full token (32 random bytes, base64url) is carried inside the
/// signed payload; the server additionally stores only its digest.
class InviteData {
  InviteData({
    required this.signalingUrl,
    required this.roomId,
    required this.sessionId,
    required this.inviteEpoch,
    required this.token,
    required this.ownerPublicKey,
    required this.genesisHash,
    required this.expiresAtMs,
  });

  final String signalingUrl;
  final String roomId;
  final String sessionId;
  final int inviteEpoch;
  final String token;
  final String ownerPublicKey;
  final String genesisHash;
  final int expiresAtMs;

  String get ownerDeviceId => deviceIdFromPublicKey(ownerPublicKey);

  Map<String, Object?> toPayload() => <String, Object?>{
        'v': kProtocolVersion,
        'signaling': signalingUrl,
        'roomId': roomId,
        'sessionId': sessionId,
        'inviteEpoch': inviteEpoch,
        'token': token,
        'tokenDigest': tokenDigestHex(token),
        'ownerPublicKey': ownerPublicKey,
        'genesisHash': genesisHash,
        'expiresAtMs': expiresAtMs,
      };

  static InviteData fromPayload(Map<String, Object?> p) {
    if (p['v'] != kProtocolVersion) {
      throw InviteException('protocol_version');
    }
    final signaling = _reqString(p, 'signaling', maxLength: 512);
    final uri = Uri.tryParse(signaling);
    if (uri == null ||
        (uri.scheme != 'wss' && uri.scheme != 'ws') ||
        uri.host.isEmpty) {
      throw InviteException('invalid_invite');
    }
    final roomId = _reqString(p, 'roomId', maxLength: 64);
    if (!kUuidPattern.hasMatch(roomId)) {
      throw InviteException('invalid_invite');
    }
    final sessionId = _reqString(p, 'sessionId', maxLength: 64);
    if (!kUuidPattern.hasMatch(sessionId)) {
      throw InviteException('invalid_invite');
    }
    final epoch = _reqInt(p, 'inviteEpoch');
    final token = _reqString(p, 'token', maxLength: 128);
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw InviteException('invalid_invite');
    }
    final digest = _reqString(p, 'tokenDigest', maxLength: 64);
    if (!_ctEqual(digest, tokenDigestHex(token))) {
      throw InviteException('invalid_invite');
    }
    final ownerPublicKey = _reqString(p, 'ownerPublicKey', maxLength: 64);
    if (!_is32ByteB64(ownerPublicKey)) {
      throw InviteException('invalid_invite');
    }
    final genesisHash = _reqString(p, 'genesisHash', maxLength: 64);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(genesisHash)) {
      throw InviteException('invalid_invite');
    }
    final expiresAtMs = _reqInt(p, 'expiresAtMs');
    return InviteData(
      signalingUrl: signaling,
      roomId: roomId,
      sessionId: sessionId,
      inviteEpoch: epoch,
      token: token,
      ownerPublicKey: ownerPublicKey,
      genesisHash: genesisHash,
      expiresAtMs: expiresAtMs,
    );
  }
}

class InviteException implements Exception {
  InviteException(this.code);
  /// Stable machine-readable code (e.g. invalid_invite, invite_expired).
  final String code;
  @override
  String toString() => 'InviteException($code)';
}

String tokenDigestHex(String token) =>
    crypto.sha256.convert(utf8.encode(token)).toString();

String generateInviteToken({Random? random}) {
  final rnd = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String encodeInvite(
  InviteData invite,
  String ownerSignatureBase64Url,
) {
  final payloadBytes = canonicalBytes(invite.toPayload());
  final payloadB64 = base64UrlEncode(payloadBytes).replaceAll('=', '');
  return 'eir:v1:$payloadB64.$ownerSignatureBase64Url';
}

/// Parses and authenticates an invite string. Returns the invite when the
/// owner signature verifies and the expiry is in the future.
/// Throws [InviteException] otherwise. [nowMs] is injectable for tests.
Future<InviteData> decodeAndVerifyInvite(
  String text, {
  required DeviceIdentityStore identityStore,
  int? nowMs,
}) async {
  if (text.length > 4096) throw InviteException('invalid_invite');
  final match = RegExp(r'^eir:v1:([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)$').firstMatch(text);
  if (match == null) throw InviteException('invalid_invite');
  final payloadBytes = _b64UrlDecode(match.group(1)!);
  final signatureBytes = _b64UrlDecode(match.group(2)!);
  if (payloadBytes == null || signatureBytes == null) {
    throw InviteException('invalid_invite');
  }
  final Object? decoded;
  try {
    decoded = decodeCanonical(payloadBytes);
  } catch (_) {
    throw InviteException('invalid_invite');
  }
  if (decoded is! Map) throw InviteException('invalid_invite');
  final payload = Map<String, Object?>.from(decoded);
  final invite = InviteData.fromPayload(payload);
  final signed = await verifyDomain(
    'invite',
    invite.toPayload(),
    base64Encode(signatureBytes),
    invite.ownerPublicKey,
    identityStore: identityStore,
  );
  if (!signed) throw InviteException('invalid_invite');
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  if (invite.expiresAtMs <= now) throw InviteException('invite_expired');
  return invite;
}

/// Builds and signs an invite for [invite]. The owner key must match
/// [ownerPublicKey] inside the invite payload.
Future<String> buildSignedInvite(
  InviteData invite,
  DeviceKeyPair ownerKeyPair, {
  required DeviceIdentityStore identityStore,
}) async {
  if (ownerKeyPair.identity.publicKeyBase64 != invite.ownerPublicKey) {
    throw ArgumentError('invite ownerPublicKey must match the signing identity');
  }
  final signature = await signDomain(
    'invite',
    invite.toPayload(),
    ownerKeyPair,
    identityStore: identityStore,
  );
  final signatureBytes = base64Decode(signature);
  return encodeInvite(
    invite,
    base64UrlEncode(signatureBytes).replaceAll('=', ''),
  );
}

List<int>? _b64UrlDecode(String s) {
  try {
    var normalized = s.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return base64Decode(normalized);
  } catch (_) {
    return null;
  }
}

int _reqInt(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is! int || v.abs() > kMaxCanonicalInt) {
    throw InviteException('invalid_invite');
  }
  return v;
}

String _reqString(Map<String, Object?> m, String key, {int maxLength = 1024}) {
  final v = m[key];
  if (v is! String || v.isEmpty || v.length > maxLength) {
    throw InviteException('invalid_invite');
  }
  if (v.codeUnits.any((u) => u < 0x20 || u == 0x7f)) {
    throw InviteException('invalid_invite');
  }
  return v;
}

bool _is32ByteB64(String s) {
  try {
    return base64Decode(s).length == 32;
  } catch (_) {
    return false;
  }
}

bool _ctEqual(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
