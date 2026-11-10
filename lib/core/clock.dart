/// Leader-anchored shared monotonic clock.
///
/// Peers never compare raw `DateTime.now()` values. Instead the fixed
/// leader (room owner) exposes its monotonic clock; followers estimate a
/// constant offset with an NTP-style four-timestamp exchange carried over
/// the authenticated DataChannel (TIME_PING / TIME_PONG). All timestamps
/// are integer milliseconds of a monotonic stopwatch - they are meaningful
/// only relative to the leader's clock.
///
/// The follower keeps the lowest-RTT sample per sync round and blends it
/// with the current estimate (emaAlpha) to avoid stepping the shared
/// clock on every sample. [sharedNowMs] therefore stays smooth while
/// still converging to the leader.
class LeaderClock {
  LeaderClock({this.emaAlpha = 0.3, this.maxRoundTripMs = 500});

  /// Blending factor for new offset samples once an estimate exists.
  final double emaAlpha;

  /// Samples whose round trip exceeds this are discarded as outliers.
  final int maxRoundTripMs;

  final Stopwatch _local = Stopwatch()..start();

  double? _offsetMs;
  int _bestRttMs = 1 << 30;
  int _syncCount = 0;

  int localMonoMs() => _local.elapsedMilliseconds;

  /// Shared-time estimate in leader-monotonic milliseconds.
  /// On the leader itself this is exactly its local monotonic clock.
  int sharedNowMs() {
    final offset = _offsetMs ?? 0;
    return _local.elapsedMilliseconds + offset.round();
  }

  int? get offsetMsEstimate => _offsetMs?.round();
  int get bestRoundTripMs => _bestRttMs == (1 << 30) ? 0 : _bestRttMs;
  int get syncCount => _syncCount;
  bool get hasEstimate => _offsetMs != null;

  void resetEstimate() {
    _offsetMs = null;
    _bestRttMs = 1 << 30;
    _syncCount = 0;
  }

  /// Force offset to a known value. Used by the leader itself (identity
  /// offset) and by tests.
  void forceOffset(Duration offset) {
    _offsetMs = offset.inMilliseconds.toDouble();
    _bestRttMs = 0;
  }

  /// Records a TIME_PONG sample.
  ///  [t1] local monotonic ms when TIME_PING was sent
  ///  [t2] leader monotonic ms when it received the ping
  ///  [t3] leader monotonic ms when it sent the pong
  ///  [t4] local monotonic ms when the pong arrived
  /// Returns the round-trip time, or null when the sample is rejected.
  int? addSample({
    required int t1,
    required int t2,
    required int t3,
    required int t4,
  }) {
    if (t2 < 0 || t3 < t2) return null;
    final rtt = (t4 - t1) - (t3 - t2);
    if (rtt < 0 || rtt > maxRoundTripMs) return null;
    final theta = ((t2 - t1) + (t3 - t4)) / 2.0;
    _syncCount += 1;
    if (_offsetMs == null) {
      _offsetMs = theta;
      _bestRttMs = rtt;
      return rtt;
    }
    // Keep the estimate anchored to the best (lowest RTT) samples; reject
    // samples that are worse than the recorded best by more than 25%.
    if (rtt <= _bestRttMs * 1.25 + 20) {
      _offsetMs = _offsetMs! * (1 - emaAlpha) + theta * emaAlpha;
      if (rtt < _bestRttMs) _bestRttMs = rtt;
    }
    return rtt;
  }

}
