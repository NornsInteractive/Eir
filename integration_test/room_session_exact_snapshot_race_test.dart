// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

// Exact snapshot/commit concurrency regression (Linux harness: real
// RoomSession x2, real Player, real WebRTC DataChannel, loopback
// signaling/media servers). No product hooks, no forged business state,
// no source-text assertions.
//
// Why this exists: the previous timing test waited for the guest's
// snapshot load to finish (duration > 0) before sending live commits, so
// it only proved sequential order, not the concurrent race where live
// commits arrive while the snapshot open is still in flight. This file
// instead injects time control through the EXISTING public constructor
// parameter `player: Player` (room_session.dart:194): a real media_kit
// Player subclass whose first open() is held on a one-shot Completer
// gate before calling super.open(). The gate only delays the real mpv
// load; it does not implement or copy any room business logic.
//
// - E1 exact race: owner has A paused, member late-joins and its
//   snapshot open(A) blocks on the gate; while blocked the owner runs
//   add B / switch B / play B (owner is unaffected by the member gate);
//   after the commits are provably sent, the gate opens and the member
//   must end at B (playlist A/B, current=B, real player playlist uri=B,
//   position advancing, no A fallback). Real player media/state are
//   asserted, not only RoomSession fields.
// - E2 same-invite rejoin old operation: with the snapshot open still
//   gated, the member leaves and re-joins with the SAME invite (same
//   roomId/sessionId). Since the fix resets _publish/_commit queues
//   in _resetRoomState, the NEW generation's snapshot now applies
//   independently while the OLD gate is still held (playlist=A,
//   current=A, mode=paused, real PlayerURI=A, playing=false); the old
//   blocked open must not pollute the re-entered room's state, and
//   releasing the old gate afterwards must not roll it back. Then
//   live B commits advance it to B playing (real player uri=B,
//   position advancing). E2 uses super-then-hold only (it still has a
//   real pending core Future, but the old backend load already
//   finished, so releasing it cannot late-open A over B); E1 keeps
//   hold-before-super to prove a real snapshot blocking the queue.

/// A real [Player] that holds its very first [open] on a one-shot gate.
///
/// Only timing is controlled: once released, every call goes straight
/// to the real native implementation via super. No playlist/behavior is
/// faked; the room session sees (and tests assert on) the genuine
/// Player state.
class GatedPlayer extends Player {
  GatedPlayer();

  final Completer<void> _entered = Completer<void>();
  final Completer<void> _release = Completer<void>();
  bool _gateArmed = true;

  /// URIs of every open() call in order (diagnostics + assertions).
  final List<String> openUris = <String>[];

  /// Completes once the first open() has been entered (gate holding).
  Future<void> get entered => _entered.future;

  bool get isReleased => _release.isCompleted;

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    String uri;
    if (playable is Media) {
      uri = playable.uri;
    } else {
      uri = playable.toString();
    }
    openUris.add(uri);
    if (_gateArmed) {
      _gateArmed = false;
      if (!_entered.isCompleted) _entered.complete();
      await _release.future;
    }
    return super.open(playable, play: play);
  }
}

/// A real [Player] that lets the FIRST open() run to the real backend
/// via super, then holds its core-Future completion on a one-shot gate.
///
/// E2-only. Kept separate from [GatedPlayer] (hold-before-super) so E1
/// still proves a genuine snapshot blocking the commit-apply queue.
/// With super-then-hold the old backend load (A) has already
/// finished before leave; the old Dart Future is still pending, so
/// the rejoin reset can be observed, but releasing the old gate later
/// completes an already-loaded open and cannot late-open A over the
/// re-entered room's B. Only the first open() is gated; later opens
/// go straight to the real native implementation.
class GatedAfterOpenPlayer extends Player {
  GatedAfterOpenPlayer();

  final Completer<void> _entered = Completer<void>();
  final Completer<void> _release = Completer<void>();
  bool _gateArmed = true;

  /// URIs of every open() call in order (diagnostics + assertions).
  final List<String> openUris = <String>[];

