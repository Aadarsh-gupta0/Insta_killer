# insta_killer_domain

The rules, in pure Dart. Quota, permits, schedules, cooldowns, streaks, clock-tamper
resolution and the insights derived from the event log.

**No Flutter dependency, ever.** NFR-6 requires this layer to be shared unchanged between
iOS and Android, and D-007 made that immediate rather than hypothetical. The cheapest way
to enforce it is to keep Flutter out of `pubspec.yaml` so a platform import fails to
resolve rather than failing review.

```
dart pub get
dart test
dart analyze
```

102 tests, 93.5% line coverage (NFR-5 floor is 80%).

## What lives here

| File | Rule it owns |
|---|---|
| `clock.dart` | FR-20 — two clocks, and what to believe when they disagree |
| `quota_day.dart` | FR-16 — the day resets at 06:00, not midnight |
| `quota.dart` | FR-16, FR-17 — the daily allowance |
| `permit.dart` | FR-15, FR-19, FR-21 — the 15-minute grant and its countdown |
| `schedule.dart` | FR-23 — recurring blocked windows on a 15-minute grid |
| `gate_policy.dart` | the composed decision: may a permit be issued right now? |
| `strictness.dart` | FR-25, FR-26 — tighten now, loosen in 24 hours |
| `streak.dart` | FR-30 — quota-clean days |
| `insights.dart` | FR-30 — the Record |

## Reading order

`gate_policy.dart` first. Everything else feeds it, and `GatePolicy.evaluate` is the only
function the platform layers need to call.

## Decisions worth knowing before you edit

- **A refusal always carries its next-available time** where one exists (NFR-4). If you
  add a refusal reason, add the time with it.
- **Check order in `evaluate` is deliberate.** Most-absolute first, so the user gets one
  honest no rather than a sequence of them.
- **Ambiguity resolves toward restriction** (NFR-2). Clock disagreement, mixed settings
  changes, an unclear day boundary — all resolve the strict way.
- **`StreakRule` defaults to `underQuota`.** FR-30 says "quota-clean days" without
  defining clean; see the comment at the top of `streak.dart` for the argument and flip
  the enum if you disagree.

## Dependencies

One, dev-only: `test ^1.25.0`. Nothing at runtime, deliberately.
