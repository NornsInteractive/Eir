import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eir/app_localization.dart';
import 'package:eir/app_settings.dart';
import 'package:eir/models.dart';
import 'package:eir/views/profile_view.dart';
import 'package:eir/views/lobby_view.dart';

import 'mvp_ui_flow_test.dart' show FakeRoomSession;

Widget createTestApp(Widget child) {
  return LiquidGlassWidgets.wrap(
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized();
    await LiquidGlassWidgets.initialize();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.init();
    await AppSettings.instance.setNickname('');
    await AppSettings.instance.setAvatar('preset:aurora');
  });

  group('ProfileView Widget Tests', () {
    testWidgets('renders ProfileView with avatar, default nickname, and device ID', (tester) async {
      final session = FakeRoomSession();

      await tester.pumpWidget(createTestApp(ProfileView(session: session)));
      await tester.pumpAndSettle();

      expect(find.byType(UserAvatar), findsWidgets);
      expect(find.text('影视爱好者'), findsOneWidget);
      expect(find.text(formatDeviceId(session.identity.deviceId)), findsOneWidget);
      expect(find.text('偏好与设置'), findsOneWidget);
      expect(find.text('存储与缓存'), findsOneWidget);
      expect(find.text('信令与网络'), findsOneWidget);
    });

    testWidgets('modifies nickname and saves to AppSettings', (tester) async {
      final session = FakeRoomSession();

      await tester.pumpWidget(createTestApp(ProfileView(session: session)));
      await tester.pumpAndSettle();

      // Tap on nickname row to edit
      await tester.tap(find.text('影视爱好者'));
      await tester.pumpAndSettle();

      // Verify TextField appears
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      // Enter new nickname
      await tester.enterText(textField, '电影达人Alice');
      await tester.pumpAndSettle();

      // Tap save button
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // Verify nickname updated in AppSettings and UI
      expect(AppSettings.instance.nickname, '电影达人Alice');
      expect(find.text('电影达人Alice'), findsOneWidget);
      expect(find.text('昵称已更新'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('opens avatar picker sheet and selects new preset', (tester) async {
      final session = FakeRoomSession();

      await tester.pumpWidget(createTestApp(ProfileView(session: session)));
      await tester.pumpAndSettle();

      // Tap avatar to open sheet
      await tester.tap(find.byType(UserAvatar).first);
      await tester.pumpAndSettle();

      expect(find.text('选择预设头像'), findsOneWidget);
      expect(find.text('星云紫罗'), findsOneWidget);

      // Tap '星云紫罗' preset
      await tester.tap(find.text('星云紫罗'));
      await tester.pumpAndSettle();

      expect(AppSettings.instance.avatar, 'preset:nebula');
    });

    testWidgets('LobbyView bottom navigation has 大厅 and 我的 tabs and switches body', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final session = FakeRoomSession();

      await tester.pumpWidget(createTestApp(LobbyView(session: session)));
      await tester.pumpAndSettle();

      // Bottom nav bar should show '大厅' and '我的'
      expect(find.text('大厅'), findsWidgets);
      expect(find.text('我的'), findsWidgets);

      // Initially on Lobby tab (creates room button is visible)
      expect(find.text('创建专属放映室'), findsOneWidget);

      // Tap '我的' tab
      await tester.tap(find.text('我的').first);
      await tester.pumpAndSettle();

      // Now ProfileView is rendered
      expect(find.byType(ProfileView), findsOneWidget);
      expect(find.text('偏好与设置'), findsOneWidget);

      // Tap '大厅' tab to return
      await tester.tap(find.text('大厅').first);
      await tester.pumpAndSettle();

      expect(find.text('创建专属放映室'), findsOneWidget);
    });
  });
}
