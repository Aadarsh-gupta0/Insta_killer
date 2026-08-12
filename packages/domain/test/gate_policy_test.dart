import 'package:insta_killer_domain/insta_killer_domain.dart';
import 'package:test/test.dart';

const goodReason = 'checking the group chat about tomorrow';

Event issued(DateTime at) => Event(at: at, kind: EventKind.permitIssued);

void main() {
  // A Wednesday afternoon, well inside a quota day, nothing scheduled.
  final afternoon = DateTime(2026, 8, 12, 14, 0);

  GateDecision decide({
    OfficeRules rules = const OfficeRules(),
    List<Event> events = const [],
    String reason = goodReason,
    Permit? active,
    DateTime? at,
    ClockGuard? guard,
  }) {
    final clock = FakeClock(wall: at ?? afternoon);
    return GatePolicy(rules).evaluate(
      clock: clock,
      events: events,
      reason: reason,
      activePermit: active,
      guard: guard,
      idFactory: () => 'permit-1',
    );
  }

  group('granting', () {
    test('issues a 15-minute permit when everything is in order', () {
      final decision = decide();

      expect(decision, isA<PermitGranted>());
      final permit = (decision as PermitGranted).permit;
      expect(permit.duration, const Duration(minutes: 15));
      expect(permit.reason, goodReason);
      expect(permit.tag, PermitTag.standard);
      expect(permit.id, 'permit-1');
    });

    test('trims the stored reason', () {
      final decision = decide(reason: '   $goodReason   ');
      expect((decision as PermitGranted).permit.reason, goodReason);
    });

    test('never offers below the platform floor by default', () {
      expect(defaultGrantDuration, platformGrantFloor);
      expect(platformGrantFloor, const Duration(minutes: 15));
    });
  });

  group('refusals', () {
    test('refuses once the quota is spent, naming the reset time', () {
      final decision = decide(
        events: List.generate(3, (i) => issued(DateTime(2026, 8, 12, 9 + i))),
      );

      expect(decision, isA<PermitRefused>());
      final refusal = decision as PermitRefused;
      expect(refusal.reason, RefusalReason.quotaExhausted);
      expect(refusal.availableAt, DateTime(2026, 8, 13, 6));
    });

    test('refuses inside a scheduled window even with quota to spare', () {
      final rules = OfficeRules(
        schedule: WeeklySchedule.daily(startHour: 13, endHour: 15),
      );

      final refusal = decide(rules: rules) as PermitRefused;
      expect(refusal.reason, RefusalReason.scheduledWindow);
      expect(refusal.availableAt, DateTime(2026, 8, 12, 15));
    });

    test('a schedule outranks the quota message', () {
      // Both would refuse. FR-23 says the window wins, and the copy must not
      // suggest that waiting for a quota reset would help.
      final rules = OfficeRules(
        schedule: WeeklySchedule.daily(startHour: 13, endHour: 15),
      );
      final refusal = decide(
        rules: rules,
        events: List.generate(3, (i) => issued(DateTime(2026, 8, 12, 9 + i))),
      ) as PermitRefused;

      expect(refusal.reason, RefusalReason.scheduledWindow);
    });

    test('demands a reason of at least 12 characters', () {
      final refusal = decide(reason: 'bored') as PermitRefused;
      expect(refusal.reason, RefusalReason.reasonTooShort);
      expect(refusal.availableAt, isNull,
          reason: 'waiting does not fix a short reason');
    });

    test('whitespace does not pad a reason to length', () {
      final refusal = decide(reason: 'a           ') as PermitRefused;
      expect(refusal.reason, RefusalReason.reasonTooShort);
    });

    test('exactly 12 characters is enough', () {
      expect(decide(reason: '123456789012'), isA<PermitGranted>());
    });

    test('refuses while another permit is running', () {
      final clock = FakeClock(wall: afternoon);
      final active = Permit(
        id: 'existing',
        issued: ClockStamp.now(clock),
        duration: const Duration(minutes: 15),
        reason: goodReason,
      );

      final refusal = decide(active: active) as PermitRefused;
      expect(refusal.reason, RefusalReason.permitAlreadyActive);
    });

    test('an expired permit does not block a new one', () {
      final past = FakeClock(wall: afternoon.subtract(const Duration(hours: 1)));
      final spent = Permit(
        id: 'spent',
        issued: ClockStamp.now(past),
        duration: const Duration(minutes: 15),
        reason: goodReason,
      );

      expect(decide(active: spent), isA<PermitGranted>());
    });

    test('refuses outright when the clock has been rolled back', () {
      final guard = ClockGuard()..observe(afternoon.add(const Duration(days: 2)));

      final refusal = decide(guard: guard) as PermitRefused;
      expect(refusal.reason, RefusalReason.clockTampered);
    });

    test('tampering is checked before anything else', () {
      // Short reason AND a rolled-back clock: the clock is the real problem.
      final guard = ClockGuard()..observe(afternoon.add(const Duration(days: 2)));
      final refusal = decide(guard: guard, reason: 'x') as PermitRefused;
      expect(refusal.reason, RefusalReason.clockTampered);
    });
  });

  group('permit lifetime', () {
    test('counts down and expires exactly on time', () {
      final clock = FakeClock(wall: afternoon);
      final permit = Permit(
        id: 'p',
        issued: ClockStamp.now(clock),
        duration: const Duration(minutes: 15),
        reason: goodReason,
      );

      expect(permit.status(clock).remaining, const Duration(minutes: 15));

      clock.advance(const Duration(minutes: 13));
      final late = permit.status(clock);
      expect(late.remaining, const Duration(minutes: 2));
      expect(late.inFinalWarning, isTrue, reason: 'FR-19 two-minute warning');
      expect(late.active, isTrue);

      clock.advance(const Duration(minutes: 2));
      expect(permit.status(clock).expired, isTrue,
          reason: 'zero remaining is expired, not active');
      expect(permit.status(clock).remaining, Duration.zero);
    });

    test('a rewound clock expires the permit immediately', () {
      final clock = FakeClock(wall: afternoon);
      final permit = Permit(
        id: 'p',
        issued: ClockStamp.now(clock),
        duration: const Duration(minutes: 15),
        reason: goodReason,
      );

      clock.advance(const Duration(minutes: 5));
      clock.setWallClock(afternoon.subtract(const Duration(hours: 2)));

      final status = permit.status(clock);
      expect(status.expired, isTrue);
      expect(status.tamperVerdict, TamperVerdict.rewound);
    });

    test('survives a JSON round trip', () {
      final clock = FakeClock(wall: afternoon);
      final permit = Permit(
        id: 'p',
        issued: ClockStamp.now(clock),
        duration: const Duration(minutes: 15),
        reason: goodReason,
        tag: PermitTag.vipCheck,
      );

      final restored = Permit.fromJson(permit.toJson());
      expect(restored.id, permit.id);
      expect(restored.duration, permit.duration);
      expect(restored.reason, permit.reason);
      expect(restored.tag, PermitTag.vipCheck);
      expect(restored.issued.wall, permit.issued.wall);
    });
  });
}
