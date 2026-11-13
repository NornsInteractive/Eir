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
import 'package:eir/media/local_media_service.dart';
import 'package:eir/views/lobby_view.dart';
import 'package:eir/views/cinema_view.dart';
import 'package:eir/views/settings_dialog.dart';
import 'package:eir/core/screen_share_service.dart';

/// Controlled fake room session for UI isolated testing without network or WebRTC side-effects.
class FakeRoomSession extends ChangeNotifier implements RoomSession {
  @override
  DeviceIdentityInfo identity = DeviceIdentityInfo(
    deviceId: 'fakedevice1234567890abcdef1234567890abcdef',
    publicKeyBase64: 'fakepublickeybase64string==',
  );

  @override
  RoomConnectionState connectionState = RoomConnectionState.disconnected;

  @override
  String? roomId;

  @override
  String? inviteText;

  @override
  String? roomCode = '839201';

  @override
  RoomRole role = RoomRole.member;

  @override
  List<RoomMember> members = [];

  @override
  List<PlaylistItem> playlist = [];

  @override
  String? currentItemId;

  @override
  PlaybackState playback = PlaybackState();

  @override
  String? lastErrorCode;

  @override
  PlaybackLoopMode loopMode = PlaybackLoopMode.loopAll;

  final StreamController<DanmakuMessage> _danmakuController =
      StreamController<DanmakuMessage>.broadcast();

  @override
  Stream<DanmakuMessage> get danmakuStream => _danmakuController.stream;

  @override
  void setLoopMode(PlaybackLoopMode mode) {
    loopMode = mode;
    notifyListeners();
  }

  @override
  void sendDanmaku(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _danmakuController.add(DanmakuMessage(
      id: 'fake-${DateTime.now().microsecondsSinceEpoch}',
      sender: 'Tester',
      text: trimmed,
      timestamp: DateTime.now(),
    ));
  }

  final List<ChatMessage> _chatMessages = [];
  @override
  List<ChatMessage> get chatMessages => List.unmodifiable(_chatMessages);

  @override
  late final CallSession callSession = CallSession(
    sendSignal: (_) async {},
    getCurrentDeviceId: () => identity.deviceId,
    getCurrentDisplayName: () => 'Tester',
    getCurrentAvatar: () => null,
  );

  @override
  late final ScreenShareService screenShareService = ScreenShareService(
    sendSignal: (_) async {},
    getCurrentDeviceId: () => identity.deviceId,
    getCurrentDisplayName: () => 'Tester',
    getCurrentAvatar: () => null,
  );

  @override
  void sendChatMessage(String text) {
    sendDanmaku(text);
    _chatMessages.add(ChatMessage(
      id: 'fake-chat-${DateTime.now().microsecondsSinceEpoch}',
      senderDeviceId: identity.deviceId,
      senderName: 'Tester',
      text: text,
      timestamp: DateTime.now(),
      isSelf: true,
    ));
    notifyListeners();
  }

  @override
  final Player player = Player();

  Map<String, MemberTelemetry> memberTelemetryMap = {};

  @override
  Map<String, MemberTelemetry> get memberTelemetry => memberTelemetryMap;

  @override
  bool get peerVerified => true;

  @override
  String? get peerDeviceId => null;

  @override
  bool get isP2pConnected => true;

  @override
  bool get isP2pConnecting => false;

  @override
  bool get isP2pFailed => false;

  @override
  Future<void> retryP2p() async {}

  // Buffer-wait API added by core; fake reports no peer buffering.
  bool _waitForPeerBuffering = true;
  @override
  bool get waitForPeerBuffering => _waitForPeerBuffering;
  @override
  set waitForPeerBuffering(bool val) {
    _waitForPeerBuffering = val;
    notifyListeners();
  }

  bool _hostBufferWaitPaused = false;
  @override
  bool get isHostWaitingPeerBuffering => _hostBufferWaitPaused && isAnyPeerBuffering;

  @override
  bool get isAnyPeerBuffering => false;

  @override
  get tailcatTransport => null;

  @override
  String? get tailcatAddr => null;

  @override
  LocalMediaService? get debugMediaService => null;

  // V1 §9 cache occupancy API (added by core; fake reports an empty/no-cache view)
  @override
  MediaCacheTelemetrySnapshot? get cacheTelemetry => null;

