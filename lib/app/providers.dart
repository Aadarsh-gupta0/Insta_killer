import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

import '../data/guardian_codes.dart';
import '../data/office_repository.dart';
import '../platform/office_api.g.dart';

/// Overridden in tests and at startup. Never read a clock directly in a widget — FR-20
/// only works if every reading comes from one place.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

final repositoryProvider = Provider<OfficeRepository>(
  (ref) => throw UnimplementedError(
    'Override repositoryProvider at the root of the app or in a test.',
  ),
);

/// The platform bridge, for the few things Dart cannot do itself — opening a Settings
/// screen, leaving to the launcher. State goes through [repositoryProvider] instead.
final hostApiProvider = Provider<OfficeHostApi>(
  (ref) => throw UnimplementedError(
    'Override hostApiProvider at the root of the app or in a test.',
  ),
);

/// Which screen the app is showing.
///
/// Set at launch from the intent, and again by the platform when Instagram is opened
/// against an already-warm engine. It lives here rather than in `main.dart` so the
/// provider layer does not have to import the app entry point back.
enum Entry { frontDesk, gate }

final entryProvider = StateProvider<Entry>((ref) => Entry.frontDesk);

/// Which app triggered the Gate, resolved to a label and icon by the platform.
///
/// Null when the app was opened from its own icon, or when the platform could not name
/// the package — uninstalled since, most likely. The Gate degrades to a generic heading
/// rather than showing a blank row.
final blockedAppProvider = StateProvider<InstalledApp?>((ref) => null);

/// Everything the office knows, loaded once and mutated through intents.
class OfficeState {
  const OfficeState({
    required this.rules,
    required this.events,
    required this.activePermit,
    required this.declaration,
    required this.clockGuard,
    required this.pendingChange,
    required this.guardian,
    required this.approvalRequest,
    required this.approvalGranted,
  });

  final OfficeRules rules;
  final List<Event> events;
  final Permit? activePermit;
  final String? declaration;
  final ClockGuard clockGuard;

  /// FR-25 — a loosening waiting out its 24 hours, if any.
  final PendingChange? pendingChange;

  /// FR-27 — the paired Guardian, if there is one.
  final GuardianPairing? guardian;

  final ApprovalRequest? approvalRequest;
  final bool approvalGranted;

  bool get guardianPaired => guardian != null;

  OfficeState copyWith({
    OfficeRules? rules,
    List<Event>? events,
    Permit? activePermit,
    bool clearActivePermit = false,
    String? declaration,
    PendingChange? pendingChange,
    bool clearPendingChange = false,
    GuardianPairing? guardian,
    bool clearGuardian = false,
    ApprovalRequest? approvalRequest,
    bool clearApprovalRequest = false,
    bool? approvalGranted,
  }) =>
      OfficeState(
        rules: rules ?? this.rules,
        events: events ?? this.events,
        activePermit:
            clearActivePermit ? null : (activePermit ?? this.activePermit),
        declaration: declaration ?? this.declaration,
        clockGuard: clockGuard,
        pendingChange:
            clearPendingChange ? null : (pendingChange ?? this.pendingChange),
        guardian: clearGuardian ? null : (guardian ?? this.guardian),
        approvalRequest: clearApprovalRequest
            ? null
            : (approvalRequest ?? this.approvalRequest),
        approvalGranted: approvalGranted ?? this.approvalGranted,
      );
}

class OfficeNotifier extends AsyncNotifier<OfficeState> {
  OfficeRepository get _repo => ref.read(repositoryProvider);

  Clock get _clock => ref.read(clockProvider);

  static const _strictness = StrictnessPolicy();
  static const _guardians = GuardianPolicy();

