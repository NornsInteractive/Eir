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

class _FakeChatCallRoomSession extends ChangeNotifier implements RoomSession {
  @override
  DeviceIdentityInfo identity = DeviceIdentityInfo(
    deviceId: 'host-dev-123',
    publicKeyBase64: 'fake-pub==',
  );

  @override
  RoomConnectionState connectionState = RoomConnectionState.connected;

  @override
  String? roomId = 'test-room-uuid';

  @override
  String? inviteText = 'eir://room?id=test-room-uuid';

  @override
  String? roomCode = '123456';

  @override
  RoomRole role = RoomRole.owner;

  @override
  List<RoomMember> members = [
    RoomMember(
      deviceId: 'host-dev-123',
      displayName: 'HostAlice',
      role: RoomRole.owner,
      online: true,
    ),
    RoomMember(
      deviceId: 'peer-dev-456',
      displayName: 'PeerBob',
      role: RoomRole.member,
      online: true,
    ),
  ];

  @override
  List<PlaylistItem> playlist = [
      PlaylistItem(
        itemId: 'item-1',
        title: 'Video.mp4',
        sourceType: 'url',
        url: 'https://example.com/v.mp4',
      ),
  ];

  @override
  String? currentItemId = 'item-1';

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

  final StreamController<DanmakuMessage> _danmakuController =
      StreamController<DanmakuMessage>.broadcast();

  @override
  Stream<DanmakuMessage> get danmakuStream => _danmakuController.stream;

  final List<ChatMessage> _chatMessages = [];

  @override
  List<ChatMessage> get chatMessages => List.unmodifiable(_chatMessages);

  @override
  late final CallSession callSession = CallSession(
    sendSignal: (_) async {},
    getCurrentDeviceId: () => identity.deviceId,
    getCurrentDisplayName: () => 'HostAlice',
    getCurrentAvatar: () => null,
  );

  @override
  bool isItemSourceOffline(PlaylistItem item) => false;

  @override
  void sendChatMessage(String text) {
    final msg = ChatMessage(
      id: 'chat-${DateTime.now().microsecondsSinceEpoch}',
      senderDeviceId: identity.deviceId,
      senderName: 'HostAlice',
      text: text,
      timestamp: DateTime.now(),
      isSelf: true,
    );
    _chatMessages.add(msg);
    _danmakuController.add(DanmakuMessage(
      id: msg.id,
      sender: msg.senderName,
      text: msg.text,
      timestamp: msg.timestamp,
    ));
    notifyListeners();
  }

  @override
  void sendDanmaku(String text) => sendChatMessage(text);

  @override
  Future<void> closeRoom() async {}

  @override
  Future<void> leaveRoom() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh', 'CN')],
    home: LiquidGlassWidgets.wrap(child: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.init();
    MediaKit.ensureInitialized();
  });

  testWidgets('CinemaView defaults to Chat tab and Danmaku bar is integrated into Chat', (tester) async {
    final session = _FakeChatCallRoomSession();

    await tester.pumpWidget(
      _wrap(
        CinemaView(
          session: session,
          onLeaveRoom: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Old standalone danmaku input bar on video stage is completely gone
    expect(find.byKey(const ValueKey('cinema-danmaku-input-field')), findsNothing);

    // Chat tab is active by default (shows empty notice and chat input)
    final i18n = AppI18n(const Locale('zh', 'CN'));
    expect(find.text(i18n.tabChat), findsOneWidget);
    expect(find.text(i18n.chatEmptyNotice), findsOneWidget);

    final chatInput = find.byKey(const ValueKey('cinema-chat-input-field'));
    final chatSendBtn = find.byKey(const ValueKey('cinema-chat-send-btn'));
    expect(chatInput, findsOneWidget);
    expect(chatSendBtn, findsOneWidget);

    // Type and send a chat message
    await tester.enterText(chatInput, 'Hello from chat & danmaku!');
    await tester.tap(chatSendBtn);
    await tester.pump(const Duration(milliseconds: 100));

    // Message is displayed in chat list
    expect(session.chatMessages.length, 1);
    expect(session.chatMessages.first.text, 'Hello from chat & danmaku!');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('cinema-chat-list-view')),
        matching: find.text('Hello from chat & danmaku!'),
      ),
      findsOneWidget,
    );

    // Call buttons are present in AppBar
    expect(find.byKey(const ValueKey('cinema-voice-call-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('cinema-video-call-btn')), findsOneWidget);
  });

  testWidgets('CinemaView shows incoming call banner with accept/decline', (tester) async {
    final session = _FakeChatCallRoomSession();

    await tester.pumpWidget(
      _wrap(
        CinemaView(
          session: session,
          onLeaveRoom: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Initially call state is idle
    expect(find.byKey(const ValueKey('cinema-call-incoming-card')), findsNothing);

    // Simulate incoming voice call
    await session.callSession.handleCallSignal({
      'type': 'call_invite',
      'callType': 'voice',
      'callerId': 'peer-dev-456',
      'callerName': 'PeerBob',
    });
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('cinema-call-incoming-card')), findsOneWidget);
    expect(find.text('PeerBob'), findsWidgets);
    expect(find.byKey(const ValueKey('cinema-call-decline-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('cinema-call-accept-btn')), findsOneWidget);

    // Tap Accept
    await tester.tap(find.byKey(const ValueKey('cinema-call-accept-btn')));
    await tester.pump(const Duration(milliseconds: 100));

    // State is connected, incoming card disappears and connected bar appears
    expect(find.byKey(const ValueKey('cinema-call-incoming-card')), findsNothing);
    expect(find.byKey(const ValueKey('cinema-call-connected-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('cinema-call-mic-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('cinema-call-hangup-btn')), findsOneWidget);

    // Tap hangup
    await tester.tap(find.byKey(const ValueKey('cinema-call-hangup-btn')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('cinema-call-connected-bar')), findsNothing);
  });

  testWidgets('CinemaView video call PIP window clamps properly to landscape viewport', (tester) async {
    final session = _FakeChatCallRoomSession();

    await tester.pumpWidget(
      _wrap(
        CinemaView(
          session: session,
          onLeaveRoom: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Simulate incoming video call
    await session.callSession.handleCallSignal({
      'type': 'call_invite',
      'callType': 'video',
      'callerId': 'peer-dev-video',
      'callerName': 'PeerAlice',
    });
    await tester.pump(const Duration(milliseconds: 100));

    // Accept Video Call
    await tester.tap(find.byKey(const ValueKey('cinema-call-accept-btn')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('cinema-video-pip-window')), findsOneWidget);

    // Simulate switching screen to mobile landscape (800x360)
    await tester.binding.setSurfaceSize(const Size(800, 360));
    await tester.pump(const Duration(milliseconds: 100));

    final pipFinder = find.byKey(const ValueKey('cinema-video-pip-window'));
    expect(pipFinder, findsOneWidget);

    final pipTopLeft = tester.getTopLeft(pipFinder);
    // On 360 height, pip window top must be within screen (<= 360 - 145 = 215)
    expect(pipTopLeft.dy, lessThanOrEqualTo(220.0));
    expect(pipTopLeft.dy, greaterThanOrEqualTo(10.0));

    // Double tap to reset
    await tester.tap(pipFinder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(pipFinder);
    await tester.pump(const Duration(milliseconds: 100));

    // Clean up
    await tester.tap(find.byKey(const ValueKey('cinema-call-hangup-btn')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.binding.setSurfaceSize(null);
  });
}
