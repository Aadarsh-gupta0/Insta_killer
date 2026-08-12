import 'package:insta_killer_domain/insta_killer_domain.dart';
import 'package:test/test.dart';

Event issued(DateTime at) => Event(at: at, kind: EventKind.permitIssued);

Event attempt(DateTime at) => Event(at: at, kind: EventKind.attemptBlocked);

void main() {
  const quota = QuotaPolicy.standard;

  test('buckets attempts by local hour', () {
    final insights = computeInsights(
      events: [
        attempt(DateTime(2026, 8, 12, 23, 10)),
        attempt(DateTime(2026, 8, 12, 23, 50)),
        attempt(DateTime(2026, 8, 11, 23, 5)),
        attempt(DateTime(2026, 8, 12, 9, 0)),
      ],
      quota: quota,
    );

    expect(insights.attemptsByHour[23], 3);
    expect(insights.attemptsByHour[9], 1);
    expect(insights.attemptsByHour[0], 0);
    expect(insights.totalAttempts, 4);
  });

  test('groups permits and attempts by quota day, not calendar day', () {
    final insights = computeInsights(
      events: [
        issued(DateTime(2026, 8, 12, 20)),
        issued(DateTime(2026, 8, 13, 2)), // still the 12th's day
        issued(DateTime(2026, 8, 13, 8)), // the 13th
      ],
      quota: quota,
    );

    expect(insights.permitsByDay['2026-08-12'], 2);
    expect(insights.permitsByDay['2026-08-13'], 1);
    expect(insights.totalPermits, 3);
  });

  group('median time to relapse', () {
    test('is null with nothing to measure', () {
      expect(computeInsights(events: const [], quota: quota).medianTimeToRelapse,
          isNull);
      expect(
        computeInsights(events: [issued(DateTime(2026, 8, 12, 9))], quota: quota)
            .medianTimeToRelapse,
        isNull,
        reason: 'a permit with no attempt after it is not a relapse',
      );
    });

    test('measures to the first attempt after each permit', () {
      final insights = computeInsights(
        events: [
          issued(DateTime(2026, 8, 12, 9, 0)),
          attempt(DateTime(2026, 8, 12, 10, 0)), // 1h
          attempt(DateTime(2026, 8, 12, 11, 0)), // ignored, already counted
          issued(DateTime(2026, 8, 12, 12, 0)),
          attempt(DateTime(2026, 8, 12, 15, 0)), // 3h
        ],
        quota: quota,
      );

      // Two gaps of 1h and 3h: even count, so the mean of the middle pair.
      expect(insights.medianTimeToRelapse, const Duration(hours: 2));
    });

    test('takes the middle value for an odd count', () {
      final insights = computeInsights(
        events: [
          issued(DateTime(2026, 8, 12, 1)),
          attempt(DateTime(2026, 8, 12, 2)), // 1h
          issued(DateTime(2026, 8, 12, 3)),
          attempt(DateTime(2026, 8, 12, 5)), // 2h
          issued(DateTime(2026, 8, 12, 6)),
          attempt(DateTime(2026, 8, 12, 16)), // 10h
        ],
        quota: quota,
      );

      expect(insights.medianTimeToRelapse, const Duration(hours: 2),
          reason: 'the 10h outlier must not drag it, which a mean would');
    });

    test('does not care what order the log arrives in', () {
      final ordered = computeInsights(
        events: [
          issued(DateTime(2026, 8, 12, 9)),
          attempt(DateTime(2026, 8, 12, 10)),
        ],
        quota: quota,
      );
      final shuffled = computeInsights(
        events: [
          attempt(DateTime(2026, 8, 12, 10)),
          issued(DateTime(2026, 8, 12, 9)),
        ],
        quota: quota,
      );

      expect(shuffled.medianTimeToRelapse, ordered.medianTimeToRelapse);
    });
  });

  test('the returned collections are unmodifiable', () {
    final insights = computeInsights(
      events: [attempt(DateTime(2026, 8, 12, 9))],
      quota: quota,
    );
    expect(() => insights.attemptsByHour[0] = 99, throwsUnsupportedError);
    expect(() => insights.permitsByDay['x'] = 1, throwsUnsupportedError);
  });
}
