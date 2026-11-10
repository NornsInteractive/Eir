// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

// New-room must NOT inherit old-room queue blocking after the fix
// (Linux harness: real RoomSession, real Player, real signaling +
// range media servers). Public APIs only; no product hooks, no
// source-text assertions.
//
// Fixed behavior under test: _resetRoomState bumps roomGeneration
// and then resets _publishQueue/_commitApplyQueue to
// Future.value(), so the new room runs on fresh queues and never
// waits for the old generation's gated core Future. Old-generation
// media sendControl/sendBinary/error callbacks are dropped by
// generation, and inline/remote manifest installs re-check
// generation across awaits so an old manifest cannot land in the
// new room.
//
// Gate placement is deliberate: the override awaits super.open(A)
// first (real backend loads A, playlist/duration visible) and only
// then holds a Completer, so the core Future is blocked without
// delaying the native load. A gate before super.open() would instead
// push the old open late and could overwrite new-room B — that
// artificial hold-then-super reversal is explicitly not what is
// measured here. Note the real media_kit library lock is released
// when super.open() returns, so a second open() for B can proceed
// while the first Dart future is still gated; the old gate is
// therefore not a library-mutex blocker for the new room.
//
// Timeline expected for the fixed behavior:
//   T0 old switch future pending, player backend has A
//   T1 leaveRoom -> createRoom -> addUrl(B) issued, gate held
//   T1+2s add(B) future completes, new playlist has B (still
//     gate not released; release is no longer a precondition)
//   T1+ B switchB/playB advance the real PlayerURI to B while
//     the old gate is still held
//   Trelease old Future completes but must not overwrite the new
//     room (playlist/current/PlayerURI stay on B)

/// A real [Player] that lets the first open() run to the real backend
/// via super, then holds its completion on a one-shot gate.
///
/// Only the first open() is gated. Once released (or for every later
/// call) each open delegates straight to the native implementation.
class GatedAfterOpenPlayer extends Player {
  GatedAfterOpenPlayer();

  final Completer<void> _entered = Completer<void>();
  final Completer<void> _release = Completer<void>();
  bool _gateArmed = true;

  /// URIs of every open() call in order.
  final List<String> openUris = <String>[];

  String? firstOpenUri;

  /// Completes once the first super.open() has returned and the gate
  /// is holding.
  Future<void> get entered => _entered.future;

  bool get isReleased => _release.isCompleted;

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final uri = playable is Media ? playable.uri : playable.toString();
    openUris.add(uri);
    firstOpenUri ??= uri;
    // Real backend first: media loads, duration resolves, playlist
    // holds the URI. Only the returned core Future is gated.
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