  @override
  int get cacheUsedBytes => 0;

  @override
  int get cacheMaxBytes => kMediaMaxCacheBytes;

  @override
  Future<int> clearUnprotectedCache() async => 0;

  @override
  void updateLocalProfile() {}

  // F4 manual retry() added by core; fake records the call (no network side-effects).
  int retryCalls = 0;
  @override
  Future<void> retry() async {
    retryCalls++;
  }

  // Recorder flags & call tracking
  int createRoomCalls = 0;
  int joinRoomCalls = 0;
  String? lastJoinPayload;
  int leaveRoomCalls = 0;
  int closeRoomCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  Duration? lastSeekPosition;
  double? lastRate;
  int addUrlCalls = 0;
  String? lastAddedUrl;
  int removeItemCalls = 0;
  String? lastRemovedItemId;
  int reorderItemCalls = 0;
  String? lastReorderedItemId;
  int? lastReorderedNewIndex;
  int replaceItemCalls = 0;
  String? lastReplacedItemId;
  String? lastReplacedUrl;
  int switchItemCalls = 0;
  String? lastSwitchedItemId;
  int grantAdminCalls = 0;
  String? lastGrantedMemberId;
  int revokeAdminCalls = 0;
  String? lastRevokedMemberId;
  int setSignalingUrlCalls = 0;
  String? lastSignalingUrl;
  int initCalls = 0;
  bool shouldInitFail = false;
  bool isDisposed = false;

  @override
  Future<void> init() async {
    initCalls++;
    if (shouldInitFail) {
      throw Exception('Simulated identity store initialization failure');
    }
  }

  @override
  Future<void> setSignalingUrl(String url) async {
    setSignalingUrlCalls++;
    lastSignalingUrl = url;
  }

  @override
  Future<void> createRoom() async {
    createRoomCalls++;
    roomId = 'room-alpha-999';
    role = RoomRole.owner;
    inviteText = 'ws://127.0.0.1:8765|room-alpha-999|fake-genesis';
    connectionState = RoomConnectionState.connected;
    notifyListeners();
  }

  @override
  Future<void> joinRoom(String invite) async {
    joinRoomCalls++;
    lastJoinPayload = invite;
    roomId = 'room-beta-888';
    role = RoomRole.member;
    connectionState = RoomConnectionState.connected;
    notifyListeners();
  }

  @override
  Future<void> joinRoomByCode(String code) async {
    await joinRoom(code);
  }

  @override
  Future<void> leaveRoom() async {
    leaveRoomCalls++;
    roomId = null;
    inviteText = null;
    connectionState = RoomConnectionState.disconnected;
    notifyListeners();
  }

  @override
  Future<void> closeRoom() async {
    closeRoomCalls++;
    leaveRoomCalls++;
    roomId = null;
    inviteText = null;
    connectionState = RoomConnectionState.disconnected;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    playCalls++;
    playback = PlaybackState(
      mode: PlaybackMode.playing,
      position: playback.position,
      rate: playback.rate,
      seq: playback.seq + 1,
    );
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playback = PlaybackState(
      mode: PlaybackMode.paused,
      position: playback.position,
      rate: playback.rate,
      seq: playback.seq + 1,
    );
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeekPosition = position;
    playback = PlaybackState(
      mode: playback.mode,
      position: position,
      rate: playback.rate,
      seq: playback.seq + 1,
    );
    notifyListeners();
  }

  @override
  Future<void> setRate(double rate) async {
    lastRate = rate;
    playback = PlaybackState(
      mode: playback.mode,
      position: playback.position,
      rate: rate,
      seq: playback.seq + 1,
    );
    notifyListeners();
  }

  @override
  Future<void> addUrl(String url, {String? title}) async {
    addUrlCalls++;
    lastAddedUrl = url;
    playlist.add(PlaylistItem(
      itemId: 'media-${playlist.length + 1}',
      title: title ?? url,
      sourceType: 'url',
      url: url,
    ));
    notifyListeners();
  }

  @override
  bool isItemSourceOffline(PlaylistItem item) => false;

  @override
  Future<void> syncKeepAlive([bool? forceEnabled]) async {}

  @override
  Future<void> pickAndAddLocalFile() async {}

