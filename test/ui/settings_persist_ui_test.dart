import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:eir/app_localization.dart';
import 'package:eir/app_settings.dart';
import 'package:eir/models.dart';
import 'package:eir/views/settings_dialog.dart';

import 'mvp_ui_flow_test.dart' as ui;

const _kSignalingKey = 'eir_setting_signaling_url';
const _kSavedZh = '信令地址已保存';
const _kSaveErrorZh = '信令地址格式无效，必须以 ws:// 或 wss:// 开头并包含有效主机名';
const _kPersistFailedZh = '信令地址保存失败，请检查存储权限并重试';
const _kInRoomZh = '房内仅保存未来连接地址，不自动打断当前会话';

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

class _GatedSession extends ui.FakeRoomSession {
  Completer<void>? gate;

  @override
  Future<void> setSignalingUrl(String url) async {
    setSignalingUrlCalls++;
    lastSignalingUrl = url;
    final g = gate;
    if (g != null) {
      await g.future;
    }
  }
}

Future<void> _restoreHealthyStore(String signalingUrl) async {
  SharedPreferences.setMockInitialValues({_kSignalingKey: signalingUrl});
}

void main() {
  final activeSessions = <ui.FakeRoomSession>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    MediaKit.ensureInitialized();
    await LiquidGlassWidgets.initialize();
    await AppSettings.instance.init();
  });

  tearDown(() {
    for (final s in activeSessions) {
      if (!s.isDisposed) {
        s.dispose();
      }
    }
    activeSessions.clear();
  });

  Widget buildTestWrapper(Widget child) {
    return LiquidGlassWidgets.wrap(
      brightnessResolver: (_) => Brightness.dark,
      child: MaterialApp(
        theme: ThemeData.dark(),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        locale: const Locale('zh', 'CN'),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('settings remain usable when session initialization has failed',
      (WidgetTester tester) async {
    final session = RoomSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(buildTestWrapper(SettingsDialog(session: session)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('settings-signaling-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-done-btn')), findsOneWidget);
    final input = find.byKey(const ValueKey('settings-signaling-input'));
    await tester.ensureVisible(input);
    await tester.enterText(input, 'ws://127.0.0.1:8765');
    final save = find.byKey(const ValueKey('settings-save-signaling-btn'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text(_kSavedZh), findsOneWidget);
  });

  testWidgets(
      'persist failure shows persist error only, keeps draft, rolls back session future config',
      (WidgetTester tester) async {
    final original = AppSettings.instance.signalingUrl;
    await _restoreHealthyStore(original);
    await AppSettings.instance.setSignalingUrl(original);
    addTearDown(() async {
      await _restoreHealthyStore(original);
      await AppSettings.instance.setSignalingUrl(original);
    });

    const newUrl = 'ws://192.168.1.50:9231';
    final session = ui.FakeRoomSession();
    activeSessions.add(session);
    session.roomId = 'room-persist-rollback';
    session.connectionState = RoomConnectionState.connected;

    await tester.pumpWidget(buildTestWrapper(SettingsDialog(session: session)));
    await tester.pumpAndSettle();
    final urlInput = find.byKey(const ValueKey('settings-signaling-input'));
    await tester.ensureVisible(urlInput);
    await tester.pumpAndSettle();
    await tester.enterText(urlInput, newUrl);
    await tester.pumpAndSettle();

    final store = _FalseWriteStore(
      <String, Object>{'flutter.$_kSignalingKey': original},
    );
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();

    final saveBtn = find.byKey(const ValueKey('settings-save-signaling-btn'));
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(find.text(_kPersistFailedZh), findsOneWidget);
    expect(find.text(_kSavedZh), findsNothing);
    expect(find.text(_kInRoomZh), findsNothing);
    expect(find.text(_kSaveErrorZh), findsNothing);

    final editable = find.descendant(
      of: urlInput,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).controller.text, newUrl);

    expect(AppSettings.instance.signalingUrl, original);
    SharedPreferences.resetStatic();
    final reloaded = await SharedPreferences.getInstance();
    expect(reloaded.getString(_kSignalingKey), original);

    expect(session.setSignalingUrlCalls, 2);
    expect(session.lastSignalingUrl, original);
    expect(session.roomId, 'room-persist-rollback');
    expect(session.connectionState, RoomConnectionState.connected);
    expect(session.isDisposed, isFalse);
  });

  testWidgets('persist failure without session keeps draft and memory',
      (WidgetTester tester) async {
    final original = AppSettings.instance.signalingUrl;
    await _restoreHealthyStore(original);
    await AppSettings.instance.setSignalingUrl(original);
    addTearDown(() async {
      await _restoreHealthyStore(original);
      await AppSettings.instance.setSignalingUrl(original);
    });

    const newUrl = 'ws://192.168.1.50:9232';
    await tester.pumpWidget(buildTestWrapper(const SettingsDialog()));
    await tester.pumpAndSettle();
    final urlInput = find.byKey(const ValueKey('settings-signaling-input'));
    await tester.ensureVisible(urlInput);
    await tester.pumpAndSettle();
    await tester.enterText(urlInput, newUrl);
    await tester.pumpAndSettle();

    final store = _FalseWriteStore(
      <String, Object>{'flutter.$_kSignalingKey': original},
    );
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();

    await tester.ensureVisible(
        find.byKey(const ValueKey('settings-save-signaling-btn')));
    await tester.tap(find.byKey(const ValueKey('settings-save-signaling-btn')));
    await tester.pumpAndSettle();

    expect(find.text(_kPersistFailedZh), findsOneWidget);
    expect(find.text(_kSavedZh), findsNothing);
    final editable = find.descendant(
      of: urlInput,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).controller.text, newUrl);
    expect(AppSettings.instance.signalingUrl, original);
  });

  testWidgets('retry succeeds after persist failure', (WidgetTester tester) async {
    final original = AppSettings.instance.signalingUrl;
    await _restoreHealthyStore(original);
    await AppSettings.instance.setSignalingUrl(original);
    addTearDown(() async {
      await _restoreHealthyStore(original);
      await AppSettings.instance.setSignalingUrl(original);
    });

    const newUrl = 'ws://192.168.1.50:9233';
    final session = ui.FakeRoomSession();
    activeSessions.add(session);
    await tester.pumpWidget(buildTestWrapper(SettingsDialog(session: session)));
    await tester.pumpAndSettle();
    final urlInput = find.byKey(const ValueKey('settings-signaling-input'));
    await tester.ensureVisible(urlInput);
    await tester.pumpAndSettle();
    await tester.enterText(urlInput, newUrl);
    await tester.pumpAndSettle();

    final failing = _FalseWriteStore(
      <String, Object>{'flutter.$_kSignalingKey': original},
    );
    SharedPreferencesStorePlatform.instance = failing;
    SharedPreferences.resetStatic();

    final saveBtn = find.byKey(const ValueKey('settings-save-signaling-btn'));
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();
    expect(find.text(_kPersistFailedZh), findsOneWidget);
    expect(AppSettings.instance.signalingUrl, original);
    expect(session.lastSignalingUrl, original);

    await _restoreHealthyStore(original);
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(find.text(_kSavingShown()), findsNothing);
    expect(AppSettings.instance.signalingUrl, newUrl);
    expect(session.lastSignalingUrl, newUrl);
    expect(find.text(_kSavedZh), findsOneWidget);
    expect(find.text(_kPersistFailedZh), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_kSignalingKey), newUrl);
  });

  testWidgets('format error does not show persist failure', (WidgetTester tester) async {
    final original = AppSettings.instance.signalingUrl;
    await _restoreHealthyStore(original);
    await AppSettings.instance.setSignalingUrl(original);
    addTearDown(() async {
      await _restoreHealthyStore(original);
      await AppSettings.instance.setSignalingUrl(original);
    });

    await tester.pumpWidget(buildTestWrapper(const SettingsDialog()));
    await tester.pumpAndSettle();
    final urlInput = find.byKey(const ValueKey('settings-signaling-input'));
    await tester.ensureVisible(urlInput);
    await tester.pumpAndSettle();
    await tester.enterText(urlInput, 'http://bad-host');
    await tester.ensureVisible(
        find.byKey(const ValueKey('settings-save-signaling-btn')));
    await tester.tap(find.byKey(const ValueKey('settings-save-signaling-btn')));
    await tester.pumpAndSettle();

    expect(find.text(_kSaveErrorZh), findsOneWidget);
    expect(find.text(_kPersistFailedZh), findsNothing);
    expect(find.text(_kSavedZh), findsNothing);
    expect(AppSettings.instance.signalingUrl, original);
  });

  testWidgets('double tap while saving does not duplicate session call',
      (WidgetTester tester) async {
    final original = AppSettings.instance.signalingUrl;
    const newUrl = 'ws://192.168.1.50:9234';
    addTearDown(() async {
      await _restoreHealthyStore(original);
      await AppSettings.instance.setSignalingUrl(original);
    });
    await _restoreHealthyStore(original);
    await AppSettings.instance.setSignalingUrl(original);

    final session = _GatedSession();
    activeSessions.add(session);
    final gate = Completer<void>();
    session.gate = gate;

    await tester.pumpWidget(buildTestWrapper(SettingsDialog(session: session)));
    await tester.pumpAndSettle();
    final urlInput = find.byKey(const ValueKey('settings-signaling-input'));
    await tester.ensureVisible(urlInput);
    await tester.pumpAndSettle();
    await tester.enterText(urlInput, newUrl);
    await tester.pumpAndSettle();

    final saveBtn = find.byKey(const ValueKey('settings-save-signaling-btn'));
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(session.setSignalingUrlCalls, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(session.setSignalingUrlCalls, 1);
    expect(session.lastSignalingUrl, newUrl);
    expect(AppSettings.instance.signalingUrl, newUrl);
    expect(find.text(_kSavedZh), findsOneWidget);
  });
}

String _kSavingShown() => '保存中...';
