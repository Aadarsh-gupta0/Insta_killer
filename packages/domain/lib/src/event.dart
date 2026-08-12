/// The append-only record (FR-29).
///
/// Everything the app knows about behaviour is derived from this list. Nothing is
/// aggregated at write time, because an aggregate computed by an extension under memory
/// pressure is an aggregate we cannot audit. Insights are recomputed from events.
library;

enum EventKind {
  /// FR-7 — a launch attempt hit the shield or the gate.
  attemptBlocked,

  /// A permit was issued.
  permitIssued,

  /// A permit ran its full length.
  permitExpired,

  /// FR-21 — the user handed back remaining time.
  permitSurrendered,

  /// A permit was refused, with [Event.detail] naming the reason.
  permitRefused,

  /// A setting changed, or a loosening was queued/applied/cancelled.
  settingChanged,

  /// FR-20 — the clock moved in a way we had to resolve.
  clockAnomaly,
}

class Event {
  const Event({
    required this.at,
    required this.kind,
    this.permitId,
    this.detail,
    this.reason,
  });

  final DateTime at;
  final EventKind kind;

  /// Links issue/expiry/surrender records for one permit.
  final String? permitId;

  /// Machine-readable qualifier — a refusal reason, the setting that changed.
  final String? detail;

  /// FR-14 — the user's own typed justification, stored verbatim with the permit.
  final String? reason;

  Map<String, Object?> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'kind': kind.name,
        if (permitId != null) 'permitId': permitId,
        if (detail != null) 'detail': detail,
        if (reason != null) 'reason': reason,
      };

  static Event fromJson(Map<String, Object?> json) => Event(
        at: DateTime.parse(json['at']! as String).toLocal(),
        kind: EventKind.values.byName(json['kind']! as String),
        permitId: json['permitId'] as String?,
        detail: json['detail'] as String?,
        reason: json['reason'] as String?,
      );

  @override
  String toString() => 'Event(${kind.name} at $at${detail == null ? '' : ' $detail'})';
}
