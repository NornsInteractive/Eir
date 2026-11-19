import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eir/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canonical record overrides legacy scalar network values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'eir_setting_server_domain': 'https://legacy.example',
      'eir_setting_signaling_url': 'wss://legacy.example/ws',
      'eir_setting_turn_server': 'legacy.turn.example:3478',
      'eir_setting_turn_username': 'legacy-user',
      'eir_setting_turn_credential': 'legacy-pass',
      'eir_last_config_sync_time': 77,
      'eir_setting_theme_mode': 'light',
      'eir_setting_network_config': jsonEncode(<String, Object>{
        'serverDomain': 'https://record.example',
        'signalingUrl': 'wss://record.example/ws',
        'turnServer': 'record.turn.example:3478',
        'turnUsername': 'record-user',
        'turnCredential': 'record-pass',
        'lastConfigSyncTime': 88,
      }),
    });
    SharedPreferences.resetStatic();

    await AppSettings.instance.init();

    final settings = AppSettings.instance;
    expect(settings.serverDomain, 'https://record.example');
    expect(settings.signalingUrl, 'wss://record.example/ws');
    expect(settings.turnServer, 'record.turn.example:3478');
    expect(settings.turnUsername, 'record-user');
    expect(settings.turnCredential, 'record-pass');
    expect(settings.lastConfigSyncTime, 88);
    expect(settings.themeMode.name, 'light');
  });
}
