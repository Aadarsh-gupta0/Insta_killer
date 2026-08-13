# Insta_killer

An intentional-access gate for Instagram. When you open Instagram, Instagram does not
open — a gate appears, and the only way past is to spend one of a finite number of
15-minute permits.

**Shipping platform: Android.** iOS is paused, not abandoned ([D-012](docs/DECISIONS.md)).
Test device: OnePlus 12R, Android 16 (OxygenOS 16).

## State of things

| | Status |
|---|---|
| `packages/domain` — the rules | **107 tests, 93%+ coverage.** Analyzer clean. |
| `lib/` — the Flutter app | **55 tests.** Gate, Front Desk, Office Rules, platform repository. |
| `android/` — enforcement + Pigeon bridge | **Verified on device**, 13 Aug 2026. |
| `ios-spike/` | Written, never compiled. Paused. |

```
dart test           # in packages/domain — the rules
flutter test        # at the root — the screens
flutter analyze     # clean
```

The build environment has no Android SDK (`dl.google.com` is blocked by network policy),
so nothing here is compiled by CI — the Dart and Flutter tests are the full extent of what
is verified automatically. The Kotlin is verified by running it on the phone.

## Read these first

| Document | What it is |
|---|---|
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | Every architectural choice, with the option it rejected. Start at D-012. |
| [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md) | What this app cannot do, in plain language. Ships with the build. |
| [`docs/P0_SPIKE_ANDROID.md`](docs/P0_SPIKE_ANDROID.md) | The device runbook, including the OxygenOS survival check. |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Control flow. iOS-shaped and now partly stale — see D-012. |
| [`docs/P0_SPIKE.md`](docs/P0_SPIKE.md) | iOS runbook. Paused; the entry point if it resumes. |

Requirements live in the SRS (v1.0, 12 Aug 2026). Where the kickoff brief and the SRS
disagree, the SRS wins.

## Layout

```
packages/domain/       the rules, pure Dart, no Flutter import ever (D-011)
  clock · quota · permit · schedule · strictness · streak · insights

lib/
  app/providers.dart   Riverpod wiring; the only place rules meet UI
  data/                repository seam — in-memory for tests, Pigeon-backed in the app
  design/tokens.dart   the Permit Office: palette, type, spacing, motion
  features/gate/       the reflex interrupt — 4s pause, declaration, reason
  features/home/       Front Desk
  features/settings/   Office Rules — the master switch and the cooldown
  platform/            Pigeon bridge + the repository behind it

android/               enforcement services, alarms, and the Kotlin half of the bridge
ios-spike/             paused
```

## Why Android is the better platform here

Not a consolation prize. It does two things iOS cannot:

- **Interrupts the launch itself.** An `AccessibilityService` is told the instant
  Instagram foregrounds and puts our gate in front of it — closer to the original
  *"kill Instagram whenever I open it"* than iOS's shield ever gets.
- **Reads Instagram's notifications**, which makes per-sender VIP alerts real. On iOS
  that needs a Professional account and Meta App Review, and is permanently unavailable
  here ([D-008](docs/DECISIONS.md)).

The trade is honest and worth knowing: iOS shields are enforced by the OS and survive our
app being killed. On Android the block *is* our process, so OxygenOS can switch it off
silently. That is why the app watches its own pulse ([D-010](docs/DECISIONS.md)).

## How enforcement works

```
Instagram opens
      │
ForegroundWatcher   AccessibilityService — told instantly, and exempt from the
      │             background-activity-launch limits that stop a plain service
      │             opening a screen
      ├── blocking off?     → do nothing
      ├── permit running?   → do nothing      (compares a timestamp, not an alarm)
      └── otherwise         → launch MainActivity with reason=gate
                                    │
                            the Flutter Gate
                                    │
                     4s pause · declaration · reason ≥ 12 chars
                                    │
                        GatePolicy.evaluate()   ← every rule, pure Dart
                                    │
                     ┌──────────────┴──────────────┐
                  refused                       granted
                     │                             │
        reason + next possible time    grantEndsAt = now + 15 min
                                       alarms for T-2min and T-0
```

The watcher checks a timestamp rather than waiting for an alarm to re-arm blocking.
Alarms get dropped — by Doze, by OxygenOS, by a reboot — and under an alarm-driven design
a dropped one would leave Instagram open indefinitely. Here it costs a notification.

Native knows two things: whether to act, and whether a permit is running. Everything else
crosses the bridge as JSON that Kotlin never parses, so a service that cannot read the
quota cannot be tempted to check it ([D-013](docs/DECISIONS.md)).

## Next

1. Onboarding — the permission ladder and the signed declaration (FR-24). The Gate
   already displays the declaration, so until this exists that part of it is blank.
2. Remaining screens: Hours (schedules), The Record (insights), VIPs.
3. Surface the D-010 watchdog on the Front Desk, not only in Office Rules.
4. The multi-day OxygenOS survival check — Q5 in
   [`docs/P0_SPIKE_ANDROID.md`](docs/P0_SPIKE_ANDROID.md).
