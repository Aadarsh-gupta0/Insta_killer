import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insta_killer/app/providers.dart';
import 'package:insta_killer/data/guardian_codes.dart';
import 'package:insta_killer/data/office_repository.dart';
import 'package:insta_killer/design/office_button.dart';
import 'package:insta_killer/design/tokens.dart';
import 'package:insta_killer/features/guardian/guardian_screen.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

void main() {
  final now = DateTime(2026, 8, 13, 14);

  group('HmacCodeSigner', () {
    test('is deterministic for one secret', () {
      const signer = HmacCodeSigner('K7P29XMF3TQA8HN52WRJ');
      expect(signer.sign('481920'), signer.sign('481920'));
    });

    test('always produces exactly six digits', () {
      final rng = Random(1);
      for (var i = 0; i < 500; i++) {
        final secret = generateGuardianSecret(random: rng);
        final challenge = generateChallenge(random: rng);
        final code = HmacCodeSigner(secret).sign(challenge);

        expect(code, hasLength(6));
        expect(int.tryParse(code), isNotNull,
            reason: 'a code with a letter in it cannot be read over a phone');
      }
    });

    test('different secrets give different answers to the same challenge', () {
      expect(
        const HmacCodeSigner('K7P29XMF3TQA8HN52WRJ').sign('481920'),
        isNot(const HmacCodeSigner('2WRJ8HN53TQA9XMFK7P2').sign('481920')),
      );
    });

    test('different challenges give different answers', () {
      const signer = HmacCodeSigner('K7P29XMF3TQA8HN52WRJ');
      expect(signer.sign('481920'), isNot(signer.sign('481921')));
    });

    test('ignores whitespace around a typed challenge', () {
      const signer = HmacCodeSigner('K7P29XMF3TQA8HN52WRJ');
      expect(signer.sign(' 481920 '), signer.sign('481920'));
    });
  });

  group('secrets', () {
    test('avoid glyphs that are misread aloud', () {
      final rng = Random(7);
      for (var i = 0; i < 200; i++) {
        final secret = generateGuardianSecret(random: rng);
        // I, L, O, U, 0 and 1 are the ones that get misheard or mistyped.
        expect(RegExp('[ILOU01]').hasMatch(secret), isFalse,
            reason: 'ambiguous characters turn into failed pairings: $secret');
      }
    });

    test('are grouped for reading out, and normalise back', () {
      final secret = generateGuardianSecret(random: Random(3));
      expect(secret.split('-'), hasLength(5));
      expect(normaliseSecret(secret), hasLength(20));
    });

    test('normalise past casing, spaces and dashes', () {
      const canonical = 'K7P29XMF3TQA8HN52WRJ';
      expect(normaliseSecret('k7p2-9xmf-3tqa-8hn5-2wrj'), canonical);
      expect(normaliseSecret('K7P2 9XMF 3TQA 8HN5 2WRJ'), canonical);
      expect(looksLikeSecret('k7p2 9xmf 3tqa 8hn5 2wrj'), isTrue);
      expect(looksLikeSecret('too short'), isFalse);
    });

    test('are not predictable across calls', () {
      final secrets = {for (var i = 0; i < 50; i++) generateGuardianSecret()};
      expect(secrets, hasLength(50));
    });
  });

  group('the approval round trip', () {
    late InMemoryOfficeRepository repo;
    late ProviderContainer container;

    const secret = 'K7P29XMF3TQA8HN52WRJ';

    Future<void> open({
      OfficeRules rules = const OfficeRules(),
      PendingChange? pending,
      bool paired = true,
    }) async {
      repo = InMemoryOfficeRepository(
        rules: rules.copyWith(guardianPaired: paired),
        pendingChange: pending,
        guardianSecret: paired ? secret : null,
        guardianPairing:
            paired ? GuardianPairing(name: 'Priya', pairedAt: now) : null,
      );
      container = ProviderContainer(overrides: [
        repositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(FakeClock(wall: now)),
      ]);
      addTearDown(container.dispose);
      await container.read(officeProvider.future);
    }

    PendingChange queued({String id = 'chg-1', bool unpair = false}) =>
        PendingChange(
          id: id,
          requestedAt: now,
          appliesAt: now.add(const Duration(hours: 24)),
          resulting: OfficeRules(
            guardianPaired: !unpair,
            quota: const QuotaPolicy(permitsPerDay: 9),
          ),
          description: unpair ? 'guardian removed' : 'quota to 9',
        );

    test('the right code from the Guardian is accepted', () async {
      await open(pending: queued());
      final notifier = container.read(officeProvider.notifier);

      final request = await notifier.requestApproval();
      expect(request, isNotNull);

      // What the Guardian's phone would compute from the same secret.
      final answer = const HmacCodeSigner(secret).sign(request!.challenge);

      expect(await notifier.submitApproval(answer), ApprovalVerdict.accepted);
      expect(await repo.loadApprovalGranted(), isTrue);
    });

    test('a guessed code is refused', () async {
      await open(pending: queued());
      final notifier = container.read(officeProvider.notifier);
      await notifier.requestApproval();

      expect(await notifier.submitApproval('000000'),
          ApprovalVerdict.wrongCode);
      expect(await repo.loadApprovalGranted(), isFalse);
    });

    test('asking twice does not invalidate a code already in flight', () async {
      await open(pending: queued());
      final notifier = container.read(officeProvider.notifier);

      final first = await notifier.requestApproval();
      final second = await notifier.requestApproval();

      expect(second!.challenge, first!.challenge,
          reason: 'the Guardian may already be typing the first one');
    });

    test('approval does not survive the request being replaced', () async {
      await open(
        rules: const OfficeRules(enforcementEnabled: true),
        pending: queued(),
      );
      final notifier = container.read(officeProvider.notifier);

      final request = await notifier.requestApproval();
      await notifier
          .submitApproval(const HmacCodeSigner(secret).sign(request!.challenge));
      expect(await repo.loadApprovalGranted(), isTrue);

      // The user asks for something else instead — another loosening, so it queues and
      // replaces the first.
      await notifier.requestRulesChange(
        const OfficeRules(guardianPaired: true),
        description: 'blocking off',
      );

      expect(await repo.loadApprovalGranted(), isFalse,
          reason: 'agreeing to a quota rise is not agreeing to unblocking');
      expect(await repo.loadApprovalRequest(), isNull);
    });

    test('an immediate change discards a queued one built on stale rules',
        () async {
      await open(pending: queued());
      final notifier = container.read(officeProvider.notifier);

      // A tightening, so it applies now. The queued loosening captured the rules as they
      // were and would undo this when it landed.
      await notifier.requestRulesChange(
        const OfficeRules(
          guardianPaired: true,
          quota: QuotaPolicy(permitsPerDay: 1),
        ),
        description: 'quota to 1',
      );

      expect(await repo.loadPendingChange(), isNull);
      expect((await repo.loadRules()).quota.permitsPerDay, 1);
    });

    test('an approved change still waits out its cooldown', () async {
      await open(pending: queued());
      final notifier = container.read(officeProvider.notifier);

      final request = await notifier.requestApproval();
      await notifier
          .submitApproval(const HmacCodeSigner(secret).sign(request!.challenge));

      final office = container.read(officeProvider).valueOrNull!;
      expect(office.pendingChange, isNotNull,
          reason: 'approval is not a fast path');
      expect(office.rules.quota.permitsPerDay, 3);
    });
  });

  group('the screen', () {
    Future<void> pumpGuardian(
      WidgetTester tester, {
      InMemoryOfficeRepository? repository,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider
                .overrideWithValue(repository ?? InMemoryOfficeRepository()),
            clockProvider.overrideWithValue(FakeClock(wall: now)),
          ],
          child: WidgetsApp(
            color: Palette.ledger,
            builder: (context, _) => DefaultTextStyle(
              style: TextStyles.bodyText,
              child: const GuardianScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('offers a shared code when nobody is paired', (tester) async {
      await pumpGuardian(tester);

      expect(find.text('NO GUARDIAN'), findsOneWidget);
      expect(find.text('THE SHARED CODE'), findsOneWidget);
    });

    testWidgets('refuses to pair without a name', (tester) async {
      final repo = InMemoryOfficeRepository();
      await pumpGuardian(tester, repository: repo);

      final finder = find.widgetWithText(OfficeButton, 'THEY HAVE IT — PAIR');
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();

      expect(find.textContaining('name'), findsWidgets);
      expect(await repo.loadGuardianPairing(), isNull);
    });

    testWidgets('shows who is paired once there is one', (tester) async {
      final repo = InMemoryOfficeRepository(
        rules: const OfficeRules(guardianPaired: true),
        guardianPairing: GuardianPairing(name: 'Priya', pairedAt: now),
      );
      await pumpGuardian(tester, repository: repo);

      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('NO GUARDIAN'), findsNothing);
    });

    testWidgets('the Guardian half turns a challenge into an answer',
        (tester) async {
      await pumpGuardian(tester);

      final fields = find.byType(EditableText);
      // Last two fields on the screen belong to the Guardian block: secret, challenge.
      await tester.enterText(fields.at(fields.evaluate().length - 2),
          'K7P2-9XMF-3TQA-8HN5-2WRJ');
      await tester.enterText(fields.last, '481920');
      await tester.pump();

      final button = find.widgetWithText(OfficeButton, 'WORK OUT THE ANSWER');
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();

      expect(find.text('READ THIS BACK'), findsOneWidget);
      expect(
        find.text(const HmacCodeSigner('K7P29XMF3TQA8HN52WRJ').sign('481920')),
        findsOneWidget,
      );
    });
  });
}
