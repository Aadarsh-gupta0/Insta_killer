/// The one question both platforms ask: may a permit be issued right now?
///
/// Everything else in this package feeds this. Keeping the answer in one pure function
/// is what stops iOS and Android drifting apart (D-007) and what lets the rules be tested
/// without a device (NFR-5).
library;

import 'clock.dart';
import 'event.dart';
import 'permit.dart';
import 'quota.dart';
import 'schedule.dart';

/// FR-14 — a typed reason of at least this many characters.
const int minimumReasonLength = 12;

/// Everything the decision depends on, in one object.
class OfficeRules {
  const OfficeRules({
    this.quota = QuotaPolicy.standard,
    this.schedule = const WeeklySchedule.empty(),
    this.strictMode = true,
    this.grantDuration = defaultGrantDuration,
    this.blockedAppCount = 0,
    this.enforcementEnabled = false,
  });

  final QuotaPolicy quota;
  final WeeklySchedule schedule;
  final bool strictMode;
  final Duration grantDuration;

  /// The master switch.
  ///
  /// A rule, not a preference, which is why it lives here rather than only in the
  /// platform layer: switching enforcement *off* is the largest loosening available, and
  /// it has to go through the same cooldown as everything else (FR-25). Otherwise Strict
  /// Mode has a hole straight through it labelled "off".
  ///
  /// Defaults to false so installing the app changes nothing until onboarding says so.
  final bool enforcementEnabled;

  /// Only the count — the tokens themselves are opaque and live on the platform side
  /// (C-3). It is here because removing an app is a loosening change (FR-25) and the
  /// cooldown classifier needs something to compare.
  final int blockedAppCount;

  OfficeRules copyWith({
    QuotaPolicy? quota,
    WeeklySchedule? schedule,
    bool? strictMode,
    Duration? grantDuration,
    int? blockedAppCount,
    bool? enforcementEnabled,
  }) =>
      OfficeRules(
        quota: quota ?? this.quota,
        schedule: schedule ?? this.schedule,
        strictMode: strictMode ?? this.strictMode,
        grantDuration: grantDuration ?? this.grantDuration,
        blockedAppCount: blockedAppCount ?? this.blockedAppCount,
        enforcementEnabled: enforcementEnabled ?? this.enforcementEnabled,
      );

  Map<String, Object?> toJson() => {
        'quota': quota.toJson(),
        'schedule': schedule.toJson(),
        'strictMode': strictMode,
        'grantDurationMs': grantDuration.inMilliseconds,
        'blockedAppCount': blockedAppCount,
        'enforcementEnabled': enforcementEnabled,
      };

  /// Missing keys fall back to the stricter default rather than throwing.
  ///
  /// This is read at every cold start, including the first one after an update that
  /// added a field. Failing to parse would leave the app with no rules at all, and "no
  /// rules" resolves to "nothing is blocked" — the opposite of what NFR-2 requires when
  /// state is inconsistent.
  static OfficeRules fromJson(Map<String, Object?> json) => OfficeRules(
        quota: json['quota'] == null
            ? QuotaPolicy.standard
            : QuotaPolicy.fromJson((json['quota']! as Map).cast<String, Object?>()),
        schedule: json['schedule'] == null
            ? const WeeklySchedule.empty()
            : WeeklySchedule.fromJson(json['schedule']! as List<Object?>),
        strictMode: json['strictMode'] as bool? ?? true,
        grantDuration: json['grantDurationMs'] == null
            ? defaultGrantDuration
            : Duration(milliseconds: json['grantDurationMs']! as int),
        blockedAppCount: json['blockedAppCount'] as int? ?? 0,
        enforcementEnabled: json['enforcementEnabled'] as bool? ?? false,
      );
}

enum RefusalReason {
  quotaExhausted,
  scheduledWindow,
  reasonTooShort,
  permitAlreadyActive,
  clockTampered,
}

/// The answer, with everything the UI needs to explain itself.
///
/// NFR-4 requires every refusal to state the reason and the next possible time, so a
/// refusal carries [availableAt] rather than making the caller work it out.
sealed class GateDecision {
  const GateDecision();
}

class PermitGranted extends GateDecision {
  const PermitGranted(this.permit);

  final Permit permit;
}

class PermitRefused extends GateDecision {
  const PermitRefused({
    required this.reason,
    this.availableAt,
    this.detail,
  });

  final RefusalReason reason;

  /// When this refusal stops applying. Null means "not from waiting" — a reason that is
  /// too short is fixed by typing more, not by time.
  final DateTime? availableAt;

  final String? detail;
}

class GatePolicy {
  const GatePolicy(this.rules);

  final OfficeRules rules;

  /// Order matters. The checks run cheapest-and-most-absolute first so that the refusal
  /// the user sees is the most fundamental one — being told "your reason is too short"
  /// and then, after fixing it, "and also the quota is gone" is worse than one honest no.
  GateDecision evaluate({
    required Clock clock,
    required Iterable<Event> events,
    required String reason,
    Permit? activePermit,
    PermitTag tag = PermitTag.standard,
    String Function()? idFactory,
    ClockGuard? guard,
  }) {
    final now = clock.wall();

    if (guard != null && guard.observe(now)) {
      return const PermitRefused(
        reason: RefusalReason.clockTampered,
        detail: 'The device clock moved backwards.',
      );
    }

    if (activePermit != null && activePermit.status(clock).active) {
      final status = activePermit.status(clock);
      return PermitRefused(
        reason: RefusalReason.permitAlreadyActive,
        availableAt: now.add(status.remaining),
        detail: 'A permit is already running.',
      );
    }

    // FR-23: a scheduled window beats the quota. Having permits left is irrelevant
    // inside one, and the copy must not imply otherwise.
    if (rules.schedule.isBlockedAt(now)) {
      return PermitRefused(
        reason: RefusalReason.scheduledWindow,
        availableAt: rules.schedule.blockedUntil(now),
        detail: 'A scheduled block is in force.',
      );
    }

    final quotaState = rules.quota.stateAt(now, events);
    if (quotaState.exhausted) {
      return PermitRefused(
        reason: RefusalReason.quotaExhausted,
        availableAt: quotaState.resetsAt,
        detail: 'Pad empty.',
      );
    }

    if (reason.trim().length < minimumReasonLength) {
      return const PermitRefused(
        reason: RefusalReason.reasonTooShort,
        detail: 'State a reason of at least '
            '$minimumReasonLength characters.',
      );
    }

    return PermitGranted(
      Permit(
        id: (idFactory ?? _defaultId)(),
        issued: ClockStamp.now(clock),
        duration: rules.grantDuration,
        reason: reason.trim(),
        tag: tag,
      ),
    );
  }

  static int _counter = 0;

  static String _defaultId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
}
