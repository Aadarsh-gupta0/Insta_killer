# Insta_killer

An intentional-access gate for Instagram. When you open Instagram, Instagram does not
open — a gate appears, and the only way past is to spend one of a finite number of
15-minute permits.

**Shipping platform: Android.** iOS is paused, not abandoned ([D-012](docs/DECISIONS.md)).
Test device: OnePlus 12R, Android 16 (OxygenOS 16).

## State of things

| | Status |
|---|---|
| `packages/domain` — the rules | **102 tests, 93.5% coverage.** Analyzer clean. |
| `lib/` — the Flutter app | **26 widget tests.** Gate and Front Desk built and passing. |
| `android-spike/` — enforcement proof | Verified working on device. Not yet merged into the app. |
| Native wiring — services → Flutter gate | **Next.** Not started. |
| `ios-spike/` | Written, never compiled. Paused. |

```
dart test           # in packages/domain — the rules
flutter test        # at the root — the screens
flutter analyze     # clean
```

Nothing in this repository has been compiled for Android. The build environment has no
Android SDK (`dl.google.com` is blocked by network policy), so Dart and Flutter tests are
the full extent of what has been verified here. The Kotlin is hand-checked.

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
  data/                repository seam — in-memory today, Pigeon-backed next
  design/tokens.dart   the Permit Office: palette, type, spacing, motion
  features/gate/       the reflex interrupt — 4s pause, declaration, reason
  features/home/       Front Desk

android/               the Flutter app's Android project
android-spike/         standalone P0 proof: AccessibilityService, gate, notification probe
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

## Next

1. Merge the spike's services into `android/`, and launch the Flutter Gate from
   `ForegroundWatcher` instead of the throwaway `GateActivity`.
2. Pigeon bridge, so the Dart rules and the native services read one store.
3. Permit expiry via `AlarmManager`, boot receiver, and the D-010 watchdog.
4. Remaining screens: Blocklist, Hours, The Record, Office Rules, onboarding.
