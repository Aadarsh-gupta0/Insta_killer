# Insta_killer

An intentional-access gate for Instagram. When you open Instagram, Instagram does not
open — a gate appears, and the only way past is to tear off one of a finite number of
15-minute permits.

**Status: P0, feasibility spike. Written, not yet run on device.**

## Read these first

| Document | What it is |
|---|---|
| [`docs/P0_SPIKE.md`](docs/P0_SPIKE.md) | **iOS runbook.** Build the spike, answer four questions, report back. |
| [`docs/P0_SPIKE_ANDROID.md`](docs/P0_SPIKE_ANDROID.md) | **Android runbook.** Same, for the other phone. |
| [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md) | What this app cannot do, in plain language. Ships with the build. |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | Every architectural choice, with the option it rejected. |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Control flow and layers. Provisional until P0 reports. |

Requirements live in the SRS (v1.0, 12 Aug 2026). Where the kickoff brief and the SRS
disagree, the SRS wins.

## The two platforms are not equivalent

Both get the block. They differ in ways worth knowing before reading anything else:

Test devices: **iPhone, iOS 26.4.1** · **OnePlus 12R, Android 16 (OxygenOS 16)**.

| | iOS 26.4.1 | Android 16 |
|---|---|---|
| Enforcement | OS refuses to open the app, draws a shield | We detect the launch and put our gate in front |
| Route to the Gate | Shortcuts automation (26.5 would remove this) | Direct, no user setup |
| Shortest enforced grant | 15 minutes, platform floor | Any duration |
| Per-sender VIP alerts | **impossible** — needs a Professional account | works, no API needed |
| Needs anyone's approval | Apple's, for distribution | no |
| Survives our app being killed | yes — the OS enforces it | **no** — OxygenOS can switch it off silently |

The last row is the important trade: Android is the more *capable* platform and iOS is the
more *reliable* enforcer. Neither is strictly better.

Why: [D-007](docs/DECISIONS.md), [D-008](docs/DECISIONS.md), [D-009](docs/DECISIONS.md),
[D-010](docs/DECISIONS.md).

## Layout

```
docs/                              specs, decisions, limitations
ios-spike/                         P0 only — standalone SwiftUI, no Flutter (D-006)
  InstaKillerSpike/                app target
  ShieldConfigurationExtension/    what the block screen looks like
  ShieldActionExtension/           what its buttons do
  Entitlements/                    reference entitlements to compare against
android-spike/                     P0 only — plain Kotlin, zero dependencies
  app/src/main/java/…/
    ForegroundWatcher.kt           AccessibilityService — detects the launch
    GateActivity.kt                the block screen
    NotificationProbe.kt           NotificationListenerService — the VIP probe
    SpikeActivity.kt               diagnostic panel
```

The Flutter project does not exist yet, on purpose. P0 needs no Dart, and adding a build
system between us and the questions only creates places for a failure to hide.

## Phases

- **P0** — feasibility spikes, both platforms ← *here*
- **P1** — enforcement core: permit round-trip, quota, event log
- **P2** — the Flutter product: design system, nine screens, Strict Mode
- **P3** — the Gate: breathing beat, Live Activity, App Intents
- **P4** — VIP notifications — Android only (D-008)

## Neither spike has been run

I wrote both in a Linux container with no macOS, no Xcode, no Android SDK and no phone
attached. The Swift is verified against Apple's current documentation but never compiled;
the Kotlin is hand-checked but never compiled. Treat the first build on each device as
part of the test.
