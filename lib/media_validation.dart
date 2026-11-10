import 'dart:async';

import 'package:media_kit/media_kit.dart';

class MediaPlaybackResult {
  const MediaPlaybackResult({
    required this.success,
    required this.uri,
    required this.elapsed,
    this.duration,
    this.finalPosition,
    this.playing = false,
    this.playbackObserved = false,
    this.renderedVideo = false,
    this.error,
  });

  final bool success;
  final String uri;
  final Duration elapsed;
  final Duration? duration;
  final Duration? finalPosition;
  final bool playing;
  final bool playbackObserved;
  final bool renderedVideo;
  final String? error;

  @override
  String toString() {
    return 'MediaPlaybackResult(success=$success, uri=<redacted>, duration=$duration, '
        'finalPosition=$finalPosition, playing=$playing, playbackObserved=$playbackObserved, '
        'renderedVideo=$renderedVideo, elapsed=${elapsed.inMilliseconds}ms, error=$error)';
  }
}

Future<MediaPlaybackResult> probeMediaPlayback({
  required String uri,
  Duration timeout = const Duration(seconds: 20),
  bool play = false,
}) async {
  final stopwatch = Stopwatch()..start();
  Player? player;
  StreamSubscription<Duration>? durationSub;
  StreamSubscription<String>? errorSub;
  MediaPlaybackResult result = MediaPlaybackResult(
    success: false,
    uri: uri,
    elapsed: Duration.zero,
    error: 'not completed',
  );

  Duration remaining() {
    final r = timeout - stopwatch.elapsed;
    if (r <= Duration.zero) throw TimeoutException('media playback', timeout);
    return r;
  }

  try {
    MediaKit.ensureInitialized();
    player = Player();

    final durationCompleter = Completer<Duration>();
    durationSub = player.stream.duration.listen((duration) {
      if (duration > Duration.zero && !durationCompleter.isCompleted) {
        durationCompleter.complete(duration);
      }
    });
    errorSub = player.stream.error.listen((message) {
      if (!durationCompleter.isCompleted) {
        durationCompleter.completeError(StateError(message));
      }
    });

    await player.open(Media(uri), play: play).timeout(remaining());

    Duration? duration;
    try {
      duration = await durationCompleter.future.timeout(remaining());
    } on TimeoutException {
      duration = player.state.duration;
      if (duration == Duration.zero) duration = null;
    }

    bool playbackObserved = false;
    bool playing = player.state.playing;
    Duration? finalPosition;
    if (play && duration != null) {
      await player.play().timeout(remaining());
      final startPosition = player.state.position;
      finalPosition = startPosition;
      while (stopwatch.elapsed < timeout && !(finalPosition! > startPosition)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (stopwatch.elapsed >= timeout) break;
        finalPosition = player.state.position;
        playing = player.state.playing;
      }
      finalPosition ??= player.state.position;
      playing = player.state.playing;
      playbackObserved = finalPosition > startPosition;
    } else {
      finalPosition = player.state.position;
      playing = player.state.playing;
    }

    stopwatch.stop();
    final success =
        duration != null && duration > Duration.zero && (!play || playbackObserved);
    result = MediaPlaybackResult(
      success: success,
      uri: uri,
      duration: duration,
      finalPosition: finalPosition,
      playing: playing,
      playbackObserved: playbackObserved,
      renderedVideo: false,
      elapsed: stopwatch.elapsed,
      error: success ? null : 'no playable duration/progress observed',
    );
  } catch (e) {
    stopwatch.stop();
    result = MediaPlaybackResult(
      success: false,
      uri: uri,
      duration: null,
      finalPosition: null,
      playing: false,
      playbackObserved: false,
      renderedVideo: false,
      elapsed: stopwatch.elapsed,
      error: '$e',
    );
  } finally {
    const grace = Duration(seconds: 3);
    try {
      final s = durationSub;
      if (s != null) await s.cancel().timeout(grace);
    } catch (_) {}
    try {
      final s = errorSub;
      if (s != null) await s.cancel().timeout(grace);
    } catch (_) {}
    try {
      final p = player;
      if (p != null) await p.dispose().timeout(grace);
    } catch (_) {}
  }

  return result;
}
