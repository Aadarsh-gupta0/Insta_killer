import 'package:insta_killer_domain/insta_killer_domain.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 8, 12, 14);
  const policy = StrictnessPolicy();
  const base = OfficeRules(); // strict mode on, quota 3

  ChangeOutcome request(OfficeRules to, {OfficeRules from = base}) =>
      policy.request(
        from: from,
        to: to,
        now: now,
        description: 'test',
        idFactory: () => 'chg-1',
      );

  group('classification', () {
    test('raising the quota loosens', () {
      expect(
        classifyChange(base, base.copyWith(quota: const QuotaPolicy(permitsPerDay: 5))),
        ChangeDirection.loosen,
      );
    });

    test('lowering the quota tightens', () {
      expect(
        classifyChange(base, base.copyWith(quota: const QuotaPolicy(permitsPerDay: 1))),
        ChangeDirection.tighten,
      );
    });

    test('removing a blocked app loosens', () {
      final from = base.copyWith(blockedAppCount: 3);
      expect(classifyChange(from, from.copyWith(blockedAppCount: 2)),
          ChangeDirection.loosen);
    });

    test('adding a blocked app tightens', () {
      final from = base.copyWith(blockedAppCount: 3);
      expect(classifyChange(from, from.copyWith(blockedAppCount: 4)),
          ChangeDirection.tighten);
    });

    test('shortening a schedule loosens', () {
      final from =
          base.copyWith(schedule: WeeklySchedule.daily(startHour: 22, endHour: 24));
      final to =
          base.copyWith(schedule: WeeklySchedule.daily(startHour: 23, endHour: 24));
      expect(classifyChange(from, to), ChangeDirection.loosen);
    });

    test('moving a window without changing its length still loosens', () {
      // Some hours were freed even though the total is identical.
      final from =
          base.copyWith(schedule: WeeklySchedule.daily(startHour: 22, endHour: 23));
      final to =
          base.copyWith(schedule: WeeklySchedule.daily(startHour: 9, endHour: 10));
      expect(classifyChange(from, to), ChangeDirection.loosen);
    });

    test('longer grants loosen', () {
      expect(
        classifyChange(base, base.copyWith(grantDuration: const Duration(minutes: 30))),
        ChangeDirection.loosen,
      );
    });

    test('turning Strict Mode off loosens; on tightens', () {
      expect(classifyChange(base, base.copyWith(strictMode: false)),
          ChangeDirection.loosen);
      expect(
        classifyChange(base.copyWith(strictMode: false), base),
        ChangeDirection.tighten,
      );
    });

    test('a mixed change counts as loosening', () {
      // Blocking one more app while tripling the quota is not a tightening.
      final to = base.copyWith(
        blockedAppCount: 1,
        quota: const QuotaPolicy(permitsPerDay: 9),
      );
      expect(classifyChange(base, to), ChangeDirection.loosen,
          reason: 'otherwise a loosening can be smuggled in behind a tightening');
    });

    test('changing the day boundary is treated as loosening', () {
      expect(
        classifyChange(
            base, base.copyWith(quota: const QuotaPolicy(boundary: DayBoundary(hour: 4)))),
        ChangeDirection.loosen,
      );
    });

    test('an identical edit is neutral', () {
      expect(classifyChange(base, base.copyWith()), ChangeDirection.neutral);
    });
  });

  group('cooldown', () {
    test('a tightening applies at once', () {
      final outcome =
          request(base.copyWith(quota: const QuotaPolicy(permitsPerDay: 1)));
      expect(outcome, isA<ChangeApplied>());
    });

    test('a loosening waits 24 hours', () {
      final outcome =
          request(base.copyWith(quota: const QuotaPolicy(permitsPerDay: 5)));

      expect(outcome, isA<ChangeQueued>());
      final pending = (outcome as ChangeQueued).pending;
      expect(pending.appliesAt, now.add(const Duration(hours: 24)));
      expect(pending.remaining(now), const Duration(hours: 24));
    });

    test('you cannot disable Strict Mode to escape the cooldown', () {
      final outcome = request(base.copyWith(strictMode: false));
      expect(outcome, isA<ChangeQueued>(),
          reason: 'the escape hatch is itself a loosening');
    });

    test('with Strict Mode off, everything applies immediately', () {
      final off = base.copyWith(strictMode: false);
      final outcome = request(
        off.copyWith(quota: const QuotaPolicy(permitsPerDay: 9)),
        from: off,
      );
      expect(outcome, isA<ChangeApplied>());
    });

    test('a queued change is cancellable until it lands', () {
      final pending =
          (request(base.copyWith(quota: const QuotaPolicy(permitsPerDay: 5)))
                  as ChangeQueued)
              .pending;

      expect(policy.canCancel(pending, now), isTrue);
      expect(
          policy.canCancel(pending, now.add(const Duration(hours: 23, minutes: 59))),
          isTrue);
      expect(policy.canCancel(pending, now.add(const Duration(hours: 24))), isFalse);
    });

    test('applies only once due', () {
      final pending =
          (request(base.copyWith(quota: const QuotaPolicy(permitsPerDay: 5)))
                  as ChangeQueued)
              .pending;

      expect(policy.applyIfDue(pending, now.add(const Duration(hours: 23))), isNull);

      final applied = policy.applyIfDue(pending, now.add(const Duration(hours: 24)));
      expect(applied, isNotNull);
      expect(applied!.quota.permitsPerDay, 5);
    });

    test('remaining never goes negative', () {
      final pending =
          (request(base.copyWith(quota: const QuotaPolicy(permitsPerDay: 5)))
                  as ChangeQueued)
              .pending;
      expect(pending.remaining(now.add(const Duration(days: 3))), Duration.zero);
    });
  });
}
