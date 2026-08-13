/// The day, as the quota understands it.
///
/// FR-16 resets the quota at a user-defined boundary, default 06:00 local. So a "day" is
/// not midnight-to-midnight: at 02:00 you are still spending yesterday's permits, which
/// is the entire point — the 2am scroll should not be handed a fresh allowance.
library;

/// Minutes past local midnight at which the quota rolls over.
class DayBoundary {
  const DayBoundary({this.hour = 6, this.minute = 0})
      : assert(hour >= 0 && hour < 24, 'hour must be 0..23'),
        assert(minute >= 0 && minute < 60, 'minute must be 0..59');

  static const DayBoundary defaultBoundary = DayBoundary();

  final int hour;
  final int minute;

  int get minutesFromMidnight => hour * 60 + minute;

  Map<String, Object?> toJson() => {'hour': hour, 'minute': minute};

  static DayBoundary fromJson(Map<String, Object?> json) => DayBoundary(
        hour: json['hour']! as int,
        minute: json['minute']! as int,
      );

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is DayBoundary && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

/// One quota period, identified by the calendar date it began on.
class QuotaDay implements Comparable<QuotaDay> {
  const QuotaDay._(this.startsAt, this.boundary);

  /// Which quota day [instant] falls in.
  factory QuotaDay.forInstant(DateTime instant, DayBoundary boundary) {
    final todaysBoundary = DateTime(
      instant.year,
      instant.month,
      instant.day,
      boundary.hour,
      boundary.minute,
    );
    // Before today's boundary, we are still inside yesterday's day.
    final start = instant.isBefore(todaysBoundary)
        ? _shiftDays(todaysBoundary, -1)
        : todaysBoundary;
    return QuotaDay._(start, boundary);
  }

  final DateTime startsAt;
  final DayBoundary boundary;

  DateTime get endsAt => _shiftDays(startsAt, 1);

  QuotaDay get next => QuotaDay._(endsAt, boundary);

  QuotaDay get previous => QuotaDay._(_shiftDays(startsAt, -1), boundary);

  bool contains(DateTime instant) =>
      !instant.isBefore(startsAt) && instant.isBefore(endsAt);

  /// A stable key for grouping events. Not a display string.
  String get key => '${startsAt.year.toString().padLeft(4, '0')}-'
      '${startsAt.month.toString().padLeft(2, '0')}-'
      '${startsAt.day.toString().padLeft(2, '0')}';

  /// Days between two quota days, ignoring the time component.
  int daysBetween(QuotaDay other) {
    final a = DateTime(startsAt.year, startsAt.month, startsAt.day);
    final b =
        DateTime(other.startsAt.year, other.startsAt.month, other.startsAt.day);
    return a.difference(b).inDays;
  }

  @override
  int compareTo(QuotaDay other) => startsAt.compareTo(other.startsAt);

  @override
  bool operator ==(Object other) =>
      other is QuotaDay && other.startsAt == startsAt;

  @override
  int get hashCode => startsAt.hashCode;

  @override
  String toString() => 'QuotaDay($key from $boundary)';
}

/// Adds days via the calendar rather than by adding 24 hours.
///
/// `DateTime.add(Duration(days: 1))` adds exactly 86400 seconds, which lands on the
/// wrong wall-clock time across a DST transition — the quota would reset an hour late
/// twice a year. Constructing a new DateTime keeps the boundary at the stated time.
DateTime _shiftDays(DateTime from, int days) => DateTime(
      from.year,
      from.month,
      from.day + days,
      from.hour,
      from.minute,
      from.second,
    );