  @override
  Future<OfficeState> build() async {
    var rules = await _repo.loadRules();
    final events = await _repo.loadEvents();
    final permit = await _repo.loadActivePermit();
    final mark = await _repo.loadClockHighWaterMark();
    final declaration = await _repo.loadDeclaration();
    var pending = await _repo.loadPendingChange();
    final guardian = await _repo.loadGuardianPairing();
    var approvalRequest = await _repo.loadApprovalRequest();
    var approvalGranted = await _repo.loadApprovalGranted();

    // A cooldown that only elapses while the app is open would be no cooldown at all, so
    // a change that came due while we were closed is applied here, on the next start.
    if (pending != null &&
        _guardians.canApply(
          change: pending,
          now: _clock.wall(),
          paired: guardian != null,
          approved: approvalGranted,
        )) {
      rules = pending.resulting;
      await _repo.saveRules(rules);
      await _repo.savePendingChange(null);
      await _repo.saveApprovalRequest(null);
      await _repo.saveApprovalGranted(false);
      pending = null;
      approvalRequest = null;
      approvalGranted = false;
    }

    return OfficeState(
      rules: rules,
      events: events,
      activePermit: permit,
      declaration: declaration,
      clockGuard: ClockGuard(highWaterMark: mark),
      pendingChange: pending,
      guardian: guardian,
      approvalRequest: approvalRequest,
      approvalGranted: approvalGranted,
    );
  }

  /// FR-25 — the asymmetry. Tightening lands now; loosening waits 24 hours.
  ///
  /// Returns what happened so the screen can say so rather than guess.
  Future<ChangeOutcome> requestRulesChange(
    OfficeRules to, {
    required String description,
  }) async {
    final current = await future;

    final outcome = _strictness.request(
      from: current.rules,
      to: to,
      now: _clock.wall(),
      description: description,
    );

    final event = Event(
      at: _clock.wall(),
      kind: EventKind.settingChanged,
      detail: switch (outcome) {
        ChangeApplied() => 'applied: $description',
        ChangeQueued() => 'queued: $description',
      },
    );
    await _repo.append(event);

    switch (outcome) {
      case ChangeApplied(:final rules):
        await _repo.saveRules(rules);

        // A queued change carries a full snapshot of the rules as they were when it was
        // requested, so anything applied since would be silently reverted the moment it
        // lands — tighten the quota today and a week-old queued loosening undoes it
        // along with everything else it captured. Discarding the queued one is the
        // strict resolution: what gets dropped is always a loosening.
        final hadPending = current.pendingChange != null;
        if (hadPending) {
          await _repo.savePendingChange(null);
          await _repo.saveApprovalRequest(null);
          await _repo.saveApprovalGranted(false);
        }

        state = AsyncData(current.copyWith(
          rules: rules,
          events: [...current.events, event],
          clearPendingChange: hadPending,
          clearApprovalRequest: hadPending,
          approvalGranted: false,
        ));

      case ChangeQueued(:final pending):
        // One at a time. Replacing rather than queueing behind the existing one, so the
        // countdown on screen always refers to the change the user just asked for.
        //
        // Any approval already given is discarded with the old request. A Guardian who
        // agreed to "quota to 4" has not agreed to whatever replaced it.
        await _repo.savePendingChange(pending);
        await _repo.saveApprovalRequest(null);
        await _repo.saveApprovalGranted(false);
        state = AsyncData(current.copyWith(
          pendingChange: pending,
          events: [...current.events, event],
          clearApprovalRequest: true,
          approvalGranted: false,
        ));
    }

    return outcome;
  }

  /// FR-26 — cancellable right up to the moment it lands.
  Future<void> cancelPendingChange() async {
    final current = await future;
    final pending = current.pendingChange;
    if (pending == null) return;
    if (!_strictness.canCancel(pending, _clock.wall())) return;

    final event = Event(
      at: _clock.wall(),
      kind: EventKind.settingChanged,
      detail: 'cancelled: ${pending.description}',
    );
    await _repo.append(event);
    await _repo.savePendingChange(null);
    await _repo.saveApprovalRequest(null);
    await _repo.saveApprovalGranted(false);
    state = AsyncData(current.copyWith(
      events: [...current.events, event],
      clearPendingChange: true,
      clearApprovalRequest: true,
      approvalGranted: false,
    ));
  }

