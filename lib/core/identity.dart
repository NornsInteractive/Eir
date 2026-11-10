import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceIdentity {
  DeviceIdentity({required this.deviceId, required this.publicKeyBase64});
  final String deviceId;
  final String publicKeyBase64;
}

class DeviceKeyPair {
  DeviceKeyPair({required this.identity, required this.keyPair});
  final DeviceIdentity identity;
  final SimpleKeyPair keyPair;
}

/// Raised when the persisted device key is unreadable or fails
/// consistency checks. Callers must surface this as a controlled error;
/// it is never safe to silently generate a replacement key.
class IdentityStoreCorrupted implements Exception {
  IdentityStoreCorrupted(this.reason);
  final String reason;
  @override
  String toString() => 'IdentityStoreCorrupted: $reason';
}

/// Minimal key/value abstraction so tests can inject an in-memory store
/// instead of bypassing the real FlutterSecureStorage code path.
abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureStorageStore implements SecureKeyValueStore {
  FlutterSecureStorageStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> _map = <String, String>{};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<void> delete(String key) async => _map.remove(key);
}

/// Persistent Ed25519 device identity.
///
/// The stored record is 64 bytes: 32-byte seed || 32-byte public key.
/// On load the seed is re-derived to a public key and compared with the
/// stored public key; any length or consistency violation raises
/// [IdentityStoreCorrupted] instead of fabricating an identity.
class DeviceIdentityStore {
  DeviceIdentityStore({SecureKeyValueStore? store})
      : _store = store ?? FlutterSecureStorageStore();

  final SecureKeyValueStore _store;
  static const _privateKeyKey = 'eir_device_private_key_v1';

  final Ed25519 _algo = Ed25519();

  Future<DeviceKeyPair> loadOrCreate() async {
    final stored = await _store.read(_privateKeyKey);
    SimpleKeyPair keyPair;
    if (stored != null && stored.isNotEmpty) {
      keyPair = await _restore(stored);
    } else {
      keyPair = await _algo.newKeyPair();
      final priv = await keyPair.extractPrivateKeyBytes();
      final pub = (await keyPair.extractPublicKey()).bytes;
      await _store.write(_privateKeyKey, base64Encode([...priv, ...pub]));
    }
    final pub = (await keyPair.extractPublicKey()).bytes;
    final deviceId = crypto.sha256.convert(pub).toString();
    return DeviceKeyPair(
      identity: DeviceIdentity(
        deviceId: deviceId,
        publicKeyBase64: base64Encode(pub),
      ),
      keyPair: keyPair,
    );
  }

  Future<SimpleKeyPair> _restore(String stored) async {
    final Uint8List bytes;
    try {
      bytes = base64Decode(stored);
    } catch (_) {
      throw IdentityStoreCorrupted('stored private key is not valid base64');
    }
    if (bytes.length != 64) {
      throw IdentityStoreCorrupted(
        'stored private key must be 64 bytes, found ${bytes.length}',
      );
    }
    final seed = bytes.sublist(0, 32);
    final storedPub = bytes.sublist(32);
    final derived = await _algo.newKeyPairFromSeed(seed);
    final derivedPub = (await derived.extractPublicKey()).bytes;
    if (derivedPub.length != 32) {
      throw IdentityStoreCorrupted('re-derived public key has invalid length');
    }
    var mismatch = 0;
    for (var i = 0; i < 32; i++) {
      mismatch |= derivedPub[i] ^ storedPub[i];
    }
    if (mismatch != 0) {
      throw IdentityStoreCorrupted(
        'stored public key does not match stored private seed',
      );
    }
    return SimpleKeyPairData(
      seed,
      publicKey: SimplePublicKey(derivedPub, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
  }

  Future<Signature> sign(SimpleKeyPair keyPair, List<int> message) {
    return _algo.sign(message, keyPair: keyPair);
  }

  /// Verifies [signatureBytes] over [message] for [publicKeyBase64].
  /// Returns false for malformed keys/signatures and for verification
  /// failure; never throws for bad peer input.
  Future<bool> verify(
    String publicKeyBase64,
    List<int> message,
    List<int> signatureBytes,
  ) async {
    try {
      final pubBytes = base64Decode(publicKeyBase64);
      if (pubBytes.length != 32) return false;
      if (signatureBytes.length != 64) return false;
      final pub = SimplePublicKey(pubBytes, type: KeyPairType.ed25519);
      final sig = Signature(signatureBytes, publicKey: pub);
      return await _algo.verify(message, signature: sig);
    } catch (_) {
      return false;
    }
  }
}
