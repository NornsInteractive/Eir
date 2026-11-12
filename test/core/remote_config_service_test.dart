import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eir/app_settings.dart';
import 'package:eir/core/remote_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('AppSettings has expected default server domain and TURN configurations', () async {
    final settings = AppSettings.instance;
    await settings.init();

    expect(settings.serverDomain, equals('https://eir.norns.cc.cd'));
    expect(settings.turnServer, equals('ip.norns.cc.cd:3478'));
    expect(settings.turnUsername, equals('norns'));
    expect(settings.turnCredential, equals('norns'));
  });

  test('RemoteConfigService.resolveConfigUrl normalizes various domain formats', () {
    expect(
      RemoteConfigService.resolveConfigUrl('eir.norns.cc.cd'),
      equals('https://eir.norns.cc.cd/api/config'),
    );
    expect(
      RemoteConfigService.resolveConfigUrl('https://eir.norns.cc.cd/'),
      equals('https://eir.norns.cc.cd/api/config'),
    );
    expect(
      RemoteConfigService.resolveConfigUrl('http://192.168.1.100:8080'),
      equals('http://192.168.1.100:8080/api/config'),
    );
    expect(
      RemoteConfigService.resolveConfigUrl('https://custom.com/api/config'),
      equals('https://custom.com/api/config'),
    );
    expect(
      RemoteConfigService.resolveConfigUrl('https://custom.com/api/v1/config/'),
      equals('https://custom.com/api/v1/config'),
    );
  });

  test('RemoteConfigService.decryptPayload decrypts valid AES-256-GCM ciphertext', () async {
    const secret = 'eir_secure_config_key_2026';
    final plainMap = {
      'server_domain': 'https://eir-backup.norns.cc.cd',
      'signaling_server': 'wss://eir-backup.norns.cc.cd/ws',
      'turn_server': 'turn.backup.com:3478',
      'turn_username': 'backup_user',
      'turn_credential': 'backup_password',
    };
    final plainBytes = utf8.encode(jsonEncode(plainMap));

    final keyBytes = crypto.sha256.convert(utf8.encode(secret)).bytes;
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(keyBytes);
    final secretBox = await algorithm.encrypt(plainBytes, secretKey: secretKey);

    final payload = {
      'version': 1,
      'algorithm': 'AES-256-GCM',
      'iv': base64Encode(secretBox.nonce),
      'tag': base64Encode(secretBox.mac.bytes),
      'ciphertext': base64Encode(secretBox.cipherText),
    };

    final decrypted = await RemoteConfigService.decryptPayload(payload, secret: secret);
    expect(decrypted, isNotNull);
    expect(decrypted!['server_domain'], equals('https://eir-backup.norns.cc.cd'));
    expect(decrypted['signaling_server'], equals('wss://eir-backup.norns.cc.cd/ws'));
    expect(decrypted['turn_server'], equals('turn.backup.com:3478'));
    expect(decrypted['turn_username'], equals('backup_user'));
    expect(decrypted['turn_credential'], equals('backup_password'));
  });

  test('RemoteConfigService.decryptPayload rejects corrupted ciphertext gracefully', () async {
    final corruptedPayload = {
      'version': 1,
      'algorithm': 'AES-256-GCM',
      'iv': base64Encode([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]),
      'tag': base64Encode(List.filled(16, 0)),
      'ciphertext': base64Encode([10, 20, 30, 40]),
    };

    final decrypted = await RemoteConfigService.decryptPayload(corruptedPayload);
    expect(decrypted, isNull);
  });
}
