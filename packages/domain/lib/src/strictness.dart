/// Strict Mode's asymmetry (FR-25, FR-26).
///
/// Tightening is instant. Loosening waits 24 hours with a visible countdown, and can be
/// cancelled at any point before it lands. The asymmetry is the whole mechanism: it costs
/// nothing to become stricter in a good moment, and it costs a day to become laxer in a
/// bad one.
library;

import 'gate_policy.dart';

const Duration looseningCooldown = Duration(hours: 24);

enum ChangeDirection {
  tighten,
  loosen,

  /// No effect on strictness — cosmetic settings, shield copy wording.
  neutral,
}

/// Works out which way a settings edit moves the strictness dial.
///
/// When an edit moves several dimensions at once and any one of them loosens, the whole
/// edit is a loosening. Otherwise a user could hide "quota 3 → 10" behind "also add one
/// blocked app" and have it apply instantly.
ChangeDirection classifyChange(OfficeRules from, OfficeRules to) {
  var sawTighten = false;
  var sawLoosen = false;

  void compare(num before, num after, {required bool moreIsStricter}) {
    if (before == after) return;
    final stricter = moreIsStricter ? after > before : after < before;
    if (stricter) {
      sawTighten = true;
    } else {
      sawLoosen = true;
    }
  }

  compare(from.quota.permitsPerDay, to.quota.permitsPerDay,
      moreIsStricter: false);
  compare(from.grantDuration.inSeconds, to.grantDuration.inSeconds,
      moreIsStricter: false);
  compare(from.blockedAppCount, to.blockedAppCount, moreIsStricter: true);
  compare(from.schedule.blockedMinutesPerWeek,
      to.schedule.blockedMinutesPerWeek,
      moreIsStricter: true);

  if (from.strictMode != to.strictMode) {
    if (to.strictMode) {
      sawTighten = true;
    } else {
      sawLoosen = true;
    }
  }

  // A day boundary move is genuinely ambiguous — it can shift a reset earlier or later
  // depending on when you ask. Treated as a loosening because we resolve ambiguity
  // toward more restriction (NFR-2), and making the user wait is the restrictive option.
  if (from.quota.boundary != to.quota.boundary) sawLoosen = true;

  // Same schedule size but different cells: some hours were freed, some blocked. The
  // freed ones are a loosening.
  if (from.schedule.blockedMinutesPerWeek ==
          to.schedule.blockedMinutesPerWeek &&
      from.schedule != to.schedule) {
    sawLoosen = true;
  }

  if (sawLoosen) return ChangeDirection.loosen;
  if (sawTighten) return ChangeDirection.tighten;
  return ChangeDirection.neutral;
}

class PendingChange {
  const PendingChange({
    required this.id,
    required this.requestedAt,
    required this.appliesAt,
    required this.resulting,
    required this.description,
  });

  final String id;
  final DateTime requestedAt;
  final DateTime appliesAt;
  final OfficeRules resulting;
  final String description;

  bool isDue(DateTime now) => !now.isBefore(appliesAt);

  Duration remaining(DateTime now) {
    final left = appliesAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

sealed class ChangeOutcome {
  const ChangeOutcome();
}

/// Applied immediately — a tightening, or any change while Strict Mode is off.
class ChangeApplied extends ChangeOutcome {
  const ChangeApplied(this.rules);

  final OfficeRules rules;
}

/// Queued behind the cooldown.
class ChangeQueued extends ChangeOutcome {
  const ChangeQueued(this.pending);

  final PendingChange pending;
}

class StrictnessPolicy {
  const StrictnessPolicy({this.cooldown = looseningCooldown});

  final Duration cooldown;

  /// Requests a move from [from] to [to].
  ///
  /// Note the check is on `from.strictMode`, the mode currently in force. Turning Strict
  /// Mode off is itself a loosening, so it queues — you cannot disable the cooldown to
  /// escape the cooldown.
  ChangeOutcome request({
    required OfficeRules from,
    required OfficeRules to,
    required DateTime now,
    required String description,
    String Function()? idFactory,
  }) {
    final direction = classifyChange(from, to);

    if (!from.strictMode || direction != ChangeDirection.loosen) {
      return ChangeApplied(to);
    }

    return ChangeQueued(
      PendingChange(
        id: (idFactory ?? _defaultId)(),
        requestedAt: now,
        appliesAt: now.add(cooldown),
        resulting: to,
        description: description,
      ),
    );
  }

  /// FR-26 — cancellable right up to the moment it lands.
  ///
  /// A change that is already due cannot be cancelled: at that point it is the current
  /// state and cancelling would be a loosening of its own, needing its own cooldown.
  bool canCancel(PendingChange pending, DateTime now) => !pending.isDue(now);

  /// Applies whatever is due. Returns null when nothing is.
  OfficeRules? applyIfDue(PendingChange pending, DateTime now) =>
      pending.isDue(now) ? pending.resulting : null;

  static int _counter = 0;

  static String _defaultId() =>
      'chg-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
}
