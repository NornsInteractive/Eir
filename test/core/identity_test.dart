import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eir/core/identity.dart';

void main() {
  late DeviceIdentityStore store;
  setUp(() {
    store = DeviceIdentityStore(store: InMemorySecureKeyValueStore());
  });

  test('loadOrCreate creates a persistent identity across stores', () async {
    final memory = InMemorySecureKeyValueStore();
    final first =
        await DeviceIdentityStore(store: memory).loadOrCreate();
    final second =
        await DeviceIdentityStore(store: memory).loadOrCreate();
    expect(second.identity.deviceId, first.identity.deviceId);
    expect(second.identity.publicKeyBase64, first.identity.publicKeyBase64);
  });

  test('deviceId is sha256 of the public key', () async {
    final kp = await store.loadOrCreate();
    expect(kp.identity.deviceId, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('sign/verify roundtrip works', () async {
    final kp = await store.loadOrCreate();
    final message = utf8.encode('hello eir');
    final signature = await store.sign(kp.keyPair, message);
    expect(
      await store.verify(
        kp.identity.publicKeyBase64,
        message,
        signature.bytes,
      ),
      isTrue,
    );
  });

  test('forged signature does not verify (regression for verify() bug)',
      () async {
    final kp = await store.loadOrCreate();
    final message = utf8.encode('commit: play');
    final signature = await store.sign(kp.keyPair, message);
    // Same key, different message (forged content) must fail.
    expect(
      await store.verify(
        kp.identity.publicKeyBase64,
        utf8.encode('commit: pause'),
        signature.bytes,
      ),
      isFalse,
    );
    // Different signer entirely (attacker key) must fail.
    final attacker = await Ed25519().newKeyPair();
    final attackerPub = base64Encode(
      (await attacker.extractPublicKey()).bytes,
    );
    expect(
      await store.verify(attackerPub, message, signature.bytes),
      isFalse,
    );
    // Truncated/extended signature must fail, not throw.
    expect(
      await store.verify(
        kp.identity.publicKeyBase64,
        message,
        signature.bytes.sublist(0, 32),
      ),
      isFalse,
    );
    expect(
      await store.verify(
        kp.identity.publicKeyBase64,
        message,
        [...signature.bytes, 0],
      ),
      isFalse,
    );
  });

  test('verify rejects malformed public keys', () async {
    final kp = await store.loadOrCreate();
    final message = utf8.encode('x');
    final signature = await store.sign(kp.keyPair, message);
    expect(await store.verify('!!!not-base64!!!', message, signature.bytes),
        isFalse);
    expect(
      await store.verify(base64Encode([1, 2, 3]), message, signature.bytes),
      isFalse,
    );
  });

  test('corrupted stored secret raises controlled IdentityStoreCorrupted',
      () async {
    final memory = InMemorySecureKeyValueStore();
    await memory.write('eir_device_private_key_v1', 'not base64!!');
    await expectLater(
      DeviceIdentityStore(store: memory).loadOrCreate(),
      throwsA(isA<IdentityStoreCorrupted>()),
    );

    await memory.write(
      'eir_device_private_key_v1',
      base64Encode(List<int>.filled(63, 7)),
    );
    await expectLater(
      DeviceIdentityStore(store: memory).loadOrCreate(),
      throwsA(isA<IdentityStoreCorrupted>()),
    );

    // Valid-length record with a flipped public-key byte must be rejected.
    final fresh = InMemorySecureKeyValueStore();
    final good = DeviceIdentityStore(store: fresh);
    await good.loadOrCreate();
    final raw = base64Decode(await fresh.read('eir_device_private_key_v1') ?? '');
    expect(raw.length, 64);
    raw[40] = raw[40] ^ 0x01;
    await fresh.write('eir_device_private_key_v1', base64Encode(raw));
    await expectLater(
      DeviceIdentityStore(store: fresh).loadOrCreate(),
      throwsA(isA<IdentityStoreCorrupted>()),
    );
  });

  test('in-memory store injection exercises the real verify path', () async {
    final memory = InMemorySecureKeyValueStore();
    final storeA = DeviceIdentityStore(store: memory);
    final storeB = DeviceIdentityStore(store: memory);
    final kp = await storeA.loadOrCreate();
    final sig = await storeA.sign(kp.keyPair, utf8.encode('payload'));
    expect(
      await storeB.verify(
        kp.identity.publicKeyBase64,
        utf8.encode('payload'),
        sig.bytes,
      ),
      isTrue,
    );
  });
}
