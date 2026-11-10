import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:eir/app_settings.dart';

const _kSignalingKey = 'eir_setting_signaling_url';

/// Store that reports write failure (returns false) without persisting.
class _FalseWriteStore extends SharedPreferencesStorePlatform {
  _FalseWriteStore(this._data);
  final Map<String, Object> _data;
  int setValueCalls = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    setValueCalls++;
    return false;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final filter = parameters.filter;
    _data.removeWhere(
      (String key, _) =>
          key.startsWith(filter.prefix) &&
          (filter.allowList == null || filter.allowList!.contains(key)),
    );
    return true;
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    final filter = parameters.filter;
    final result = Map<String, Object>.from(_data);
    result.removeWhere(
      (String key, _) =>
          !key.startsWith(filter.prefix) ||
          (filter.allowList != null && !filter.allowList!.contains(key)),
    );
    return result;
  }

  @override
  Future<bool> clear() async => clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));
}

/// Store that throws on write, simulating platform exception.
class _ThrowWriteStore extends SharedPreferencesStorePlatform {
  _ThrowWriteStore(this._data);
  final Map<String, Object> _data;
  int setValueCalls = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    setValueCalls++;
    throw Exception('simulated platform write failure');
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final filter = parameters.filter;
    _data.removeWhere(
      (String key, _) =>
          key.startsWith(filter.prefix) &&
          (filter.allowList == null || filter.allowList!.contains(key)),
    );
    return true;
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    final filter = parameters.filter;
    final result = Map<String, Object>.from(_data);
    result.removeWhere(
      (String key, _) =>
          !key.startsWith(filter.prefix) ||
          (filter.allowList != null && !filter.allowList!.contains(key)),
    );
    return result;
  }

  @override
  Future<bool> clear() async => clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));
}

Future<void> _restoreHealthyStore(String signalingUrl) async {
  SharedPreferences.setMockInitialValues({_kSignalingKey: signalingUrl});
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.init();
  });

  group('AppSettings.setSignalingUrl persistence contract', () {
    test('successful await persists, updates memory and notifies', () async {
      final original = AppSettings.instance.signalingUrl;
      var notifications = 0;
      void listener() => notifications++;
      AppSettings.instance.addListener(listener);
      addTearDown(() async {
        AppSettings.instance.removeListener(listener);
        await _restoreHealthyStore(original);
        await AppSettings.instance.setSignalingUrl(original);
      });

      const target = 'ws://192.168.1.50:9123';
      await AppSettings.instance.setSignalingUrl(target);

      expect(AppSettings.instance.signalingUrl, target);
      expect(notifications, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kSignalingKey), target);
    });

    test('trimmed input is persisted trimmed', () async {
      final original = AppSettings.instance.signalingUrl;
      addTearDown(() async {
        await _restoreHealthyStore(original);
        await AppSettings.instance.setSignalingUrl(original);
      });

      await AppSettings.instance
          .setSignalingUrl('  ws://192.168.1.51:9124  ');
      expect(AppSettings.instance.signalingUrl, 'ws://192.168.1.51:9124');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kSignalingKey), 'ws://192.168.1.51:9124');
    });

    test('illegal addresses are rejected without write or notify', () async {
      final original = AppSettings.instance.signalingUrl;
      await _restoreHealthyStore(original);
      await AppSettings.instance.setSignalingUrl(original);
      var notifications = 0;
      void listener() => notifications++;
      AppSettings.instance.addListener(listener);
      addTearDown(() {
        AppSettings.instance.removeListener(listener);
      });

      for (final bad in <String>[
        'http://bad-host',
        'wss://',
        'ws://',
        '',
        '   ',
        'ws:invalid',
        'ftp://127.0.0.1:9999',
      ]) {
        await expectLater(
          AppSettings.instance.setSignalingUrl(bad),
          throwsArgumentError,
          reason: 'bad=$bad must be rejected',
        );
      }
      expect(AppSettings.instance.signalingUrl, original);
      expect(notifications, 0);
      SharedPreferences.resetStatic();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kSignalingKey), original);
    });

    test('write returning false retains memory and persistent storage', () async {
      final original = AppSettings.instance.signalingUrl;
      await _restoreHealthyStore(original);
      await AppSettings.instance.setSignalingUrl(original);

      final store = _FalseWriteStore(
        <String, Object>{'flutter.$_kSignalingKey': original},
      );
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();

      var notifications = 0;
      void listener() => notifications++;
      AppSettings.instance.addListener(listener);
      addTearDown(() async {
        AppSettings.instance.removeListener(listener);
        await _restoreHealthyStore(original);
      });

      await expectLater(
        AppSettings.instance.setSignalingUrl('ws://192.168.1.52:9125'),
        throwsStateError,
      );
      expect(store.setValueCalls, 1);
      expect(AppSettings.instance.signalingUrl, original);
      expect(notifications, 0);
      SharedPreferences.resetStatic();
      final reloaded = await SharedPreferences.getInstance();
      expect(reloaded.getString(_kSignalingKey), original);
    });

    test('write throwing retains memory and persistent storage', () async {
      final original = AppSettings.instance.signalingUrl;
      await _restoreHealthyStore(original);
      await AppSettings.instance.setSignalingUrl(original);

      final store = _ThrowWriteStore(
        <String, Object>{'flutter.$_kSignalingKey': original},
      );
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();

      var notifications = 0;
      void listener() => notifications++;
      AppSettings.instance.addListener(listener);
      addTearDown(() async {
        AppSettings.instance.removeListener(listener);
        await _restoreHealthyStore(original);
      });

      await expectLater(
        AppSettings.instance.setSignalingUrl('ws://192.168.1.53:9126'),
        throwsException,
      );
      expect(store.setValueCalls, 1);
      expect(AppSettings.instance.signalingUrl, original);
      expect(notifications, 0);
      SharedPreferences.resetStatic();
      final reloaded = await SharedPreferences.getInstance();
      expect(reloaded.getString(_kSignalingKey), original);
    });

    test('retry succeeds after a failed write', () async {
      final original = AppSettings.instance.signalingUrl;
      await _restoreHealthyStore(original);
      await AppSettings.instance.setSignalingUrl(original);

      final failing = _FalseWriteStore(
        <String, Object>{'flutter.$_kSignalingKey': original},
      );
      SharedPreferencesStorePlatform.instance = failing;
      SharedPreferences.resetStatic();
      await expectLater(
        AppSettings.instance.setSignalingUrl('ws://192.168.1.54:9127'),
        throwsStateError,
      );
      expect(AppSettings.instance.signalingUrl, original);

      await _restoreHealthyStore(original);
      addTearDown(() async {
        await _restoreHealthyStore(original);
        await AppSettings.instance.setSignalingUrl(original);
      });
      const target = 'ws://192.168.1.54:9127';
      await AppSettings.instance.setSignalingUrl(target);
      expect(AppSettings.instance.signalingUrl, target);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kSignalingKey), target);
    });

    test('same value is a no-op without notify', () async {
      final original = AppSettings.instance.signalingUrl;
      var notifications = 0;
      void listener() => notifications++;
      AppSettings.instance.addListener(listener);
      addTearDown(() => AppSettings.instance.removeListener(listener));

      await AppSettings.instance.setSignalingUrl(original);
      expect(notifications, 0);
      expect(AppSettings.instance.signalingUrl, original);
    });
  });
}
