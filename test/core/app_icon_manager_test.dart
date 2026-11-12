import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eir/app_settings.dart';
import 'package:eir/core/app_icon_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('AppIconStyle resolves valid IDs and falls back gracefully', () {
    expect(AppIconStyle.fromId('classic'), equals(AppIconStyle.classic));
    expect(AppIconStyle.fromId('neon'), equals(AppIconStyle.neon));
    expect(AppIconStyle.fromId('stealth'), equals(AppIconStyle.stealth));
    expect(AppIconStyle.fromId('silver'), equals(AppIconStyle.silver));
    expect(AppIconStyle.fromId('custom'), equals(AppIconStyle.custom));
    expect(AppIconStyle.fromId('unknown_invalid'), equals(AppIconStyle.classic));
    expect(AppIconStyle.fromId(null), equals(AppIconStyle.classic));
  });

  test('AppSettings persists appIconStyle and customAppIconPath independently', () async {
    final settings = AppSettings.instance;
    await settings.init();

    expect(settings.appIconStyle, equals('classic'));
    expect(settings.customAppIconPath, isNull);

    await settings.setAppIconStyle('neon');
    expect(settings.appIconStyle, equals('neon'));

    await settings.setCustomAppIconPath('/tmp/my_icon.png');
    expect(settings.customAppIconPath, equals('/tmp/my_icon.png'));

    // Reinitialize to test persistence
    await settings.init();
    expect(settings.appIconStyle, equals('neon'));
    expect(settings.customAppIconPath, equals('/tmp/my_icon.png'));

    // Clear custom path
    await settings.setCustomAppIconPath(null);
    expect(settings.customAppIconPath, isNull);
  });
}
