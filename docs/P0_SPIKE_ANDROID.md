# P0 — Android feasibility spike

**Status: written, not compiled.** This environment blocks `dl.google.com`, so I could not
install the Android SDK or run a single Gradle build against it. The project is complete
and hand-checked, but treat the first build as part of the test — if something fails to
compile, send me the error rather than assuming the design is wrong.

Android exists in v1.0 because of D-007, and it is not the junior platform. It can do two
things iOS cannot do at all:

- **Interrupt the launch itself.** An `AccessibilityService` is told the instant Instagram
  reaches the foreground, and can put our own screen in front of it. This is much closer to
  the original *"kill Instagram whenever I open it"* than iOS's shield.
- **Read Instagram's notifications.** Which makes the VIP feature — the one thing that is
  permanently impossible on your iPhone (D-008) — a thirty-line service here.

It also carries none of the Family Controls entitlement risk. Nothing here needs Apple's
permission, or Meta's.

---

## Build it

**Target device: OnePlus 12R, Android 16 (OxygenOS 16).** `compileSdk`/`targetSdk` are set
to 36 to match. Two consequences of that pairing are already handled in the code and
explained below — read the OxygenOS section before you conclude anything is broken.

1. Open `android-spike/` in Android Studio. It may offer to upgrade AGP and Kotlin —
   accepting is fine.
2. Plug in the phone with USB debugging on, and Run.
3. There are **no dependencies at all** — no AndroidX, no Compose. If Gradle tries to
   resolve something beyond the Android plugin itself, something is wrong.

## Grant the two permissions

Both are deliberately awkward — Android makes them awkward because they are powerful, and
a blocker that could be turned off with one tap would be worthless anyway.

**Accessibility.** In the app, tap *Open accessibility settings* → Installed apps →
InstaKiller P0 → on.

> **Android 13+ will probably grey this out** with a "Restricted setting" message, because
> the app was sideloaded rather than installed from a store. Fix: Settings → Apps →
> InstaKiller P0 → ⋮ (top right) → **Allow restricted settings**, then go back. This is not
> a bug in the app and it will apply to the real build too — worth knowing now, because it
> is a step every future reinstall needs.

**Notification access.** Tap *Open notification access settings* → InstaKiller P0 → on →
confirm the warning dialog.

---

## Then fight OxygenOS, which is the real adversary here

OnePlus ships one of the most aggressive background-process killers of any Android OEM,
and this app is exactly the kind it kills: two long-lived services doing nothing visible
most of the time. Worse, **OxygenOS is known to silently revert battery-optimisation
exemptions after a day or two** unless the app is locked in Recents.

That matters more than it sounds. A blocker that dies quietly is worse than no blocker at
all — you would trust it, stop noticing, and it would simply have stopped working. Assume
this *will* happen and watch for it.

Do all four, in this order:

1. **Settings → Battery → Battery optimisation** → InstaKiller P0 → **Don't optimise**.
2. **Settings → Battery → More settings** → turn off **Deep Optimisation** and **Sleep
   Standby Optimisation**. The second one suspends network and background work overnight,
   which is precisely when a notification listener needs to be alive.
3. **Settings → Apps → InstaKiller P0 → Allow auto-launch** → on.
4. **Open Recents, pull down on the InstaKiller card, tap the padlock.** This is the step
   people skip, and it is the one that stops OxygenOS reverting step 1 on its own.

Re-check all four after any OxygenOS update — they get reset.

`dontkillmyapp.com/oneplus` is the community reference for this if the menu names have
moved in OxygenOS 16; the settings exist under some name regardless.

**During the spike, check the detection counter after a few hours of normal use.** If it
stops incrementing while blocking is still switched on, the services were killed, and P1
needs a watchdog — a periodic self-check that notices its own services are dead and tells
you loudly. That is a real feature we would have to build, not a settings problem.

---

---

## Verifying the merged app (do this now — the spike is superseded)

The enforcement services now live in the Flutter app, not in `android-spike/`. **The
merged build has never been compiled**, so treat the first run as the real test.

```
flutter run --release        # from the repo root, phone attached
```

