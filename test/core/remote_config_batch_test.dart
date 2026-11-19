import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:eir/app_settings.dart';
import 'package:eir/core/remote_config_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

const _kServerDomain = 'eir_setting_server_domain';
const _kSignaling = 'eir_setting_signaling_url';
const _kTurnServer = 'eir_setting_turn_server';
const _kTurnUsername = 'eir_setting_turn_username';
const _kTurnCredential = 'eir_setting_turn_credential';
const _kLastSync = 'eir_last_config_sync_time';
const _kNetworkRecord = 'eir_setting_network_config';
const _kThemeMode = 'eir_setting_theme_mode';
const _kLocale = 'eir_setting_locale';

Map<String, Object> _baselineData() => <String, Object>{
      'flutter.$_kServerDomain': 'https://old.example',
      'flutter.$_kSignaling': 'wss://old.example/ws',
      'flutter.$_kTurnServer': 'old.turn.example:3478',
      'flutter.$_kTurnUsername': 'old-user',
      'flutter.$_kTurnCredential': 'old-pass',
      'flutter.$_kLastSync': 111,
      'flutter.$_kThemeMode': 'dark',
      'flutter.$_kLocale': 'en_US',
    };

class _FailingStore extends SharedPreferencesStorePlatform {
  _FailingStore(this.data, {this.failKey});

  final Map<String, Object> data;
  final String? failKey;
  int setValueCalls = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    setValueCalls++;
    if (failKey != null && key == 'flutter.$failKey') return false;
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final filter = parameters.filter;
    data.removeWhere(
      (String key, _) =>
          key.startsWith(filter.prefix) &&
          (filter.allowList == null || filter.allowList!.contains(key)),
    );
    return true;
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final filter = parameters.filter;
    final result = Map<String, Object>.from(data);
    result.removeWhere(
      (String key, _) =>
          !key.startsWith(filter.prefix) ||
          (filter.allowList != null && !filter.allowList!.contains(key)),
    );
    return result;
  }

  @override
  Future<bool> clear() async => clearWithParameters(
        ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')),
      );

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
      );
}

/// Simulates a platform that accepts one write and then fails all later
/// writes, including any rollback attempt.
class _MidBatchFailingStore extends SharedPreferencesStorePlatform {
  _MidBatchFailingStore(this.data, {this.successfulWrites = 1});

  final Map<String, Object> data;
  final int successfulWrites;
  int setValueCalls = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    setValueCalls++;
    if (setValueCalls > successfulWrites) return false;
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    setValueCalls++;
    if (setValueCalls > successfulWrites) return false;
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final filter = parameters.filter;
    data.removeWhere(
      (String key, _) =>
          key.startsWith(filter.prefix) &&
          (filter.allowList == null || filter.allowList!.contains(key)),
    );
    return true;
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final filter = parameters.filter;
    final result = Map<String, Object>.from(data);
    result.removeWhere(
      (String key, _) =>
          !key.startsWith(filter.prefix) ||
          (filter.allowList != null && !filter.allowList!.contains(key)),
    );
    return result;
  }

  @override
  Future<bool> clear() async => clearWithParameters(
        ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')),
      );

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
      );
}

Future<void> _resetHealthyBaseline() async {
  SharedPreferences.setMockInitialValues(_baselineData());
  SharedPreferences.resetStatic();

  final settings = AppSettings.instance;
  await settings.setServerDomain('https://baseline-sentinel.invalid');
  await settings.setSignalingUrl('wss://baseline-sentinel.invalid/ws');
  await settings.setTurnConfig(
    server: 'baseline-sentinel.invalid:3478',
    username: 'sentinel',
    credential: 'sentinel',
  );
  await settings.setLastConfigSyncTime(-1);

  await settings.setServerDomain('https://old.example');
  await settings.setSignalingUrl('wss://old.example/ws');
  await settings.setTurnConfig(
    server: 'old.turn.example:3478',
    username: 'old-user',
    credential: 'old-pass',
  );
  await settings.setLastConfigSyncTime(111);
}

Future<Map<String, dynamic>> _encryptedPayload(
  Map<String, dynamic> plain,
) async {
  const secret = RemoteConfigService.defaultConfigSecret;
  final plainBytes = utf8.encode(jsonEncode(plain));
  final keyBytes = crypto.sha256.convert(utf8.encode(secret)).bytes;
  final algorithm = AesGcm.with256bits();
  final secretBox = await algorithm.encrypt(
    plainBytes,
    secretKey: SecretKey(keyBytes),
  );
  return <String, dynamic>{
    'version': 1,
    'algorithm': 'AES-256-GCM',
    'iv': base64Encode(secretBox.nonce),
    'tag': base64Encode(secretBox.mac.bytes),
    'ciphertext': base64Encode(secretBox.cipherText),
  };
}

