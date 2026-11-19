import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eir/app_settings.dart';

const _kSignalingKey = 'eir_setting_signaling_url';
const _kRecordKey = 'eir_setting_network_config';

/// Each load runs in a fresh isolate because [AppSettings] is a process-wide
/// singleton that only reads storage once per instance.
Future<Map<String, String>> _load(Map<String, Object> values) {
  return Isolate.run(() async {
    SharedPreferences.setMockInitialValues(values);
    await AppSettings.instance.init();
    final prefs = await SharedPreferences.getInstance();
    return <String, String>{
      'url': AppSettings.instance.signalingUrl,
      'stored': prefs.getString(_kSignalingKey) ?? '',
    };
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saved legacy local signaling address is not migrated on load', () async {
    const legacyLocalUrls = <String>[
      'ws://127.0.0.1:8765',
      'ws://localhost:8765',
      'ws://127.0.0.1:8765/',
      'ws://localhost:8765/',
      'ws://127.0.0.1:8080/ws',
      'ws://localhost:8080/ws',
      'ws://127.0.0.1:8080',
      'ws://localhost:8080',
    ];

    for (final saved in legacyLocalUrls) {
      final result = await _load(<String, Object>{_kSignalingKey: saved});
      expect(result['url'], saved, reason: 'saved address must survive load');
      expect(result['stored'], saved,
          reason: 'load must not rewrite the saved scalar');
    }
  });

  test('no saved signaling address keeps the product default', () async {
    final result = await _load(<String, Object>{});
    expect(result['url'], AppSettings.defaultSignalingUrl);
    expect(result['stored'], '');
  });

  test('authoritative record wins over a conflicting legacy local scalar',
      () async {
    final result = await _load(<String, Object>{
      _kSignalingKey: 'ws://127.0.0.1:8765',
      _kRecordKey:
          '{"serverDomain":"https://record.example","signalingUrl":"wss://record.example/ws","turnServer":"record.turn.example:3478","turnUsername":"record-user","turnCredential":"record-pass","lastConfigSyncTime":88}',
    });
    expect(result['url'], 'wss://record.example/ws');
  });
}
