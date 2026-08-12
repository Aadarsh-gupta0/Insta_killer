import 'package:insta_killer_domain/insta_killer_domain.dart';
import 'package:test/test.dart';

Event issued(DateTime at) => Event(at: at, kind: EventKind.permitIssued);

void main() {
  const boundary = DayBoundary(); // 06:00

  group('QuotaDay', () {
    test('an evening belongs to the day that just started', () {
      final day = QuotaDay.forInstant(DateTime(2026, 8, 12, 22, 30), boundary);
      expect(day.startsAt, DateTime(2026, 8, 12, 6));
      expect(day.endsAt, DateTime(2026, 8, 13, 6));
    });

    test('the 2am scroll still spends yesterday\'s permits', () {
      final day = QuotaDay.forInstant(DateTime(2026, 8, 12, 2, 15), boundary);
      expect(day.startsAt, DateTime(2026, 8, 11, 6),
          reason: 'this is the whole reason the boundary is not midnight');
    });

    test('the boundary instant itself starts the new day', () {
      final day = QuotaDay.forInstant(DateTime(2026, 8, 12, 6), boundary);
      expect(day.startsAt, DateTime(2026, 8, 12, 6));
    });

    test('one minute before the boundary is still the old day', () {
      final day = QuotaDay.forInstant(DateTime(2026, 8, 12, 5, 59), boundary);
      expect(day.startsAt, DateTime(2026, 8, 11, 6));
    });

    test('contains is half-open so days never overlap', () {
      final day = QuotaDay.forInstant(DateTime(2026, 8, 12, 12), boundary);
      expect(day.contains(day.startsAt), isTrue);
      expect(day.contains(day.endsAt), isFalse);
      expect(day.next.contains(day.endsAt), isTrue);
    });

    test('rolls across a month end', () {
      final day = QuotaDay.forInstant(DateTime(2026, 8, 31, 23), boundary);
      expect(day.next.startsAt, DateTime(2026, 9, 1, 6));
    });

    test('keeps the boundary time when stepping days', () {
      var day = QuotaDay.forInstant(DateTime(2026, 3, 28, 12), boundary);
      for (var i = 0; i < 5; i++) {
        day = day.next;
        expect(day.startsAt.hour, 6,
            reason: 'adding 24h instead of a calendar day drifts across DST');
        expect(day.startsAt.minute, 0);
      }
    });

    test('a custom boundary is honoured', () {
      const midnight = DayBoundary(hour: 0);
      final day = QuotaDay.forInstant(DateTime(2026, 8, 12, 2), midnight);
      expect(day.startsAt, DateTime(2026, 8, 12));
    });

    test('daysBetween counts calendar days', () {
      final a = QuotaDay.forInstant(DateTime(2026, 8, 12, 12), boundary);
      final b = QuotaDay.forInstant(DateTime(2026, 8, 5, 12), boundary);
      expect(a.daysBetween(b), 7);
    });
  });

  group('QuotaPolicy', () {
    const policy = QuotaPolicy.standard; // 3 per day

    test('counts only permits inside the current day', () {
      final now = DateTime(2026, 8, 12, 20);
      final events = [
        issued(DateTime(2026, 8, 12, 7)), // today
        issued(DateTime(2026, 8, 12, 19)), // today
        issued(DateTime(2026, 8, 12, 5)), // before the boundary: yesterday
        issued(DateTime(2026, 8, 10, 12)), // long gone
      ];

      final state = policy.stateAt(now, events);
      expect(state.issued, 2);
      expect(state.remaining, 1);
      expect(state.exhausted, isFalse);
    });

    test('exhausts at the configured limit and names the reset time', () {
      final now = DateTime(2026, 8, 12, 20);
      final events = List.generate(3, (i) => issued(DateTime(2026, 8, 12, 9 + i)));

      final state = policy.stateAt(now, events);
      expect(state.exhausted, isTrue);
      expect(state.remaining, 0);
      expect(state.resetsAt, DateTime(2026, 8, 13, 6));
    });

    test('never reports negative remaining after the quota is lowered', () {
      final now = DateTime(2026, 8, 12, 20);
      final events = List.generate(5, (i) => issued(DateTime(2026, 8, 12, 8 + i)));

      final state = const QuotaPolicy(permitsPerDay: 2).stateAt(now, events);
      expect(state.issued, 5);
      expect(state.remaining, 0);
    });

    test('ignores non-issue events', () {
      final now = DateTime(2026, 8, 12, 20);
      final events = [
        Event(at: DateTime(2026, 8, 12, 9), kind: EventKind.attemptBlocked),
        Event(at: DateTime(2026, 8, 12, 10), kind: EventKind.permitRefused),
        Event(at: DateTime(2026, 8, 12, 11), kind: EventKind.permitExpired),
      ];
      expect(policy.stateAt(now, events).issued, 0);
    });

    test('a zero quota is permanently exhausted', () {
      final state = const QuotaPolicy(permitsPerDay: 0)
          .stateAt(DateTime(2026, 8, 12, 20), const []);
      expect(state.exhausted, isTrue);
    });
  });
}
