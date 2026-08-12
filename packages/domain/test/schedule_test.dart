import 'package:insta_killer_domain/insta_killer_domain.dart';
import 'package:test/test.dart';

void main() {
  // 2026-08-12 is a Wednesday.
  final wed = DateTime(2026, 8, 12, 0, 0);

  group('cell arithmetic', () {
    test('Monday 00:00 is cell zero', () {
      expect(WeeklySchedule.cellFor(DateTime(2026, 8, 10, 0, 0)), 0);
    });

    test('cells are exactly 15 minutes wide', () {
      expect(WeeklySchedule.cellFor(DateTime(2026, 8, 10, 0, 14)), 0);
      expect(WeeklySchedule.cellFor(DateTime(2026, 8, 10, 0, 15)), 1);
      expect(WeeklySchedule.cellFor(DateTime(2026, 8, 10, 1, 0)), 4);
    });

    test('the week is 672 cells and Sunday is the last day', () {
      expect(cellsPerWeek, 672);
      expect(WeeklySchedule.cellFor(DateTime(2026, 8, 16, 23, 45)), 671);
    });

    test('rejects out-of-range cells rather than silently wrapping', () {
      expect(() => WeeklySchedule([672]), throwsArgumentError);
      expect(() => WeeklySchedule([-1]), throwsArgumentError);
    });
  });

  group('daily windows', () {
    test('blocks the stated hours every day', () {
      final schedule =
          WeeklySchedule.daily(startHour: 23, endHour: 23, endMinute: 45);
      expect(schedule.isBlockedAt(wed.add(const Duration(hours: 23))), isTrue);
      expect(
          schedule.isBlockedAt(
              wed.add(const Duration(hours: 23, minutes: 44))),
          isTrue);
      expect(
          schedule.isBlockedAt(
              wed.add(const Duration(hours: 23, minutes: 45))),
          isFalse);
    });

    test('a window crossing midnight lands on both days', () {
      // 23:00 to 02:00.
      final schedule = WeeklySchedule.daily(startHour: 23, endHour: 2);

      expect(schedule.isBlockedAt(DateTime(2026, 8, 12, 23, 30)), isTrue);
      expect(schedule.isBlockedAt(DateTime(2026, 8, 13, 1, 30)), isTrue);
      expect(schedule.isBlockedAt(DateTime(2026, 8, 13, 2, 0)), isFalse);
      expect(schedule.isBlockedAt(DateTime(2026, 8, 13, 12, 0)), isFalse);
    });

    test('a Sunday-night window wraps onto Monday', () {
      final schedule = WeeklySchedule.daily(startHour: 23, endHour: 1);
      expect(schedule.isBlockedAt(DateTime(2026, 8, 16, 23, 30)), isTrue); // Sun
      expect(schedule.isBlockedAt(DateTime(2026, 8, 10, 0, 30)), isTrue); // Mon
    });

    test('reports total blocked minutes', () {
      final schedule = WeeklySchedule.daily(startHour: 0, endHour: 1);
      expect(schedule.blockedMinutesPerWeek, 7 * 60);
    });
  });

  group('blockedUntil', () {
    test('is null outside a window', () {
      final schedule = WeeklySchedule.daily(startHour: 23, endHour: 24);
      expect(schedule.blockedUntil(DateTime(2026, 8, 12, 12)), isNull);
    });

    test('walks to the end of a contiguous run, not just the current cell', () {
      final schedule = WeeklySchedule.daily(startHour: 22, endHour: 24);
      expect(
        schedule.blockedUntil(DateTime(2026, 8, 12, 22, 5)),
        DateTime(2026, 8, 13, 0, 0),
      );
    });

    test('walks across midnight through a wrapping window', () {
      final schedule = WeeklySchedule.daily(startHour: 23, endHour: 2);
      expect(
        schedule.blockedUntil(DateTime(2026, 8, 12, 23, 30)),
        DateTime(2026, 8, 13, 2, 0),
      );
    });

    test('returns null rather than looping when every cell is blocked', () {
      final always = WeeklySchedule(List.generate(cellsPerWeek, (i) => i));
      expect(always.isBlockedAt(wed), isTrue);
      expect(always.blockedUntil(wed), isNull,
          reason: 'the caller must say "indefinitely", not spin');
    });
  });

  group('editing', () {
    test('adding and removing cells', () {
      final base = WeeklySchedule([0, 1, 2]);
      expect(base.withCells([3]).blockedCells, {0, 1, 2, 3});
      expect(base.withoutCells([0]).blockedCells, {1, 2});
    });

    test('equality ignores ordering', () {
      expect(WeeklySchedule([3, 1, 2]), WeeklySchedule([1, 2, 3]));
    });

    test('survives a JSON round trip', () {
      final schedule = WeeklySchedule.daily(startHour: 9, endHour: 17);
      expect(WeeklySchedule.fromJson(schedule.toJson()), schedule);
    });
  });
}
