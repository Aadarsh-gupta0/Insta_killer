import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insta_killer/app/providers.dart';
import 'package:insta_killer/data/office_repository.dart';
import 'package:insta_killer/design/office_button.dart';
import 'package:insta_killer/design/tokens.dart';
import 'package:insta_killer/features/settings/office_rules_screen.dart';
import 'package:insta_killer/platform/office_api.g.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

class FakeHost extends OfficeHostApi {
  FakeHost({
    this.accessibility = true,
    this.notificationAccess = true,
    this.heartbeat = 0,
  });

  bool accessibility;
  bool notificationAccess;
  int heartbeat;

  int accessibilitySettingsOpened = 0;

  @override
  Future<NativeState> state() async => NativeState(
        blockingEnabled: false,
        grantEndsAtEpochMs: 0,
        launchReason: LaunchReason.icon,
        permissions: Permissions(
          accessibility: accessibility,
          notificationAccess: notificationAccess,
          instagramInstalled: true,
        ),
        lastWatcherHeartbeatEpochMs: heartbeat,
      );

  @override
  Future<void> openAccessibilitySettings() async =>
      accessibilitySettingsOpened++;

  @override
  Future<void> setBlockingEnabled(bool enabled) async {}
}

void main() {
  final afternoon = DateTime(2026, 8, 12, 14);

  late InMemoryOfficeRepository repo;
  late FakeClock clock;
  late FakeHost host;

  Future<void> pumpRules(
    WidgetTester tester, {
    OfficeRules rules = const OfficeRules(),
    PendingChange? pending,
    bool accessibility = true,
  }) async {
    repo = InMemoryOfficeRepository(rules: rules, pendingChange: pending);
    clock = FakeClock(wall: afternoon);
    host = FakeHost(accessibility: accessibility);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(clock),
          hostApiProvider.overrideWithValue(host),
        ],
        child: WidgetsApp(
          color: Palette.ledger,
          builder: (context, _) => DefaultTextStyle(
            style: TextStyles.bodyText,
            child: const OfficeRulesScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// The screen is long, so most controls start below the fold. Scrolling them into
  /// view first is what a user does and what `tap` needs.
  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.widgetWithText(OfficeButton, label);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
    await tester.pump();
  }

  group('the master switch', () {
    testWidgets('turning blocking on applies immediately', (tester) async {
      await pumpRules(tester);

      expect(find.text('off'), findsWidgets);
      await tap(tester, 'START BLOCKING');

      expect((await repo.loadRules()).enforcementEnabled, isTrue);
      expect(await repo.loadPendingChange(), isNull,
          reason: 'a tightening must not be made to wait');
      expect(find.text('Applied.'), findsOneWidget);
    });

    testWidgets('turning blocking off queues behind the cooldown',
        (tester) async {
      await pumpRules(tester, rules: const OfficeRules(enforcementEnabled: true));

      await tap(tester, 'REQUEST BLOCKING OFF');

      expect((await repo.loadRules()).enforcementEnabled, isTrue,
          reason: 'still enforcing until the cooldown elapses');

      final pending = await repo.loadPendingChange();
      expect(pending, isNotNull);
      expect(pending!.appliesAt, afternoon.add(const Duration(hours: 24)));
      expect(find.text('CHANGE QUEUED'), findsOneWidget);
    });

    testWidgets('is disabled while the accessibility service is off',
        (tester) async {
      await pumpRules(tester, accessibility: false);

      final button = tester.widget<OfficeButton>(
          find.widgetWithText(OfficeButton, 'START BLOCKING'));
      expect(button.enabled, isFalse,
          reason: 'switching blocking on without a watcher would be a lie');
      expect(find.textContaining('accessibility service is switched on'),
          findsOneWidget);
    });

    testWidgets('offers a route to the accessibility settings', (tester) async {
      await pumpRules(tester, accessibility: false);

      await tap(tester, 'OPEN SETTINGS');
      expect(host.accessibilitySettingsOpened, 1);
    });
  });

  group('quota', () {
    testWidgets('fewer permits applies at once', (tester) async {
      await pumpRules(tester);

      await tap(tester, 'FEWER');
      expect((await repo.loadRules()).quota.permitsPerDay, 2);
      expect(await repo.loadPendingChange(), isNull);
    });

    testWidgets('more permits has to be requested', (tester) async {
      await pumpRules(tester);

      await tap(tester, 'REQUEST MORE');
      expect((await repo.loadRules()).quota.permitsPerDay, 3,
          reason: 'unchanged until the cooldown elapses');
      expect((await repo.loadPendingChange())!.resulting.quota.permitsPerDay, 4);
    });

    testWidgets('cannot go below zero', (tester) async {
      await pumpRules(
        tester,
        rules: const OfficeRules(quota: QuotaPolicy(permitsPerDay: 0)),
      );

      final fewer =
          tester.widget<OfficeButton>(find.widgetWithText(OfficeButton, 'FEWER'));
      expect(fewer.enabled, isFalse);
    });
  });

  group('FR-26 — cancelling a queued change', () {
    testWidgets('shows a countdown and withdraws on cancel', (tester) async {
      final pending = PendingChange(
        id: 'chg-1',
        requestedAt: afternoon.subtract(const Duration(hours: 20)),
        appliesAt: afternoon.add(const Duration(hours: 4)),
        resulting: const OfficeRules(quota: QuotaPolicy(permitsPerDay: 9)),
        description: 'quota to 9',
      );
      await pumpRules(tester, pending: pending);

      expect(find.text('CHANGE QUEUED'), findsOneWidget);
      expect(find.text('quota to 9'), findsOneWidget);
      expect(find.text('04:00:00'), findsOneWidget);

      await tap(tester, 'CANCEL THIS CHANGE');

      expect(await repo.loadPendingChange(), isNull);
      expect(find.text('CHANGE QUEUED'), findsNothing);
    });
  });

  group('strict mode', () {
    testWidgets('cannot be switched off instantly', (tester) async {
      await pumpRules(tester);

      await tap(tester, 'REQUEST STRICT MODE OFF');

      expect((await repo.loadRules()).strictMode, isTrue);
      expect(await repo.loadPendingChange(), isNotNull,
          reason: 'the escape hatch is itself a loosening');
    });
  });

  group('honesty', () {
    testWidgets('FR-28 — states plainly that uninstalling removes everything',
        (tester) async {
      await pumpRules(tester);

      expect(find.textContaining('Uninstalling this app removes every block'),
          findsOneWidget);
      expect(find.textContaining('OxygenOS'), findsOneWidget,
          reason: 'D-010 — the OEM can switch the block off on its own');
    });

    testWidgets('explains why permits cannot be shorter than 15 minutes',
        (tester) async {
      await pumpRules(tester);
      expect(find.textContaining('shortest interval the platform schedules'),
          findsOneWidget);
    });

    testWidgets('reports the watcher as never seen while enforcing',
        (tester) async {
      await pumpRules(tester, rules: const OfficeRules(enforcementEnabled: true));
      expect(find.text('never'), findsOneWidget);
    });
  });

  testWidgets('survives XXL Dynamic Type', (tester) async {
    repo = InMemoryOfficeRepository();
    clock = FakeClock(wall: afternoon);
    host = FakeHost();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(clock),
          hostApiProvider.overrideWithValue(host),
        ],
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: WidgetsApp(
            color: Palette.ledger,
            builder: (context, _) => DefaultTextStyle(
              style: TextStyles.bodyText,
              child: const OfficeRulesScreen(),
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
