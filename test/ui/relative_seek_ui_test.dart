import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eir/app_localization.dart';
import 'package:eir/app_settings.dart';
import 'package:eir/models.dart';
import 'package:eir/views/cinema_view.dart';

class _FakeRelativeSeekSession extends ChangeNotifier implements RoomSession {
  @override
  DeviceIdentityInfo identity = DeviceIdentityInfo(
    deviceId: 'test-device-id-1234567890abcdef',
    publicKeyBase64: 'fake-pubkey==',
  );
  @override
  RoomConnectionState connectionState = RoomConnectionState.connected;
  @override
  String? roomId = 'test-room-uuid-1234';
  @override
  String? inviteText = 'eir://room?id=test-room-uuid-1234&token=someToken';
  @override
  String? roomCode = '654321';
  @override
  RoomRole role = RoomRole.owner;
  @override
  List<RoomMember> members = [];
  @override
  List<PlaylistItem> playlist = [];
  @override
  String? currentItemId;
  @override
  PlaybackState playback = PlaybackState();
  @override
  Player get player => Player();
  @override
  bool p2pConnecting = false;
  @override
  bool p2pFailed = false;
  @override
  Map<String, MemberTelemetry> memberTelemetry = {};
  @override
  String? lastErrorCode;
  @override
  bool get isP2pConnected => false;
  @override
  bool get isP2pConnecting => p2pConnecting;
  @override
  bool get isP2pFailed => p2pFailed;
  @override
  bool waitForPeerBuffering = true;
  @override
  bool isHostWaitingPeerBuffering = false;
  @override
  bool isAnyPeerBuffering = false;
  @override
  PlaybackLoopMode loopMode = PlaybackLoopMode.loopAll;
  @override
  Stream<DanmakuMessage> get danmakuStream => const Stream.empty();
  @override
  List<ChatMessage> get chatMessages => const [];
  @override
  late final CallSession callSession = CallSession(
    sendSignal: (_) async {},
    getCurrentDeviceId: () => identity.deviceId,
    getCurrentDisplayName: () => 'Tester',
    getCurrentAvatar: () => null,
  );
  @override
  void sendChatMessage(String text) {}

  Duration? lastRelativeSeekOffset;

  @override
  Future<void> seekRelative(Duration offset) async {
    lastRelativeSeekOffset = offset;
    notifyListeners();
  }

  @override
  bool isItemSourceOffline(PlaylistItem item) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.init();
    MediaKit.ensureInitialized();
  });

  testWidgets('CinemaView shortcut ArrowRight/Left and UI seek triggers seekRelative', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final session = _FakeRelativeSeekSession();
    session.playlist = [
      PlaylistItem(
        itemId: 'sample-video-1',
        title: 'Sample Video',
        sourceType: 'url',
        url: 'http://127.0.0.1:8080/sample.mp4',
        duration: const Duration(minutes: 5),
      ),
    ];
    session.currentItemId = 'sample-video-1';
    session.playback = PlaybackState(
      mode: PlaybackMode.playing,
      position: const Duration(seconds: 30),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN')],
        home: LiquidGlassWidgets.wrap(
          child: CinemaView(
            session: session,
            onLeaveRoom: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Test Keyboard shortcut ArrowRight (+10s)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(session.lastRelativeSeekOffset, const Duration(seconds: 10));

    // 2. Test Keyboard shortcut ArrowLeft (-10s)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(session.lastRelativeSeekOffset, const Duration(seconds: -10));

    // 3. Enter the real fullscreen console (f shortcut) so ±10 buttons render
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();

    // 4. Test on-screen button cinema-forward-10-btn (+10s)
    final forwardBtn = find.byKey(const ValueKey('cinema-forward-10-btn'));
    expect(forwardBtn, findsOneWidget);
    await tester.tap(forwardBtn);
    await tester.pump();
    expect(session.lastRelativeSeekOffset, const Duration(seconds: 10));

    // 5. Test on-screen button cinema-rewind-10-btn (-10s)
    final rewindBtn = find.byKey(const ValueKey('cinema-rewind-10-btn'));
    expect(rewindBtn, findsOneWidget);
    await tester.tap(rewindBtn);
    await tester.pump();
    expect(session.lastRelativeSeekOffset, const Duration(seconds: -10));
  });
}
