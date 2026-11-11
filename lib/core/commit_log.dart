import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'canonical.dart';
import 'protocol.dart';

/// Default commit payload guard values.
const int kMaxCommitParamsBytes = 48 * 1024;
const int kMaxPendingCommits = 32;
const int kMaxTrackedRequestIds = 512;

final RegExp _actionPattern = RegExp(r'^[a-z0-9_]{1,32}$');
final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _cleanToken = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

/// A ROOM_COMMIT message. Signed by the room owner only. Rides the
/// DataChannel as JSON; the signed byte string is the restricted canonical
/// encoding of the unsigned map (fields below minus `signature`).
///
/// The wire map adds a `type: 'commit'` discriminator for routing; the
/// discriminator is NOT part of the signed payload (purpose domain
/// separation `room_commit` already binds it). `fromWireJson` strips it.
class RoomCommit {
  RoomCommit({
    required this.seq,
    required this.prevHash,
    required this.requestId,
    required this.aclVersion,
    required this.action,
    required this.params,
    required this.effectiveSharedMs,
    required this.roomId,
    required this.sessionId,
    this.signature,
  });

  final int seq;
  final String prevHash;
  final String? requestId;
  final int aclVersion;
  final String action;
  final Map<String, Object?> params;
  final int effectiveSharedMs;
  final String roomId;
  final String sessionId;
  final String? signature;

  Map<String, Object?> toUnsignedMap() => <String, Object?>{
        'protocolVersion': kProtocolVersion,
        'seq': seq,
        'prevHash': prevHash,
        'requestId': requestId,
        'aclVersion': aclVersion,
        'action': action,
        'params': params,
        'effectiveSharedMs': effectiveSharedMs,
        'roomId': roomId,
        'sessionId': sessionId,
      };

  Map<String, Object?> toMap() => <String, Object?>{
        ...toUnsignedMap(),
        if (signature != null) 'signature': signature,
      };

  /// Wire form including the routing discriminator.
  Map<String, Object?> toWireMap() => <String, Object?>{
        'type': 'commit',
        ...toMap(),
      };

  String toWireJson() => jsonEncode(toWireMap());

  String hash() => canonicalHashHex(toUnsignedMap());

  static RoomCommit fromMap(Map<String, Object?> m) {
    final version = _reqInt(m, 'protocolVersion', min: 1);
    if (version != kProtocolVersion) {
      throw FormatException('unsupported protocolVersion: $version');
    }
    final seq = _reqInt(m, 'seq', min: 1);
    final prevHash = _reqHex(m, 'prevHash');
    final requestId = _optToken(m, 'requestId');
    final aclVersion = _reqInt(m, 'aclVersion', min: 1);
    final action = _reqString(m, 'action', maxLength: 32);
    if (!_actionPattern.hasMatch(action)) {
      throw FormatException('invalid action: $action');
    }
    final paramsRaw = m['params'];
    if (paramsRaw is! Map) {
      throw FormatException('params must be a map');
    }
    final params = parseRestrictedMap(paramsRaw, 'params');
    final paramsBytes = canonicalBytes(params);
    if (paramsBytes.length > kMaxCommitParamsBytes) {
      throw FormatException('params exceed $kMaxCommitParamsBytes bytes');
    }
    final effectiveSharedMs = _reqInt(m, 'effectiveSharedMs', min: 0);
    final roomId = _reqString(m, 'roomId', maxLength: 64);
    final sessionId = _reqString(m, 'sessionId', maxLength: 64);
    final signature = _optString(m, 'signature', maxLength: 128);
    return RoomCommit(
      seq: seq,
      prevHash: prevHash,
      requestId: requestId,
      aclVersion: aclVersion,
      action: action,
      params: params,
      effectiveSharedMs: effectiveSharedMs,
      roomId: roomId,
      sessionId: sessionId,
      signature: signature,
    );
  }

  static RoomCommit fromWireJson(String wire) {
    if (wire.length > kMaxEnvelopeBytes) {
      throw FormatException('commit exceeds $kMaxEnvelopeBytes bytes');
    }
    final decoded = jsonDecode(wire);
    if (decoded is! Map) {
      throw FormatException('commit must decode to a map');
    }
    final map = Map<String, Object?>.from(decoded);
    final type = map.remove('type');
    if (type != null && type != 'commit') {
      throw FormatException('commit wire type must be commit');
    }
    return RoomCommit.fromMap(map);
  }
}

enum CommitClass {
  /// seq == lastSeq + 1 and prevHash matches: apply now.
  ready,

  /// seq <= lastSeq: already applied or stale (duplicate).
  duplicate,

  /// seq == lastSeq + 1 but prevHash mismatch, or unknown chain state.
  chainRejected,

  /// seq > lastSeq + 1: parked until missing commits arrive.
  outOfOrder,
}

class CommitChain {
  CommitChain({required String genesisHash})
      : lastSeq = 0,
        lastHash = genesisHash;

  int lastSeq;
  String lastHash;
  final Map<int, RoomCommit> _pending = <int, RoomCommit>{};
  final Map<String, int> _requestIdToSeq = <String, int>{};

  /// Domain separation purpose for commit signatures.
  static const String signaturePurpose = 'room_commit';

  int get pendingCount => _pending.length;

  bool hasAppliedRequest(String? requestId) =>
      requestId != null && _requestIdToSeq.containsKey(requestId);

  int? seqForRequest(String? requestId) =>
      requestId == null ? null : _requestIdToSeq[requestId];

