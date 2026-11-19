import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eir/app_localization.dart';
import 'package:eir/app_settings.dart';
import 'package:eir/core/room_session.dart';
import 'package:eir/core/screen_share_service.dart';
import 'package:eir/views/screen_share_live_view.dart';

import 'mvp_ui_flow_test.dart' show FakeRoomSession;

class _StatsTestScreenShareService extends ScreenShareService {
  _StatsTestScreenShareService({
    this.customRttMs,
    this.customBitrateMbps,
    this.customPacketLoss,
  }) : super(
          sendSignal: (_) async {},
          getCurrentDeviceId: () => 'dev-tester',
          getCurrentDisplayName: () => 'Tester',
          getCurrentAvatar: () => null,
        );

  final int? customRttMs;
  final double? customBitrateMbps;
  final double? customPacketLoss;

  @override
  int? get rttMs => customRttMs;

  @override
  double? get bitrateMbps => customBitrateMbps;

  @override
  double? get packetLoss => customPacketLoss;

  @override
  bool get isActive => true;
}

class _StatsTestRoomSession extends FakeRoomSession {
  _StatsTestRoomSession(this._customService);

  final ScreenShareService _customService;

  @override
  ScreenShareService get screenShareService => _customService;
}

Widget _wrapWithApp(Widget child, {Locale locale = const Locale('zh', 'CN')}) {
  return LiquidGlassWidgets.wrap(
    child: MaterialApp(
      locale: locale,
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

  group('Screen Share Stream Health UI Tests', () {
    testWidgets('shows localized "暂无数据" when metrics are individually or all null (no ?? 0 fallback)', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = _StatsTestScreenShareService(
        customRttMs: null,
        customBitrateMbps: null,
        customPacketLoss: null,
      );
      final session = _StatsTestRoomSession(service);

      await tester.pumpWidget(_wrapWithApp(ScreenShareLiveView(session: session)));
      await tester.pump();

      // Tap on the 60 FPS live indicator pill to show health sheet
      final fpsIndicator = find.text('60 FPS');
      expect(fpsIndicator, findsOneWidget);
      await tester.tap(fpsIndicator);
      await tester.pump(const Duration(milliseconds: 300));

      // Diagnostics sheet header
      expect(find.text('实时网络与画质看板'), findsOneWidget);
      expect(find.text('实时帧率'), findsOneWidget);
      expect(find.text('往返延迟'), findsOneWidget);
      expect(find.text('实时码率'), findsOneWidget);
      expect(find.text('丢包率'), findsOneWidget);

      // Verify "暂无数据" appears for RTT, Bitrate, and Packet Loss
      expect(find.text('暂无数据'), findsNWidgets(3));

      // Verify that no ?? 0 placeholders are displayed
      expect(find.text('0 ms'), findsNothing);
      expect(find.text('0.0 Mbps'), findsNothing);
      expect(find.text('0.0%'), findsNothing);
    });

    testWidgets('shows correctly formatted values when metrics are present', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = _StatsTestScreenShareService(
        customRttMs: 42,
        customBitrateMbps: 3.8,
        customPacketLoss: 0.012, // 1.2%
      );
      final session = _StatsTestRoomSession(service);

      await tester.pumpWidget(_wrapWithApp(ScreenShareLiveView(session: session)));
      await tester.pump();

      // Tap on the 60 FPS live indicator pill to open health sheet
      await tester.tap(find.text('60 FPS'));
      await tester.pump(const Duration(milliseconds: 300));

      // Check values
      expect(find.text('42 ms'), findsOneWidget);
      expect(find.text('3.8 Mbps'), findsOneWidget);
      expect(find.text('1.2%'), findsOneWidget);
      expect(find.text('暂无数据'), findsNothing);
    });

    testWidgets('supports English locale and partial null metrics independently', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Partial null: RTT present, Bitrate null, Packet Loss present
      final service = _StatsTestScreenShareService(
        customRttMs: 28,
        customBitrateMbps: null,
        customPacketLoss: 0.005,
      );
      final session = _StatsTestRoomSession(service);

      await tester.pumpWidget(_wrapWithApp(
        ScreenShareLiveView(session: session),
        locale: const Locale('en', 'US'),
      ));
      await tester.pump();

      await tester.tap(find.text('60 FPS'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Stream Diagnostics'), findsOneWidget);
      expect(find.text('28 ms'), findsOneWidget);
      expect(find.text('No data'), findsOneWidget); // for bitrate
      expect(find.text('0.5%'), findsOneWidget);
    });
  });
}
