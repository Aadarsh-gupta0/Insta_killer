/// The daily allowance (FR-16, FR-17).
library;

import 'event.dart';
import 'quota_day.dart';

class QuotaPolicy {
  const QuotaPolicy({
    this.permitsPerDay = 3,
    this.boundary = DayBoundary.defaultBoundary,
  }) : assert(permitsPerDay >= 0, 'a negative quota is not a thing');

  static const QuotaPolicy standard = QuotaPolicy();

  final int permitsPerDay;
  final DayBoundary boundary;

  QuotaPolicy copyWith({int? permitsPerDay, DayBoundary? boundary}) =>
      QuotaPolicy(
        permitsPerDay: permitsPerDay ?? this.permitsPerDay,
        boundary: boundary ?? this.boundary,
      );

  Map<String, Object?> toJson() => {
        'permitsPerDay': permitsPerDay,
        'boundary': boundary.toJson(),
      };

  static QuotaPolicy fromJson(Map<String, Object?> json) => QuotaPolicy(
        permitsPerDay: json['permitsPerDay']! as int,
        boundary:
            DayBoundary.fromJson((json['boundary']! as Map).cast<String, Object?>()),
      );

  QuotaState stateAt(DateTime instant, Iterable<Event> events) {
    final day = QuotaDay.forInstant(instant, boundary);
    final issued = events
        .where((e) => e.kind == EventKind.permitIssued && day.contains(e.at))
        .length;

    return QuotaState(
      day: day,
      issued: issued,
      permitsPerDay: permitsPerDay,
    );
  }
}

class QuotaState {
  const QuotaState({
    required this.day,
    required this.issued,
    required this.permitsPerDay,
  });

  final QuotaDay day;
  final int issued;
  final int permitsPerDay;

  /// Clamped at zero: a quota lowered mid-day can leave [issued] above the new limit,
  /// and "-1 permits remaining" is not a thing we should ever render.
  int get remaining {
    final left = permitsPerDay - issued;
    return left < 0 ? 0 : left;
  }

  bool get exhausted => remaining == 0;

  /// FR-17 — every refusal names the next possible time.
  DateTime get resetsAt => day.endsAt;
}
