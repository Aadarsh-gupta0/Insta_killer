import 'package:insta_killer_domain/insta_killer_domain.dart';
import 'package:test/test.dart';

/// Stands in for HMAC. Deterministic, and deliberately not the real algorithm — the
/// policy must not care which one is used.
class FakeSigner implements CodeSigner {
  const FakeSigner([this.salt = '']);

  final String salt;

  @override
  String sign(String challenge) {
    final sum = (challenge + salt)
        .codeUnits
        .fold<int>(7, (a, b) => (a * 31 + b) % 1000000);
    return sum.toString().padLeft(6, '0');
  }
}

void main() {
  final now = DateTime(2026, 8, 13, 14);
  const policy = GuardianPolicy();
  const signer = FakeSigner();

  PendingChange change({
    String id = 'chg-1',
    bool resultingPaired = true,
    DateTime? requestedAt,
  }) =>
      PendingChange(
        id: id,
        requestedAt: requestedAt ?? now,
        appliesAt: (requestedAt ?? now).add(const Duration(hours: 24)),
        resulting: OfficeRules(
          guardianPaired: resultingPaired,
          quota: const QuotaPolicy(permitsPerDay: 9),
        ),
        description: 'quota to 9',
      );

  group('classification', () {
    const base = OfficeRules();

    test('pairing a Guardian tightens', () {
      expect(
        classifyChange(base, base.copyWith(guardianPaired: true)),
        ChangeDirection.tighten,
      );
    });

    test('removing a Guardian loosens', () {
      final paired = base.copyWith(guardianPaired: true);
      expect(classifyChange(paired, base), ChangeDirection.loosen);
      expect(isUnpairing(paired, base), isTrue);
    });
  });

  group('when approval is required', () {
    test('an unpaired office needs no approval at all', () {
      expect(
        policy.canApply(
          change: change(),
          now: now.add(const Duration(hours: 24)),
          paired: false,
          approved: false,
        ),
        isTrue,
      );
    });

    test('a paired office holds the change until the Guardian agrees', () {
      final due = now.add(const Duration(hours: 24));

      expect(
        policy.canApply(
            change: change(), now: due, paired: true, approved: false),
        isFalse,
        reason: 'the cooldown elapsed but nobody has agreed',
      );
      expect(
        policy.canApply(change: change(), now: due, paired: true, approved: true),
        isTrue,
      );
    });

    test('approval does not buy you out of the wait', () {
      expect(
        policy.canApply(
          change: change(),
          now: now.add(const Duration(hours: 1)),
          paired: true,
          approved: true,
        ),
        isFalse,
        reason: 'a Guardian must not become a way to go faster',
      );
    });
  });

  group('the unpair safety valve', () {
    final unpair = change(resultingPaired: false);

    test('an unapproved unpair lands after seven days', () {
      expect(
        policy.canApply(
          change: unpair,
          now: now.add(const Duration(days: 6, hours: 23)),
          paired: true,
          approved: false,
        ),
        isFalse,
      );
      expect(
        policy.canApply(
          change: unpair,
          now: now.add(const Duration(days: 7)),
          paired: true,
          approved: false,
        ),
        isTrue,
        reason: 'a Guardian who vanishes must not lock the phone forever',
      );
    });

    test('the valve does not apply to ordinary loosenings', () {
      expect(
        policy.canApply(
          change: change(),
          now: now.add(const Duration(days: 30)),
          paired: true,
          approved: false,
        ),
        isFalse,
        reason: 'otherwise waiting a week defeats the whole mechanism',
      );
      expect(policy.unattendedApplyTime(change(), paired: true), isNull);
    });

    test('reports when an unattended unpair would land', () {
      expect(
        policy.unattendedApplyTime(unpair, paired: true),
        now.add(const Duration(days: 7)),
      );
    });
  });

  group('challenge and response', () {
    test('a correct response is accepted', () {
      final request = policy.challengeFor(
        change: change(),
        now: now,
        digits: () => '481920',
      );
      expect(request.challenge, '481920');

      expect(
        policy.verify(
          request: request,
          change: change(),
          response: signer.sign('481920'),
          now: now,
          signer: signer,
        ),
        ApprovalVerdict.accepted,
      );
    });

    test('tolerates surrounding whitespace when the code is typed', () {
      final request = policy.challengeFor(
          change: change(), now: now, digits: () => '481920');

      expect(
        policy.verify(
          request: request,
          change: change(),
          response: '  ${signer.sign('481920')} ',
          now: now,
          signer: signer,
        ),
        ApprovalVerdict.accepted,
      );
    });

    test('a wrong code is refused', () {
      final request = policy.challengeFor(
          change: change(), now: now, digits: () => '481920');

      expect(
        policy.verify(
          request: request,
          change: change(),
          response: '000000',
          now: now,
          signer: signer,
        ),
        ApprovalVerdict.wrongCode,
      );
    });

    test('a code from a different Guardian is refused', () {
      final request = policy.challengeFor(
          change: change(), now: now, digits: () => '481920');

      expect(
        policy.verify(
          request: request,
          change: change(),
          response: const FakeSigner('someone else').sign('481920'),
          now: now,
          signer: signer,
        ),
        ApprovalVerdict.wrongCode,
      );
    });

    test('an approval for one change cannot be reused for another', () {
      final request = policy.challengeFor(
          change: change(id: 'chg-1'), now: now, digits: () => '481920');

      expect(
        policy.verify(
          request: request,
          change: change(id: 'chg-2'),
          response: signer.sign('481920'),
          now: now,
          signer: signer,
        ),
        ApprovalVerdict.staleRequest,
        reason: 'approving a quota rise must not also approve blocking off',
      );
    });

    test('a challenge goes stale after a day', () {
      final request = policy.challengeFor(
          change: change(), now: now, digits: () => '481920');

      expect(
        policy.verify(
          request: request,
          change: change(),
          response: signer.sign('481920'),
          now: now.add(const Duration(hours: 24)),
          signer: signer,
        ),
        ApprovalVerdict.expired,
      );
    });

    test('survives a JSON round trip', () {
      final request = policy.challengeFor(
          change: change(), now: now, digits: () => '481920');

      final restored = ApprovalRequest.fromJson(request.toJson());
      expect(restored.challenge, '481920');
      expect(restored.changeId, 'chg-1');
      expect(restored.issuedAt.millisecondsSinceEpoch,
          request.issuedAt.millisecondsSinceEpoch);
    });
  });

  test('pairing survives a JSON round trip', () {
    final restored = GuardianPairing.fromJson(
      GuardianPairing(name: 'Priya', pairedAt: now).toJson(),
    );
    expect(restored.name, 'Priya');
    expect(restored.pairedAt.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
  });
}
