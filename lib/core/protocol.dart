import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'canonical.dart';
import 'identity.dart';

const int kProtocolVersion = 1;

/// Maximum accepted size for a DataChannel control message (64 KiB per spec).
const int kMaxEnvelopeBytes = 64 * 1024;

/// Device ids are lowercase hex sha256 of the public key.
final RegExp kDeviceIdPattern = RegExp(r'^[0-9a-f]{64}$');

/// Message/type identifiers: lowercase snake, bounded.
final RegExp kTypePattern = RegExp(r'^[a-z0-9_]{1,32}$');

final RegExp kUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Domain-separated signing helper. [unsigned] must already satisfy the
/// restricted canonical value model (use [parseRestrictedMap] first).
Future<String> signDomain(
  String purpose,
  Object? unsigned,
  DeviceKeyPair keyPair, {
  required DeviceIdentityStore identityStore,
}) async {
  final bytes = domainSeparatedCanonical(purpose, unsigned);
  final signature = await identityStore.sign(keyPair.keyPair, bytes);
  return base64Encode(signature.bytes);
}

/// Verifies a domain-separated signature created with [signDomain].
/// Returns false on any structural or cryptographic problem.
Future<bool> verifyDomain(
  String purpose,
  Object? unsigned,
  String base64Signature,
  String publicKeyBase64, {
  required DeviceIdentityStore identityStore,
}) async {
  try {
    final signatureBytes = base64Decode(base64Signature);
    if (signatureBytes.length != 64) return false;
    final bytes = domainSeparatedCanonical(purpose, unsigned);
    return await identityStore.verify(publicKeyBase64, bytes, signatureBytes);
  } catch (_) {
    return false;
  }
}

/// Validates [raw] into a restricted canonical map; nested values are
/// type-checked and strings bounded. Throws [FormatException] otherwise.
Map<String, Object?> parseRestrictedMap(Map raw, String path) {
  final out = <String, Object?>{};
  raw.forEach((key, value) {
    if (key is! String) throw FormatException('$path key must be a string');
    out[key] = _asCanonicalValue(value, '$path.$key');
  });
  return validateCanonicalValue(out, path: path)! as Map<String, Object?>;
}

Object? _asCanonicalValue(Object? value, String path) {
  if (value == null || value is bool) return value;
  if (value is int) {
    if (value.abs() > kMaxCanonicalInt) {
      throw FormatException('integer out of range at $path');
    }
    return value;
  }
  if (value is double) {
    throw FormatException('floating point at $path is not allowed');
  }
  if (value is String) {
    if (value.codeUnits.any((u) => u < 0x20 || u == 0x7f)) {
      throw FormatException('control character at $path');
    }
    if (value.length > 32 * 1024) {
      throw FormatException('string at $path exceeds 32 KiB');
    }
    return value;
  }
  if (value is List) {
    if (value.length > 4096) {
      throw FormatException('list at $path exceeds 4096 elements');
    }
    return value.map((e) => _asCanonicalValue(e, path)).toList();
  }
  if (value is Map) return parseRestrictedMap(value, path);
  throw FormatException('unsupported type ${value.runtimeType} at $path');
}

String reqString(Map<String, Object?> m, String key, {int maxLength = 1024}) {
  final v = m[key];
  if (v is! String || v.isEmpty || v.length > maxLength) {
    throw FormatException('$key missing or invalid');
  }
  if (v.codeUnits.any((u) => u < 0x20 || u == 0x7f)) {
    throw FormatException('$key contains control characters');
  }
  return v;
}

int reqInt(Map<String, Object?> m, String key, {int min = 0, int? max}) {
  final v = m[key];
  if (v is! int) throw FormatException('$key missing or not an integer');
  if (v < min) throw FormatException('$key below minimum');
  if (v.abs() > kMaxCanonicalInt) throw FormatException('$key out of range');
  if (max != null && v > max) throw FormatException('$key above maximum');
  return v;
}

int? optInt(Map<String, Object?> m, String key, {int min = 0, int? max}) {
  if (m[key] == null) return null;
  return reqInt(m, key, min: min, max: max);
}

String? optString(Map<String, Object?> m, String key, {int maxLength = 1024}) {
  if (m[key] == null) return null;
  return reqString(m, key, maxLength: maxLength);
}

/// Reads a standard JSON-decoded map as a restricted canonical map.
Map<String, Object?> decodeRestrictedMapWire(String wire, {int maxBytes = kMaxEnvelopeBytes}) {
  if (wire.length > maxBytes) {
    throw FormatException('message exceeds $maxBytes bytes');
  }
  final decoded = jsonDecode(wire);
  if (decoded is! Map) {
    throw FormatException('message must decode to a map');
  }
  return parseRestrictedMap(decoded, '\$');
}

/// Device id derived from a public key: lowercase hex sha256.
String deviceIdFromPublicKey(String publicKeyBase64) {
  final pubBytes = base64Decode(publicKeyBase64);
  return crypto.sha256.convert(pubBytes).toString();
}

bool publicKeyMatchesDeviceId(String publicKeyBase64, String deviceId) {
  if (!kDeviceIdPattern.hasMatch(deviceId)) return false;
  try {
    final pubBytes = base64Decode(publicKeyBase64);
    if (pubBytes.length != 32) return false;
    return crypto.sha256.convert(pubBytes).toString() == deviceId;
  } catch (_) {
    return false;
  }
}

/// Genesis record: the trust root a room commits to. Not transmitted itself;
/// only its canonical hash propagates (inside invites and the commit chain).
Map<String, Object?> buildGenesis({
  required String roomId,
  required String sessionId,
  required String ownerPublicKey,
  required int createdAtMs,
}) {
  final genesis = <String, Object?>{
    'v': kProtocolVersion,
    'roomId': roomId,
    'sessionId': sessionId,
    'ownerPublicKey': ownerPublicKey,
    'createdAtMs': createdAtMs,
  };
  validateCanonicalValue(genesis, path: '\$genesis');
  return genesis;
}

String genesisHashHex(Map<String, Object?> genesis) => canonicalHashHex(genesis);

/// Room-scope gate for DataChannel control messages. Every authenticated
/// message carries the room and session identifiers set at room creation,
/// plus the sender identity. Signaling-level attacks (e.g. injecting media
/// frames into a different room, replayed traffic from another session, or
/// traffic from an unverified source) fail this check before any parsing,
/// canonical re-encoding, signature verification or service routing.
///
/// When [expectedSenderId] is non-null the sender must match exactly;
/// media-plane messages additionally require it (the peer identity is only
/// trusted after a fingerprint-bound handshake).
bool isRoomScopedMessage(
  Map<String, Object?> msg, {
  required String roomId,
  required String sessionId,
  required String? expectedSenderId,
}) {
  if (msg['protocolVersion'] != kProtocolVersion) return false;
  if (msg['roomId'] != roomId) return false;
  if (msg['sessionId'] != sessionId) return false;
  if (expectedSenderId != null && msg['senderId'] != expectedSenderId) {
    return false;
  }
  return true;
}