Permissions are the same three as the spike, plus one that is new:

1. Accessibility → InstaKiller → on (plus the **Allow restricted settings** dance).
2. Notification access → on.
3. The four OxygenOS battery steps above, including the padlock in Recents.
4. **Notifications**: the app asks on first launch. Accept it, or FR-19's two-minute
   warning silently never arrives.

Then walk this path, which is the whole product in one pass:

- [ ] Open the app from the launcher → the **Front Desk** appears, not the Gate
- [ ] Front Desk says *"Nothing is being blocked"* in red at the bottom
- [ ] Tap **Office rules** → the permissions block shows accessibility and notification
      access as `granted`, and *Watcher last seen* reads something recent
- [ ] Tap **Start blocking** → it applies instantly and the notice says `Applied.`
      *(if the button is dead, the accessibility service is off — the screen says so and
      offers a route to Settings)*
- [ ] Open Instagram → the **Gate** appears, with the four-second ring counting down
- [ ] Both buttons are dead until the ring completes
- [ ] Swipe back during the pause → **nothing happens**
- [ ] Type fewer than 12 characters → *Request a permit* stays disabled
- [ ] Type a real reason → request → the Gate accepts and the app closes to home
- [ ] Open Instagram again → **it opens normally**, permit is running
- [ ] Front Desk shows a live `MM:SS` countdown in blue
- [ ] Wait for the two-minute warning notification
- [ ] Wait for expiry → notification, and Instagram is gated again on next open
- [ ] Issue three permits in one day → the fourth is refused with `Pad empty` and
      `Next issue 06:00`
- [ ] Reboot mid-permit → the permit is still running and still expires on time

And the asymmetry, which is the part most likely to feel wrong before it feels right:

- [ ] Office rules → **Fewer** permits → applies immediately
- [ ] **Request more** → nothing changes, a `CHANGE QUEUED` box appears counting down
      from 24:00:00
- [ ] **Cancel this change** → the box disappears, nothing was altered
- [ ] **Request blocking off** → still blocking, and a 24-hour countdown starts
      *(this is the one to be sure of: if blocking switches off immediately, Strict Mode
      has a hole straight through it)*

Report anything that deviates. The Dart side is covered by 141 tests; the Kotlin is not
covered by anything at all, so failures are far likelier to be on that side of the
bridge.

---

## The checklist

Screenshot the panel and fill in the blanks.

### Environment
- [ ] Panel reports Android 16 / API 36 and the OnePlus model
- [ ] "Instagram installed" shows ✅
      *(❌ while Instagram is clearly installed means the `<queries>` block in the manifest
      is not taking effect — a real Android 11+ trap, tell me and I will fix it)*
- [ ] Both permission rows show ✅
- [ ] All four OxygenOS steps above done, including the padlock in Recents

### Q1 — Detection
- [ ] Turn **Blocking ON**, leave the app, open Instagram
- [ ] Come back. Did the detection counter increase? `__________`
- [ ] What latency does the last-detection line report? `__________ ms`
      *(anything under ~300ms means the reflex is genuinely interrupted; over a second and
      the user sees their feed first, which defeats the point)*

### Q2 — The gate **← the one that matters**
- [ ] When you opened Instagram, did our gate appear over it? `__________`
- [ ] Did it appear **before** you could see any Instagram content, or after a flash of
      the feed? `__________`
- [ ] Does the 4-second countdown run, with both buttons disabled until it finishes?
- [ ] **Swipe back from the screen edge during the countdown.** Does it escape?
      `__________`
      *(it must not — FR-13 depends on this. Test the edge **swipe**, not a button: on
      Android 16 with targetSdk 36 predictive back is on by default, `onBackPressed()` is
      never called, and the gesture is the only back there is. This is handled with an
      `OnBackInvokedCallback`; if the swipe escapes, that registration is failing and I
      need to know)*
- [ ] Does a peek animation show Instagram behind the gate as you start the swipe?
      `__________`
      *(cosmetic, but it undercuts the whole screen — tell me and I will suppress it)*
- [ ] Swipe back **after** the countdown finishes. Do you land on the home screen?
      `__________`
