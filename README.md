# Insta_killer

An intentional-access gate for Instagram. When you open Instagram, Instagram does not
open — a gate appears, and the only way past is to tear off one of a finite number of
15-minute permits.

**Status: P0, feasibility spike. Written, not yet run on device.**

## Read these first

| Document | What it is |
|---|---|
| [`docs/P0_SPIKE.md`](docs/P0_SPIKE.md) | The runbook. Build the spike, answer four questions, report back. |
| [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md) | What this app cannot do, in plain language. Ships with the build. |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | Every architectural choice, with the option it rejected. |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Control flow and layers. Provisional until P0 reports. |

Requirements live in the SRS (v1.0, 12 Aug 2026). Where the kickoff brief and the SRS
disagree, the SRS wins.

## Layout

```
docs/                              specs, decisions, limitations
ios-spike/                         P0 only — standalone SwiftUI, no Flutter (D-006)
  InstaKillerSpike/                app target
  ShieldConfigurationExtension/    what the block screen looks like
  ShieldActionExtension/           what its buttons do
  Entitlements/                    reference entitlements to compare against
```

The Flutter project does not exist yet, on purpose. P0 needs no Dart, and adding a build
system between us and the four questions only creates places for a failure to hide.

## Phases

- **P0** — feasibility spike ← *here*
- **P1** — enforcement core: three extensions, the 15-minute permit round-trip, quota, event log
- **P2** — the Flutter product: design system, nine screens, Strict Mode
- **P3** — the Gate: breathing beat, Live Activity, App Intents
- **P4** — VIP notifications, feature-flagged
- **P5** — Android
