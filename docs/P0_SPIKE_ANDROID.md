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

1. Open `android-spike/` in Android Studio. It will offer to upgrade AGP and Kotlin —
   accept. If it does, also bump `compileSdk`/`targetSdk` from 35 to 36 in
   `app/build.gradle.kts`; compileSdk 36 needs AGP 8.9+.
2. Plug in the Android phone with USB debugging on, and Run.
3. There are **no dependencies at all** — no AndroidX, no Compose. If Gradle tries to
   resolve something beyond the Android plugin itself, something is wrong.

**Tell me the Android version and phone model** (Settings → About phone). Several
behaviours below fork on it, particularly the Restricted Settings step, and I have written
against API 29–35 without knowing which you have.

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

## The checklist

Screenshot the panel and fill in the blanks.

### Environment
- [ ] Android version and model: `__________`
- [ ] "Instagram installed" shows ✅
      *(❌ while Instagram is clearly installed means the `<queries>` block in the manifest
      is not taking effect — a real Android 11+ trap, tell me and I will fix it)*
- [ ] Both permission rows show ✅

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
- [ ] Press the system Back button during the countdown. Does it escape? `__________`
      *(it should not — FR-13 depends on this)*
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