  /// Commits an already-signature-verified [commit] to the chain.
  CommitClass classify(RoomCommit commit) {
    if (commit.seq <= lastSeq) return CommitClass.duplicate;
    if (commit.seq == lastSeq + 1) {
      return commit.prevHash == lastHash
          ? CommitClass.ready
          : CommitClass.chainRejected;
    }
    return CommitClass.outOfOrder;
  }

  void park(RoomCommit commit) {
    if (_pending.length >= kMaxPendingCommits) {
      final oldest = _pending.keys.reduce((a, b) => a < b ? a : b);
      _pending.remove(oldest);
    }
    _pending[commit.seq] = commit;
  }

  /// Removes and returns every commit that is now applicable in order.
  List<RoomCommit> drainReady() {
    final out = <RoomCommit>[];
    while (true) {
      final next = _pending[lastSeq + 1];
      if (next == null) break;
      if (next.prevHash != lastHash) break;
      _pending.remove(next.seq);
      markApplied(next);
      out.add(next);
    }
    return out;
  }

  /// Marks [commit] applied. Callers must invoke this only for the
  /// sequential path (seq == lastSeq + 1 with matching prevHash) or via
  /// [drainReady]; otherwise the chain is corrupted.
  void markApplied(RoomCommit commit) {
    lastSeq = commit.seq;
    lastHash = commit.hash();
    final requestId = commit.requestId;
    if (requestId != null) {
      _requestIdToSeq[requestId] = commit.seq;
      while (_requestIdToSeq.length > kMaxTrackedRequestIds) {
        _requestIdToSeq.remove(_requestIdToSeq.keys.first);
      }
    }
  }

  /// Resets the chain to a snapshot position (after verified snapshot).
  void resetTo(int seq, String hash) {
    lastSeq = seq;
    lastHash = hash;
    _pending.clear();
  }
}

/// Room ACL with a monotonic version. Only commits mutate it; snapshots
/// can replace it wholesale. The owner is always 'owner' and cannot be
/// demoted by an ACL commit.
class RoomAcl {
  RoomAcl({required this.ownerDeviceId});

  String ownerDeviceId;
  int version = 1;
  final Map<String, String> _roles = <String, String>{}; // memberId -> admin|member

  void transferOwnership(String newOwnerDeviceId) {
    ownerDeviceId = newOwnerDeviceId;
    _roles.remove(newOwnerDeviceId);
    version += 1;
  }

  String roleOf(String deviceId) {
    if (deviceId == ownerDeviceId) return 'owner';
    return _roles[deviceId] ?? 'none';
  }

  bool isAdmitted(String deviceId) =>
      deviceId == ownerDeviceId || _roles.containsKey(deviceId);

  bool canControl(String deviceId) {
    final role = roleOf(deviceId);
    return role == 'owner' || role == 'admin';
  }

  /// Work with the ACL as of a specific commit: this mutates version.
  /// Returns true when membership/role state changed.
  bool applyCommit(String action, Map<String, Object?> params) {
    switch (action) {
      case 'member_admit':
        final memberId = _memberId(params);
        if (memberId == null) return false;
        if (_roles.containsKey(memberId)) {
          // Idempotent re-admit; never demotes an existing admin.
          return true;
        }
        _roles[memberId] = 'member';
        version += 1;
        return true;
      case 'grant_admin':
        final memberId = _memberId(params);
        if (memberId == null || !_roles.containsKey(memberId)) return false;
        _roles[memberId] = 'admin';
        version += 1;
        return true;
      case 'revoke_admin':
        final memberId = _memberId(params);
        if (memberId == null || _roles[memberId] != 'admin') return false;
        _roles[memberId] = 'member';
        version += 1;
        return true;
      default:
        return false;
    }
  }

  Map<String, String> snapshot() => Map<String, String>.from(_roles);

  void loadSnapshot(Map<String, String> roles, int aclVersion) {
    _roles
      ..clear()
      ..addAll(roles);
    version = aclVersion;
  }

  String? _memberId(Map<String, Object?> params) {
    final v = params['memberId'];
    if (v is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(v)) return null;
    return v;
  }
}

int _reqInt(Map<String, Object?> m, String key, {int min = 0, int? max}) {
  final v = m[key];
  if (v is! int) throw FormatException('$key missing or not an integer');
  if (v < min) throw FormatException('$key below minimum');
  if (v.abs() > kMaxCanonicalInt) throw FormatException('$key out of range');
  if (max != null && v > max) throw FormatException('$key above maximum');
  return v;
}

String _reqHex(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is! String || !_hex64.hasMatch(v)) {
    throw FormatException('$key must be 64 lowercase hex');
  }
  return v;
}

String _reqString(Map<String, Object?> m, String key, {int maxLength = 1024}) {
  final v = m[key];
  if (v is! String || v.isEmpty || v.length > maxLength) {
    throw FormatException('$key missing or invalid');
  }
  if (v.codeUnits.any((u) => u < 0x20 || u == 0x7f)) {
    throw FormatException('$key contains control characters');
  }
  return v;
}

String? _optString(Map<String, Object?> m, String key, {int maxLength = 1024}) {
  final v = m[key];
  if (v == null) return null;
  return _reqString(m, key, maxLength: maxLength);
}

String? _optToken(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v == null) return null;
  if (v is! String || !_cleanToken.hasMatch(v)) {
    throw FormatException('$key invalid');
  }
  return v;
}

/// Hex sha256 helper kept for chain internals and tests.
String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();
