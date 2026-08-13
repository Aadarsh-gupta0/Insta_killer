/// The rules of Insta_killer.
///
/// Pure Dart on purpose. Nothing in here may import Flutter or any platform channel —
/// NFR-6 requires this layer to be shared unchanged between iOS and Android, and D-007
/// made that a near-term need rather than a someday one.
library;

export 'src/clock.dart';
export 'src/event.dart';
export 'src/gate_policy.dart';
export 'src/guardian.dart';
export 'src/insights.dart';
export 'src/permit.dart';
export 'src/quota.dart';
export 'src/quota_day.dart';
export 'src/schedule.dart';
export 'src/streak.dart';
export 'src/strictness.dart';
