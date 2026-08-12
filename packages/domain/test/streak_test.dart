import 'package:insta_killer_domain/insta_killer_domain.dart';
import 'package:test/test.dart';

Event issued(DateTime at) => Event(at: at, kind: EventKind.permitIssued);

Event attempt(DateTime at) => Event(at: at, kind: EventKind.attemptBlocked);

/// Noon on the given August day, comfortably inside its quota day.
DateTime aug(int day, [int hour = 12]) => DateTime(2026, 8, day, hour);

void main() {
  const quota = QuotaPolicy.standard; // 3/day, 06:00 boundary

  group('computeStreaks (default: under quota)', () {
    test('an empty log is a clean day one', () {
      final summary =
          computeStreaks(events: const [], quota: quota, upTo: aug(12));
      expect(summary.current, 1);
      expect(summary.longest, 1);
    });

    test('days under the quota keep the streak', () {
      final events = [
        issued(aug(10)),
        issued(aug(11)),
        issued(aug(12)),
      ];
      final summary =
          computeStreaks(events: events, quota: quota, upTo: aug(12, 20));

      expect(summary.totalDays, 3);
      expect(summary.current, 3, reason: '1 of 3 permits is not exhaustion');
    });

    test('exhausting the quota breaks the streak', () {
      final events = [
        issued(aug(10)),
        // Aug 11 exhausts it.
        issued(aug(11, 8)), issued(aug(11, 12)), issued(aug(11, 18)),
        issued(aug(12)),
      ];
      final summary =
          computeStreaks(events: events, quota: quota, upTo: aug(12, 20));

      expect(summary.current, 1, reason: 'only today survives');
      expect(summary.longest, 1);
      expect(summary.cleanDays, 2);
      expect(summary.totalDays, 3);
    });

    test('days with no events at all are clean', () {
      final events = [issued(aug(10)), issued(aug(14))];
      final summary =
          computeStreaks(events: events, quota: quota, upTo: aug(14, 20));

      expect(summary.totalDays, 5);
      expect(summary.cleanDays, 5, reason: 'a gap in the log is not a relapse');
      expect(summary.current, 5);
    });

    test('longest survives after the current streak breaks', () {
      final events = [
        issued(aug(1)), // clean days 1..5
        // Aug 6 exhausts
        issued(aug(6, 7)), issued(aug(6, 9)), issued(aug(6, 11)),
        // 7 and 8 clean, then 9 exhausts
        issued(aug(9, 7)), issued(aug(9, 9)), issued(aug(9, 11)),
      ];
      final summary =
          computeStreaks(events: events, quota: quota, upTo: aug(10, 20));

      expect(summary.longest, 5, reason: 'Aug 1-5');
      expect(summary.current, 1, reason: 'only Aug 10');
    });

    test('an exhausted day today zeroes the current streak', () {
      final events = [
        issued(aug(11)),
        issued(aug(12, 7)), issued(aug(12, 9)), issued(aug(12, 11)),
      ];
      final summary =
          computeStreaks(events: events, quota: quota, upTo: aug(12, 20));
      expect(summary.current, 0);
    });

    test('a late-night permit counts against the day it started', () {
      // 02:00 on the 13th is still the 12th's quota day.
      final events = [
        issued(aug(12, 8)),
        issued(aug(12, 20)),
        issued(DateTime(2026, 8, 13, 2)),
      ];
      final summary = computeStreaks(
          events: events, quota: quota, upTo: DateTime(2026, 8, 13, 3));

      expect(summary.current, 0,
          reason: 'the 2am permit exhausted the 12th, and we are still in it');
    });

    test('attempts alone never break a streak', () {
      final events = [
        attempt(aug(10)), attempt(aug(10, 13)), attempt(aug(10, 14)),
        attempt(aug(11)), attempt(aug(12)),
      ];
      final summary =
          computeStreaks(events: events, quota: quota, upTo: aug(12, 20));

      expect(summary.current, 3,
          reason: 'resisting is the behaviour we want, not a failure');
    });
  });

  group('computeStreaks (noPermits rule)', () {
    test('any permit at all breaks the streak', () {
      final events = [issued(aug(10)), issued(aug(12))];
      final summary = computeStreaks(
        events: events,
        quota: quota,
        upTo: aug(12, 20),
        rule: StreakRule.noPermits,
      );

      expect(summary.current, 0);
      expect(summary.longest, 1, reason: 'only Aug 11 was permit-free');
    });
  });

  test('events dated in the future report today only', () {
    final events = [issued(aug(20))];
    final summary =
        computeStreaks(events: events, quota: quota, upTo: aug(12, 20));
    expect(summary.totalDays, 1);
  });
}
