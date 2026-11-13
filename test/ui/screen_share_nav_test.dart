import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eir/app_localization.dart';
import 'package:eir/app_settings.dart';
import 'package:eir/views/lobby_view.dart';
import 'package:eir/views/screen_share_lobby_view.dart';
import 'package:eir/views/profile_view.dart';

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
  });

  group('Screen Share Navigation UI Tests', () {
    testWidgets('LobbyView displays 3 bottom tabs and navigates cleanly between Lobby, ScreenShare, and Profile', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final session = FakeRoomSession();

      await tester.pumpWidget(createTestApp(LobbyView(session: session)));
      await tester.pumpAndSettle();

      // Bottom bar has 大厅, 投屏, 我的
      expect(find.text('大厅'), findsWidgets);
      expect(find.text('投屏'), findsWidgets);
      expect(find.text('我的'), findsWidgets);

      // Initially on Lobby (Create Cinema Room button is visible)
      expect(find.text('创建专属放映室'), findsOneWidget);

      // 1. Switch to 投屏 tab
      await tester.tap(find.text('投屏').first);
      await tester.pumpAndSettle();

      // Verify ScreenShareLobbyView is rendered
      expect(find.byType(ScreenShareLobbyView), findsOneWidget);
      expect(find.text('实时投屏'), findsOneWidget);
      expect(find.byKey(const ValueKey('start-screen-share-btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('cast-code-input')), findsOneWidget);
      expect(find.byKey(const ValueKey('join-cast-btn')), findsOneWidget);
      expect(find.text('捕获指定应用窗口或整机屏幕'), findsOneWidget);
      expect(find.text('或输入 6 位投屏码观看'), findsOneWidget);

      // 2. Switch to 我的 tab
      await tester.tap(find.text('我的').first);
      await tester.pumpAndSettle();

      // Verify ProfileView is rendered
      expect(find.byType(ProfileView), findsOneWidget);
      expect(find.text('偏好与设置'), findsOneWidget);

      // 3. Switch back to 大厅 tab
      await tester.tap(find.text('大厅').first);
      await tester.pumpAndSettle();

      // Verify Lobby is rendered back
      expect(find.text('创建专属放映室'), findsOneWidget);
    });
  });
}
