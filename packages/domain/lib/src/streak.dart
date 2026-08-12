/// Streaks of quota-clean days (FR-30).
///
/// **An ambiguity in the SRS, resolved and flagged.** FR-30 asks for "current and longest
/// streak of quota-clean days" without defining clean. Two readings are defensible:
/// a day with *no* permits, or a day that did not *exhaust* the quota. This package
/// implements both and defaults to [StreakRule.underQuota], because §1.2 measures success
/// as "a reduction in blocked attempts per day without a rise in permits issued" — permits
/// used deliberately are the product working, not a failure. Switch the default if you
/// disagree; it is one enum.
library;

import 'event.dart';
import 'quota.dart';
import 'quota_day.dart';

enum StreakRule {
  /// Clean means no permit was issued at all.
  noPermits,

  /// Clean means the quota was not exhausted.
  underQuota,
}

class StreakSummary {
  const StreakSummary({
    required this.current,
    required this.longest,
    required this.cleanDays,
    required this.totalDays,
  });

  /// Counting back from today. Today counts provisionally — spending the last permit
  /// this evening resets it to zero, which is the point.
  final int current;

  final int longest;
  final int cleanDays;
  final int totalDays;

  @override
  String toString() =>
      'StreakSummary(current: $current, longest: $longest, '
      'clean: $cleanDays/$totalDays)';
}

/// Walks every quota day from the first recorded event to the one containing [upTo].
///
/// Days with no events are clean: nothing happened, nothing was spent. A gap in the log
/// is not a gap in the streak.
StreakSummary computeStreaks({
  required Iterable<Event> events,
  required QuotaPolicy quota,
  required DateTime upTo,
  StreakRule rule = StreakRule.underQuota,
}) {
  final eventList = events.toList()..sort((a, b) => a.at.compareTo(b.at));
  final today = QuotaDay.forInstant(upTo, quota.boundary);

  if (eventList.isEmpty) {
    return const StreakSummary(
        current: 1, longest: 1, cleanDays: 1, totalDays: 1);
  }

  final issuedPerDay = <String, int>{};
  for (final event in eventList) {
    if (event.kind != EventKind.permitIssued) continue;
    final day = QuotaDay.forInstant(event.at, quota.boundary);
    issuedPerDay[day.key] = (issuedPerDay[day.key] ?? 0) + 1;
  }

  bool isClean(QuotaDay day) {
    final issued = issuedPerDay[day.key] ?? 0;
    return switch (rule) {
      StreakRule.noPermits => issued == 0,
      StreakRule.underQuota => issued < quota.permitsPerDay,
    };
  }

  final firstDay = QuotaDay.forInstant(eventList.first.at, quota.boundary);
  final span = today.daysBetween(firstDay);
  if (span < 0) {
    // Every event is in the future — a clock change, most likely. Report today only
    // rather than inventing a streak.
    return StreakSummary(
      current: isClean(today) ? 1 : 0,
      longest: isClean(today) ? 1 : 0,
      cleanDays: isClean(today) ? 1 : 0,
      totalDays: 1,
    );
  }

  var longest = 0;
  var running = 0;
  var cleanDays = 0;
  var current = 0;

  var day = firstDay;
  for (var i = 0; i <= span; i++) {
    if (isClean(day)) {
      running++;
      cleanDays++;
      if (running > longest) longest = running;
    } else {
      running = 0;
    }
    day = day.next;
  }
  current = running; // the run still going as of today

  return StreakSummary(
    current: current,
    longest: longest,
    cleanDays: cleanDays,
    totalDays: span + 1,
  );
}