  // --- FR-27, the Guardian ------------------------------------------------------

  /// Pairs a Guardian. A tightening, so it lands immediately.
  Future<void> pairGuardian({
    required String name,
    required String secret,
  }) async {
    final current = await future;

    await _repo.saveGuardianSecret(normaliseSecret(secret));
    await _repo.saveGuardianPairing(
      GuardianPairing(name: name.trim(), pairedAt: _clock.wall()),
    );

    final outcome = _strictness.request(
      from: current.rules,
      to: current.rules.copyWith(guardianPaired: true),
      now: _clock.wall(),
      description: 'guardian paired',
    );
    // Pairing classifies as a tightening, so this is always ChangeApplied. Going through
    // the policy anyway keeps one path for every rules change rather than a special case
    // that could drift.
    if (outcome case ChangeApplied(:final rules)) {
      await _repo.saveRules(rules);
      state = AsyncData(current.copyWith(
        rules: rules,
        guardian: GuardianPairing(name: name.trim(), pairedAt: _clock.wall()),
      ));
    }
  }

  /// Raises the challenge for the queued change. Idempotent — asking twice does not
  /// invalidate a code the Guardian is already working on.
  Future<ApprovalRequest?> requestApproval() async {
    final current = await future;
    final pending = current.pendingChange;
    if (pending == null || !current.guardianPaired) return null;

    final existing = current.approvalRequest;
    if (existing != null &&
        existing.changeId == pending.id &&
        !existing.isExpired(_clock.wall())) {
      return existing;
    }

    final request = _guardians.challengeFor(
      change: pending,
      now: _clock.wall(),
      digits: generateChallenge,
    );
    await _repo.saveApprovalRequest(request);
    state = AsyncData(current.copyWith(approvalRequest: request));
    return request;
  }

  /// Checks what the Guardian read back.
  Future<ApprovalVerdict> submitApproval(String response) async {
    final current = await future;
    final pending = current.pendingChange;
    final request = current.approvalRequest;
    final secret = await _repo.loadGuardianSecret();

    if (pending == null || request == null || secret == null) {
      return ApprovalVerdict.staleRequest;
    }

    final verdict = _guardians.verify(
      request: request,
      change: pending,
      response: response,
      now: _clock.wall(),
      signer: HmacCodeSigner(secret),
    );

    if (verdict != ApprovalVerdict.accepted) return verdict;

    final event = Event(
      at: _clock.wall(),
      kind: EventKind.settingChanged,
      detail: 'guardian approved: ${pending.description}',
    );
    await _repo.append(event);
    await _repo.saveApprovalGranted(true);
    state = AsyncData(current.copyWith(
      approvalGranted: true,
      events: [...current.events, event],
    ));

    // The change may already be past its cooldown and waiting only on this.
    await reconcile();
    return verdict;
  }

  /// What the Guardian's own phone computes. Used only in Guardian mode.
  String? answerChallenge(String challenge, String secret) =>
      challenge.trim().length == 6
          ? HmacCodeSigner(normaliseSecret(secret)).sign(challenge)
          : null;

  /// FR-7 — every launch attempt is recorded, whether or not it becomes a permit.
  ///
  /// Awaits [future] rather than reading [state] directly. The Gate calls this from its
  /// first post-frame callback, which on a cold launch fires while this notifier is
  /// still loading — reading `state.valueOrNull` there returns null and the attempt is
  /// silently dropped. Blocked attempts per day is the number the whole product is
  /// measured on, so dropping them quietly is the worst available failure.
  Future<void> recordAttempt() async {
    final current = await future;

    final event = Event(at: _clock.wall(), kind: EventKind.attemptBlocked);
    await _repo.append(event);
    state = AsyncData(current.copyWith(events: [...current.events, event]));
  }

