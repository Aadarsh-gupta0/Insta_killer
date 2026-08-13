/// FR-27 — a trusted third party who has to agree before anything gets looser.
///
/// The mechanism is a challenge and a response. Your phone shows a six-digit challenge;
/// the Guardian's phone turns it into a six-digit response using a secret the two paired
/// once; you type the response back. Nothing travels over a network we own — the two
/// codes go over whatever you already use to talk to each other.
///
/// **This package does not do the arithmetic.** It says what a challenge is, when one is
/// required, and whether a response is acceptable; the signing itself is injected as
/// [CodeSigner] so the domain keeps its no-dependency rule (D-011) and the policy stays
/// testable without any crypto at all.
library;

import 'gate_policy.dart';
import 'strictness.dart';

/// Turns a challenge into the response the Guardian would give.
///
/// Implemented in the app over HMAC-SHA256. Both phones can compute it, which is the
/// honest limit of this design — see the note on [GuardianPolicy].
abstract interface class CodeSigner {
  String sign(String challenge);
}

/// A paired Guardian. The shared secret is deliberately **not** here: it lives in its own
/// storage slot, never in the rules blob, so it is not carried around inside every
/// settings object that gets logged or serialised.
class GuardianPairing {
  const GuardianPairing({required this.name, required this.pairedAt});

  final String name;
  final DateTime pairedAt;

  Map<String, Object?> toJson() => {
        'name': name,
        'pairedAt': pairedAt.toUtc().toIso8601String(),
      };

  static GuardianPairing fromJson(Map<String, Object?> json) => GuardianPairing(
        name: json['name']! as String,
        pairedAt: DateTime.parse(json['pairedAt']! as String).toLocal(),
      );
}

/// One outstanding "please let me do this" question.
class ApprovalRequest {
  const ApprovalRequest({
    required this.challenge,
    required this.issuedAt,
    required this.changeId,
  });

  /// Six digits, shown to the owner to pass on.
  final String challenge;

  final DateTime issuedAt;

  /// Binds this approval to one specific queued change. Approving a quota rise must not
  /// also approve turning blocking off.
  final String changeId;

  bool isExpired(DateTime now, {Duration lifetime = const Duration(hours: 24)}) =>
      now.difference(issuedAt) >= lifetime;

  Map<String, Object?> toJson() => {
        'challenge': challenge,
        'issuedAt': issuedAt.toUtc().toIso8601String(),
        'changeId': changeId,
      };

  static ApprovalRequest fromJson(Map<String, Object?> json) => ApprovalRequest(
        challenge: json['challenge']! as String,
        issuedAt: DateTime.parse(json['issuedAt']! as String).toLocal(),
        changeId: json['changeId']! as String,
      );
}

enum ApprovalVerdict {
  accepted,

  /// The digits do not match what the Guardian's phone would have produced.
  wrongCode,

  /// The response is for a different request — an old code being reused.
  staleRequest,

  expired,
}

/// What a queued change is still waiting for.
class GuardianGate {
  const GuardianGate({required this.needsApproval, required this.approved});

  final bool needsApproval;
  final bool approved;

  bool get satisfied => !needsApproval || approved;
}

class GuardianPolicy {
  const GuardianPolicy();

  /// How long an unpair request waits when the Guardian never answers.
  ///
  /// A deliberate escape hatch. Unpairing is a loosening, so it needs the Guardian's
  /// approval like anything else — but a Guardian who has lost their phone, fallen out
  /// with you, or simply stopped replying would otherwise leave the settings locked
  /// permanently, with uninstalling as the only way out. That is a worse outcome than a
  /// week's delay, and it cannot be used to shortcut an ordinary loosening because those
  /// still require approval outright.
  static const Duration unpairSafetyValve = Duration(days: 7);

  /// Whether [change] can land, given the pairing state.
  ///
  /// With a Guardian paired, a loosening needs **both** the cooldown and the approval.
  /// FR-27 says loosening *requires* the Guardian's code; it does not say the code buys
  /// you out of the wait. Making approval a fast path would turn the Guardian into a way
  /// to go faster, which is the opposite of the point.
  GuardianGate gateFor({
    required PendingChange change,
    required bool paired,
    required bool approved,
  }) =>
      GuardianGate(needsApproval: paired, approved: approved);

  /// Whether a queued change is ready to apply.
  bool canApply({
    required PendingChange change,
    required DateTime now,
    required bool paired,
    required bool approved,
  }) {
    if (!change.isDue(now)) return false;
    if (!paired || approved) return true;

    // The valve, and only for removing the Guardian. Everything else waits indefinitely
    // for an answer — which is the point of having a Guardian at all.
    return isUnpairRequest(change, paired: paired) &&
        !now.isBefore(change.requestedAt.add(unpairSafetyValve));
  }

  /// When an unapproved change could land without the Guardian, if ever.
  DateTime? unattendedApplyTime(PendingChange change, {required bool paired}) =>
      isUnpairRequest(change, paired: paired)
          ? change.requestedAt.add(unpairSafetyValve)
          : null;

  /// True when [change] is the one that removes the Guardian.
  static bool isUnpairRequest(PendingChange change, {required bool paired}) =>
      paired && !change.resulting.guardianPaired;

  /// A fresh challenge for [change].
  ///
  /// [digits] supplies the randomness so this stays a pure function in tests. It must be
  /// unpredictable in production: a challenge the owner can guess ahead of time is a
  /// challenge they can have answered before they need it.
  ApprovalRequest challengeFor({
    required PendingChange change,
    required DateTime now,
    required String Function() digits,
  }) =>
      ApprovalRequest(
        challenge: digits(),
        issuedAt: now,
        changeId: change.id,
      );

  ApprovalVerdict verify({
    required ApprovalRequest request,
    required PendingChange change,
    required String response,
    required DateTime now,
    required CodeSigner signer,
  }) {
    if (request.changeId != change.id) return ApprovalVerdict.staleRequest;
    if (request.isExpired(now)) return ApprovalVerdict.expired;

    final expected = signer.sign(request.challenge);
    // Compared digit by digit over the full length rather than with ==, so the loop does
    // not exit early on the first mismatch. Timing here is not a realistic attack, but a
    // constant-time compare costs nothing and stops the habit of writing the other kind.
    if (!_constantTimeEquals(expected, response.trim())) {
      return ApprovalVerdict.wrongCode;
    }
    return ApprovalVerdict.accepted;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Whether [to] removes the Guardian, which is the one change that gets the safety valve.
bool isUnpairing(OfficeRules from, OfficeRules to) =>
    from.guardianPaired && !to.guardianPaired;
