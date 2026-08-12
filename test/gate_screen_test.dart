import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insta_killer/app/providers.dart';
import 'package:insta_killer/data/office_repository.dart';
import 'package:insta_killer/design/office_button.dart';
import 'package:insta_killer/design/tokens.dart';
import 'package:insta_killer/features/gate/gate_screen.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

const validReason = 'checking the group chat about tomorrow';

void main() {
  final afternoon = DateTime(2026, 8, 12, 14);

  late InMemoryOfficeRepository repo;
  late FakeClock clock;

  Future<void> pumpGate(
    WidgetTester tester, {
    OfficeRules rules = const OfficeRules(),
    List<Event> events = const [],
    String? declaration,
    VoidCallback? onLeave,
  }) async {
    repo = InMemoryOfficeRepository(
      rules: rules,
      events: events,
      declaration: declaration,
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
            child: GateScreen(onLeave: onLeave),
          ),
        ),
      ),
    );
    // Let the AsyncNotifier resolve and the first frame settle.
    await tester.pump();
    await tester.pump();
  }

  OfficeButton button(WidgetTester tester, String label) =>
      tester.widget<OfficeButton>(find.widgetWithText(OfficeButton, label));

  group('FR-13 — the pause is not skippable', () {
    testWidgets('both actions are disabled before four seconds', (tester) async {
      await pumpGate(tester);

      expect(button(tester, 'LEAVE').enabled, isFalse);
      expect(button(tester, 'REQUEST A PERMIT').enabled, isFalse);

      // Still locked at 3.9s. If this ever passes early, the interrupt is gone.
      await tester.pump(const Duration(milliseconds: 3900));
      expect(button(tester, 'LEAVE').enabled, isFalse);
    });

    testWidgets('Leave unlocks once the pause elapses', (tester) async {
      var left = false;
      await pumpGate(tester, onLeave: () => left = true);

      await tester.pump(const Duration(seconds: 4));
      expect(button(tester, 'LEAVE').enabled, isTrue);

      await tester.tap(find.widgetWithText(OfficeButton, 'LEAVE'));
      await tester.pump();
      expect(left, isTrue);
    });

    testWidgets('the reason field only appears after the pause', (tester) async {
      await pumpGate(tester);
      expect(find.text('STATE YOUR REASON'), findsNothing);

      await tester.pump(const Duration(seconds: 4));
      expect(find.text('STATE YOUR REASON'), findsOneWidget);
    });
  });

  group('FR-14 — a typed reason of at least 12 characters', () {
    testWidgets('the request stays disabled until the reason is long enough',
        (tester) async {
      await pumpGate(tester);
      await tester.pump(const Duration(seconds: 4));

      expect(button(tester, 'REQUEST A PERMIT').enabled, isFalse);

      await tester.enterText(find.byType(EditableText), 'bored');
      await tester.pump();
      expect(button(tester, 'REQUEST A PERMIT').enabled, isFalse);

      await tester.enterText(find.byType(EditableText), validReason);
      await tester.pump();
      expect(button(tester, 'REQUEST A PERMIT').enabled, isTrue);
    });

    testWidgets('whitespace does not count toward the minimum', (tester) async {
      await pumpGate(tester);
      await tester.pump(const Duration(seconds: 4));

      await tester.enterText(find.byType(EditableText), 'ok          ');
      await tester.pump();
      expect(button(tester, 'REQUEST A PERMIT').enabled, isFalse);
    });
  });

  group('FR-7 — the attempt is recorded', () {
    testWidgets('opening the Gate logs a blocked attempt', (tester) async {
      await pumpGate(tester);

      final events = await repo.loadEvents();
      expect(events, hasLength(1));
      expect(events.single.kind, EventKind.attemptBlocked);
    });

    testWidgets('the attempt is logged even if the user just leaves',
        (tester) async {
      await pumpGate(tester, onLeave: () {});
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.widgetWithText(OfficeButton, 'LEAVE'));
      await tester.pump();

      final events = await repo.loadEvents();
      expect(events.where((e) => e.kind == EventKind.attemptBlocked), hasLength(1));
    });
  });

  group('granting and refusing', () {
    testWidgets('a valid request issues a permit and records it', (tester) async {
      await pumpGate(tester);
      await tester.pump(const Duration(seconds: 4));
      await tester.enterText(find.byType(EditableText), validReason);
      await tester.pump();

      await tester.tap(find.widgetWithText(OfficeButton, 'REQUEST A PERMIT'));
      await tester.pump();
      await tester.pump();

      final permit = await repo.loadActivePermit();
      expect(permit, isNotNull);
      expect(permit!.duration, const Duration(minutes: 15));
      expect(permit.reason, validReason);

      final events = await repo.loadEvents();
      expect(events.where((e) => e.kind == EventKind.permitIssued), hasLength(1));
    });

    testWidgets('an exhausted quota refuses and names the next issue time',
        (tester) async {
      await pumpGate(
        tester,
        events: [
          for (var i = 0; i < 3; i++)
            Event(at: DateTime(2026, 8, 12, 9 + i), kind: EventKind.permitIssued),
        ],
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.enterText(find.byType(EditableText), validReason);
      await tester.pump();

      await tester.tap(find.widgetWithText(OfficeButton, 'REQUEST A PERMIT'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Pad empty'), findsOneWidget);
      // The day boundary is 06:00, so the next issue is tomorrow morning.
      expect(find.text('Next issue 06:00.'), findsOneWidget);
      expect(await repo.loadActivePermit(), isNull);
    });

    testWidgets('a scheduled window refuses even with quota left', (tester) async {
      await pumpGate(
        tester,
        rules: OfficeRules(
          schedule: WeeklySchedule.daily(startHour: 13, endHour: 15),
        ),
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.enterText(find.byType(EditableText), validReason);
      await tester.pump();

      await tester.tap(find.widgetWithText(OfficeButton, 'REQUEST A PERMIT'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Closed hours'), findsOneWidget);
      expect(find.text('Next issue 15:00.'), findsOneWidget);
    });
  });

  group('FR-24 — the declaration', () {
    testWidgets('is shown back to the user', (tester) async {
      await pumpGate(tester, declaration: 'I want my evenings back.');
      expect(find.text('I want my evenings back.'), findsOneWidget);
      expect(find.text('YOU WROTE'), findsOneWidget);
    });

    testWidgets('the heading is hidden when nothing was declared', (tester) async {
      await pumpGate(tester);
      expect(find.text('YOU WROTE'), findsNothing);
    });

    testWidgets('blank declarations do not leave an empty heading',
        (tester) async {
      await pumpGate(tester, declaration: '   ');
      expect(find.text('YOU WROTE'), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('survives the largest Dynamic Type setting without overflow',
        (tester) async {
      repo = InMemoryOfficeRepository(declaration: 'I want my evenings back.');
      clock = FakeClock(wall: afternoon);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            clockProvider.overrideWithValue(clock),
          ],
          child: MediaQuery(
            // §3.7 asks for XXL without clipping; 2.0 is beyond it.
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: WidgetsApp(
              color: Palette.ledger,
              builder: (context, _) => DefaultTextStyle(
                style: TextStyles.bodyText,
                child: const GateScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(tester.takeException(), isNull);
    });

    testWidgets('actions carry semantic labels and hints', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpGate(tester);

      expect(
        find.bySemanticsLabel('Leave'),
        findsOneWidget,
        reason: 'VoiceOver needs a label, not just a rendered string',
      );
      handle.dispose();
    });
  });
}