  @override
  Future<void> addLocalFile(dynamic file, {String? title}) async {}

  @override
  Future<void> addDirectLocalMedia({
    String? path,
    dynamic file,
    required String title,
    int? sizeBytes,
  }) async {}

  @override
  Future<void> removeItem(String itemId) async {
    removeItemCalls++;
    lastRemovedItemId = itemId;
    playlist.removeWhere((e) => e.itemId == itemId);
    notifyListeners();
  }

  @override
  Future<void> reorderItem(String itemId, int newIndex) async {
    reorderItemCalls++;
    lastReorderedItemId = itemId;
    lastReorderedNewIndex = newIndex;
    final idx = playlist.indexWhere((e) => e.itemId == itemId);
    if (idx >= 0) {
      final item = playlist.removeAt(idx);
      playlist.insert(newIndex.clamp(0, playlist.length), item);
      notifyListeners();
    }
  }

  @override
  Future<void> replaceItem(String itemId, {String? url, dynamic file}) async {
    replaceItemCalls++;
    lastReplacedItemId = itemId;
    lastReplacedUrl = url;
    final idx = playlist.indexWhere((e) => e.itemId == itemId);
    if (idx >= 0) {
      final old = playlist[idx];
      playlist[idx] = PlaylistItem(
        itemId: old.itemId,
        title: old.title,
        sourceType: 'url',
        url: url ?? old.url,
      );
      notifyListeners();
    }
  }

  @override
  Future<void> switchItem(String itemId) async {
    switchItemCalls++;
    lastSwitchedItemId = itemId;
    currentItemId = itemId;
    notifyListeners();
  }

  @override
  Future<void> admitMember(String memberId) async {}

  @override
  Future<void> grantAdmin(String memberId) async {
    grantAdminCalls++;
    lastGrantedMemberId = memberId;
    final idx = members.indexWhere((m) => m.deviceId == memberId);
    if (idx >= 0) {
      final m = members[idx];
      members[idx] = RoomMember(
        deviceId: m.deviceId,
        displayName: m.displayName,
        role: RoomRole.admin,
        online: m.online,
      );
      notifyListeners();
    }
  }

