import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insta_killer/app/providers.dart';
import 'package:insta_killer/data/office_repository.dart';
import 'package:insta_killer/design/office_button.dart';
import 'package:insta_killer/design/tokens.dart';
import 'package:insta_killer/features/home/front_desk_screen.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

void main() {
  final afternoon = DateTime(2026, 8, 12, 14);

  late InMemoryOfficeRepository repo;
  late FakeClock clock;

  Event issued(DateTime at) => Event(at: at, kind: EventKind.permitIssued);

  Event attempt(DateTime at) => Event(at: at, kind: EventKind.attemptBlocked);

  Future<void> pumpDesk(
    WidgetTester tester, {
    List<Event> events = const [],
    Permit? activePermit,
    OfficeRules rules = const OfficeRules(),
  }) async {
    repo = InMemoryOfficeRepository(
      rules: rules,
      events: events,
      activePermit: activePermit,
    );
    clock = FakeClock(wall: afternoon);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(clock),
        ],
        child: WidgetsApp(
          color: Palette.ledger,
          builder: (context, _) => DefaultTextStyle(
            style: TextStyles.bodyText,
            child: const FrontDeskScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('at a glance', () {
    testWidgets('shows the remaining quota and the next issue time',
        (tester) async {
      await pumpDesk(tester, events: [issued(DateTime(2026, 8, 12, 9))]);

      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('06:00'), findsOneWidget, reason: 'the day boundary');
    });

    testWidgets('counts only today\'s attempts', (tester) async {
      await pumpDesk(tester, events: [
        attempt(DateTime(2026, 8, 12, 9)),
        attempt(DateTime(2026, 8, 12, 11)),
        attempt(DateTime(2026, 8, 12, 5)), // before the boundary — yesterday
        attempt(DateTime(2026, 8, 10, 12)),
      ]);

      expect(find.text('2'), findsOneWidget);
      expect(find.text('02'), findsOneWidget, reason: 'the headline numeral');
      expect(find.text('attempts turned away today'), findsOneWidget);
    });

    testWidgets('says "attempt" in the singular for one', (tester) async {
      await pumpDesk(tester, events: [attempt(DateTime(2026, 8, 12, 9))]);
      expect(find.text('attempt turned away today'), findsOneWidget);
    });

    testWidgets('an exhausted pad has no Return early action', (tester) async {
      await pumpDesk(tester, events: [
        for (var i = 0; i < 3; i++) issued(DateTime(2026, 8, 12, 9 + i)),
      ]);

      expect(find.text('0 of 3'), findsOneWidget);
      expect(find.widgetWithText(OfficeButton, 'RETURN EARLY'), findsNothing);
    });
  });

  group('an active permit', () {
    Permit runningPermit(FakeClock at, {Duration age = Duration.zero}) {
      final issuedAt = FakeClock(wall: at.wall().subtract(age), monotonic: -age);
      return Permit(
        id: 'p-1',
        issued: ClockStamp.now(issuedAt),
        duration: const Duration(minutes: 15),
        reason: 'checking the group chat',
      );
    }

    testWidgets('shows a mono countdown instead of the attempt count',
        (tester) async {
      clock = FakeClock(wall: afternoon);
      await pumpDesk(tester, activePermit: runningPermit(clock));

      expect(find.text('PERMIT ISSUED'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('NO PERMIT IN FORCE'), findsNothing);
    });

    testWidgets('counts down as time passes', (tester) async {
      clock = FakeClock(wall: afternoon);
      await pumpDesk(
        tester,
        activePermit: runningPermit(clock, age: const Duration(minutes: 3)),
      );

      expect(find.text('12:00'), findsOneWidget);
    });

    testWidgets('FR-21 — returning early forfeits the rest', (tester) async {
      clock = FakeClock(wall: afternoon);
      await pumpDesk(tester, activePermit: runningPermit(clock));

      expect(find.widgetWithText(OfficeButton, 'RETURN EARLY'), findsOneWidget);
      await tester.tap(find.widgetWithText(OfficeButton, 'RETURN EARLY'));
      await tester.pump();
      await tester.pump();

      expect(await repo.loadActivePermit(), isNull);
      final events = await repo.loadEvents();
      expect(
        events.where((e) => e.kind == EventKind.permitSurrendered),
        hasLength(1),
      );
      expect(find.text('NO PERMIT IN FORCE'), findsOneWidget);
    });

    testWidgets('an expired permit is not shown as running', (tester) async {
      clock = FakeClock(wall: afternoon);
      await pumpDesk(
        tester,
        activePermit: runningPermit(clock, age: const Duration(minutes: 20)),
      );

      expect(find.text('PERMIT ISSUED'), findsNothing);
      expect(find.text('NO PERMIT IN FORCE'), findsOneWidget);
    });
  });

  group('streak', () {
    testWidgets('renders one stamp per clean day', (tester) async {
      await pumpDesk(tester, events: [
        attempt(DateTime(2026, 8, 10, 9)),
        attempt(DateTime(2026, 8, 12, 9)),
      ]);

      // Aug 10, 11 and 12: no permits issued, so three clean days.
      expect(find.text('3 days'), findsOneWidget);
    });

    testWidgets('says so plainly when today is not clean', (tester) async {
      await pumpDesk(tester, events: [
        for (var i = 0; i < 3; i++) issued(DateTime(2026, 8, 12, 9 + i)),
      ]);

      expect(find.text('None today'), findsOneWidget);
    });
  });

  testWidgets('survives XXL Dynamic Type without overflowing', (tester) async {
    repo = InMemoryOfficeRepository(
      events: [attempt(DateTime(2026, 8, 12, 9))],
    );
    clock = FakeClock(wall: afternoon);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(clock),
        ],
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: WidgetsApp(
            color: Palette.ledger,
            builder: (context, _) => DefaultTextStyle(
              style: TextStyles.bodyText,
              child: const FrontDeskScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