- [ ] Press LEAVE after the countdown. Do you land on the home screen, not back in
      Instagram? `__________`
- [ ] Open Instagram again immediately. Does the gate appear a second time? `__________`
      *(debounce bug if it fires several times per open; broken if it fires zero times)*

### Q3 — The VIP probe
- [ ] Have someone DM you on Instagram, or DM yourself from a second account
- [ ] Does "Instagram notifications seen" increase? `__________`
- [ ] **Does the captured line show a usable sender name?** Paste it here, redacting
      whatever you like: `__________`

This last one decides whether the VIP feature is worth building at all. Instagram controls
the notification format and it varies:

| Notification | Typical title | Usable as a VIP filter? |
|---|---|---|
| Direct message | the sender's username | yes |
| Like / comment | "username liked your photo" | yes, with parsing |
| Grouped summary | "3 new messages" | no — we skip these |

If DMs arrive with the sender in the title, FR-31's per-handle rules work as specified. If
they arrive pre-grouped with no sender, the feature degrades to "Instagram wants you", and
I would argue for cutting it rather than shipping something that vague.

### Q5 — Survival **← run this one over days, not minutes**
This is the question OxygenOS makes interesting, and none of the others matter if it fails.
- [ ] Note the detection count now: `__________`
- [ ] Use the phone normally for a day or two, opening Instagram as you would anyway
- [ ] Detection count after: `__________` — still climbing?
- [ ] Did the gate ever *not* appear when you opened Instagram? `__________`
- [ ] Reboot the phone. Does the gate still appear afterwards, with no manual step?
      `__________`
- [ ] Re-check the four OxygenOS settings. Did any revert on their own? `__________`

If the answer to that last one is yes, we build the watchdog in P1 and the app tells you
when it has been muzzled. If the services survive untouched for a week, Android is the
more reliable of your two platforms and that changes which one we treat as primary.

### Q4 — The resistance ceiling
Worth knowing exactly how weak this is before we build strictness features on top of it.
- [ ] How many taps to disable the accessibility service from Settings? `__________`
- [ ] Does disabling it stop the gate immediately? `__________`

On Android there is no Screen Time passcode to hide behind. The realistic options for
FR-27/FR-28 are a `DeviceAdminReceiver` to block uninstall, or simply accepting that this
platform's ceiling is lower. We will decide that in P1, once you have seen how easy it is.

---

## Two design questions this spike should settle

**A. Gate, or bounce?**

`ForegroundWatcher` currently launches the gate. Commented out beside it is
`performGlobalAction(GLOBAL_ACTION_HOME)`, which throws the user straight to the home
screen with no screen at all — the closest thing on either platform to what you originally
asked for.

Try both if you can (it is a one-line swap). The brief argues for friction-with-a-reason,
and I think it is right, but the bounce is more honest about the goal and you are the one
who has to live with it.

**B. Should Android use the shield metaphor at all?**

The Permit Office design and the whole permit model were shaped by iOS's constraints — the
15-minute floor exists because `DeviceActivity` says so, not because 15 minutes is the
right amount of time. Android has no such floor: a 3-minute permit is trivially
enforceable here with a handler and a timestamp.

I would still keep the two platforms behaving identically, because the point is the habit
and not the mechanism, and a user who learns that Android is more permissive will use
Android. But it is a real choice and it belongs to you, not to me. Flag it if you disagree
and I will let Android use its own floor.

---

## What failure means

| Failure | Consequence |
|---|---|
| Gate appears after a visible flash of the feed | Detection is too slow. Fall back to also polling `UsageStatsManager`, or accept the flash. |
| Gate never appears, service is connected | Background activity launch is being refused. Next remedy is `SYSTEM_ALERT_WINDOW` (which exempts us) or an overlay window instead of an Activity. |
| Gate appears 3–4 times per open | Debounce window too short. One-line fix, tell me the count. |
| Notification titles have no sender | VIP feature is not viable on Android either. That would make it not viable anywhere, and I would recommend cutting FR-31…FR-35 entirely rather than shipping a digest that pretends. |