  /// Completes once the first super.open() has returned and the gate
  /// is holding.
  Future<void> get entered => _entered.future;

  bool get isReleased => _release.isCompleted;

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    String uri;
    if (playable is Media) {
      uri = playable.uri;
    } else {
      uri = playable.toString();
    }
    openUris.add(uri);
    await super.open(playable, play: play);
    if (_gateArmed) {
      _gateArmed = false;
      if (!_entered.isCompleted) _entered.complete();
      await _release.future;
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('E1 snapshot open blocks, live B commits queue behind it',
      (tester) async {
    final fixtureBytes = await _fixtureBytes();
    final mediaServer = await _startRangeServer(fixtureBytes);
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final signalingUrl = 'ws://127.0.0.1:${signaling.port}';
    final urlA = 'http://127.0.0.1:${mediaServer.port}/a.mp4';
    final urlB = 'http://127.0.0.1:${mediaServer.port}/b.mp4';

    final memberPlayer = GatedPlayer();
    final sessionA = RoomSession(
        identityStore:
            DeviceIdentityStore(store: InMemorySecureKeyValueStore()));
    final sessionB = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
      player: memberPlayer,
    );
    addTearDown(() async {
      memberPlayer.release();
      try {
        sessionA.dispose();
      } catch (_) {}
      try {
        sessionB.dispose();
      } catch (_) {}
      try {
        await memberPlayer.dispose();
      } catch (_) {}
      try {
        await signaling.stop();
      } catch (_) {}
      try {
        await mediaServer.close(force: true);
      } catch (_) {}
    });

    await sessionA.init();
    await sessionB.init();
    await sessionA.setSignalingUrl(signalingUrl);
    await sessionB.setSignalingUrl(signalingUrl);
    await sessionA.createRoom();

    // Owner has A paused before the guest joins (switch carries the
    // current paused mode, per RoomSession.switchItem).
    await sessionA.addUrl(urlA, title: 'A');
    expect(sessionA.playlist, hasLength(1));
    final itemA = sessionA.playlist.single.itemId;
    await sessionA.switchItem(itemA);
    expect(sessionA.currentItemId, itemA);
    expect(sessionA.playback.mode, PlaybackMode.paused);

    final invite = sessionA.inviteText;
    expect(invite, isNotNull);
    await sessionB.joinRoom(invite!);
    final verified = await _waitFor(
      () => sessionA.peerVerified && sessionB.peerVerified,
      timeout: const Duration(seconds: 20),
    );
    expect(verified, isTrue);

    // The snapshot task must reach the real player.open(A) and block on
    // the gate; that is what holds the unified commit-apply queue.
    final gateEntered = await _waitFor(
      () => memberPlayer.openUris.isNotEmpty,
      timeout: const Duration(seconds: 20),
    );
    expect(gateEntered, isTrue,
        reason: 'member never entered snapshot open '
            '(playlist=${sessionB.playlist.length}, '
            'current=${sessionB.currentItemId}, '
            'err=${sessionB.lastErrorCode}, opens=${memberPlayer.openUris})');
    expect(memberPlayer.openUris.first, urlA,
        reason: 'first open must be the snapshot open of A');
    expect(memberPlayer.isReleased, isFalse);
    // Product state of the snapshot is visible (playlist/current set
    // before the blocking load) but no media has been decoded yet.
    expect(sessionB.playlist.map((e) => e.title), ['A']);
    expect(sessionB.currentItemId, itemA);
    expect(memberPlayer.state.playlist.medias, isEmpty,
        reason: 'gate must block before mpv loads any media');

    // While the snapshot open is blocked, the owner runs add B /
    // switch B / play B. The owner has its own unfenced player, so all
    // three must complete. Their futures include _sendDc, i.e. the
    // commits are actually sent before the member gate opens.
    await sessionA.addUrl(urlB, title: 'B');
    expect(sessionA.playlist.map((e) => e.title), ['A', 'B']);
    final itemB =
        sessionA.playlist.firstWhere((e) => e.title == 'B').itemId;
    await sessionA.switchItem(itemB);
    await sessionA.play();
    expect(sessionA.currentItemId, itemB);
    expect(sessionA.playback.mode, PlaybackMode.playing);

    // Give the loopback DataChannel a moment to deliver the commits to
    // the member (they stay queued behind the blocked snapshot task).
    // The member must NOT have applied B yet while the gate is held.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(memberPlayer.isReleased, isFalse);
    expect(memberPlayer.openUris, [urlA],
        reason: 'no second open may start while snapshot open is gated');
    expect(sessionB.playlist.map((e) => e.title), ['A'],
        reason: 'B commits must queue behind the blocked snapshot task '
            '(playlist=${sessionB.playlist.map((e) => e.title)}, '
            'current=${sessionB.currentItemId}, err=${sessionB.lastErrorCode})');
    expect(sessionB.currentItemId, itemA);

    // Release the gate: snapshot open(A) completes for real, then the
    // queued add/switch/play commits apply in order.
    memberPlayer.release();
    final advanced = await _waitFor(
      () =>
          sessionB.playlist.length == 2 &&
          sessionB.currentItemId == itemB &&
          sessionB.playback.mode == PlaybackMode.playing,
      timeout: const Duration(seconds: 30),
    );
    expect(advanced, isTrue,
        reason: 'queued B commits did not apply after gate release '
            '(playlist=${sessionB.playlist.map((e) => e.title)}, '
            'current=${sessionB.currentItemId}, '
            'mode=${sessionB.playback.mode}, err=${sessionB.lastErrorCode}, '
            'opens=${memberPlayer.openUris})');
    expect(sessionB.playlist.map((e) => e.title), ['A', 'B']);
    // Real player evidence: B media loaded, playing, advancing.
    final playerOnB = await _waitFor(
      () =>
          memberPlayer.state.playlist.medias.isNotEmpty &&
          memberPlayer.state.playlist
              .medias[memberPlayer.state.playlist.index]
              .uri ==
              urlB &&
          memberPlayer.state.duration > Duration.zero &&
          memberPlayer.state.playing,
      timeout: const Duration(seconds: 30),
    );
    expect(playerOnB, isTrue,
        reason: 'member player did not load/play B media '
            '(opens=${memberPlayer.openUris}, '
            'playlist=${memberPlayer.state.playlist.medias.map((m) => m.uri)}, '
            'duration=${memberPlayer.state.duration}, '
            'playing=${memberPlayer.state.playing})');
    final positionBefore = memberPlayer.state.position;
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(memberPlayer.state.position,
        greaterThan(positionBefore),
        reason: 'member player position did not advance on B '
            '(before=$positionBefore, after=${memberPlayer.state.position})');
    expect(memberPlayer.state.position,
        greaterThanOrEqualTo(const Duration(milliseconds: 300)));
    // No A fallback after settling.
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(sessionB.currentItemId, itemB);
    expect(sessionB.playlist.map((e) => e.title), ['A', 'B']);
    expect(
        memberPlayer.state.playlist.medias[memberPlayer.state.playlist.index]
            .uri,
        urlB);
    expect(memberPlayer.openUris, [urlA, urlB]);

    await sessionA.closeRoom();
    final closed = await _waitFor(
      () =>
          sessionA.connectionState == RoomConnectionState.disconnected &&
          sessionB.connectionState == RoomConnectionState.disconnected,
      timeout: const Duration(seconds: 10),
    );
    expect(closed, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('E2 same-invite leave+rejoin: old blocked open cannot pollute',
      (tester) async {
    final t0 = DateTime.now();
    int msSinceT0() => DateTime.now().difference(t0).inMilliseconds;
    final fixtureBytes = await _fixtureBytes();
    final mediaServer = await _startRangeServer(fixtureBytes);
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final signalingUrl = 'ws://127.0.0.1:${signaling.port}';
    final urlA = 'http://127.0.0.1:${mediaServer.port}/a.mp4';
    final urlB = 'http://127.0.0.1:${mediaServer.port}/b.mp4';

    final memberPlayer = GatedAfterOpenPlayer();
    final sessionA = RoomSession(
        identityStore:
            DeviceIdentityStore(store: InMemorySecureKeyValueStore()));
    final sessionB = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
      player: memberPlayer,
    );
    addTearDown(() async {
      memberPlayer.release();
      try {
        sessionA.dispose();
      } catch (_) {}
      try {
        sessionB.dispose();
      } catch (_) {}
      try {
        await memberPlayer.dispose();
      } catch (_) {}
      try {
        await signaling.stop();
      } catch (_) {}
      try {
        await mediaServer.close(force: true);
      } catch (_) {}
    });

    await sessionA.init();
    await sessionB.init();
    await sessionA.setSignalingUrl(signalingUrl);
    await sessionB.setSignalingUrl(signalingUrl);
    await sessionA.createRoom();
    final roomId = sessionA.roomId;
    expect(roomId, isNotNull);

    await sessionA.addUrl(urlA, title: 'A');
    expect(sessionA.playlist, hasLength(1));
    final itemA = sessionA.playlist.single.itemId;
    await sessionA.switchItem(itemA);
    expect(sessionA.playback.mode, PlaybackMode.paused);

    final invite = sessionA.inviteText;
    expect(invite, isNotNull);
    await sessionB.joinRoom(invite!);
    final verified = await _waitFor(
      () => sessionA.peerVerified && sessionB.peerVerified,
      timeout: const Duration(seconds: 20),
    );
    expect(verified, isTrue);
    final gateEntered = await _waitFor(
      () => memberPlayer.openUris.isNotEmpty,
      timeout: const Duration(seconds: 20),
    );
    expect(gateEntered, isTrue,
        reason: 'member never entered snapshot open '
            '(playlist=${sessionB.playlist.length}, '
            'err=${sessionB.lastErrorCode})');
    expect(memberPlayer.openUris.first, urlA);
    // Super-then-hold (E2 only): the real backend has already loaded
    // A even though the core Future is still gated. Waiting for it
    // proves we still have a real pending core task across leave,
    // without letting a late super.open(A) overwrite the re-entered
    // room's B after release.
    final oldBackendOnA = await _waitFor(
      () =>
          memberPlayer.state.playlist.medias.isNotEmpty &&
          memberPlayer.state.playlist
                  .medias[memberPlayer.state.playlist.index]
                  .uri ==
              urlA &&
          memberPlayer.state.duration > Duration.zero,
      timeout: const Duration(seconds: 20),
    );
    expect(oldBackendOnA, isTrue,
        reason: 'old snapshot backend did not load A before leave '
            '(opens=${memberPlayer.openUris}, '
            'player=${memberPlayer.state.playlist.medias.map((m) => m.uri)}, '
            'duration=${memberPlayer.state.duration}, '
            'err=${sessionB.lastErrorCode})');
    expect(memberPlayer.isReleased, isFalse);
    expect(sessionB.playlist.map((e) => e.title), ['A']);
    expect(sessionB.currentItemId, itemA);
    expect(sessionB.playback.mode, PlaybackMode.paused);
    expect(memberPlayer.state.playing, isFalse);
    print('[exact-race] T=${msSinceT0()}ms E2 old-gated '
        'released=${memberPlayer.isReleased} '
        'roomId=${sessionB.roomId} current=${sessionB.currentItemId} '
        'playlist=${sessionB.playlist.map((e) => e.title)} '
        'mode=${sessionB.playback.mode} '
        'opens=${memberPlayer.openUris} '
        'playerURI=${_playerUri(memberPlayer)} '
        'playerDur=${memberPlayer.state.duration} '
        'playerPos=${memberPlayer.state.position} '
        'playing=${memberPlayer.state.playing} '
        'err=${sessionB.lastErrorCode}');

    // Leave while the OLD generation's core Future is still gated.
    // _resetRoomState bumps generation and freshens the queues, so
    // the old pending task is now stale but its gate is still held.
    await sessionB.leaveRoom();
    expect(sessionB.roomId, isNull);
    expect(sessionB.connectionState, RoomConnectionState.disconnected);
    expect(sessionB.playlist, isEmpty);
    expect(memberPlayer.isReleased, isFalse);

    // Re-join with the SAME invite text: same roomId (and hence the
    // same invite-embedded sessionId) as before the leave.
    await sessionB.joinRoom(invite);
    expect(sessionB.roomId, roomId);
    final reverified = await _waitFor(
      () => sessionA.peerVerified && sessionB.peerVerified,
      timeout: const Duration(seconds: 20),
    );
    expect(reverified, isTrue,
        reason: 'rejoin with same invite did not re-verify the peer '
            '(err=${sessionB.lastErrorCode})');
    // New-generation snapshot must apply INDEPENDENTLY while the old
    // gate is still held: _resetRoomState freshens _publish/_commit
    // queues, so the re-entered room is NOT queued behind the stale
    // core Future. Product state (playlist/current/mode) plus the
    // REAL player (PlayerURI=A, playing=false, duration>0) must all
    // land before any release. This replaces the obsolete
    // `expect(playlist, isEmpty)` / still-blocked expectation that
    // pinned the old shared-queue behavior.
    final snapshotWhileGated = await _waitFor(
      () =>
          sessionB.playlist.length == 1 &&
          sessionB.currentItemId == itemA &&
          sessionB.playback.mode == PlaybackMode.paused &&
          memberPlayer.state.duration > Duration.zero &&
          _playerUri(memberPlayer) == urlA &&
          !memberPlayer.state.playing,
      timeout: const Duration(seconds: 30),
    );
    print('[exact-race] T=${msSinceT0()}ms E2 snapshot-while-gated '
        'ok=$snapshotWhileGated released=${memberPlayer.isReleased} '
        'roomId=${sessionB.roomId} current=${sessionB.currentItemId} '
        'playlist=${sessionB.playlist.map((e) => e.title)} '
        'mode=${sessionB.playback.mode} '
        'opens=${memberPlayer.openUris} '
        'playerURI=${_playerUri(memberPlayer)} '
        'playerDur=${memberPlayer.state.duration} '
        'playerPos=${memberPlayer.state.position} '
        'playing=${memberPlayer.state.playing} '
        'err=${sessionB.lastErrorCode}');
    expect(snapshotWhileGated, isTrue,
        reason: 'new-generation snapshot did not apply A paused while '
            'old gate held (playlist=${sessionB.playlist.map((e) => e.title)}, '
            'current=${sessionB.currentItemId}, '
            'mode=${sessionB.playback.mode}, err=${sessionB.lastErrorCode}, '
            'opens=${memberPlayer.openUris}, '
            'player=${memberPlayer.state.playlist.medias.map((m) => m.uri)}, '
            'duration=${memberPlayer.state.duration}, '
            'released=${memberPlayer.isReleased})');
    expect(memberPlayer.isReleased, isFalse,
        reason: 'new snapshot must land with the old gate still held');
    expect(memberPlayer.openUris, [urlA, urlA],
        reason: 'second open must be the re-entered snapshot A '
            '(opens=${memberPlayer.openUris})');
    expect(_playerUri(memberPlayer), urlA);
    expect(sessionB.playlist.map((e) => e.title), ['A']);
    expect(sessionB.currentItemId, itemA);
    expect(sessionB.playback.mode, PlaybackMode.paused);
    final beforeReleasePlaylist =
        sessionB.playlist.map((e) => '${e.title}:${e.url}').join(',');
    final beforeReleaseCurrent = sessionB.currentItemId;
    final beforeReleaseMode = sessionB.playback.mode;
    final beforeReleaseUri = _playerUri(memberPlayer);
    final beforeReleasePlaying = memberPlayer.state.playing;
    final beforeReleaseOpens =
        List<String>.unmodifiable(memberPlayer.openUris);
    print('[exact-race] T=${msSinceT0()}ms E2 before-release '
        'released=${memberPlayer.isReleased} '
        'roomId=${sessionB.roomId} current=$beforeReleaseCurrent '
        'playlist=$beforeReleasePlaylist mode=$beforeReleaseMode '
        'opens=$beforeReleaseOpens playerURI=$beforeReleaseUri '
        'playing=$beforeReleasePlaying pos=${memberPlayer.state.position} '
        'err=${sessionB.lastErrorCode}');

    // Now release the OLD gate only. The stale generation completes
    // but its generation guard must keep it from overwriting the
    // re-entered room: playlist/current/mode/PlayerURI/playing and
    // the open count must all be unchanged after it settles.
    memberPlayer.release();
    print('[exact-race] T=${msSinceT0()}ms E2 releaseGateOldOnly '
        'released=${memberPlayer.isReleased}');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final afterReleasePlaylist =
        sessionB.playlist.map((e) => '${e.title}:${e.url}').join(',');
    final afterReleaseCurrent = sessionB.currentItemId;
    final afterReleaseMode = sessionB.playback.mode;
    final afterReleaseUri = _playerUri(memberPlayer);
    final afterReleasePlaying = memberPlayer.state.playing;
    print('[exact-race] T=${msSinceT0()}ms E2 after-release '
        'released=${memberPlayer.isReleased} '
        'roomId=${sessionB.roomId} current=$afterReleaseCurrent '
        'playlist=$afterReleasePlaylist mode=$afterReleaseMode '
        'opens=${memberPlayer.openUris} playerURI=$afterReleaseUri '
        'playing=$afterReleasePlaying pos=${memberPlayer.state.position} '
        'err=${sessionB.lastErrorCode}');
    expect(sessionB.playlist.length, 1,
        reason: 'old completion changed re-entered playlist: '
            'before=$beforeReleasePlaylist after=$afterReleasePlaylist');
    expect(afterReleasePlaylist, beforeReleasePlaylist,
        reason: 'old completion changed re-entered playlist: '
            'before=$beforeReleasePlaylist after=$afterReleasePlaylist');
    expect(afterReleaseCurrent, beforeReleaseCurrent,
        reason: 'old completion changed re-entered current: '
            'before=$beforeReleaseCurrent after=$afterReleaseCurrent');
    expect(afterReleaseCurrent, itemA);
    expect(afterReleaseMode, beforeReleaseMode);
    expect(afterReleaseMode, PlaybackMode.paused);
    expect(afterReleaseUri, beforeReleaseUri);
    expect(afterReleaseUri, urlA);
    expect(afterReleasePlaying, beforeReleasePlaying);
    expect(afterReleasePlaying, isFalse);
    expect(memberPlayer.openUris, beforeReleaseOpens,
        reason: 'old completion opened again '
            '(before=$beforeReleaseOpens opens=${memberPlayer.openUris})');
    expect(memberPlayer.openUris, [urlA, urlA],
        reason: 'no third open from old completion '
            '(opens=${memberPlayer.openUris})');
    expect(sessionB.roomId, roomId,
        reason: 'old completion changed roomId '
            '(old=$roomId new=${sessionB.roomId})');

    // Live commits on the re-entered room must still apply normally.
    await sessionA.addUrl(urlB, title: 'B');
    final itemB =
        sessionA.playlist.firstWhere((e) => e.title == 'B').itemId;
    await sessionA.switchItem(itemB);
    await sessionA.play();
    final advanced = await _waitFor(
      () =>
          sessionB.playlist.length == 2 &&
          sessionB.currentItemId == itemB &&
          sessionB.playback.mode == PlaybackMode.playing,
      timeout: const Duration(seconds: 30),
    );
    expect(advanced, isTrue,
        reason: 'live commits did not apply after rejoin '
            '(playlist=${sessionB.playlist.map((e) => e.title)}, '
            'current=${sessionB.currentItemId}, '
            'mode=${sessionB.playback.mode}, err=${sessionB.lastErrorCode})');
    final playerOnB = await _waitFor(
      () =>
          memberPlayer.state.playlist.medias.isNotEmpty &&
          memberPlayer.state.playlist
              .medias[memberPlayer.state.playlist.index]
              .uri ==
              urlB &&
          memberPlayer.state.playing &&
          memberPlayer.state.position >=
              const Duration(milliseconds: 300),
      timeout: const Duration(seconds: 30),
    );
    expect(playerOnB, isTrue,
        reason: 'member player did not play B after rejoin '
            '(opens=${memberPlayer.openUris}, '
            'player=${memberPlayer.state.playlist.medias.map((m) => m.uri)}, '
            'playing=${memberPlayer.state.playing}, '
            'position=${memberPlayer.state.position})');
    final positionBeforeB = memberPlayer.state.position;
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(memberPlayer.state.position, greaterThan(positionBeforeB),
        reason: 'member player position did not advance on B after '
            'rejoin (before=$positionBeforeB, '
            'after=${memberPlayer.state.position})');
    expect(memberPlayer.state.position,
        greaterThanOrEqualTo(const Duration(milliseconds: 300)));
    expect(_playerUri(memberPlayer), urlB);
    expect(memberPlayer.openUris, [urlA, urlA, urlB],
        reason: 'opens must be old A, rejoin A, then B '
            '(opens=${memberPlayer.openUris})');
    expect(sessionB.playlist.map((e) => e.title), ['A', 'B']);
    expect(sessionB.currentItemId, itemB);
    expect(sessionB.playback.mode, PlaybackMode.playing);
    expect(memberPlayer.state.playing, isTrue);
    print('[exact-race] T=${msSinceT0()}ms E2 final-B '
        'roomId=${sessionB.roomId} current=${sessionB.currentItemId} '
        'playlist=${sessionB.playlist.map((e) => e.title)} '
        'mode=${sessionB.playback.mode} '
        'opens=${memberPlayer.openUris} '
        'playerURI=${_playerUri(memberPlayer)} '
        'playerDur=${memberPlayer.state.duration} '
        'posBefore=$positionBeforeB posAfter=${memberPlayer.state.position} '
        'playing=${memberPlayer.state.playing} '
        'err=${sessionB.lastErrorCode}');

    await sessionA.closeRoom();
    final closed = await _waitFor(
      () =>
          sessionA.connectionState == RoomConnectionState.disconnected &&
          sessionB.connectionState == RoomConnectionState.disconnected,
      timeout: const Duration(seconds: 10),
    );
    expect(closed, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<List<int>> _fixtureBytes() async {
  final host = File('/tmp/eir-media-fixture.mp4');
  if (host.existsSync()) return host.readAsBytes();
  final data = await rootBundle.load('assets/eir_media_fixture.mp4');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<HttpServer> _startRangeServer(List<int> bytes) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null && range.startsWith('bytes=')) {
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
      if (match != null) {
        final start = int.parse(match.group(1)!);
        final endStr = match.group(2)!;
        final end = endStr.isEmpty
            ? bytes.length - 1
            : int.parse(endStr).clamp(0, bytes.length - 1);
        final chunk = bytes.sublist(start, end + 1);
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set('content-type', 'video/mp4')
          ..headers.set('accept-ranges', 'bytes')
          ..headers.set('content-range',
              'bytes $start-$end/${bytes.length}')
          ..contentLength = chunk.length
          ..add(chunk);
        await request.response.close();
        return;
      }
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.set('content-type', 'video/mp4')
      ..headers.set('accept-ranges', 'bytes')
      ..contentLength = bytes.length
      ..add(bytes);
    await request.response.close();
  });
  return server;
}

String _playerUri(Player p) {
  final playlist = p.state.playlist;
  if (playlist.medias.isEmpty) return '<empty>';
  return playlist.medias[playlist.index].uri;
}

Future<bool> _waitFor(
  bool Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  return condition();
}
