# Architecture

**Provisional until P0 reports.** The control flow below assumes iOS 26.5+ and
`.openParentalControlsApp`. If P0 shows otherwise, the Gate moves behind the Shortcuts
automation and this document gets rewritten, not amended.

## The revised enforcement path

The kickoff brief specifies two parallel paths — a shield that can only close the attempt
(Path A) and a Shortcuts automation that reaches the real Gate (Path B) — because a shield
button could not open our app. On iOS 26.5 it can. The paths collapse into one:

```
user taps Instagram
        │
        ▼
iOS consults ManagedSettingsStore("instakiller")
        │
   isActive? ──no──▶ Instagram opens (a permit is running)
        │ yes
        ▼
ShieldConfigurationExtension  ── reads title/subtitle/buttons from App Group
        │                        (FR-8: subtitle is the user's own declaration)
        ▼
   shield renders
        │
   ┌────┴─────────────────────┐
   │                          │
"Close"                "Request a permit"
   │                          │
   ▼                          ▼
.close              ShieldActionExtension
                              │
                    ┌─────────┴──────────┐
              iOS 26.5+              below 26.5
                    │                     │
       .openParentalControlsApp    local notification
                    │                  (user taps)
                    └─────────┬──────────┘
                              ▼
                    Insta_killer foregrounds → THE GATE
                              │
                     4s pause, declaration shown,
                     typed reason ≥ 12 chars (FR-13, FR-14)
                              │
                       quota check (pure Dart)
                              │
                    ┌─────────┴─────────┐
                 refused              granted
                    │                    │
              next reset time      store.isActive = false
                                   DeviceActivitySchedule(15 min)
                                          │
                                   user taps Instagram again ← friction, kept on purpose
                                          │
                              intervalWillEndWarning / intervalDidEnd
                                          │
                                   store.isActive = true
```

The relaunch step is not a workaround for a missing API. We cannot foreground Instagram
after granting, and we would not want to: making the user tap again is the last cheap
moment of intent in the sequence.

## Layers

```
┌──────────────── Flutter (Riverpod) ────────────────┐
│ Gate · Front Desk · Permit pad · Blocklist ·       │
│ Hours · VIPs · The Record · Office Rules           │
│                                                    │
│ domain/ — pure Dart, no platform imports (NFR-6)   │
│   quota · streaks · schedule resolution · cooldown │
└──────────────────────▲ Pigeon ▼────────────────────┘
┌──────────────────────┴─────────────────────────────┐
│ iOS Runner (Swift)                                 │
│  FamilyControls auth · picker as a platform view   │
│  ManagedSettingsStore · DeviceActivityCenter       │
└────────────────── App Group ───────────────────────┘
         │                │                 │
   ShieldConfig      ShieldAction      DeviceActivity
   (copy only)      (grant / close)      Monitor
                                       (re-shield)
```

**The rule for extensions:** they read state and append events. They compute nothing that
the app could have computed for them. The one unavoidable exception is the shield action
extension's permit decision, which is reduced to comparing two integers the app wrote
(see D-002) and fails closed when they are stale.

## Shared state

`group.com.aadarsh.instakiller`

| What | Where | Written by |
|---|---|---|
| Encoded `FamilyActivitySelection` | `UserDefaults` | app |
| Shield copy (4 strings) | `UserDefaults` | app |
| Active grant, quota remaining, day boundary | `UserDefaults` | app; read by ShieldAction |
| Append-only event log | SQLite, WAL | app + all extensions |

Reconciliation runs on every `didBecomeActive` and always resolves disagreement toward
*more* restriction (NFR-2).

## Known open questions

Tracked in `P0_SPIKE.md` and unresolved until the device reports:

1. Whether a Shortcuts "App Opened" automation fires at all while an app is shielded.
2. Whether `.openParentalControlsApp` survives a cold launch fast enough for NFR-1.
3. Whether `ApplicationToken` expiry (`ManagedSettingsStore.TokenExpiryMessage`, iOS 26.5)
   is a real operational concern over weeks or a rare edge case. It is new enough that
   there is no field experience to draw on.
