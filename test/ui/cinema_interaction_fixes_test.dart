import 'dart:async';
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

class _FakeCinemaRoomSession extends ChangeNotifier implements RoomSession {
  @override
  DeviceIdentityInfo identity = DeviceIdentityInfo(
    deviceId: 'test-device-id-host',
    publicKeyBase64: 'fake-pubkey==',
  );

  @override
  RoomConnectionState connectionState = RoomConnectionState.connected;

  @override
  String? roomId = 'test-room-uuid-1234';

  @override
  String? inviteText = 'eir://room?id=test-room-uuid-1234';

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
  bool get isP2pConnected => true;

  @override
  bool get isP2pConnecting => false;

  @override
  bool get isP2pFailed => false;

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

  int closeRoomCalls = 0;
  int leaveRoomCalls = 0;

  @override
  Future<void> closeRoom() async {
    closeRoomCalls++;
  }

  @override
  Future<void> leaveRoom() async {
    leaveRoomCalls++;
  }

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

  Widget createSubject(RoomSession session, {VoidCallback? onLeave}) {
    return MaterialApp(
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
          onLeaveRoom: onLeave ?? () {},
        ),
      ),
    );
  }

  testWidgets('BUG-CONN-09: Back button triggers secondary confirmation dialog before room disband', (tester) async {
    final session = _FakeCinemaRoomSession();
    bool leaveCallbackInvoked = false;

    await tester.pumpWidget(createSubject(session, onLeave: () {
      leaveCallbackInvoked = true;
    }));
    await tester.pumpAndSettle();

    // Find the leading back button
    final backBtn = find.byKey(const ValueKey('cinema-back-leave-btn'));
    expect(backBtn, findsOneWidget);

    // Tap back button
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    // Confirmation dialog must appear
    expect(find.text('解散房间'), findsWidgets);
    expect(find.text('解散房间后，所有正在一起观影的好友都将断开连接。确定解散吗？'), findsOneWidget);
    expect(session.closeRoomCalls, 0);
    expect(leaveCallbackInvoked, isFalse);

    // Cancel first
    final cancelBtn = find.text('取消');
    expect(cancelBtn, findsOneWidget);
    await tester.tap(cancelBtn);
    await tester.pumpAndSettle();

    // Verify dialog dismissed and room NOT closed
    expect(find.text('解散房间后，所有正在一起观影的好友都将断开连接。确定解散吗？'), findsNothing);
    expect(session.closeRoomCalls, 0);
    expect(leaveCallbackInvoked, isFalse);

    // Tap back again and confirm disband
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    final confirmDisbandBtn = find.text('解散');
    expect(confirmDisbandBtn, findsOneWidget);
    await tester.tap(confirmDisbandBtn);
    await tester.pumpAndSettle();

    expect(session.closeRoomCalls, 1);
    expect(leaveCallbackInvoked, isTrue);
  });

  testWidgets('BUG-PLAY-06: Host displays peer buffering waiting banner when isHostWaitingPeerBuffering is true', (tester) async {
    final session = _FakeCinemaRoomSession();
    session.isHostWaitingPeerBuffering = true;

    await tester.pumpWidget(createSubject(session));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('好友正在缓冲，已为您暂停等候...'), findsOneWidget);
  });
}
