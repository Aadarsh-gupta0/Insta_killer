import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

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

/// Everything the office knows, loaded once and mutated through intents.
class OfficeState {
  const OfficeState({
    required this.rules,
    required this.events,
    required this.activePermit,
    required this.declaration,
    required this.clockGuard,
  });

  final OfficeRules rules;
  final List<Event> events;
  final Permit? activePermit;
  final String? declaration;
  final ClockGuard clockGuard;

  OfficeState copyWith({
    OfficeRules? rules,
    List<Event>? events,
    Permit? activePermit,
    bool clearActivePermit = false,
    String? declaration,
  }) =>
      OfficeState(
        rules: rules ?? this.rules,
        events: events ?? this.events,
        activePermit:
            clearActivePermit ? null : (activePermit ?? this.activePermit),
        declaration: declaration ?? this.declaration,
        clockGuard: clockGuard,
      );
}

class OfficeNotifier extends AsyncNotifier<OfficeState> {
  OfficeRepository get _repo => ref.read(repositoryProvider);

  Clock get _clock => ref.read(clockProvider);

  @override
  Future<OfficeState> build() async {
    final rules = await _repo.loadRules();
    final events = await _repo.loadEvents();
    final permit = await _repo.loadActivePermit();
    final mark = await _repo.loadClockHighWaterMark();
    final declaration = await _repo.loadDeclaration();

    return OfficeState(
      rules: rules,
      events: events,
      activePermit: permit,
      declaration: declaration,
      clockGuard: ClockGuard(highWaterMark: mark),
    );
  }

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
    final current = await future;
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
