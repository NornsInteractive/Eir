// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:eir/core/room_session.dart';

import '../server/signaling_server.dart';

// Owner queue fixed-behavior check (Linux harness: real owner RoomSession,
// real Player, real WebRTC DataChannel, loopback signaling/media servers).
// No product hooks, no forged business state, no source-text assertions.
//
// Fixed behavior under test: _enqueueCommitApply returns the real
// done.future (no outer 10s timeout), so _publishCommitNow / the publish
// queue must wait for the real apply to finish before allocating the next
// seq. A play issued while a switch open() is still gated must queue, not
// allocate a duplicate seq and not complete early.
//
// Preserved original failure log (pre-fix, /tmp/eir-owner-queue-timeout-report.md):
//   Expected: playing, Actual: paused
//   switchTimeout(seq=2, mode=paused, uri=<empty>)
//     -> playTimeout(seq=2, mode=paused)
//     -> afterRelease(seq=2, mode=paused, uri=urlA, pos=0, playing=false)

/// A real [Player] that holds its very first [open] on a one-shot gate.
///
/// Only timing is controlled: once released, every call goes straight
/// to the real native implementation via super.
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('owner gated switch stays pending past 10s, queued play applies',
      (tester) async {
    final fixtureBytes = await _fixtureBytes();
    final mediaServer = await _startRangeServer(fixtureBytes);
    final signaling = SignalingServer();
    await signaling.start(address: InternetAddress.loopbackIPv4, port: 0);
    final signalingUrl = 'ws://127.0.0.1:${signaling.port}';
    final urlA = 'http://127.0.0.1:${mediaServer.port}/a.mp4';

    final ownerPlayer = GatedPlayer();
    final owner = RoomSession(
      identityStore: DeviceIdentityStore(store: InMemorySecureKeyValueStore()),
      player: ownerPlayer,
    );
    addTearDown(() async {
      ownerPlayer.release();
      try {
        owner.dispose();
      } catch (_) {}
      try {
        await ownerPlayer.dispose();
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
    expect(owner.role, RoomRole.owner);
    expect(owner.roomId, isNotNull);

    // Owner normally builds room with A (no gate involved yet).
    await owner.addUrl(urlA, title: 'A');
    expect(owner.playlist, hasLength(1));
    final itemA = owner.playlist.single.itemId;
    final seqAfterAdd = owner.playback.seq;
    print(
        '[owner-queue] baseline after add: seq=$seqAfterAdd current=${owner.currentItemId} mode=${owner.playback.mode} playerURI=${_playerUri(ownerPlayer)} playerPos=${ownerPlayer.state.position} playing=${ownerPlayer.state.playing}');
    expect(owner.playlist.single.title, 'A');

    // Switch to A: first open blocks on the gate. The returned Future is
    // the real publish/apply chain, so it must stay pending while the
    // gate is held — no early completion past the old 10s boundary.
    final switchStartedAt = DateTime.now();
    var switchCompleted = false;
    final switchFuture = owner.switchItem(itemA);
    unawaited(switchFuture.then<void>(
      (_) {
        switchCompleted = true;
      },
      onError: (_) {
        switchCompleted = true;
      },
    ));
    final gateEntered = await _waitFor(
      () => ownerPlayer.openUris.isNotEmpty,
      timeout: const Duration(seconds: 15),
    );
    expect(gateEntered, isTrue,
        reason: 'owner never entered switch open '
            '(current=${owner.currentItemId}, '
            'err=${owner.lastErrorCode}, opens=${ownerPlayer.openUris})');
    expect(ownerPlayer.openUris.first, urlA);

    // Hold the gate for >10s total and prove the switch Future does not
    // complete early while the real open() is still blocked.
    final gateHoldUntil =
        switchStartedAt.add(const Duration(seconds: 11));
    while (DateTime.now().isBefore(gateHoldUntil)) {
      if (switchCompleted) break;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    final gatedElapsed = DateTime.now().difference(switchStartedAt);
    final seqWhileGated = owner.playback.seq;
    final modeWhileGated = owner.playback.mode;
    final currentWhileGated = owner.currentItemId;
    final uriWhileGated = _playerUri(ownerPlayer);
    final posWhileGated = ownerPlayer.state.position;
    print(
        '[owner-queue] while gated >10s (elapsed=${gatedElapsed.inMilliseconds}ms) '
        'switchCompleted=$switchCompleted seq=$seqWhileGated current=$currentWhileGated mode=$modeWhileGated '
        'released=${ownerPlayer.isReleased} opens=${ownerPlayer.openUris} '
        'playerURI=$uriWhileGated playerPos=$posWhileGated '
        'playing=${ownerPlayer.state.playing} err=${owner.lastErrorCode}');
    expect(gatedElapsed, greaterThanOrEqualTo(const Duration(seconds: 10)),
        reason: 'gate must be held past the old 10s boundary');
    expect(switchCompleted, isFalse,
        reason: 'switch Future completed early while open() was still gated '
            '(elapsed=${gatedElapsed.inMilliseconds}ms, seq=$seqWhileGated, '
            'mode=$modeWhileGated, uri=$uriWhileGated)');
    expect(ownerPlayer.isReleased, isFalse);
    expect(ownerPlayer.openUris, [urlA]);
    expect(ownerPlayer.state.playlist.medias, isEmpty,
        reason: 'gate must block before mpv loads any media');
    expect(owner.currentItemId, itemA);

    // Latest play while the switch open is still blocked: call it, but do
    // NOT await it. It must queue behind the real switch apply.
    var playCompleted = false;
    final playFuture = owner.play();
    unawaited(playFuture.then<void>(
      (_) {
        playCompleted = true;
      },
      onError: (_) {
        playCompleted = true;
      },
    ));
    await Future<void>.delayed(const Duration(seconds: 2));
    print(
        '[owner-queue] after play queued (not awaited) '
        'switchCompleted=$switchCompleted playCompleted=$playCompleted '
        'seq=${owner.playback.seq} current=${owner.currentItemId} mode=${owner.playback.mode} '
        'released=${ownerPlayer.isReleased} opens=${ownerPlayer.openUris} '
        'playerURI=${_playerUri(ownerPlayer)} playerPos=${ownerPlayer.state.position} '
        'playing=${ownerPlayer.state.playing} err=${owner.lastErrorCode}');
    expect(switchCompleted, isFalse,
        reason: 'switch must stay queued while gate is held');
    expect(playCompleted, isFalse,
        reason: 'play must queue behind the gated switch apply, not complete early');
    expect(ownerPlayer.isReleased, isFalse);
    expect(ownerPlayer.openUris, [urlA]);
    expect(ownerPlayer.state.playlist.medias, isEmpty);

    // Release the gate: the switch open(A) completes for real, then the
    // queued play must allocate the NEXT seq (not the switch seq) and arm
    // the decoder. Only now are the queued Futures awaited.
    ownerPlayer.release();
    final loaded = await _waitFor(
      () =>
          ownerPlayer.state.playlist.medias.isNotEmpty &&
          ownerPlayer.state.playlist.medias[ownerPlayer.state.playlist.index]
                  .uri ==
              urlA &&
          ownerPlayer.state.duration > Duration.zero,
      timeout: const Duration(seconds: 30),
    );
    expect(loaded, isTrue,
        reason: 'switch open(A) did not load after gate release '
            '(opens=${ownerPlayer.openUris}, '
            'player=${ownerPlayer.state.playlist.medias.map((m) => m.uri)}, '
            'duration=${ownerPlayer.state.duration}, err=${owner.lastErrorCode})');
    await switchFuture;
    await playFuture;
    expect(switchCompleted, isTrue,
        reason: 'switch Future did not complete after real apply');
    expect(playCompleted, isTrue,
        reason: 'queued play Future did not complete after real apply');

    // Real player must be playing and its position must advance.
    final playing = await _waitFor(
      () =>
          owner.playback.mode == PlaybackMode.playing &&
          ownerPlayer.state.playing,
      timeout: const Duration(seconds: 30),
    );
    expect(playing, isTrue,
        reason: 'owner did not end playing after gate release '
            '(seq=${owner.playback.seq}, mode=${owner.playback.mode}, '
            'playing=${ownerPlayer.state.playing}, '
            'pos=${ownerPlayer.state.position}, err=${owner.lastErrorCode})');
    final seqAfterRelease = owner.playback.seq;
    final modeAfterRelease = owner.playback.mode;
    final currentAfterRelease = owner.currentItemId;
    final uriAfterRelease = _playerUri(ownerPlayer);
    final posAfterRelease = ownerPlayer.state.position;
    final playingAfterRelease = ownerPlayer.state.playing;
    print(
        '[owner-queue] after release+await seq=$seqAfterRelease current=$currentAfterRelease mode=$modeAfterRelease '
        'playerURI=$uriAfterRelease pos=$posAfterRelease playing=$playingAfterRelease '
        'opens=${ownerPlayer.openUris} err=${owner.lastErrorCode}');
    expect(seqAfterRelease, greaterThan(seqWhileGated),
        reason: 'queued play did not advance seq past the gated switch '
            '(gated=$seqWhileGated, afterRelease=$seqAfterRelease)');
    expect(seqAfterRelease, greaterThan(seqAfterAdd),
        reason: 'seq must advance past add '
            '(add=$seqAfterAdd, afterRelease=$seqAfterRelease)');
    expect(modeAfterRelease, PlaybackMode.playing);
    expect(currentAfterRelease, itemA);
    expect(uriAfterRelease, urlA);
    expect(playingAfterRelease, isTrue);
    final posBeforeAdvance = ownerPlayer.state.position;
    await Future<void>.delayed(const Duration(seconds: 2));
    final posAfterAdvanceWait = ownerPlayer.state.position;
    print(
        '[owner-queue] advance check before=$posBeforeAdvance after=$posAfterAdvanceWait seq=${owner.playback.seq} mode=${owner.playback.mode} playing=${ownerPlayer.state.playing}');
    expect(posAfterAdvanceWait, greaterThan(posBeforeAdvance),
        reason: 'real player position did not advance while playing '
            '(before=$posBeforeAdvance, after=$posAfterAdvanceWait)');
    await owner.closeRoom();
    final closed = await _waitFor(
      () => owner.connectionState == RoomConnectionState.disconnected,
      timeout: const Duration(seconds: 10),
    );
    expect(closed, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

String _playerUri(GatedPlayer p) {
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
