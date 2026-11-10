import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:eir/core/canonical.dart';
import 'package:eir/core/commit_log.dart';
import 'package:eir/core/identity.dart';
import 'package:eir/core/invite.dart';
import 'package:eir/core/protocol.dart';

Future<(DeviceKeyPair, DeviceIdentityStore)> newIdentity() async {
  final store = DeviceIdentityStore(store: InMemorySecureKeyValueStore());
  return (await store.loadOrCreate(), store);
}

void main() {
  group('genesis + invite', () {
    test('genesis hash is stable and invite verifies', () async {
      final (owner, store) = await newIdentity();
      final genesis = buildGenesis(
        roomId: '11111111-2222-3333-4444-555555555555',
        sessionId: '66666666-7777-8888-9999-000000000000',
        ownerPublicKey: owner.identity.publicKeyBase64,
        createdAtMs: 1700000000000,
      );
      final hash1 = genesisHashHex(genesis);
      final hash2 = genesisHashHex(Map<String, Object?>.from(genesis));
      expect(hash1, hash2);

      final invite = InviteData(
        signalingUrl: 'wss://signal.example.test/',
        roomId: '11111111-2222-3333-4444-555555555555',
        sessionId: '66666666-7777-8888-9999-000000000000',
        inviteEpoch: 1,
        token: generateInviteToken(),
        ownerPublicKey: owner.identity.publicKeyBase64,
        genesisHash: hash1,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 3600 * 1000,
      );
      final text = await buildSignedInvite(invite, owner, identityStore: store);
      expect(text, startsWith('eir:v1:'));
      final parsed = await decodeAndVerifyInvite(text, identityStore: store);
      expect(parsed.roomId, invite.roomId);
      expect(parsed.sessionId, invite.sessionId);
      expect(parsed.genesisHash, hash1);
      expect(parsed.ownerDeviceId, owner.identity.deviceId);
    });

    test('tampered invite payload fails signature verification', () async {
      final (owner, store) = await newIdentity();
      final invite = InviteData(
        signalingUrl: 'wss://signal.example.test/',
        roomId: '11111111-2222-3333-4444-555555555555',
        sessionId: '66666666-7777-8888-9999-000000000000',
        inviteEpoch: 1,
        token: generateInviteToken(),
        ownerPublicKey: owner.identity.publicKeyBase64,
        genesisHash: 'a' * 64,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 3600 * 1000,
      );
      final text = await buildSignedInvite(invite, owner, identityStore: store);
      final payloadB64 = text.split(':').last.split('.').first;
      final decoded = decodeCanonical(base64Decode(_b64UrlToStd(payloadB64)))
          as Map<String, Object?>;
      decoded['genesisHash'] = 'b' * 64;
      final tamperedPayloadB64 = base64UrlEncode(canonicalBytes(decoded))
          .replaceAll('=', '');
      final sig = text.split('.').last;
      final tampered = 'eir:v1:$tamperedPayloadB64.$sig';
      await expectLater(
        decodeAndVerifyInvite(tampered, identityStore: store),
        throwsA(isA<InviteException>()),
      );
    });

    test('expired invite is rejected with invite_expired', () async {
      final (owner, store) = await newIdentity();
      final invite = InviteData(
        signalingUrl: 'wss://signal.example.test/',
        roomId: '11111111-2222-3333-4444-555555555555',
        sessionId: '66666666-7777-8888-9999-000000000000',
        inviteEpoch: 1,
        token: generateInviteToken(),
        ownerPublicKey: owner.identity.publicKeyBase64,
        genesisHash: 'c' * 64,
        expiresAtMs: 1000, // long expired
      );
      final text = await buildSignedInvite(invite, owner, identityStore: store);
      try {
        await decodeAndVerifyInvite(text, identityStore: store, nowMs: 2000);
        fail('expired invite must throw');
      } on InviteException catch (e) {
        expect(e.code, 'invite_expired');
      }
    });

    test('invite signed by a different key fails verification', () async {
      final (owner, store) = await newIdentity();
      final (attacker, attackerStore) = await newIdentity();
      final payload = <String, Object?>{
        'v': kProtocolVersion,
        'signaling': 'wss://signal.example.test/',
        'roomId': '11111111-2222-3333-4444-555555555555',
        'sessionId': '66666666-7777-8888-9999-000000000000',
        'inviteEpoch': 1,
        'token': generateInviteToken(),
        'tokenDigest': tokenDigestHex(generateInviteToken()),
        'ownerPublicKey': owner.identity.publicKeyBase64,
        'genesisHash': 'd' * 64,
        'expiresAtMs': DateTime.now().millisecondsSinceEpoch + 3600 * 1000,
      };
      // fix digest mismatch so ONLY the signature is under test
      payload['tokenDigest'] = tokenDigestHex(payload['token'] as String);
      final forgedSignature = await signDomain(
        'invite',
        payload,
        attacker,
        identityStore: attackerStore,
      );
      final payloadB64 = base64UrlEncode(canonicalBytes(payload))
          .replaceAll('=', '');
      final sigB64 = base64UrlEncode(base64Decode(forgedSignature))
          .replaceAll('=', '');
      final wire = 'eir:v1:$payloadB64.$sigB64';
      await expectLater(
        decodeAndVerifyInvite(wire, identityStore: store),
        throwsA(isA<InviteException>()),
      );
    });

    test('domain separation: invite signature cannot verify as room_commit',
        () async {
      final (owner, store) = await newIdentity();
      final signed = await signDomain(
        'invite',
        {'x': 1},
        owner,
        identityStore: store,
      );
      final verified = await verifyDomain(
        'room_commit',
        {'x': 1},
        signed,
        owner.identity.publicKeyBase64,
        identityStore: store,
      );
      expect(verified, isFalse);
    });

    test('commit signatures verify only under the owner key', () async {
      final (owner, store) = await newIdentity();
      final (attacker, attackerStore) = await newIdentity();
      final commit = <String, Object?>{
        'seq': 1,
        'prevHash': 'e' * 64,
        'requestId': 'req-1',
        'aclVersion': 1,
        'action': 'play',
        'params': {'positionMs': 0, 'rateMilli': 1000, 'itemId': 'item-1'},
        'effectiveSharedMs': 1234,
        'roomId': '11111111-2222-3333-4444-555555555555',
        'sessionId': '66666666-7777-8888-9999-000000000000',
      };
      final signature = await signDomain(
        CommitChain.signaturePurpose,
        commit,
        attacker,
        identityStore: attackerStore,
      );
      expect(
        await verifyDomain(
          CommitChain.signaturePurpose,
          commit,
          signature,
          owner.identity.publicKeyBase64,
          identityStore: store,
        ),
        isFalse,
      );
      expect(
        await verifyDomain(
          CommitChain.signaturePurpose,
          commit,
          signature,
          attacker.identity.publicKeyBase64,
          identityStore: store,
        ),
        isTrue,
      );
    });
  });

  group('control request canonical rules', () {
    test('payloads reject floats (rate is carried as integer milli-units)',
        () {
      expect(
        () => parseRestrictedMap({'rate': 1.5}, '\$'),
        throwsFormatException,
      );
      final ok = parseRestrictedMap({'rateMilli': 1500}, '\$');
      expect(ok['rateMilli'], 1500);
    });

    test('control characters in committed strings are rejected', () {
      expect(
        () => parseRestrictedMap({'title': 'bad\nname'}, '\$'),
        throwsFormatException,
      );
      expect(
        () => parseRestrictedMap({'title': 'valid title ✓'}, '\$'),
        returnsNormally,
      );
    });
  });
}

final throwsFormatException =
    throwsA(anyOf(isA<FormatException>(), isA<CanonicalValueError>()));

String _b64UrlToStd(String s) {
  var normalized = s.replaceAll('-', '+').replaceAll('_', '/');
  while (normalized.length % 4 != 0) {
    normalized += '=';
  }
  return normalized;
}