  /// The whole product, in one method.
  Future<GateDecision> requestPermit(String reason,
      {PermitTag tag = PermitTag.standard}) async {
    final current = await future;

    final decision = GatePolicy(current.rules).evaluate(
      clock: _clock,
      events: current.events,
      reason: reason,
      activePermit: current.activePermit,
      tag: tag,
      guard: current.clockGuard,
    );

    await _repo.saveClockHighWaterMark(
        current.clockGuard.highWaterMark ?? _clock.wall());

    switch (decision) {
      case PermitGranted(:final permit):
        final event = Event(
          at: _clock.wall(),
          kind: EventKind.permitIssued,
          permitId: permit.id,
          reason: permit.reason,
        );
        await _repo.append(event);
        await _repo.setActivePermit(permit);
        state = AsyncData(current.copyWith(
          events: [...current.events, event],
          activePermit: permit,
        ));

      case PermitRefused(:final reason):
        final event = Event(
          at: _clock.wall(),
          kind: EventKind.permitRefused,
          detail: reason.name,
        );
        await _repo.append(event);
        state = AsyncData(current.copyWith(events: [...current.events, event]));
    }

    return decision;
  }

  /// FR-21 — remaining time is forfeited, not banked.
  Future<void> surrenderPermit() async {
    final current = await future;
    final permit = current.activePermit;
    if (permit == null) return;

    final event = Event(
      at: _clock.wall(),
      kind: EventKind.permitSurrendered,
      permitId: permit.id,
    );
    await _repo.append(event);
    await _repo.setActivePermit(null);
    state = AsyncData(current.copyWith(
      events: [...current.events, event],
      clearActivePermit: true,
    ));
  }

  /// Called on resume. NFR-2: any inconsistency resolves toward more restriction, so a
  /// permit that expired while we were backgrounded is cleared here rather than lingering.
  Future<void> reconcile() async {
    var current = await future;

    // The cooldown runs on wall time, not on how long the app was open — and with a
    // Guardian paired it also needs their agreement (FR-27).
    final pending = current.pendingChange;
    if (pending != null &&
        _guardians.canApply(
          change: pending,
          now: _clock.wall(),
          paired: current.guardianPaired,
          approved: current.approvalGranted,
        )) {
      await _repo.saveRules(pending.resulting);
      await _repo.savePendingChange(null);
      await _repo.saveApprovalRequest(null);
      await _repo.saveApprovalGranted(false);
      current = current.copyWith(
        rules: pending.resulting,
        clearPendingChange: true,
        clearApprovalRequest: true,
        approvalGranted: false,
      );
      state = AsyncData(current);
    }

    final permit = current.activePermit;
    if (permit == null) return;

    final status = permit.status(_clock);
    if (!status.expired) return;

    final event = Event(
      at: _clock.wall(),
      kind: status.tamperVerdict == TamperVerdict.rewound
          ? EventKind.clockAnomaly
          : EventKind.permitExpired,
      permitId: permit.id,
    );
    await _repo.append(event);
    await _repo.setActivePermit(null);
    state = AsyncData(current.copyWith(
      events: [...current.events, event],
      clearActivePermit: true,
    ));
  }
}

final officeProvider =
    AsyncNotifierProvider<OfficeNotifier, OfficeState>(OfficeNotifier.new);

/// Derived, so the Front Desk never recomputes quota maths in a build method.
final quotaStateProvider = Provider<QuotaState?>((ref) {
  final office = ref.watch(officeProvider).valueOrNull;
  if (office == null) return null;
  return office.rules.quota
      .stateAt(ref.watch(clockProvider).wall(), office.events);
});

final streakProvider = Provider<StreakSummary?>((ref) {
  final office = ref.watch(officeProvider).valueOrNull;
  if (office == null) return null;
  return computeStreaks(
    events: office.events,
    quota: office.rules.quota,
    upTo: ref.watch(clockProvider).wall(),
  );
});

final insightsProvider = Provider<Insights?>((ref) {
  final office = ref.watch(officeProvider).valueOrNull;
  if (office == null) return null;
  return computeInsights(events: office.events, quota: office.rules.quota);
});
