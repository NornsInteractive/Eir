import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eir/app_settings.dart';
import 'package:eir/core/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateService and AppSettings pending update tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('AppSettings hasPendingUpdate toggle and persistence', () async {
      final settings = AppSettings.instance;
      expect(settings.hasPendingUpdate, isFalse);

      bool notified = false;
      void listener() {
        notified = true;
      }

      settings.addListener(listener);

      await settings.setPendingUpdate(true);
      expect(settings.hasPendingUpdate, isTrue);
      expect(notified, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('eir_has_pending_update'), isTrue);

      notified = false;
      await settings.setPendingUpdate(false);
      expect(settings.hasPendingUpdate, isFalse);
      expect(notified, isTrue);
      expect(prefs.getBool('eir_has_pending_update'), isFalse);

      settings.removeListener(listener);
    });

    test('AppSettings lastUpdateCheckDate tracking', () async {
      final settings = AppSettings.instance;
      const today = '2026-11-11';
      await settings.setLastUpdateCheckDate(today);
      expect(settings.lastUpdateCheckDate, equals(today));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('eir_last_update_check_date'), equals(today));
    });

    test('UpdateInfo model parsing from Yggdrasil API format', () {
      final json = {
        'code': 0,
        'message': 'success',
        'data': {
          'has_update': true,
          'is_force': false,
          'app_id': 'com.norns.eir',
          'app_name': 'Eir',
          'version_code': 5,
          'version_name': '1.0.4',
          'changelog': 'Bug fixes and performance improvements',
          'download_url': 'https://example.com/eir.apk',
          'short_download_url': 'https://s.example.com/eir',
          'file_size': 10485760,
          'file_name': 'eir-v1.0.4.apk',
        }
      };

      final info = UpdateInfo.fromJson(
        json['data'] as Map<String, dynamic>,
        activeVersionCode: 4,
      );

      expect(info.hasUpdate, isTrue);
      expect(info.isForce, isFalse);
      expect(info.latestVersionCode, equals(5));
      expect(info.latestVersionName, equals('1.0.4'));
      expect(info.downloadUrl, equals('https://example.com/eir.apk'));
      expect(info.shortDownloadUrl, equals('https://s.example.com/eir'));
      expect(info.fileSize, equals(10485760));
    });
  });
}
