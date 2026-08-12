/// A permit: time-boxed, quota-consuming, non-refundable.
library;

import 'clock.dart';

/// The platform floor (C-6, FR-15). Fifteen minutes is not a product decision — it is
/// the shortest interval `DeviceActivity` schedules reliably.
const Duration platformGrantFloor = Duration(minutes: 15);

/// The default grant.
const Duration defaultGrantDuration = platformGrantFloor;

enum PermitTag {
  /// An ordinary permit requested from the Gate.
  standard,

  /// FR-33 — a short VIP check. Shorter than the floor, so it leans on a schedule's
  /// warningTime on iOS (D-005) and a plain timer on Android.
  vipCheck,
}

class Permit {
  const Permit({
    required this.id,
    required this.issued,
    required this.duration,
    required this.reason,
    this.tag = PermitTag.standard,
  });

  final String id;

  /// Both clocks at the moment of issue. Storing the pair is what makes FR-20 possible.
  final ClockStamp issued;

  final Duration duration;

  /// FR-14 — the user's own words, minimum 12 characters, kept with the record.
  final String reason;

  final PermitTag tag;

  /// Nominal end, by wall clock. Correct only while nobody has touched the clock; use
  /// [remaining] for anything the user sees.
  DateTime get nominalEnd => issued.wall.add(duration);

  /// How much time is left, resolved against both clocks.
  ///
  /// Returns [Duration.zero] once spent, and also whenever tampering is detected —
  /// NFR-2 says inconsistency resolves toward more restriction, and an expired permit is
  /// the more restrictive reading.
  PermitStatus status(Clock clock) {
    final resolution = resolveElapsed(since: issued, clock: clock);

    if (resolution.verdict == TamperVerdict.rewound) {
      return PermitStatus(
        remaining: Duration.zero,
        expired: true,
        tamperVerdict: resolution.verdict,
      );
    }

    final left = duration - resolution.elapsed;
    final expired = left <= Duration.zero;
    return PermitStatus(
      remaining: expired ? Duration.zero : left,
      expired: expired,
      tamperVerdict: resolution.verdict,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'issued': issued.toJson(),
        'durationMs': duration.inMilliseconds,
        'reason': reason,
        'tag': tag.name,
      };

  static Permit fromJson(Map<String, Object?> json) => Permit(
        id: json['id']! as String,
        issued: ClockStamp.fromJson(
            (json['issued']! as Map).cast<String, Object?>()),
        duration: Duration(milliseconds: json['durationMs']! as int),
        reason: json['reason']! as String,
        tag: PermitTag.values.byName(json['tag']! as String),
      );
}

class PermitStatus {
  const PermitStatus({
    required this.remaining,
    required this.expired,
    required this.tamperVerdict,
  });

  final Duration remaining;
  final bool expired;
  final TamperVerdict tamperVerdict;

  bool get active => !expired;

  /// FR-19 — the two-minute warning.
  bool get inFinalWarning =>
      active && remaining <= const Duration(minutes: 2);
}