Future<HttpServer> _configServer(Map<String, dynamic> plain) async {
  final payload = await _encryptedPayload(plain);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(payload));
    await request.response.close();
  });
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  setUp(() async {
    await _resetHealthyBaseline();
  });

  group('AppSettings.applyRemoteConfig coherent batch', () {
    test(
      'success persists and updates all values plus sync time once',
      () async {
        final settings = AppSettings.instance;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kThemeMode, 'dark');
        await prefs.setString(_kLocale, 'en_US');

        var notifications = 0;
        void listener() => notifications++;
        settings.addListener(listener);
        addTearDown(() => settings.removeListener(listener));

        await settings.applyRemoteConfig(
          serverDomain: 'https://new.example',
          signalingUrl: 'wss://new.example/ws',
          turnServer: 'new.turn.example:3478',
          turnUsername: 'new-user',
          turnCredential: 'new-pass',
          lastConfigSyncTime: 222,
        );

        expect(settings.serverDomain, 'https://new.example');
        expect(settings.signalingUrl, 'wss://new.example/ws');
        expect(settings.turnServer, 'new.turn.example:3478');
        expect(settings.turnUsername, 'new-user');
        expect(settings.turnCredential, 'new-pass');
        expect(settings.lastConfigSyncTime, 222);
        expect(notifications, 1);

        expect(prefs.getString(_kServerDomain), 'https://new.example');
        expect(prefs.getString(_kSignaling), 'wss://new.example/ws');
        expect(prefs.getString(_kNetworkRecord), isNotNull);
        expect(prefs.getString(_kTurnServer), 'new.turn.example:3478');
        expect(prefs.getString(_kTurnUsername), 'new-user');
        expect(prefs.getString(_kTurnCredential), 'new-pass');
        expect(prefs.getInt(_kLastSync), 222);
        expect(prefs.getString(_kThemeMode), 'dark');
        expect(prefs.getString(_kLocale), 'en_US');
      },
    );

    test('single setting save preserves all other networking values', () async {
      final settings = AppSettings.instance;
      final prefs = await SharedPreferences.getInstance();

      await settings.setSignalingUrl('wss://single.example/ws');

      expect(settings.serverDomain, 'https://old.example');
      expect(settings.signalingUrl, 'wss://single.example/ws');
      expect(settings.turnServer, 'old.turn.example:3478');
      expect(settings.turnUsername, 'old-user');
      expect(settings.turnCredential, 'old-pass');
      expect(settings.lastConfigSyncTime, 111);

      final raw = prefs.getString(_kNetworkRecord);
      expect(raw, isNotNull);
      final record = jsonDecode(raw!) as Map<String, dynamic>;
      expect(record['serverDomain'], 'https://old.example');
      expect(record['signalingUrl'], 'wss://single.example/ws');
      expect(record['turnServer'], 'old.turn.example:3478');
      expect(record['turnUsername'], 'old-user');
      expect(record['turnCredential'], 'old-pass');
      expect(record['lastConfigSyncTime'], 111);

      expect(prefs.getString(_kServerDomain), 'https://old.example');
      expect(prefs.getString(_kSignaling), 'wss://single.example/ws');
      expect(prefs.getString(_kTurnServer), 'old.turn.example:3478');
      expect(prefs.getInt(_kLastSync), 111);
    });

    test(
      'a failed record write keeps the previously saved configuration',
      () async {
        final settings = AppSettings.instance;
        final store = _FailingStore(_baselineData(), failKey: _kNetworkRecord);
        SharedPreferencesStorePlatform.instance = store;
        SharedPreferences.resetStatic();

        var notifications = 0;
        void listener() => notifications++;
        settings.addListener(listener);
        addTearDown(() => settings.removeListener(listener));

        await expectLater(
          settings.applyRemoteConfig(
            serverDomain: 'https://new.example',
            signalingUrl: 'wss://new.example/ws',
            turnServer: 'new.turn.example:3478',
            turnUsername: 'new-user',
            turnCredential: 'new-pass',
            lastConfigSyncTime: 222,
          ),
          throwsStateError,
        );

        expect(notifications, 0);
        expect(settings.serverDomain, 'https://old.example');
        expect(settings.signalingUrl, 'wss://old.example/ws');
        expect(settings.turnServer, 'old.turn.example:3478');
        expect(settings.turnUsername, 'old-user');
        expect(settings.turnCredential, 'old-pass');
        expect(settings.lastConfigSyncTime, 111);

        expect(store.data['flutter.$_kServerDomain'], 'https://old.example');
        expect(store.data['flutter.$_kSignaling'], 'wss://old.example/ws');
        expect(store.data['flutter.$_kTurnServer'], 'old.turn.example:3478');
        expect(store.data['flutter.$_kLastSync'], 111);
      },
    );

    test(
      'a failed record write keeps the previous sync time and values',
      () async {
        final settings = AppSettings.instance;
        final store = _FailingStore(_baselineData(), failKey: _kNetworkRecord);
        SharedPreferencesStorePlatform.instance = store;
        SharedPreferences.resetStatic();

        await expectLater(
          settings.applyRemoteConfig(
            serverDomain: 'https://new.example',
            signalingUrl: 'wss://new.example/ws',
            turnServer: 'new.turn.example:3478',
            turnUsername: 'new-user',
            turnCredential: 'new-pass',
            lastConfigSyncTime: 222,
          ),
          throwsStateError,
        );

        expect(settings.serverDomain, 'https://old.example');
        expect(settings.signalingUrl, 'wss://old.example/ws');
        expect(settings.turnServer, 'old.turn.example:3478');
        expect(settings.lastConfigSyncTime, 111);

        expect(store.data['flutter.$_kServerDomain'], 'https://old.example');
        expect(store.data['flutter.$_kSignaling'], 'wss://old.example/ws');
        expect(store.data['flutter.$_kTurnServer'], 'old.turn.example:3478');
        expect(store.data['flutter.$_kTurnUsername'], 'old-user');
        expect(store.data['flutter.$_kTurnCredential'], 'old-pass');
        expect(store.data['flutter.$_kLastSync'], 111);
      },
    );

    test(
      'partial write plus failed rollback never leaves mixed config values',
      () async {
        final settings = AppSettings.instance;
        final store = _MidBatchFailingStore(
          Map<String, Object>.from(_baselineData()),
          successfulWrites: 1,
        );
        SharedPreferencesStorePlatform.instance = store;
        SharedPreferences.resetStatic();

        try {
          await settings.applyRemoteConfig(
            serverDomain: 'https://new.example',
            signalingUrl: 'wss://new.example/ws',
            turnServer: 'new.turn.example:3478',
            turnUsername: 'new-user',
            turnCredential: 'new-pass',
            lastConfigSyncTime: 222,
          );
        } catch (_) {}

        final persisted = <Object?>[
          store.data['flutter.$_kServerDomain'],
          store.data['flutter.$_kSignaling'],
          store.data['flutter.$_kTurnServer'],
          store.data['flutter.$_kTurnUsername'],
          store.data['flutter.$_kTurnCredential'],
          store.data['flutter.$_kLastSync'],
        ];
        final old = <Object?>[
          'https://old.example',
          'wss://old.example/ws',
          'old.turn.example:3478',
          'old-user',
          'old-pass',
          111,
        ];
        final updated = <Object?>[
          'https://new.example',
          'wss://new.example/ws',
          'new.turn.example:3478',
          'new-user',
          'new-pass',
          222,
        ];
        expect(persisted, anyOf(equals(old), equals(updated)));
      },
    );

    test(
      'single setter updates memory only after confirmed persistence',
      () async {
        final settings = AppSettings.instance;
        final store = _FailingStore(_baselineData(), failKey: _kNetworkRecord);
        SharedPreferencesStorePlatform.instance = store;
        SharedPreferences.resetStatic();

        var notifications = 0;
        void listener() => notifications++;
        settings.addListener(listener);
        addTearDown(() => settings.removeListener(listener));

        await expectLater(
          settings.setServerDomain('https://blocked.example'),
          throwsStateError,
        );
        expect(settings.serverDomain, 'https://old.example');
        expect(notifications, 0);
        expect(store.data['flutter.$_kServerDomain'], 'https://old.example');
      },
    );
  });

  group('RemoteConfigService.fetchAndApply', () {
    test('applies a valid remote payload and records sync time', () async {
      final settings = AppSettings.instance;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeMode, 'light');

      final server = await _configServer(<String, dynamic>{
        'server_domain': 'https://remote.example',
        'signaling_server': 'wss://remote.example/ws',
        'turn_server': 'turn.remote.example:3478',
        'turn_username': 'remote-user',
        'turn_credential': 'remote-pass',
      });
      addTearDown(() => server.close(force: true));

      final result = await RemoteConfigService.fetchAndApply(
        serverDomain: 'http://127.0.0.1:${server.port}',
      );

      expect(result.success, isTrue);
      expect(settings.serverDomain, 'https://remote.example');
      expect(settings.signalingUrl, 'wss://remote.example/ws');
      expect(settings.turnServer, 'turn.remote.example:3478');
      expect(settings.turnUsername, 'remote-user');
      expect(settings.turnCredential, 'remote-pass');
      expect(settings.lastConfigSyncTime, greaterThan(111));
      expect(prefs.getString(_kThemeMode), 'light');
    });

    test(
      'invalid signaling URL rejects the whole payload without writes',
      () async {
        final settings = AppSettings.instance;
        final store = _FailingStore(_baselineData());
        SharedPreferencesStorePlatform.instance = store;
        SharedPreferences.resetStatic();

        final server = await _configServer(<String, dynamic>{
          'server_domain': 'https://remote.example',
          'signaling_server': 'http://remote.example/ws',
          'turn_server': 'turn.remote.example:3478',
          'turn_username': 'remote-user',
          'turn_credential': 'remote-pass',
        });
        addTearDown(() => server.close(force: true));

        final result = await RemoteConfigService.fetchAndApply(
          serverDomain: 'http://127.0.0.1:${server.port}',
        );

        expect(result.success, isFalse);
        expect(store.setValueCalls, 0);
        expect(settings.serverDomain, 'https://old.example');
        expect(settings.signalingUrl, 'wss://old.example/ws');
        expect(settings.turnServer, 'old.turn.example:3478');
        expect(settings.lastConfigSyncTime, 111);
      },
    );

    test(
      'invalid TURN server rejects the whole payload without writes',
      () async {
        final settings = AppSettings.instance;
        final store = _FailingStore(_baselineData());
        SharedPreferencesStorePlatform.instance = store;
        SharedPreferences.resetStatic();

        final server = await _configServer(<String, dynamic>{
          'server_domain': 'https://remote.example',
          'signaling_server': 'wss://remote.example/ws',
          'turn_server': 'not a valid turn host',
          'turn_username': 'remote-user',
          'turn_credential': 'remote-pass',
        });
        addTearDown(() => server.close(force: true));

        final result = await RemoteConfigService.fetchAndApply(
          serverDomain: 'http://127.0.0.1:${server.port}',
        );

        expect(result.success, isFalse);
        expect(store.setValueCalls, 0);
        expect(settings.serverDomain, 'https://old.example');
        expect(settings.turnServer, 'old.turn.example:3478');
        expect(settings.lastConfigSyncTime, 111);
      },
    );

    test(
      'storage failure reports failure and keeps the old coherent state',
      () async {
        final settings = AppSettings.instance;
        final store = _FailingStore(_baselineData(), failKey: _kNetworkRecord);
        SharedPreferencesStorePlatform.instance = store;
        SharedPreferences.resetStatic();

        final server = await _configServer(<String, dynamic>{
          'server_domain': 'https://remote.example',
          'signaling_server': 'wss://remote.example/ws',
          'turn_server': 'turn.remote.example:3478',
          'turn_username': 'remote-user',
          'turn_credential': 'remote-pass',
        });
        addTearDown(() => server.close(force: true));

        final result = await RemoteConfigService.fetchAndApply(
          serverDomain: 'http://127.0.0.1:${server.port}',
        );

        expect(result.success, isFalse);
        expect(settings.serverDomain, 'https://old.example');
        expect(settings.signalingUrl, 'wss://old.example/ws');
        expect(settings.turnServer, 'old.turn.example:3478');
        expect(settings.turnUsername, 'old-user');
        expect(settings.turnCredential, 'old-pass');
        expect(settings.lastConfigSyncTime, 111);
        expect(store.data['flutter.$_kServerDomain'], 'https://old.example');
        expect(store.data['flutter.$_kSignaling'], 'wss://old.example/ws');
        expect(store.data['flutter.$_kLastSync'], 111);
      },
    );
  });
}
