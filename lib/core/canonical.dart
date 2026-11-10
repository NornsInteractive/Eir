import 'dart:convert';
import 'dart:typed_data';

import 'package:canonical_json/canonical_json.dart' as cj;
import 'package:crypto/crypto.dart' as crypto;

/// Eir restricted canonical encoding.
///
/// This is NOT RFC 8785. Eir uses the `canonical_json` package
/// (https://github.com/google/dart-neats, laptop.org canonical JSON rules)
/// hardened with additional restrictions enforced by this file:
///
///  * values are limited to Map and List, String,
///    int, bool and null. Doubles/floats are rejected everywhere.
///  * integers must stay within the JSON safe-integer range
///    (|value| <= 2^53 - 1).
///  * strings must contain no control characters (< 0x20) and no DEL.
///  * map keys must be non-empty strings without control characters.
///  * map keys are ordered by UTF-8 byte ascending (package rule).
///  * output carries no insignificant whitespace.
///
/// Signers and verifiers MUST both route through `canonicalBytes` so the
/// rules cannot drift apart. Signed payloads additionally carry a domain
/// separator via [domainSeparate] so a signature made for one purpose can
/// never be replayed as another.
const int kMaxCanonicalInt = 9007199254740991; // 2^53 - 1

class CanonicalValueError extends FormatException {
  CanonicalValueError(String message) : super('canonical value: $message');
}

bool _isCleanString(String s) {
  for (final unit in s.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) return false;
  }
  return true;
}

/// Validates [value] against the Eir restricted value model.
/// Throws [CanonicalValueError] on any violation. Returns the value.
Object? validateCanonicalValue(Object? value, {String path = '\$'}) {
  if (value == null || value is bool) return value;
  if (value is int) {
    if (value.abs() > kMaxCanonicalInt) {
      throw CanonicalValueError('integer out of safe range at $path');
    }
    return value;
  }
  if (value is double) {
    throw CanonicalValueError('floating point values are not allowed at $path');
  }
  if (value is String) {
    if (!_isCleanString(value)) {
      throw CanonicalValueError('string contains control characters at $path');
    }
    return value;
  }
  if (value is List) {
    for (var i = 0; i < value.length; i++) {
      validateCanonicalValue(value[i], path: '$path[$i]');
    }
    return value;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String || key.isEmpty) {
        throw CanonicalValueError('map key must be a non-empty string at $path');
      }
      if (!_isCleanString(key)) {
        throw CanonicalValueError('map key contains control characters at $path');
      }
      validateCanonicalValue(entry.value, path: '$path.$key');
    }
    return Map<String, Object?>.fromEntries(
      value.entries.map((e) => MapEntry(e.key as String, e.value)),
    );
  }
  throw CanonicalValueError(
    'unsupported type ${value.runtimeType} at $path',
  );
}

/// Encodes [value] to canonical bytes. Throws [CanonicalValueError] when the
/// value violates the restricted model.
Uint8List canonicalBytes(Object? value) {
  final validated = validateCanonicalValue(value);
  final bytes = cj.canonicalJson.encode(validated);
  return Uint8List.fromList(bytes);
}

/// Decodes canonical bytes. Returns a validated structure (plain
/// Map/List/scalars). Throws [CanonicalValueError] or
/// [FormatException] on invalid input.
Object? decodeCanonical(List<int> bytes) {
  final decoded = cj.canonicalJson.decode(bytes);
  return validateCanonicalValue(decoded);
}

/// SHA-256 of canonical encoding of [value]. Used for genesis hashes,
/// commit-chain hashes and media manifest mediaIds.
String canonicalHashHex(Object? value) {
  return crypto.sha256.convert(canonicalBytes(value)).toString();
}

/// Domain-separated signing input: `EirSign/v1/<purpose>\n<canonical bytes>`.
Uint8List domainSeparate(String purpose, List<int> canonicalPayload) {
  _validatePurpose(purpose);
  final prefix = utf8.encode('EirSign/v1/$purpose\n');
  return Uint8List(prefix.length + canonicalPayload.length)
    ..setRange(0, prefix.length, prefix)
    ..setRange(prefix.length, prefix.length + canonicalPayload.length, canonicalPayload);
}

void _validatePurpose(String purpose) {
  if (purpose.isEmpty || purpose.length > 64 || !RegExp(r'^[a-z0-9_]+$').hasMatch(purpose)) {
    throw CanonicalValueError('invalid signature purpose: "$purpose"');
  }
}

/// Canonical encoding of [value] prefixed with the domain separator for
/// [purpose]. This is the exact byte string handed to Ed25519 sign/verify.
Uint8List domainSeparatedCanonical(String purpose, Object? value) {
  return domainSeparate(purpose, canonicalBytes(value));
}
