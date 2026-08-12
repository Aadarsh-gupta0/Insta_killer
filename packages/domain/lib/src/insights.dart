/// The Record (FR-30). Facts, no congratulation.
library;

import 'event.dart';
import 'quota.dart';
import 'quota_day.dart';

class Insights {
  const Insights({
    required this.attemptsByHour,
    required this.permitsByDay,
    required this.attemptsByDay,
    required this.medianTimeToRelapse,
    required this.totalAttempts,
    required this.totalPermits,
  });

  /// 24 buckets, index = local hour. The shape of the habit — this is the chart that
  /// tells you the 11pm problem is a different problem from the 9am one.
  final List<int> attemptsByHour;

  final Map<String, int> permitsByDay;
  final Map<String, int> attemptsByDay;

  /// Median gap between a permit being issued and the next blocked attempt.
  ///
  /// Null when no permit has ever been followed by an attempt. Median rather than mean
  /// because one forgotten phone on a desk overnight would drag a mean into fiction.
  final Duration? medianTimeToRelapse;

  final int totalAttempts;
  final int totalPermits;
}

Insights computeInsights({
  required Iterable<Event> events,
  required QuotaPolicy quota,
}) {
  final sorted = events.toList()..sort((a, b) => a.at.compareTo(b.at));

  final byHour = List<int>.filled(24, 0);
  final permitsByDay = <String, int>{};
  final attemptsByDay = <String, int>{};
  var totalAttempts = 0;
  var totalPermits = 0;

  for (final event in sorted) {
    final dayKey = QuotaDay.forInstant(event.at, quota.boundary).key;
    switch (event.kind) {
      case EventKind.attemptBlocked:
        byHour[event.at.hour]++;
        attemptsByDay[dayKey] = (attemptsByDay[dayKey] ?? 0) + 1;
        totalAttempts++;
      case EventKind.permitIssued:
        permitsByDay[dayKey] = (permitsByDay[dayKey] ?? 0) + 1;
        totalPermits++;
      case _:
        break;
    }
  }

  return Insights(
    attemptsByHour: List.unmodifiable(byHour),
    permitsByDay: Map.unmodifiable(permitsByDay),
    attemptsByDay: Map.unmodifiable(attemptsByDay),
    medianTimeToRelapse: _medianTimeToRelapse(sorted),
    totalAttempts: totalAttempts,
    totalPermits: totalPermits,
  );
}

Duration? _medianTimeToRelapse(List<Event> sorted) {
  final gaps = <Duration>[];

  for (var i = 0; i < sorted.length; i++) {
    if (sorted[i].kind != EventKind.permitIssued) continue;
    for (var j = i + 1; j < sorted.length; j++) {
      if (sorted[j].kind == EventKind.attemptBlocked) {
        gaps.add(sorted[j].at.difference(sorted[i].at));
        break;
      }
    }
  }

  if (gaps.isEmpty) return null;
  gaps.sort();

  final mid = gaps.length ~/ 2;
  if (gaps.length.isOdd) return gaps[mid];
  return Duration(
    microseconds:
        (gaps[mid - 1].inMicroseconds + gaps[mid].inMicroseconds) ~/ 2,
  );
}