  @override
  Future<void> revokeAdmin(String memberId) async {
    revokeAdminCalls++;
    lastRevokedMemberId = memberId;
    final idx = members.indexWhere((m) => m.deviceId == memberId);
    if (idx >= 0) {
      final m = members[idx];
      members[idx] = RoomMember(
        deviceId: m.deviceId,
        displayName: m.displayName,
        role: RoomRole.member,
        online: m.online,
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    isDisposed = true;
    _danmakuController.close();
    player.dispose();
    super.dispose();
  }
}

void main() {
  final activeSessions = <FakeRoomSession>[];

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

  Widget buildTestWrapper(Widget child, {Locale locale = const Locale('zh', 'CN')}) {
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
        locale: locale,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('LobbyView displays init state, handles retry and dispatches create/join',
      (WidgetTester tester) async {
    final session = FakeRoomSession();
    activeSessions.add(session);

    // 1. Initializing state
    await tester.pumpWidget(
      buildTestWrapper(
        LobbyView(
          session: session,
          isInitialized: false,
          initError: null,
        ),
      ),
    );
    // Bounded pump for indeterminate loading animation
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final i18n = AppI18n(const Locale('zh', 'CN'));
    expect(find.text(i18n.initializingEngine), findsOneWidget);

    // Tapping create when not initialized should NOT trigger createRoom
    await tester.tap(find.text('创建专属放映室'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(session.createRoomCalls, 0);

    // 2. Init error state with retry callback
    bool retryInvoked = false;
    await tester.pumpWidget(
      buildTestWrapper(
        LobbyView(
          session: session,
          isInitialized: false,
          initError: 'Corrupted identity store file',
          onRetryInit: () {
            retryInvoked = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('客户端初始化失败'), findsOneWidget);
    expect(find.text('Corrupted identity store file'), findsOneWidget);
    expect(find.text('重试初始化'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lobby-retry-init-btn')));
    await tester.pumpAndSettle();
    expect(retryInvoked, isTrue);

    // 3. Fully initialized state
    await tester.pumpWidget(
      buildTestWrapper(
        LobbyView(
          session: session,
          isInitialized: true,
          initError: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Brand title & Badge
    expect(find.text('Eir'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);

    // Verify Action buttons
    expect(find.text('创建专属放映室'), findsOneWidget);
    expect(find.text('加入放映室'), findsOneWidget);

    // Dispatch create room
    await tester.tap(find.byKey(const ValueKey('lobby-create-btn')));
    await tester.pumpAndSettle();
    expect(session.createRoomCalls, 1);
    expect(session.setSignalingUrlCalls, 1);

    // Dispatch join room with payload
    final inputFinder = find.byKey(const ValueKey('lobby-join-input'));
    expect(inputFinder, findsOneWidget);
    await tester.enterText(inputFinder, 'ws://127.0.0.1:8765|room-alpha-123|genesis');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lobby-join-btn')));
    await tester.pumpAndSettle();
    expect(session.joinRoomCalls, 1);
    expect(session.lastJoinPayload, 'ws://127.0.0.1:8765|room-alpha-123|genesis');

    // Verify NO mock movie titles exist
    expect(find.text('星际穿越 · 4K 原盘私享'), findsNothing);
    expect(find.text('奥本海默 · 70mm 胶片全画幅'), findsNothing);
    expect(find.text('沙丘 2 · 杜比全景声特别放映'), findsNothing);

    // Verify the removed promotional feature card is gone
    expect(find.text('毫秒级同频播放'), findsNothing);
  });

  testWidgets('CinemaView enforces member read-only mode vs Admin/Host shared controls',
      (WidgetTester tester) async {
    final session = FakeRoomSession();
    activeSessions.add(session);
    session.role = RoomRole.member;

    await tester.pumpWidget(
      buildTestWrapper(
        CinemaView(
          session: session,
          onLeaveRoom: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Member has read-only indicator
    final i18n = AppI18n(const Locale('zh', 'CN'));
    expect(find.text(i18n.readOnlyControlTooltip), findsOneWidget);

    // Tapping play button in read-only mode should not dispatch play
    final playBtnFinder = find.byTooltip(i18n.readOnlyControlTooltip);
    expect(playBtnFinder, findsOneWidget);
    await tester.tap(playBtnFinder);
    await tester.pumpAndSettle();
    expect(session.playCalls, 0);

    // Promote to Admin
    session.role = RoomRole.admin;
    session.playback = PlaybackState(mode: PlaybackMode.paused);
    session.notifyListeners();
    await tester.pumpAndSettle();

    // Now play button tooltip indicates shared play
    final adminPlayBtn = find.byTooltip(i18n.playTooltip);
    expect(adminPlayBtn, findsOneWidget);
    await tester.tap(adminPlayBtn);
    await tester.pumpAndSettle();
    expect(session.playCalls, 1);
    expect(session.playback.mode, PlaybackMode.playing);

    // Tapping pause button dispatches pause
    final adminPauseBtn = find.byTooltip(i18n.pauseTooltip);
    expect(adminPauseBtn, findsOneWidget);
    await tester.tap(adminPauseBtn);
    await tester.pumpAndSettle();
    expect(session.pauseCalls, 1);
  });

  testWidgets('CinemaView playlist handles reorder, replace, switch and remove dispatches',
      (WidgetTester tester) async {
    final session = FakeRoomSession();
    activeSessions.add(session);
    session.role = RoomRole.owner;
    session.playlist = [
      PlaylistItem(itemId: 'item-1', title: 'Sample One.mp4', sourceType: 'url', url: 'https://cdn.example.com/1.mp4'),
      PlaylistItem(itemId: 'item-2', title: 'Sample Two.mp4', sourceType: 'url', url: 'https://cdn.example.com/2.mp4'),
    ];
    session.currentItemId = 'item-1';

    await tester.pumpWidget(
      buildTestWrapper(
        CinemaView(
          session: session,
          onLeaveRoom: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final i18n = AppI18n(const Locale('zh', 'CN'));
    await tester.tap(find.text(i18n.tabPlaylist));
    await tester.pumpAndSettle();

    // Sample One appears in both player HUD title pill and playlist item tile
    expect(find.text('Sample One.mp4'), findsNWidgets(2));
    expect(
      find.descendant(of: find.byType(ReorderableListView), matching: find.text('Sample One.mp4')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(ReorderableListView), matching: find.text('Sample Two.mp4')),
      findsOneWidget,
    );

    // Item-1 is currently playing
    expect(find.text('正在播放'), findsOneWidget);

    // 1. Reorder: move item-1 down
    final moveDownBtns = find.byTooltip('下移');
    expect(moveDownBtns, findsWidgets);
    await tester.tap(moveDownBtns.first);
    await tester.pumpAndSettle();
    expect(session.reorderItemCalls, 1);
    expect(session.lastReorderedItemId, 'item-1');
    expect(session.lastReorderedNewIndex, 1);

    // 2. Switch media: switch to item-2
    final switchBtns = find.byTooltip('切换到此条目');
    expect(switchBtns, findsOneWidget);
    await tester.tap(switchBtns);
    await tester.pumpAndSettle();
    expect(session.switchItemCalls, 1);
    expect(session.lastSwitchedItemId, 'item-2');

    // 3. Replace media item: opens dialog and submits new URL
    final replaceBtns = find.byTooltip('替换此条目');
    expect(replaceBtns, findsWidgets);
    await tester.tap(replaceBtns.first);
    await tester.pumpAndSettle();

    expect(find.textContaining('替换播单条目'), findsOneWidget);
    final dialogInput = find.byKey(const ValueKey('replace-item-url-input'));
    expect(dialogInput, findsOneWidget);
    await tester.enterText(dialogInput, 'https://cdn.example.com/replacement.mp4');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('replace-item-submit-btn')));
    await tester.pumpAndSettle();
    expect(session.replaceItemCalls, 1);
    expect(session.lastReplacedUrl, 'https://cdn.example.com/replacement.mp4');

    // 4. Remove item: remove item-2
    final removeBtns = find.byTooltip('移除条目');
    expect(removeBtns, findsWidgets);
    await tester.tap(removeBtns.first);
    await tester.pumpAndSettle();
    expect(session.removeItemCalls, 1);
  });

  testWidgets('CinemaView owner disband action dispatches closeRoom and invokes callback',
      (WidgetTester tester) async {
    final session = FakeRoomSession();
    activeSessions.add(session);
    session.role = RoomRole.owner;
    session.roomId = 'room-owner-disband';

    bool onLeaveInvoked = false;
    await tester.pumpWidget(
      buildTestWrapper(
        CinemaView(
          session: session,
          onLeaveRoom: () {
            onLeaveInvoked = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Owner disband action button is present in AppBar
    final disbandBtn = find.text('解散房间');
    expect(disbandBtn, findsOneWidget);

    await tester.tap(disbandBtn);
    await tester.pumpAndSettle();

    // Verify session.closeRoom() was dispatched
    expect(session.closeRoomCalls, 1);
    expect(onLeaveInvoked, isTrue);
  });

  testWidgets('CinemaView member ACL grant and revoke dispatches correctly',
      (WidgetTester tester) async {
    final session = FakeRoomSession();
    activeSessions.add(session);
    session.role = RoomRole.owner;
    session.members = [
      RoomMember(deviceId: session.identity.deviceId, displayName: 'Owner Me', role: RoomRole.owner, online: true),
      RoomMember(deviceId: 'peer-user-device-456', displayName: 'Peer Two', role: RoomRole.member, online: true),
    ];

    await tester.pumpWidget(
      buildTestWrapper(
        CinemaView(
          session: session,
          onLeaveRoom: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Peers tab
    final i18n = AppI18n(const Locale('zh', 'CN'));
    await tester.tap(find.text(i18n.tabMembers));
    await tester.pumpAndSettle();

    // F08: Without telemetry, both members display '进度: 未知' and no fake timestamps
    expect(find.text('进度: 未知'), findsNWidgets(2));
    expect(find.text('01:05'), findsNothing);

    // F08: Populate real MemberTelemetry
    session.memberTelemetryMap['peer-user-device-456'] = MemberTelemetry(
      deviceId: 'peer-user-device-456',
      itemId: 'item-1',
      itemSeq: 1,
      positionMs: 65000,
      buffering: true,
      sharedMs: 1000,
    );
    session.memberTelemetryMap[session.identity.deviceId] = MemberTelemetry(
      deviceId: session.identity.deviceId,
      itemId: 'item-1',
      itemSeq: 1,
      positionMs: 68000,
      buffering: false,
      sharedMs: 1000,
    );
    session.notifyListeners();
    await tester.pumpAndSettle();

    // Verify F08: Peer Two shows formatted position 01:05 and buffering indicator
    expect(find.text('01:05'), findsOneWidget);
    expect(find.text('缓冲中'), findsOneWidget);
    expect(find.text('01:08'), findsOneWidget);
    expect(find.byKey(const ValueKey('member-telemetry-peer-user-device-456')), findsOneWidget);

    expect(find.text(i18n.grantAdmin), findsOneWidget);
    // Rev3 layout pushes member controls below the default 800x600 surface; scroll them into view.
    await tester.ensureVisible(find.text(i18n.grantAdmin));
    await tester.pumpAndSettle();
    await tester.tap(find.text(i18n.grantAdmin));
    await tester.pumpAndSettle();
    expect(session.grantAdminCalls, 1);
    expect(session.lastGrantedMemberId, 'peer-user-device-456');

    // After grant, button changes to revoke
    expect(find.text(i18n.revokeAdmin), findsOneWidget);
    await tester.ensureVisible(find.text(i18n.revokeAdmin));
    await tester.pumpAndSettle();
    await tester.tap(find.text(i18n.revokeAdmin));
    await tester.pumpAndSettle();
    expect(session.revokeAdminCalls, 1);
    expect(session.lastRevokedMemberId, 'peer-user-device-456');
  });

  testWidgets('SettingsDialog persists independent colors and signaling URL without session leak',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestWrapper(
        const SettingsDialog(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全局偏好设置'), findsOneWidget);
    expect(find.text('信令配置'), findsNWidgets(2));
    expect(find.text('独立主题色配置'), findsOneWidget);

    // Verify mock cache/IP stats are absent
    expect(find.textContaining('1240 MB'), findsNothing);
    expect(find.textContaining('192.168.1.106'), findsNothing);

    // Update signaling URL
    final urlInput = find.byKey(const ValueKey('settings-signaling-input'));
    expect(urlInput, findsOneWidget);
    await tester.ensureVisible(urlInput);
    await tester.pumpAndSettle();

    final editableTextFinder = find.descendant(
      of: urlInput,
      matching: find.byType(EditableText),
    );
    expect(editableTextFinder, findsOneWidget);
    expect(
      tester.widget<EditableText>(editableTextFinder).controller.text,
      AppSettings.instance.signalingUrl,
    );

    await tester.enterText(urlInput, 'ws://192.168.1.50:9000');
    final saveBtn = find.byKey(const ValueKey('settings-save-signaling-btn'));
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();
    expect(AppSettings.instance.signalingUrl, 'ws://192.168.1.50:9000');

    // Test independent theme colors
    final initialLight = AppSettings.instance.lightThemeColor;
    final initialDark = AppSettings.instance.darkThemeColor;

    // Pick first color swatch
    final swatchFinder = find.byType(GestureDetector);
    expect(swatchFinder, findsWidgets);

    // Verify reset default
    final resetBtns = find.text('恢复默认');
    expect(resetBtns, findsWidgets);
    await tester.ensureVisible(resetBtns.first);
    await tester.tap(resetBtns.first);
    await tester.pumpAndSettle();
    expect(AppSettings.instance.lightThemeColor, initialLight);
    expect(AppSettings.instance.darkThemeColor, initialDark);
  });

  testWidgets('SettingsDialog rev14 explicit save: close without save does not persist draft',
      (WidgetTester tester) async {
    final original = AppSettings.instance.signalingUrl;
    addTearDown(() async {
      await AppSettings.instance.setSignalingUrl(original);
    });
    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
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
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => SettingsDialog.show(context),
                  child: const Text('open-settings'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-settings'));
    await tester.pumpAndSettle();
    expect(find.text('全局偏好设置'), findsOneWidget);
    final urlInput = find.byKey(const ValueKey('settings-signaling-input'));
    await tester.ensureVisible(urlInput);
    await tester.pumpAndSettle();
    await tester.enterText(urlInput, 'ws://192.168.1.99:9999');
    await tester.pumpAndSettle();
    expect(AppSettings.instance.signalingUrl, original);
    await tester.tap(find.byKey(const ValueKey('settings-close-btn')));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.signalingUrl, original);
    await tester.tap(find.text('open-settings'));
    await tester.pumpAndSettle();
    final editable = find.descendant(
      of: find.byKey(const ValueKey('settings-signaling-input')),
      matching: find.byType(EditableText),
    );
    expect(find.text('全局偏好设置'), findsOneWidget);
    expect(
      tester.widget<EditableText>(editable).controller.text,
      original,
    );
    await tester.tap(find.byKey(const ValueKey('settings-done-btn')));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.signalingUrl, original);
    await tester.tap(find.text('open-settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('settings-signaling-input')));
    await tester.enterText(
      find.byKey(const ValueKey('settings-signaling-input')),
      'ws://192.168.1.98:8888',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-done-btn')));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.signalingUrl, original);
  });

  testWidgets('SettingsDialog rev14 invalid signaling retains draft and does not persist',
      (WidgetTester tester) async {
    final original = AppSettings.instance.signalingUrl;
    addTearDown(() async {
      await AppSettings.instance.setSignalingUrl(original);
    });
    await tester.pumpWidget(buildTestWrapper(const SettingsDialog()));
    await tester.pumpAndSettle();
    final urlInput = find.byKey(const ValueKey('settings-signaling-input'));
    await tester.ensureVisible(urlInput);
    await tester.pumpAndSettle();
    await tester.enterText(urlInput, 'http://bad-host');
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-save-signaling-btn')),
    );
    await tester.tap(
      find.byKey(const ValueKey('settings-save-signaling-btn')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('信令地址格式无效，必须以 ws:// 或 wss:// 开头并包含有效主机名'),
      findsOneWidget,
    );
    expect(AppSettings.instance.signalingUrl, original);
    final editable = find.descendant(
      of: urlInput,
      matching: find.byType(EditableText),
    );
    expect(
      tester.widget<EditableText>(editable).controller.text,
      'http://bad-host',
    );
  });

  testWidgets('SettingsDialog rev14 valid in-room save persists without interrupting session',
      (WidgetTester tester) async {
    final original = AppSettings.instance.signalingUrl;
    addTearDown(() async {
      await AppSettings.instance.setSignalingUrl(original);
    });
    final session = FakeRoomSession();
    activeSessions.add(session);
    session.roomId = 'room-in-room-check';
    session.connectionState = RoomConnectionState.connected;
    await tester.pumpWidget(buildTestWrapper(SettingsDialog(session: session)));
    await tester.pumpAndSettle();
    final urlInput = find.byKey(const ValueKey('settings-signaling-input'));
    await tester.ensureVisible(urlInput);
    await tester.pumpAndSettle();
    await tester.enterText(urlInput, '  ws://192.168.1.50:9000  ');
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-save-signaling-btn')),
    );
    await tester.tap(
      find.byKey(const ValueKey('settings-save-signaling-btn')),
    );
    await tester.pumpAndSettle();
    expect(AppSettings.instance.signalingUrl, 'ws://192.168.1.50:9000');
    expect(session.lastSignalingUrl, 'ws://192.168.1.50:9000');
    expect(session.roomId, 'room-in-room-check');
    expect(session.connectionState, RoomConnectionState.connected);
    expect(session.isDisposed, isFalse);
    expect(
      find.text('房内仅保存未来连接地址，不自动打断当前会话'),
      findsOneWidget,
    );
  });

  testWidgets('SettingsDialog rev14 theme and language switch instantly updates dialog',
      (WidgetTester tester) async {
    final originalLocale = AppSettings.instance.locale;
    addTearDown(() {
      AppSettings.instance.setLocale(originalLocale);
      AppSettings.instance.setThemeMode(ThemeMode.system);
    });
    AppSettings.instance.setLocale(const Locale('zh', 'CN'));
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: AppSettings.instance,
        builder: (context, _) {
          return LiquidGlassWidgets.wrap(
            brightnessResolver: (_) => Brightness.dark,
            child: MaterialApp(
              themeMode: AppSettings.instance.themeMode,
              locale: AppSettings.instance.locale,
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
              home: const Scaffold(body: SettingsDialog()),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('全局偏好设置'), findsOneWidget);
    AppSettings.instance.setLocale(const Locale('en', 'US'));
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('全局偏好设置'), findsNothing);
    AppSettings.instance.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    expect(AppSettings.instance.themeMode, ThemeMode.dark);
    AppSettings.instance.setLocale(const Locale('zh', 'CN'));
    await tester.pumpAndSettle();
    expect(find.text('全局偏好设置'), findsOneWidget);
  });

  testWidgets('Session persistence verification: theme and language switch does not recreate session',
      (WidgetTester tester) async {
    final session = FakeRoomSession();
    activeSessions.add(session);
    session.roomId = 'room-persistence-check';
    session.connectionState = RoomConnectionState.connected;

    // Build responsive root shell with AnimatedBuilder observing AppSettings
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: AppSettings.instance,
        builder: (context, _) {
          return MaterialApp(
            themeMode: AppSettings.instance.themeMode,
            locale: AppSettings.instance.locale,
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
            home: CinemaView(
              key: const ValueKey('cinema-view-persistent'),
              session: session,
              onLeaveRoom: () {},
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // Verify room view is mounted
    expect(find.byKey(const ValueKey('cinema-view-persistent')), findsOneWidget);
    expect(session.isDisposed, isFalse);

    // Switch theme mode
    AppSettings.instance.setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(session.isDisposed, isFalse);
    expect(session.roomId, 'room-persistence-check');

    // Switch locale to English
    AppSettings.instance.setLocale(const Locale('en', 'US'));
    await tester.pumpAndSettle();
    expect(session.isDisposed, isFalse);
    expect(session.roomId, 'room-persistence-check');

    // Switch locale back to Chinese
    AppSettings.instance.setLocale(const Locale('zh', 'CN'));
    await tester.pumpAndSettle();
    expect(session.isDisposed, isFalse);
    expect(session.roomId, 'room-persistence-check');
  });

  testWidgets('LobbyView init-error snackbar auto-dismisses after 5 seconds',
      (WidgetTester tester) async {
    final session = FakeRoomSession();
    activeSessions.add(session);

    await tester.pumpWidget(
      buildTestWrapper(
        LobbyView(
          session: session,
          isInitialized: false,
          initError: 'Corrupted identity store file',
          onRetryInit: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('客户端初始化失败'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('客户端初始化失败'), findsNothing);
  });

  testWidgets('LobbyView init-error snackbar closes manually',
      (WidgetTester tester) async {
    final session = FakeRoomSession();
    activeSessions.add(session);

    await tester.pumpWidget(
      buildTestWrapper(
        LobbyView(
          session: session,
          isInitialized: false,
          initError: 'Corrupted identity store file',
          onRetryInit: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('客户端初始化失败'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('snackbar-close-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('客户端初始化失败'), findsNothing);
  });

  testWidgets('LobbyView init-error snackbar re-shows same error after retry',
      (WidgetTester tester) async {
    final session = FakeRoomSession();
    activeSessions.add(session);

    await tester.pumpWidget(
      buildTestWrapper(
        LobbyView(
          session: session,
          isInitialized: false,
          initError: 'Corrupted identity store file',
          onRetryInit: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('客户端初始化失败'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lobby-retry-init-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(
      buildTestWrapper(
        LobbyView(
          session: session,
          isInitialized: false,
          initError: null,
          onRetryInit: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(
      buildTestWrapper(
        LobbyView(
          session: session,
          isInitialized: false,
          initError: 'Corrupted identity store file',
          onRetryInit: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('客户端初始化失败'), findsOneWidget);
  });

  testWidgets('LobbyView init-error snackbar does not duplicate on rebuild',
      (WidgetTester tester) async {
    final session = FakeRoomSession();
    activeSessions.add(session);

    await tester.pumpWidget(
      buildTestWrapper(
        LobbyView(
          session: session,
          isInitialized: false,
          initError: 'Corrupted identity store file',
          onRetryInit: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('客户端初始化失败'), findsOneWidget);

    await tester.pumpWidget(
      buildTestWrapper(
        LobbyView(
          session: session,
          isInitialized: false,
          initError: 'Corrupted identity store file',
          onRetryInit: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('客户端初始化失败'), findsOneWidget);
  });


}
