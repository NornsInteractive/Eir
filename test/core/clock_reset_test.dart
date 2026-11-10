import 'package:flutter_test/flutter_test.dart';
import 'package:eir/core/clock.dart';

// Clock reset: cross-room contamination must not survive a reset.
// Old owner offset must be cleared; the follower's first post-reset sample
// must be adopted verbatim (not EMA-blended with the stale estimate), and
// best-RTT / sync counters must restart. Uses only LeaderClock public API.
void main() {
  test('reset clears old offset; first sample after reset is fully adopted',
      () {
    final clock = LeaderClock();
    // Old owner identity offset.
    clock.forceOffset(Duration.zero);
    expect(clock.hasEstimate, isTrue);
    expect(clock.offsetMsEstimate, 0);
    clock.resetEstimate();
    expect(clock.hasEstimate, isFalse);
    expect(clock.offsetMsEstimate, isNull);
    expect(clock.syncCount, 0);
    expect(clock.bestRoundTripMs, 0);
    // New leader is ~7000ms ahead: first sample must be adopted verbatim, not
    // blended with stale 0. theta = ((9005-2000)+(9015-2020))/2 = 7000.
    final rtt = clock.addSample(t1: 2000, t2: 9005, t3: 9015, t4: 2020);
    // rtt = (2020-2000)-(9015-9005) = 10
    expect(rtt, 10);
    expect(clock.hasEstimate, isTrue);
    expect(clock.syncCount, 1);
    expect(clock.bestRoundTripMs, 10);
    expect(clock.offsetMsEstimate, 7000);
    expect(clock.offsetMsEstimate, isNot(0));
    // Shared time must jump to the new leader, not lag on old 0.
    final delta = clock.sharedNowMs() - clock.localMonoMs();
    expect(delta, greaterThan(6000));
    expect(delta, lessThan(8000));
  });

  test('old different offset is cleared (non-zero stale estimate)', () {
    final clock = LeaderClock();
    clock.forceOffset(const Duration(milliseconds: 12345));
    expect(clock.offsetMsEstimate, 12345);
    // One stale sample advances counters and sets bestRTT.
    // rtt = (50-0)-(12455-12450)=45, theta=12427.5 -> blends with 12345.
    final rtt0 = clock.addSample(t1: 0, t2: 12450, t3: 12455, t4: 50);
    expect(rtt0, 45);
    expect(clock.syncCount, 1);
    expect(clock.hasEstimate, isTrue);
    clock.resetEstimate();
    expect(clock.hasEstimate, isFalse);
    expect(clock.offsetMsEstimate, isNull);
    expect(clock.syncCount, 0);
    expect(clock.bestRoundTripMs, 0);
    // First sample for a leader 2000ms ahead must not be 12345-blended.
    // theta = ((2010-0)+(2020-30))/2 = (2010+1990)/2 = 2000, rtt = 30-10 = 20.
    final rtt1 = clock.addSample(t1: 0, t2: 2010, t3: 2020, t4: 30);
    expect(rtt1, 20);
    expect(clock.offsetMsEstimate, 2000);
    expect(clock.offsetMsEstimate, isNot(12345));
    expect(clock.bestRoundTripMs, 20);
    expect(clock.syncCount, 1);
  });

  test('best RTT and sync count cleared and rebuilt from zero', () {
    final clock = LeaderClock(emaAlpha: 0.5, maxRoundTripMs: 10000);
    // Drive counters up with clean samples from scratch (best becomes 20).
    for (var i = 0; i < 5; i++) {
      final t1 = i * 5000;
      clock.addSample(
        t1: t1,
        t2: t1 + 5015,
        t3: t1 + 5020,
        t4: t1 + 25,
      );
    }
    expect(clock.syncCount, 5);
    expect(clock.bestRoundTripMs, 20);
    expect(clock.hasEstimate, isTrue);
    expect(clock.offsetMsEstimate, 5005); // theta ((5015)+(4995))/2 = 5005
    clock.resetEstimate();
    expect(clock.hasEstimate, isFalse);
    expect(clock.syncCount, 0);
    expect(clock.bestRoundTripMs, 0);
    expect(clock.offsetMsEstimate, isNull);
    // Rebuild: first sample becomes the new best.
    clock.addSample(t1: 0, t2: 10400, t3: 10450, t4: 850); // rtt 800, theta 10000
    expect(clock.syncCount, 1);
    expect(clock.bestRoundTripMs, 800);
    expect(clock.offsetMsEstimate, 10000);
    // Second clean sample improves the best and blends.
    clock.addSample(t1: 900, t2: 10905, t3: 10910, t4: 915); // rtt 10
    expect(clock.syncCount, 2);
    expect(clock.bestRoundTripMs, 10);
    expect(clock.offsetMsEstimate, 10000);
  });
}
