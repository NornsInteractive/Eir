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
import 'package:eir/views/profile_view.dart';

class _FakeRoomSession extends ChangeNotifier implements RoomSession {
  @override
  DeviceIdentityInfo identity = DeviceIdentityInfo(
    deviceId: 'my-local-device-id-1234567890abcdef',
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
  PlaybackLoopMode loopMode = PlaybackLoopMode.loopAll;

  @override
  Stream<DanmakuMessage> get danmakuStream => const Stream.empty();

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

  testWidgets('copy invite button copies ONLY the 6-digit room code when roomCode is present', (tester) async {
    final session = _FakeRoomSession();
    session.roomCode = '654321';
    session.inviteText = 'eir://room?id=test-room-uuid-1234&token=someToken';

    String? lastCopiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments as Map?;
          lastCopiedText = args?['text'] as String?;
        }
        return null;
      },
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

    final copyButton = find.byKey(const ValueKey('cinema-copy-invite-btn'));
    expect(copyButton, findsOneWidget);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();

    // Must be exactly 6 digits, without 'eir://' appended!
    expect(lastCopiedText, '654321');
    expect(lastCopiedText!.contains('eir://'), isFalse);
  });

  testWidgets('room friends list displays friend displayName and custom/preset avatar', (tester) async {
    final session = _FakeRoomSession();
    session.members = [
      RoomMember(
        deviceId: session.identity.deviceId,
        displayName: 'HostAlice',
        role: RoomRole.owner,
        online: true,
        avatar: 'preset:nebula',
      ),
      RoomMember(
        deviceId: 'friend-device-id-9876543210fedcba',
        displayName: 'BestFriendBob',
        role: RoomRole.member,
        online: true,
        avatar: 'preset:rose',
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

    // Switch to Members Tab
    final i18n = AppI18n(const Locale('zh', 'CN'));
    await tester.tap(find.text(i18n.tabMembers));
    await tester.pumpAndSettle();

    // BestFriendBob must be displayed in the list
    expect(find.text('BestFriendBob'), findsOneWidget);
    expect(find.text('HostAlice'), findsOneWidget);

    // Verify UserAvatar renders for both members
    expect(find.byType(UserAvatar), findsNWidgets(2));
  });
}
