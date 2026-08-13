import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insta_killer/app/providers.dart';
import 'package:insta_killer/data/office_repository.dart';
import 'package:insta_killer/design/office_button.dart';
import 'package:insta_killer/design/tokens.dart';
import 'package:insta_killer/features/blocklist/blocklist_screen.dart';
import 'package:insta_killer/platform/office_api.g.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

class ThrowingHost extends OfficeHostApi {
  @override
  Future<List<InstalledApp>> installedApps() async =>
      throw StateError('package manager unavailable');
}

class FakeHost extends OfficeHostApi {
  FakeHost({this.apps = const []});

  List<InstalledApp> apps;
  final List<List<String>> watchPushes = [];

  @override
  Future<List<InstalledApp>> installedApps() async => apps;

  @override
  Future<void> setWatchedPackages(List<String> packageNames) async =>
      watchPushes.add(packageNames);

  @override
  Future<void> setBlockingEnabled(bool enabled) async {}
}

InstalledApp app(String package, String label) =>
    InstalledApp(packageName: package, label: label);

void main() {
  final afternoon = DateTime(2026, 8, 12, 14);

  late InMemoryOfficeRepository repo;
  late FakeHost host;

  final catalogue = [
    app('com.instagram.android', 'Instagram'),
    app('com.zhiliaoapp.musically', 'TikTok'),
    app('com.reddit.frontpage', 'Reddit'),
  ];

  Future<void> pumpList(
    WidgetTester tester, {
    OfficeRules rules = const OfficeRules(),
  }) async {
    repo = InMemoryOfficeRepository(rules: rules);
    host = FakeHost(apps: catalogue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(FakeClock(wall: afternoon)),
          hostApiProvider.overrideWithValue(host),
        ],
        child: WidgetsApp(
          color: Palette.ledger,
          builder: (context, _) => DefaultTextStyle(
            style: TextStyles.bodyText,
            child: const BlocklistScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    final finder = find.widgetWithText(OfficeButton, label);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapApp(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  group('listing', () {
    testWidgets('shows every launchable app the platform reported',
        (tester) async {
      await pumpList(tester);

      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('TikTok'), findsOneWidget);
      expect(find.text('Reddit'), findsOneWidget);
    });

    testWidgets('seeds the ticks from the current rules', (tester) async {
      await pumpList(
        tester,
        rules: const OfficeRules(blockedPackages: {'com.reddit.frontpage'}),
      );

      expect(find.text('1'), findsOneWidget, reason: 'Selected: 1');
    });

    testWidgets('filters by label', (tester) async {
      await pumpList(tester);

      await tester.enterText(find.byType(EditableText), 'tik');
      await tester.pump();

      expect(find.text('TikTok'), findsOneWidget);
      expect(find.text('Instagram'), findsNothing);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await pumpList(tester);
      await tester.enterText(find.byType(EditableText), 'zzzz');
      await tester.pump();

      expect(find.text('No app matches that.'), findsOneWidget);
    });
  });

  group('saving', () {
    testWidgets('adding apps applies immediately', (tester) async {
      await pumpList(tester);

      await tapApp(tester, 'Instagram');
      await tapApp(tester, 'TikTok');
      await tapButton(tester, 'SAVE THE LIST');

      final rules = await repo.loadRules();
      expect(rules.blockedPackages,
          {'com.instagram.android', 'com.zhiliaoapp.musically'});
      expect(await repo.loadPendingChange(), isNull,
          reason: 'blocking more apps is a tightening');
      expect(find.text('Applied.'), findsOneWidget);
    });

    testWidgets('removing apps waits out the cooldown', (tester) async {
      await pumpList(
        tester,
        rules: const OfficeRules(
          blockedPackages: {'com.instagram.android', 'com.reddit.frontpage'},
        ),
      );

      await tapApp(tester, 'Reddit');
      await tapButton(tester, 'SAVE THE LIST');

      final rules = await repo.loadRules();
      expect(
        rules.blockedPackages,
        {'com.instagram.android', 'com.reddit.frontpage'},
        reason: 'the list must not change until the cooldown elapses',
      );

      final pending = await repo.loadPendingChange();
      expect(pending, isNotNull);
      expect(pending!.resulting.blockedPackages, {'com.instagram.android'});
      expect(find.textContaining('24 hours'), findsOneWidget);
    });

    testWidgets('swapping one app for another is treated as a loosening',
        (tester) async {
      await pumpList(
        tester,
        rules: const OfficeRules(blockedPackages: {'com.instagram.android'}),
      );

      await tapApp(tester, 'Instagram'); // untick
      await tapApp(tester, 'TikTok'); // tick
      await tapButton(tester, 'SAVE THE LIST');

      expect(await repo.loadPendingChange(), isNotNull,
          reason: 'the count is unchanged but Instagram was freed');
    });

    testWidgets('a no-op save says so rather than filing a change',
        (tester) async {
      await pumpList(tester);

      await tapButton(tester, 'SAVE THE LIST');

      expect(find.text('Nothing changed.'), findsOneWidget);
      expect(await repo.loadPendingChange(), isNull);
    });

    testWidgets('untick then re-tick is a no-op', (tester) async {
      await pumpList(
        tester,
        rules: const OfficeRules(blockedPackages: {'com.instagram.android'}),
      );

      await tapApp(tester, 'Instagram');
      await tapApp(tester, 'Instagram');
      await tapButton(tester, 'SAVE THE LIST');

      expect(find.text('Nothing changed.'), findsOneWidget);
    });
  });

  testWidgets('reports a platform failure instead of an empty list',
      (tester) async {
    repo = InMemoryOfficeRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(FakeClock(wall: afternoon)),
          hostApiProvider.overrideWithValue(ThrowingHost()),
        ],
        child: WidgetsApp(
          color: Palette.ledger,
          builder: (context, _) => DefaultTextStyle(
            style: TextStyles.bodyText,
            child: const BlocklistScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Could not read the app list'), findsOneWidget,
        reason: 'an empty list would read as "you have no apps"');
  });
}
