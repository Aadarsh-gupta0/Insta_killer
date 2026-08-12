import 'dart:convert';

import 'package:insta_killer_domain/insta_killer_domain.dart';
import 'package:test/test.dart';

/// Every one of these types crosses a process boundary — the App Group on iOS, shared
/// preferences and the event log on Android — so a broken round trip is silent data loss
/// in the one record the product is judged on.
void main() {
  group('Event', () {
    test('round-trips through JSON', () {
      final event = Event(
        at: DateTime(2026, 8, 12, 14, 30),
        kind: EventKind.permitIssued,
        permitId: 'p-1',
        detail: 'from-gate',
        reason: 'checking the group chat',
      );

      final restored =
          Event.fromJson(jsonDecode(jsonEncode(event.toJson())) as Map<String, Object?>);

      expect(restored.at, event.at);
      expect(restored.kind, EventKind.permitIssued);
      expect(restored.permitId, 'p-1');
      expect(restored.detail, 'from-gate');
      expect(restored.reason, 'checking the group chat');
    });

    test('omits absent optional fields rather than writing nulls', () {
      final event =
          Event(at: DateTime(2026, 8, 12, 9), kind: EventKind.attemptBlocked);
      final json = event.toJson();

      expect(json.containsKey('permitId'), isFalse);
      expect(json.containsKey('detail'), isFalse);
      expect(json.containsKey('reason'), isFalse);
    });

    test('preserves the instant across timezones by storing UTC', () {
      final event =
          Event(at: DateTime(2026, 8, 12, 14, 30), kind: EventKind.attemptBlocked);
      expect(event.toJson()['at'], endsWith('Z'));

      final restored = Event.fromJson(event.toJson());
      expect(restored.at.isUtc, isFalse, reason: 'restored to local for display');
      expect(restored.at.millisecondsSinceEpoch, event.at.millisecondsSinceEpoch);
    });

    test('every kind survives the name round trip', () {
      for (final kind in EventKind.values) {
        final event = Event(at: DateTime(2026, 8, 12), kind: kind);
        expect(Event.fromJson(event.toJson()).kind, kind);
      }
    });

    test('has a readable toString for logs', () {
      final event = Event(
        at: DateTime(2026, 8, 12, 9),
        kind: EventKind.permitRefused,
        detail: 'quota',
      );
      expect(event.toString(), contains('permitRefused'));
      expect(event.toString(), contains('quota'));
    });
  });

  group('ClockStamp', () {
    test('round-trips both readings', () {
      final clock = FakeClock(
        wall: DateTime(2026, 8, 12, 14),
        monotonic: const Duration(hours: 9, minutes: 12),
      );
      final stamp = ClockStamp.now(clock);

      final restored = ClockStamp.fromJson(
          jsonDecode(jsonEncode(stamp.toJson())) as Map<String, Object?>);

      expect(restored.wall.millisecondsSinceEpoch,
          stamp.wall.millisecondsSinceEpoch);
      expect(restored.monotonic, const Duration(hours: 9, minutes: 12));
    });
  });

  group('QuotaDay', () {
    const boundary = DayBoundary();

    test('previous and next are inverses', () {
      final day = QuotaDay.forInstant(DateTime(2026, 8, 12, 14), boundary);
      expect(day.next.previous, day);
      expect(day.previous.next, day);
    });

    test('sorts chronologically', () {
      final days = [
        QuotaDay.forInstant(DateTime(2026, 8, 14, 12), boundary),
        QuotaDay.forInstant(DateTime(2026, 8, 12, 12), boundary),
        QuotaDay.forInstant(DateTime(2026, 8, 13, 12), boundary),
      ]..sort();

      expect(days.map((d) => d.key),
          ['2026-08-12', '2026-08-13', '2026-08-14']);
    });

    test('the key is zero-padded and stable', () {
      final day = QuotaDay.forInstant(DateTime(2026, 1, 5, 12), boundary);
      expect(day.key, '2026-01-05');
    });

    test('equal days share a hash code', () {
      final a = QuotaDay.forInstant(DateTime(2026, 8, 12, 9), boundary);
      final b = QuotaDay.forInstant(DateTime(2026, 8, 12, 21), boundary);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect({a, b}, hasLength(1));
    });

    test('toString names the day and boundary', () {
      final day = QuotaDay.forInstant(DateTime(2026, 8, 12, 9), boundary);
      expect(day.toString(), contains('2026-08-12'));
      expect(day.toString(), contains('06:00'));
    });
  });

  group('DayBoundary', () {
    test('rejects impossible times', () {
      expect(() => DayBoundary(hour: 24), throwsA(isA<AssertionError>()));
      expect(() => DayBoundary(minute: 60), throwsA(isA<AssertionError>()));
      expect(() => DayBoundary(hour: -1), throwsA(isA<AssertionError>()));
    });

    test('formats as a 24-hour clock', () {
      expect(const DayBoundary(hour: 6).toString(), '06:00');
      expect(const DayBoundary(hour: 23, minute: 30).toString(), '23:30');
    });

    test('value equality', () {
      expect(const DayBoundary(hour: 6), const DayBoundary());
      expect(const DayBoundary(hour: 6).hashCode, const DayBoundary().hashCode);
      expect(const DayBoundary(hour: 7), isNot(const DayBoundary()));
    });
  });
}
