import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eir/app_localization.dart';
import 'package:eir/app_settings.dart';
import 'package:eir/models.dart';
import 'package:eir/views/cinema_view.dart';
import 'mvp_ui_flow_test.dart' as ui;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    MediaKit.ensureInitialized();
    await LiquidGlassWidgets.initialize();
    await AppSettings.instance.init();
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
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        locale: const Locale('zh', 'CN'),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('CinemaView shows offline overlay (not swallowing snackbar) when lastErrorCode is source_offline',
      (WidgetTester tester) async {
    final session = ui.FakeRoomSession();
    session.role = RoomRole.member;
    session.lastErrorCode = 'source_offline';

    await tester.pumpWidget(
      buildTestWrapper(CinemaView(session: session, onLeaveRoom: () {})),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Offline overlay title + description (persistent indication that
    // survives the 5s snackbar; pre-existing code at init does not re-fire
    // the snackbar by design, so the overlay is the asserted truth).
    expect(find.text('供片端暂时离线'), findsOneWidget);
    expect(find.text('该条目的提供者连接中断，正在等待重新连线以恢复播放...'), findsOneWidget);
    session.dispose();
  });

  testWidgets('CinemaView hides offline overlay for other codes and shows buffering',
      (WidgetTester tester) async {
    final session = ui.FakeRoomSession();
    session.role = RoomRole.member;
    session.lastErrorCode = 'media_probe_failed';

    await tester.pumpWidget(
      buildTestWrapper(CinemaView(session: session, onLeaveRoom: () {})),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('供片端暂时离线'), findsNothing);
    session.dispose();
  });
}
