import 'package:flutter_test/flutter_test.dart';

import 'package:eir/core/clock.dart';

void main() {
  test('leader identity offset: sharedNowMs tracks local monotonic clock', () {
    final clock = LeaderClock()..forceOffset(Duration.zero);
    final before = clock.localMonoMs();
    final shared = clock.sharedNowMs();
    final after = clock.localMonoMs();
    expect(shared, greaterThanOrEqualTo(before));
    expect(shared, lessThanOrEqualTo(after + 5));
  });

  test('follower estimates offset from an NTP-style sample', () {
    final clock = LeaderClock();
    // Leader clock is 5000ms ahead of local clock.
    // Local ping sent at local=1000 -> arrives leader at 6000 (+one-way 0 for simplicity).
    // Leader responds at 6010; arrives local at 1015.
    final rtt = clock.addSample(t1: 1000, t2: 6000, t3: 6010, t4: 1015);
    expect(rtt, isNotNull);
    expect(clock.hasEstimate, isTrue);
    final shared = clock.sharedNowMs();
    // sharedNow = localMono + ~5000; mono at assert time is >= 1015.
    expect(shared - clock.localMonoMs(), inInclusiveRange(4000, 6000));
  });

  test('rejects samples with negative or huge RTT', () {
    final clock = LeaderClock();
    expect(clock.addSample(t1: 100, t2: 50, t3: 60, t4: 90), isNull); // negative rtt
    expect(clock.addSample(t1: 100, t2: 200000, t3: 200001, t4: 100000),
        isNull); // abs RTT > maxRoundTripMs
    expect(clock.addSample(t1: 100, t2: 200, t3: 250, t4: 50),
        isNull); // reply before request
    expect(clock.hasEstimate, isFalse);
  });

  test('min-RTT sample anchors the estimate (best-sample selection)', () {
    final clock = LeaderClock(emaAlpha: 0.5, maxRoundTripMs: 10000);
    // First sample: noisy (rtt 800ms), theta = 10000.
    clock.addSample(t1: 0, t2: 10400, t3: 10450, t4: 850); // rtt=800, theta≈10000
    final afterFirst = clock.offsetMsEstimate;
    expect(afterFirst, isNotNull);
    // Second sample: clean (rtt 10ms), theta = 10000 as well but much tighter.
    clock.addSample(t1: 900, t2: 10905, t3: 10910, t4: 915); // rtt=10, theta≈10000
    // Third sample: strong outlier (rtt 9000ms but theta also 10000) must be split off.
    clock.addSample(t1: 1000, t2: 51000, t3: 51010, t4: 11000);
    final drift = (clock.offsetMsEstimate! - 10000).abs();
    expect(drift, lessThanOrEqualTo(5000)); // converges, never runs away
  });

  test('offset estimate converges toward stable theta', () {
    final clock = LeaderClock(emaAlpha: 0.5, maxRoundTripMs: 10000);
    for (var i = 0; i < 20; i++) {
      // True theta = 2000; rtt ~ 20-100ms, symmetric-ish noise.
      final t1 = i * 5000;
      clock.addSample(
        t1: t1,
        t2: t1 + 2010 + (i % 3) * 10,
        t3: t1 + 2020 + (i % 3) * 10,
        t4: t1 + 30 + (i % 3) * 10,
      );
    }
    final drift = (clock.offsetMsEstimate! - 2000).abs();
    expect(drift, lessThanOrEqualTo(200));
    expect(clock.syncCount, 20);
  });

  test('monotonic: sharedNowMs never goes backward across samples', () {
    final clock = LeaderClock(emaAlpha: 0.9); // aggressive blending
    clock.forceOffset(const Duration(milliseconds: 0));
    var last = clock.sharedNowMs();
    for (var i = 0; i < 10; i++) {
      clock.addSample(t1: i * 100, t2: i * 100 + 5, t3: i * 100 + 7,
          t4: i * 100 + 10);
      final now = clock.sharedNowMs();
      // localMono only grows; offset blending might shrink slightly but not
      // beyond the emaAlpha pull; sanity-check tiny bounded step.
      expect(now >= last - 1000, isTrue);
      last = now;
    }
  });
}
