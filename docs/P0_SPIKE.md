# P0 — feasibility spike

**Status: written, not run.** I built this in a Linux container with no macOS, no Xcode
and no iOS device attached. Family Controls cannot be exercised anywhere except a real
iPhone, so P0 has to be run by you. Everything below is written so that it is 20 minutes
of clicking, not a debugging session.

P0 answers four questions and stops. Do not build anything else until it has.

| # | Question | Why the project dies without it |
|---|---|---|
| 1 | Does `requestAuthorization(for: .individual)` succeed on your device? | No authorization, no blocking. Everything becomes Gate-only mode (FR-2). |
| 2 | Does the picker return tokens we can persist and reload? | No tokens, no target. |
| 3 | Does assigning those tokens actually stop Instagram opening? | This is the entire product. |
| 4 | Does the shield's button reach our app on your iOS version? | Decides whether the Gate needs a Shortcuts automation at all. See D-004. |

---

## Set-up in Xcode

Create the project by hand. I have deliberately not generated an `.xcodeproj` — it is a
large file of opaque UUIDs, I cannot compile-check it from here, and a subtly corrupt one
would cost you more time than building it yourself. Every step below is in Xcode's
Signing & Capabilities UI anyway, because entitlements have to round-trip through your
developer account to become a provisioning profile.

**1. New project** → iOS → App. Name `InstaKillerSpike`, interface SwiftUI, language
Swift. Set the bundle ID to something you own, e.g. `com.aadarsh.instakillerspike`.
Set the deployment target to **iOS 26.0**.

**2. Add two extension targets** (File → New → Target):

| Target | Template | Bundle ID |
|---|---|---|
| `ShieldConfigurationExtension` | Shield Configuration Extension | `…instakillerspike.shieldconfig` |
| `ShieldActionExtension` | Shield Action Extension | `…instakillerspike.shieldaction` |

If those templates are missing from the list, you are on an Xcode too old for this —
check Xcode 26 is the selected toolchain.

**3. Capabilities — on all three targets**, not just the app:

- **Family Controls**
- **App Groups** → `group.com.aadarsh.instakiller`

The extensions missing either capability is the single most common way this spike fails,
and it fails *silently*: you get iOS's default grey shield instead of ours, and the
secondary button does nothing at all. `ios-spike/Entitlements/*.entitlements` shows what
the resulting files must contain — compare against them if something misbehaves.

**4. Add the source files.** Drag in from `ios-spike/`, with target membership as follows —
`SharedStore.swift` belongs to **all three**:

| File | App | ShieldConfig | ShieldAction |
|---|:-:|:-:|:-:|
| `InstaKillerSpike/SharedStore.swift` | ✅ | ✅ | ✅ |
| `InstaKillerSpike/ShieldController.swift` | ✅ | | |
| `InstaKillerSpike/InstaKillerSpikeApp.swift` | ✅ | | |
| `InstaKillerSpike/SpikeView.swift` | ✅ | | |
| `ShieldConfigurationExtension/…swift` | | ✅ | |
| `ShieldActionExtension/…swift` | | | ✅ |

Delete the placeholder Swift files the extension templates generated, and make sure each
extension's `Info.plist` still names *your* class as `NSExtensionPrincipalClass`.

**5. Run on the physical iPhone.** Not the Simulator — Family Controls authorization
always fails there, which will look exactly like an entitlement problem and waste your
afternoon.

**6. Before first run**, on the device: Settings → Screen Time → turn on **App & Website
Activity** if it is off. Authorization fails without it.

---

## The checklist

Fill this in and send it back. The app's own screen mirrors these rows, so a screenshot
plus the two Instagram results is a complete report.

### Environment
- [ ] Exact iOS version (Settings → General → About → Software Version): `__________`
- [ ] App Group row shows ✅, not "NOT CONFIGURED"
- [ ] `.openParentalControlsApp` row shows available / unavailable: `__________`

### Q1 — Authorization
- [ ] "Request authorization" shows the system Screen Time prompt
- [ ] Status becomes `approved`
- [ ] If it failed, the error text: `__________`

### Q2 — Selection
- [ ] Picker presents
- [ ] Selecting Instagram makes the Apps count ≥ 1
- [ ] Instagram's real name and icon render in the `Label(token)` row *(confirms C-3: iOS
      draws it, we cannot)*
- [ ] Force-quit the spike, reopen it — the counts are still there *(FR-3 persistence)*

### Q3 — The shield **← this is the one that matters**
- [ ] Tap "Apply shield", then leave the app and tap Instagram
- [ ] **Instagram does not open.** What appears instead: `__________`
- [ ] Is it our shield (pale green background, our title text) or iOS's default grey one?
      `__________`
      *(default grey = the ShieldConfiguration extension is not loading — almost always a
      missing capability on that target)*
- [ ] Reboot the phone, tap Instagram again — still blocked? `__________` *(NFR-2)*

### Q4 — The button
- [ ] Both buttons appear on the shield, with our labels
- [ ] Tap **"Request a permit"** (secondary). What happens: `__________`
  - App opens straight away → `.openParentalControlsApp` works, **D-004 confirmed**
  - A notification appears → you are below 26.5, notification fallback in play
  - Nothing → report it, this is the interesting failure
- [ ] Reopen the spike. Does section 4 show a `secondaryButtonPressed` line? `__________`
      *(proves the action extension ran and the App Group is genuinely shared)*
- [ ] Tap "Lift (simulate a permit)", then tap Instagram — does it open now? `__________`

---

## Two things I could not determine from the documentation

Both are empirical and both change the design. Please answer them while you are in there.

**A. Does a Shortcuts "App Opened" automation fire while the app is shielded?**

Create one: Shortcuts → Automation → App → Instagram → *Is Opened* → Run Immediately,
Notify When Run **off** → action *Open App* → `InstaKillerSpike`. Then tap Instagram with
the shield **on**.

Three possible outcomes, all of them useful:
- the automation fires and our app opens *instead of* the shield — Path B wins outright
- the shield appears and the automation does not fire — Shortcuts is useless as a backstop
  while shielded, and is only a fallback for iOS < 26.5
- both happen, in some order — we have a race and must de-duplicate the attempt log

Apple documents neither the ordering nor the interaction. Nobody's blog post I would trust
covers iOS 26 either.

**B. Does `.openParentalControlsApp` bring us to the foreground cold, or only when warm?**

Force-quit the spike from the app switcher first, then tap Instagram → "Request a permit".
If a cold launch works, NFR-1's "Gate interactive ≤ 400 ms" is the binding constraint and
we will have to render the Gate's first frame natively before Flutter attaches. Time it
roughly — "instant", "a beat", or "a visible pause" is precise enough.

---

## What P0 failing means

Not the end. The outcomes and their consequences:

| Failure | Consequence |
|---|---|
| Authorization denied / entitlement unavailable | Gate-only mode (FR-2). Shortcuts automation is the whole product, bypassable but real. Still worth building. |
| Shield applies but does not survive reboot | Re-apply on launch and on `DeviceActivity` interval start. Annoying, not fatal. |
| Our shield never replaces the default grey one | Extension config problem, not an architecture problem. The block still works. |
| Secondary button does nothing on 26.5+ | Fall back to the notification rung and re-open D-004. |

Report back before P1. I will not write the enforcement core until I know which of these
we are living in.
