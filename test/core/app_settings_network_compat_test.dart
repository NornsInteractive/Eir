import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eir/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads legacy scalar network keys when the record is absent', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'eir_setting_server_domain': 'https://legacy.example',
      'eir_setting_signaling_url': 'wss://legacy.example/ws',
      'eir_setting_turn_server': 'legacy.turn.example:3478',
      'eir_setting_turn_username': 'legacy-user',
      'eir_setting_turn_credential': 'legacy-pass',
      'eir_last_config_sync_time': 77,
      'eir_setting_theme_mode': 'dark',
    });
    SharedPreferences.resetStatic();

    await AppSettings.instance.init();

    final settings = AppSettings.instance;
    expect(settings.serverDomain, 'https://legacy.example');
    expect(settings.signalingUrl, 'wss://legacy.example/ws');
    expect(settings.turnServer, 'legacy.turn.example:3478');
    expect(settings.turnUsername, 'legacy-user');
    expect(settings.turnCredential, 'legacy-pass');
    expect(settings.lastConfigSyncTime, 77);
    expect(settings.themeMode.name, 'dark');
  });
}
