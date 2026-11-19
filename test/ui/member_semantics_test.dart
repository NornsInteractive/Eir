import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eir/app_localization.dart';
import 'package:eir/app_settings.dart';
import 'package:eir/apple_glass.dart';
import 'package:eir/models.dart';
import 'package:eir/views/cinema_view.dart';

class _MockRoomSession extends ChangeNotifier implements RoomSession {
  @override
  DeviceIdentityInfo identity = DeviceIdentityInfo(
    deviceId: 'owner-local-device-id-1234567890abcdef',
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

  String? lastGrantedMemberId;
  String? lastRevokedMemberId;

  @override
  Future<void> grantAdmin(String memberId) async {
    lastGrantedMemberId = memberId;
    notifyListeners();
  }

  @override
  Future<void> revokeAdmin(String memberId) async {
    lastRevokedMemberId = memberId;
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

  testWidgets('member list row is NOT exposed as button, and Grant Admin button has dedicated action & label', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final handle = tester.ensureSemantics();

    final session = _MockRoomSession();
    session.playlist = [
      PlaylistItem(
        itemId: 'sample-item-1',
        title: 'Sample Test Video',
        sourceType: 'url',
        url: 'http://127.0.0.1:8080/sample.mp4',
        duration: const Duration(minutes: 10),
      ),
    ];
    session.currentItemId = 'sample-item-1';

    const guestDeviceId = 'guest-friend-device-id-9876543210fedcba';
    session.members = [
      RoomMember(
        deviceId: session.identity.deviceId,
        displayName: 'HostAlice',
        role: RoomRole.owner,
        online: true,
      ),
      RoomMember(
        deviceId: guestDeviceId,
        displayName: 'BestFriendBob',
        role: RoomRole.member,
        online: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'US')],
        home: LiquidGlassWidgets.wrap(
          child: CinemaView(
            session: session,
            onLeaveRoom: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final i18n = AppI18n(const Locale('en', 'US'));
    await tester.tap(find.text(i18n.tabMembers));
    await tester.pumpAndSettle();

    final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
    expect(root, isNotNull);

    // Collect all nodes mentioning BestFriendBob or Grant Admin
    final matchingNodes = <SemanticsNode>[];
    void collectNodes(SemanticsNode node) {
      final data = node.getSemanticsData();
      final text = '${data.label} ${node.value}';
      if (text.contains('BestFriendBob') || text.contains('Grant Admin')) {
        matchingNodes.add(node);
      }
      node.visitChildren((child) {
        collectNodes(child);
        return true;
      });
    }
    collectNodes(root!);

    // Filter which of these are buttons
    final buttonNodes = matchingNodes.where((n) => n.getSemanticsData().hasFlag(SemanticsFlag.isButton)).toList();

    // MUST find exactly 1 button for Grant Admin, NOT 2 (the row must NOT be a button)
    expect(buttonNodes.length, 1, reason: 'Expected exactly 1 button for Grant Admin, not duplicate button on row');
    
    final realButton = buttonNodes.first;
    final buttonData = realButton.getSemanticsData();
    expect(buttonData.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(buttonData.hasAction(SemanticsAction.tap), isTrue, reason: 'Grant Admin button must have tap action');
    expect(buttonData.label, contains('Grant Admin'));
    expect(buttonData.label, contains('BestFriendBob'));

    // Check that the member row itself is NOT a button
    final rowNodes = matchingNodes.where((n) => !n.getSemanticsData().hasFlag(SemanticsFlag.isButton)).toList();
    expect(rowNodes.isNotEmpty, isTrue);
    for (final row in rowNodes) {
      final d = row.getSemanticsData();
      expect(d.hasFlag(SemanticsFlag.isButton), isFalse, reason: 'Row container must not have isButton flag');
      expect(d.hasAction(SemanticsAction.tap), isFalse, reason: 'Row container must not have tap action');
    }

    // Now tap the button via widget tester to verify action
    final actionBtnFinder = find.byKey(const ValueKey('member-acl-$guestDeviceId'));
    expect(actionBtnFinder, findsOneWidget);
    await tester.tap(actionBtnFinder);
    await tester.pumpAndSettle();

    expect(session.lastGrantedMemberId, guestDeviceId, reason: 'Tapping button must call grantAdmin with guest deviceId');

    handle.dispose();
  });

  testWidgets('member list row with Revoke Admin has only 1 button and triggers revokeAdmin', (tester) async {
    final handle = tester.ensureSemantics();

    final session = _MockRoomSession();
    session.playlist = [
      PlaylistItem(
        itemId: 'sample-item-1',
        title: 'Sample Test Video',
        sourceType: 'url',
        url: 'http://127.0.0.1:8080/sample.mp4',
        duration: const Duration(minutes: 10),
      ),
    ];
    session.currentItemId = 'sample-item-1';

    const adminGuestId = 'admin-guest-id-1122334455667788';
    session.members = [
      RoomMember(
        deviceId: session.identity.deviceId,
        displayName: 'HostAlice',
        role: RoomRole.owner,
        online: true,
      ),
      RoomMember(
        deviceId: adminGuestId,
        displayName: 'AdminCharlie',
        role: RoomRole.admin,
        online: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'US')],
        home: LiquidGlassWidgets.wrap(
          child: CinemaView(
            session: session,
            onLeaveRoom: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final i18n = AppI18n(const Locale('en', 'US'));
    await tester.tap(find.text(i18n.tabMembers));
    await tester.pumpAndSettle();

    final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
    expect(root, isNotNull);

    final matchingNodes = <SemanticsNode>[];
    void collectNodes(SemanticsNode node) {
      final data = node.getSemanticsData();
      final text = '${data.label} ${node.value}';
      if (text.contains('AdminCharlie') || text.contains('Revoke Admin')) {
        matchingNodes.add(node);
      }
      node.visitChildren((child) {
        collectNodes(child);
        return true;
      });
    }
    collectNodes(root!);

    final buttonNodes = matchingNodes.where((n) => n.getSemanticsData().hasFlag(SemanticsFlag.isButton)).toList();
    expect(buttonNodes.length, 1, reason: 'Expected exactly 1 button for Revoke Admin');

    final realButton = buttonNodes.first;
    final buttonData = realButton.getSemanticsData();
    expect(buttonData.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(buttonData.hasAction(SemanticsAction.tap), isTrue);
    expect(buttonData.label, contains('Revoke Admin'));
    expect(buttonData.label, contains('AdminCharlie'));

    // Check row is not a button
    final rowNodes = matchingNodes.where((n) => !n.getSemanticsData().hasFlag(SemanticsFlag.isButton)).toList();
    for (final row in rowNodes) {
      final d = row.getSemanticsData();
      expect(d.hasFlag(SemanticsFlag.isButton), isFalse);
      expect(d.hasAction(SemanticsAction.tap), isFalse);
    }

    // Tap button to verify action
    final actionBtnFinder = find.byKey(const ValueKey('member-acl-$adminGuestId'));
    expect(actionBtnFinder, findsOneWidget);
    await tester.tap(actionBtnFinder);
    await tester.pumpAndSettle();

    expect(session.lastRevokedMemberId, adminGuestId, reason: 'Tapping button must call revokeAdmin');

    handle.dispose();
  });

  testWidgets('non-owner viewer sees member list rows with zero button semantics on the row', (tester) async {
    final handle = tester.ensureSemantics();

    final session = _MockRoomSession();
    session.role = RoomRole.member; // Not owner
    session.playlist = [
      PlaylistItem(
        itemId: 'sample-item-1',
        title: 'Sample Test Video',
        sourceType: 'url',
        url: 'http://127.0.0.1:8080/sample.mp4',
        duration: const Duration(minutes: 10),
      ),
    ];
    session.currentItemId = 'sample-item-1';

    session.members = [
      RoomMember(
        deviceId: 'other-owner-device-id-0000111122223333',
        displayName: 'BigBossOwner',
        role: RoomRole.owner,
        online: true,
      ),
      RoomMember(
        deviceId: session.identity.deviceId,
        displayName: 'GuestMe',
        role: RoomRole.member,
        online: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'US')],
        home: LiquidGlassWidgets.wrap(
          child: CinemaView(
            session: session,
            onLeaveRoom: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final i18n = AppI18n(const Locale('en', 'US'));
    await tester.tap(find.text(i18n.tabMembers));
    await tester.pumpAndSettle();

    final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
    expect(root, isNotNull);

    final matchingNodes = <SemanticsNode>[];
    void collectNodes(SemanticsNode node) {
      final data = node.getSemanticsData();
      final text = '${data.label} ${node.value}';
      if (text.contains('BigBossOwner')) {
        matchingNodes.add(node);
      }
      node.visitChildren((child) {
        collectNodes(child);
        return true;
      });
    }
    collectNodes(root!);

    // There should be NO buttons associated with BigBossOwner
    final buttonNodes = matchingNodes.where((n) => n.getSemanticsData().hasFlag(SemanticsFlag.isButton)).toList();
    expect(buttonNodes, isEmpty, reason: 'Non-owner viewer should see no ACL button');

    // The row itself must not be a button
    for (final node in matchingNodes) {
      final d = node.getSemanticsData();
      expect(d.hasFlag(SemanticsFlag.isButton), isFalse);
      expect(d.hasAction(SemanticsAction.tap), isFalse);
    }

    handle.dispose();
  });
}
