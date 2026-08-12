import 'package:insta_killer_domain/insta_killer_domain.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime(2026, 8, 12, 14, 0);

  group('resolveElapsed', () {
    test('agrees with both clocks when time passes honestly', () {
      final clock = FakeClock(wall: t0);
      final stamp = ClockStamp.now(clock);
      clock.advance(const Duration(minutes: 7));

      final result = resolveElapsed(since: stamp, clock: clock);

      expect(result.elapsed, const Duration(minutes: 7));
      expect(result.verdict, TamperVerdict.none);
      expect(result.tampered, isFalse);
    });

    test('ignores a rewound wall clock and trusts the monotonic one', () {
      final clock = FakeClock(wall: t0);
      final stamp = ClockStamp.now(clock);

      clock.advance(const Duration(minutes: 10));
      // The attack: put the wall clock back an hour, monotonic keeps counting.
      clock.setWallClock(t0.subtract(const Duration(hours: 1)));

      final result = resolveElapsed(since: stamp, clock: clock);

      expect(result.verdict, TamperVerdict.rewound);
      expect(result.elapsed, const Duration(minutes: 10),
          reason: 'monotonic time is the truth here');
    });

    test('takes the wall clock when it jumps forward, ending a permit sooner',
        () {
      final clock = FakeClock(wall: t0);
      final stamp = ClockStamp.now(clock);

      clock.advance(const Duration(minutes: 1));
      clock.setWallClock(t0.add(const Duration(hours: 3)));

      final result = resolveElapsed(since: stamp, clock: clock);

      expect(result.verdict, TamperVerdict.advanced);
      expect(result.elapsed, const Duration(hours: 3));
    });

    test('survives a reboot by falling back to wall time', () {
      final clock = FakeClock(wall: t0);
      final stamp = ClockStamp.now(clock);

      clock.advance(const Duration(minutes: 5));
      clock.reboot(downtime: const Duration(minutes: 2));

      final result = resolveElapsed(since: stamp, clock: clock);

      // 5 minutes of use plus 2 minutes powered off. Monotonic reset to zero, so wall
      // time is the only witness and it says 7 minutes.
      expect(result.elapsed, const Duration(minutes: 7));
    });
  });

  group('ClockGuard', () {
    test('accepts time moving forward', () {
      final guard = ClockGuard();
      expect(guard.observe(t0), isFalse);
      expect(guard.observe(t0.add(const Duration(hours: 1))), isFalse);
      expect(guard.highWaterMark, t0.add(const Duration(hours: 1)));
    });

    test('catches the reboot-plus-rewind case that resolveElapsed cannot', () {
      final guard = ClockGuard();
      guard.observe(t0);

      expect(
        guard.observe(t0.subtract(const Duration(hours: 2))),
        isTrue,
        reason: 'wall time never goes backwards on its own',
      );
    });

    test('tolerates small backwards drift from NTP correction', () {
      final guard = ClockGuard();
      guard.observe(t0);
      expect(guard.observe(t0.subtract(const Duration(seconds: 20))), isFalse);
    });

    test('does not advance its mark while the clock is rolled back', () {
      final guard = ClockGuard();
      guard.observe(t0);
      guard.observe(t0.subtract(const Duration(days: 1)));

      expect(guard.highWaterMark, t0,
          reason: 'returning to real time must not be rewarded');
      expect(guard.observe(t0.subtract(const Duration(hours: 5))), isTrue);
    });
  });
}