  testWidgets('new room add/switch/play advance while old gate held; release does not overwrite new room',
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

    final player = GatedAfterOpenPlayer();
    final owner = RoomSession(
      identityStore:
          DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
      player: player,
    );
    addTearDown(() async {
      player.release();
      try {
        owner.dispose();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
      try {
        await signaling.stop();
      } catch (_) {}
      try {
        await mediaServer.close(force: true);
      } catch (_) {}
    });

    await owner.init();
    await owner.setSignalingUrl(signalingUrl);
    await owner.createRoom();
    expect(owner.connectionState, RoomConnectionState.connected);
    expect(owner.role, RoomRole.owner);
    final roomIdOld = owner.roomId!;
    print('[new-room-queue] T=${msSinceT0()}ms createOld roomId=$roomIdOld '
        'playlist=${_playlistDump(owner)} seq=${owner.playback.seq}');

    await owner.addUrl(urlA, title: 'A');
    expect(owner.playlist, hasLength(1));
    expect(owner.playlist.single.url, urlA);
    final itemA = owner.playlist.single.itemId;
    print('[new-room-queue] T=${msSinceT0()}ms addA done roomId=$roomIdOld '
        'playlist=${_playlistDump(owner)} seq=${owner.playback.seq} '
        'opens=${player.openUris}');

    // Old-room switch: start it, do not await. The core Future goes
    // _publishCommit -> _handleCommitWire -> _enqueueCommitApply ->
    // _ensureMediaLoaded -> player.open(A) -> gate (after super).
    var switchCompleted = false;
    final switchStartedAt = msSinceT0();
    final switchFuture = owner.switchItem(itemA);
    unawaited(switchFuture.then<void>(
      (_) {
        switchCompleted = true;
      },
      onError: (_) {
        switchCompleted = true;
      },
    ));
    print('[new-room-queue] T=${msSinceT0()}ms switchIssued start=$switchStartedAt '
        'itemA=$itemA');

    final entered = await _waitFor(
      () => player.openUris.isNotEmpty,
      timeout: const Duration(seconds: 15),
    );
    expect(entered, isTrue,
        reason: 'old switch never entered player.open '
            '(current=${owner.currentItemId}, err=${owner.lastErrorCode})');
    final firstUri = player.firstOpenUri ?? player.openUris.first;
    expect(firstUri, urlA,
        reason: 'first open must be A (opens=${player.openUris})');

    // Backend must already hold A even though the core Future is
    // gated. This is the "gate after super.open" proof; a gate before
    // super.open() would leave the playlist empty here.
    final backendLoaded = await _waitFor(
      () =>
          player.state.playlist.medias.isNotEmpty &&
          player.state.playlist.medias[player.state.playlist.index].uri ==
              urlA,
      timeout: const Duration(seconds: 15),
    );
    expect(backendLoaded, isTrue,
        reason: 'real backend did not load A behind the post-open gate '
            '(opens=${player.openUris}, medias='
            '${player.state.playlist.medias.map((m) => m.uri)}, '
            'dur=${player.state.duration}, err=${owner.lastErrorCode})');
    // Give mpv a beat to resolve duration so the dump is meaningful.
    await _waitFor(
      () => player.state.duration > Duration.zero,
      timeout: const Duration(seconds: 10),
    );
    print('[new-room-queue] T=${msSinceT0()}ms old-gated '
        'switchCompleted=$switchCompleted released=${player.isReleased} '
        'roomId=${owner.roomId} current=${owner.currentItemId} '
        'playlist=${_playlistDump(owner)} seq=${owner.playback.seq} '
        'opens=${player.openUris} playerURI=${_playerUri(player)} '
        'playerDur=${player.state.duration} playerPos=${player.state.position} '
        'playerPlaying=${player.state.playing} err=${owner.lastErrorCode}');
    expect(switchCompleted, isFalse,
        reason: 'old switch Future completed while post-open gate held '
            '(T=${msSinceT0()}ms, uri=${_playerUri(player)})');
    expect(player.isReleased, isFalse);
    expect(player.openUris, [urlA]);
    expect(_playerUri(player), urlA,
        reason: 'post-open gate must keep real backend on A, not empty');
    expect(owner.roomId, roomIdOld);

    // Room switch while old open is pending: leave + create + add B.
    await owner.leaveRoom();
    expect(owner.roomId, isNull);
    print('[new-room-queue] T=${msSinceT0()}ms leaveDone '
        'roomId=null playlist=${_playlistDump(owner)} '
        'switchCompleted=$switchCompleted released=${player.isReleased} '
        'playerURI=${_playerUri(player)}');

    await owner.createRoom();
    expect(owner.connectionState, RoomConnectionState.connected);
    final roomIdNew = owner.roomId!;
    expect(roomIdNew, isNot(roomIdOld),
        reason: 'new room must differ from old room '
            '(old=$roomIdOld new=$roomIdNew)');
    expect(owner.playlist, isEmpty,
        reason: 'new room playlist must start empty: ${_playlistDump(owner)}');
    print('[new-room-queue] T=${msSinceT0()}ms createNew roomId=$roomIdNew '
        'old=$roomIdOld playlist=${_playlistDump(owner)} '
        'switchCompleted=$switchCompleted released=${player.isReleased} '
        'playerURI=${_playerUri(player)}');

    // New-room add: start it, do not await. It must complete within
    // 2s while the old gate is still held — the release is no
    // longer a precondition for the new room.
    var addBCompleted = false;
    final addStartedAt = msSinceT0();
    final addFuture = owner.addUrl(urlB, title: 'B');
    unawaited(addFuture.then<void>(
      (_) {
        addBCompleted = true;
      },
      onError: (_) {
        addBCompleted = true;
      },
    ));
    print('[new-room-queue] T=${msSinceT0()}ms addBIssued start=$addStartedAt '
        'roomId=$roomIdNew urlB=$urlB');

    final addBDone = await _waitFor(
      () => addBCompleted,
      timeout: const Duration(seconds: 2),
    );
    final addBElapsed = msSinceT0() - addStartedAt;
    print('[new-room-queue] T=${msSinceT0()}ms new-addB-done '
        'addStartedAt=$addStartedAt elapsedMs=$addBElapsed '
        'addBCompleted=$addBCompleted released=${player.isReleased} '
        'switchCompleted=$switchCompleted '
        'roomId=${owner.roomId} playlist=${_playlistDump(owner)} '
        'opens=${player.openUris} playerURI=${_playerUri(player)} '
        'seq=${owner.playback.seq} err=${owner.lastErrorCode}');
    expect(addBDone, isTrue,
        reason: 'new-room addUrl(B) did not complete within 2s while old '
            'gate held (elapsed=${addBElapsed}ms, playlist='
            '${_playlistDump(owner)}, roomId=${owner.roomId}, '
            'playerURI=${_playerUri(player)}, released=${player.isReleased})');
    await addFuture.timeout(const Duration(seconds: 2));
    expect(player.isReleased, isFalse,
        reason: 'test must prove B advances with the old gate still held');
    expect(switchCompleted, isFalse,
        reason: 'old switch Future must still be gated when B lands');
    expect(owner.roomId, roomIdNew);
    expect(owner.playlist.single.url, urlB);
    expect(owner.playlist.single.title, 'B');
    // add_url only appends to the playlist; B has not reopened the
    // player yet. The backend is still on old A at this point.
    expect(player.openUris, [urlA],
        reason: 'add_url must not open B (opens=${player.openUris})');
    expect(_playerUri(player), urlA,
        reason: 'player backend must still be on A after addB, before '
            'switchB (playerURI=${_playerUri(player)})');
    final itemB = owner.playlist.single.itemId;

    // Further advance in the new room while the old gate is still
    // held: switchB + playB must actually load B in the real
    // backend (PlayerURI=B) and start playing.
    final switchBStartedAt = msSinceT0();
    await owner.switchItem(itemB).timeout(const Duration(seconds: 15));
    await owner.play().timeout(const Duration(seconds: 15));
    final bPlaying = await _waitFor(
      () =>
          _playerUri(player) == urlB &&
          player.state.playing &&
          owner.playback.mode == PlaybackMode.playing &&
          owner.currentItemId == itemB,
      timeout: const Duration(seconds: 15),
    );
    final beforeReleaseAt = msSinceT0();
    final beforeReleasePlaylist = _playlistDump(owner);
    final beforeReleaseCurrent = owner.currentItemId;
    final beforeReleaseUri = _playerUri(player);
    final beforeReleaseSeq = owner.playback.seq;
    final beforeReleaseMode = owner.playback.mode;
    final beforeReleasePlaying = player.state.playing;
    final beforeReleasePos = player.state.position;
    print('[new-room-queue] T=${beforeReleaseAt}ms new-before-release '
        'switchBStartedAt=$switchBStartedAt released=${player.isReleased} '
        'switchCompleted=$switchCompleted '
        'roomId=${owner.roomId} current=$beforeReleaseCurrent '
        'playlist=$beforeReleasePlaylist seq=$beforeReleaseSeq '
        'mode=$beforeReleaseMode playing=$beforeReleasePlaying '
        'pos=$beforeReleasePos opens=${player.openUris} '
        'playerURI=$beforeReleaseUri err=${owner.lastErrorCode}');
    expect(bPlaying, isTrue,
        reason: 'new room switchB/playB did not advance real backend to B '
            'while old gate held (current=${owner.currentItemId}, '
            'playlist=$beforeReleasePlaylist, opens=${player.openUris}, '
            'playerURI=$beforeReleaseUri, mode=$beforeReleaseMode, '
            'playing=$beforeReleasePlaying, err=${owner.lastErrorCode})');
    expect(player.isReleased, isFalse,
        reason: 'B must advance before any release');
    expect(switchCompleted, isFalse,
        reason: 'old switch Future must stay gated through B advance');
    expect(owner.roomId, roomIdNew);
    expect(owner.currentItemId, itemB);
    expect(beforeReleaseCurrent, itemB);
    expect(_playerUri(player), urlB);
    expect(beforeReleaseUri, urlB);
    expect(player.openUris, [urlA, urlB],
        reason: 'opens must be exactly old A then new B (opens=${player.openUris})');

    // Only now release the old gate. The old generation's apply
    // unwinds on generation mismatch; it must not overwrite the
    // new room's playlist/current/real URI.
    final releaseAt = msSinceT0();
    player.release();
    print('[new-room-queue] T=${releaseAt}ms releaseGateOldOnly');
    await switchFuture.timeout(const Duration(seconds: 15));
    // Let the old generation's discarded continuation settle.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final afterReleaseAt = msSinceT0();
    final afterReleasePlaylist = _playlistDump(owner);
    final afterReleaseCurrent = owner.currentItemId;
    final afterReleaseUri = _playerUri(player);
    final afterReleaseSeq = owner.playback.seq;
    final afterReleaseMode = owner.playback.mode;
    final afterReleasePlaying = player.state.playing;
    final afterReleasePos = player.state.position;
    print('[new-room-queue] T=${afterReleaseAt}ms new-after-release '
        'releaseAt=$releaseAt settleMs=${afterReleaseAt - releaseAt} '
        'switchCompleted=$switchCompleted addBCompleted=$addBCompleted '
        'roomId=${owner.roomId} current=$afterReleaseCurrent '
        'playlist=$afterReleasePlaylist seq=$afterReleaseSeq '
        'mode=$afterReleaseMode playing=$afterReleasePlaying '
        'pos=$afterReleasePos opens=${player.openUris} '
        'playerURI=$afterReleaseUri err=${owner.lastErrorCode}');
    expect(switchCompleted, isTrue,
        reason: 'old switch Future did not complete after its gate released');
    expect(owner.roomId, roomIdNew);
    expect(owner.playlist, hasLength(1),
        reason: 'old completion must not add/remove new playlist entries: '
            '$afterReleasePlaylist');
    expect(owner.playlist.single.url, urlB);
    expect(owner.playlist.single.title, 'B');
    expect(afterReleasePlaylist, beforeReleasePlaylist,
        reason: 'playlist changed across old release: '
            'before=$beforeReleasePlaylist after=$afterReleasePlaylist');
    expect(owner.currentItemId, itemB,
        reason: 'old completion changed current item: '
            'before=$beforeReleaseCurrent after=$afterReleaseCurrent');
    expect(_playerUri(player), urlB,
        reason: 'old completion overwrote real backend URI: '
            'before=$beforeReleaseUri after=$afterReleaseUri');
    expect(afterReleaseUri, urlB);
    expect(player.openUris, [urlA, urlB],
        reason: 'no third open from old completion (opens=${player.openUris})');
    expect(owner.playback.mode, PlaybackMode.playing,
        reason: 'old completion must not revert playback mode: '
            'before=$beforeReleaseMode after=$afterReleaseMode');
    expect(player.state.playing, isTrue,
        reason: 'old completion must not pause the new room');

    await owner.closeRoom();
    final closed = await _waitFor(
      () => owner.connectionState == RoomConnectionState.disconnected,
      timeout: const Duration(seconds: 10),
    );
    expect(closed, isTrue);
    print('[new-room-queue] T=${msSinceT0()}ms done old=$roomIdOld new=$roomIdNew');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

String _playlistDump(RoomSession s) {
  if (s.playlist.isEmpty) return '<empty>';
  return s.playlist.map((e) => '${e.title}:${e.url}').join(',');
}

String _playerUri(GatedAfterOpenPlayer p) {
  final playlist = p.state.playlist;
  if (playlist.medias.isEmpty) return '<empty>';
  return playlist.medias[playlist.index].uri;
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
          ..headers.set('content-range', 'bytes $start-$end/${bytes.length}')
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
