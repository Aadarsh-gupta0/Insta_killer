# Decision log

One entry per architectural choice. Each records what was chosen, what was rejected, and
why. Newest first.

---

## 2026-08-13 — D-014: Any app, not just Instagram

**Chosen:** the user picks the blocked apps from a list of everything launchable on the
device. `OfficeRules.blockedPackages` holds the set; the accessibility service re-scopes
itself to exactly that set at runtime.

**Rejected:** keeping Instagram hardcoded, which is what the spike did and what four
separate places still assumed — the manifest `<queries>`, the accessibility config's
`packageNames`, `OfficeStore.INSTAGRAM`, and the watcher's package comparison.

**Why:** the owner asked for it, and the product was always weaker without it. The habit
is the reflex open, not Instagram specifically; a user who blocks Instagram and then
reaches for the next infinite feed has been helped with the symptom and not the problem.

**How the empty case is handled, and why it matters:** an accessibility service with
`packageNames = null` observes *every app the user opens*. That is the natural
representation of "nothing selected" and it is exactly wrong — it would quietly widen our
observation at the moment the user has asked for the least. The empty set is therefore
stored as one impossible package name instead, so "nothing blocked" means the service sees
nothing at all.

**On the cooldown:** the blocklist is compared as a *set*, not a count. Swapping one app
for another leaves the count identical while freeing an app that was blocked a moment
before, and counting would have called that neutral. It is a loosening and it waits.

**What Android gives us here that iOS never could:** package names are readable. The iOS
design is built around `ApplicationToken`s being deliberately opaque (C-3) — that build
can only ever say "3 apps blocked" and can never confirm the user picked what they meant
to. Here the Blocklist shows names and icons, and the Gate can name the app it just turned
away. If iOS resumes, this screen has no equivalent there and the difference should be
stated in onboarding rather than papered over.

**Cost:** `<queries>` now declares the MAIN/LAUNCHER intent, so we can see every launchable
package. That is broader than one hardcoded package and narrower than `QUERY_ALL_PACKAGES`,
which is both more access than the feature needs and a Play policy problem if this is ever
distributed.

---

## 2026-08-13 — D-013: Native holds two numbers; everything else crosses as opaque JSON

**Chosen:** the Pigeon bridge exposes exactly two pieces of typed state that Kotlin acts
on — `blockingEnabled` and `grantEndsAt` — plus a `read`/`write` pair for JSON strings
Kotlin never parses. Rules, quota, schedule, event log and settings all live in
`packages/domain` and cross the bridge as text.

**Rejected:** a richer bridge with `permitsRemainingToday`, `isWithinSchedule` and the
day boundary exposed as typed fields, so the service could decide for itself whether to
show the Gate.

**Why:** the same argument as D-002, which the iOS design reached first. Every rule
duplicated into the native layer is a rule that can silently diverge from the tested one,
in a process with no debugger attached. Android makes this easier than iOS did — the
service does not need to decide anything, because unlike a shield extension it can simply
launch our UI and let Dart decide. So it gets told two things: whether to act at all, and
whether a permit is currently running.

Making the rest opaque is not cosmetic. A native service that *cannot read* the quota
cannot be tempted into checking it.

**The one asymmetry worth naming:** enforcement resumes by comparing `grantEndsAt`
against the clock on every accessibility event, not by an alarm switching blocking back
on. Alarms get dropped — by Doze, by OxygenOS, by a reboot — and a dropped alarm under
the alarm-driven design would mean Instagram stays open indefinitely. Under this one it
costs a notification. The alarms exist only for FR-19's warnings.

**Cost:** the event log is a JSON blob rewritten on every append, which is fine only
while Dart is the sole writer. The moment a service needs to append, this has to become
real storage — D-001's reasoning, which applies as soon as there are two writers.

---

## 2026-08-12 — D-012: iOS is paused; Android is the shipping platform

**Chosen:** all development continues on Android. The iOS spike, its Swift, and the
Screen Time findings stay in the repository untouched and unbuilt.

**Rejected:** deleting the iOS work, and continuing both in parallel as D-007 planned.

**Why:** the owner's call, and the evidence supports it. Android's spike works on the
device today; iOS's has never been compiled, needs an entitlement Apple can decline, and
on 26.4.1 depends on a Shortcuts automation whose behaviour under a shield is still
unverified (open question A, still unanswered). Meanwhile the feature the product was
originally asked for — *"tell me if there's important notifications from my favourite
persons"* — is Android-only and permanently unavailable on this iPhone (D-008). One
platform that does everything beats two that each do part of it.

**What this does not change:** the domain layer stays pure Dart with no platform imports
(D-011). It would be easy to argue that with one platform the abstraction is now dead
weight, and to start reaching into it from Flutter widgets. Don't. It costs nothing to
keep, it is the reason the rules are tested at all, and resuming iOS is a decision away.

**Resuming iOS:** `docs/P0_SPIKE.md` is still the entry point and still accurate. The
cheapest thing that would improve it is an update to iOS 26.5, which activates
`.openParentalControlsApp` and removes the Shortcuts dependency entirely (D-009).

---

## 2026-08-12 — D-011: The domain layer is a standalone package, not a folder in the app

**Chosen:** `packages/domain/` is its own pure-Dart package with its own `pubspec.yaml`
and no Flutter dependency. The Flutter app will depend on it by path.

**Rejected:** `lib/domain/` inside the Flutter app, as the kickoff brief's tree proposes.

**Why:** NFR-6 says the domain layer must be free of platform imports, and D-007 turned
that from a someday-maybe into a requirement with a date on it — two platforms are being
built at once and this is the only code they share. A folder convention is enforced by
review, and review is exactly what erodes at 1am when a Riverpod provider would be so
convenient to reach for. A separate package with no Flutter in its dependency graph makes
`import 'package:flutter/…'` fail to resolve. The rule enforces itself.

It also makes the rules testable without a device or a Flutter toolchain, which is how
102 tests and 93.5% line coverage exist before either spike has been compiled.

**Rejected also:** publishing it to pub.dev. No reason to; a path dependency is fine.

**Cost:** one more `pubspec.yaml`, and `flutter test` at the app level will not run these
tests — `dart test` in the package does. CI needs both.

**Dependency note** (the brief asks for these): one dev dependency, `test ^1.25.0`. Zero
runtime dependencies, and that is worth keeping — every runtime dependency here would be
one the Android and iOS builds both inherit.

---

## 2026-08-12 — D-010: OEM process death is an expected failure, and the app must announce it

**Context:** the Android device is a **OnePlus 12R on Android 16 / OxygenOS 16**. OnePlus
runs one of the most aggressive background-process killers of any OEM, and is documented as
*silently reverting* battery-optimisation exemptions days after the user grants them unless
the app is locked in the Recents list.

**Chosen:** treat the enforcement services dying as a normal operating condition rather
than an error. P1 adds a watchdog — a heartbeat the services write and the app checks —
and when the heartbeat is stale the app says so **on the Front Desk, in `stamp` red**,
naming the OxygenOS setting that most likely caused it.

**Rejected:** documenting the battery settings in onboarding and assuming they hold.

**Why:** a blocker that dies quietly is strictly worse than no blocker. The user stops
noticing the gate, concludes the habit is under control, and the app is now actively
lying by omission — it is displaying a streak it did not earn. NFR-7 makes honesty a
requirement, and the only way to be honest about this is to detect it. Onboarding
instructions cannot, because the setting reverts *after* onboarding.

**Cost:** a periodic check that itself has to survive, which is a little circular. The way
out is that the watchdog lives in the *app*, not the services: whenever the app is
foregrounded it compares the last heartbeat against the clock. That is enough — a user who
never opens the app also is not being lied to by it.

**Note:** this asymmetry is worth stating plainly. iOS shields are enforced by the OS and
survive our app being killed; Android's enforcement *is* our process, so it dies when the
OEM decides it dies. iOS is the more reliable enforcer even though Android is the more
capable platform. Q5 in `P0_SPIKE_ANDROID.md` measures how bad this actually is before we
build anything on the assumption.

---

## 2026-08-12 — D-009: Target device is iOS 26.4.1 — Shortcuts is the primary Gate route

**Context:** the iPhone is on **iOS 26.4.1**. That lands between the two APIs that matter:

| API | Needs | Available here |
|---|---|---|
| `ShieldConfiguration.secondaryButtonSubmenuItems` | 26.4 | ✅ |
| `ShieldActionResponse.openParentalControlsApp` | 26.5 | ❌ |
| `ManagedSettingsStore.isActive` | 26.5 | ❌ |
| `ManagedSettingsStore.TokenExpiryMessage` | 26.5 | ❌ |

**Chosen:** ship the brief's original two-path architecture. The shield enforces; the
Shortcuts automation is how the Gate gets on screen. Grants are applied by clearing and
restoring `shield.applications` (the D-003 fallback), with the token set mirrored in the
App Group so the monitor extension can always restore it.

**Rejected:** asking you to update to iOS 26.5 before we start.

**Why:** an OS upgrade is a real imposition and 26.5 is not required for a working
product — it is required for a *simpler* one. All the 26.5 code paths are already written
and version-gated, so if you update at any point the better architecture activates with no
work from me. That said, the difference is not cosmetic: on 26.5 the Gate is reachable
from the shield itself, which removes the single most fragile dependency in the product
(an automation you can delete, and which may not even fire while an app is shielded — see
open question A in `P0_SPIKE.md`). Worth doing when convenient. Your call, not a blocker.

**Immediate consequence:** open question A is no longer a curiosity, it is the load-bearing
unknown. If a Shortcuts "App Opened" automation does *not* fire while Instagram is
shielded, then on 26.4.1 there is **no route to the Gate at all** while enforcement is on,
and the Gate only ever appears in Gate-only mode with the shield disabled. Test it first.

**Silver lining:** 26.4's submenu means the secondary button can offer *three* actions
without a screen — "15-minute permit", "VIP check", "Not now" — which recovers some of
what the missing `.openParentalControlsApp` costs us, since a plain permit no longer needs
the Gate at all.

---

## 2026-08-12 — D-008: The VIP feature is an Android feature; iOS is capped at Digest

**Context:** the Instagram account is **personal**, and staying personal.

**Chosen:** iOS implements Rung 0 (Digest) only, permanently, and says so in the UI.
Android implements real per-sender VIP alerts with `NotificationListenerService`.

**Rejected:** keeping Rung 1 (Meta Graph API) on the iOS roadmap as "future work".

**Why:** Rung 1 is not merely unbuilt, it is *unreachable* without converting the account
to Professional — that is a hard Meta precondition, not a technical difficulty we could
engineer around. Leaving it on the roadmap would be dishonest about a capability that is
gated on a decision already made. FR-32's three states collapse to two on iOS: `Digest
only` and nothing else.

Android has no such gate. `NotificationListenerService` delivers Instagram's own
notifications with the sender in `EXTRA_TITLE`, which is precisely the per-handle filtering
FR-31 asks for, with no API, no backend, no App Review and no account conversion.

**Consequence:** the feature the user originally asked for — *"tell me if there's important
notifications from my favourite persons"* — is an Android-only capability. That is now one
of the stronger arguments for D-007, and it should be stated plainly in onboarding on both
platforms rather than buried.

**Cost:** the two platforms are genuinely unequal in a user-visible way. Do not paper over
it with shared UI copy.

---

## 2026-08-12 — D-007: iOS and Android built in parallel, sharing the Dart domain layer

**Chosen:** both platforms proceed together. `lib/domain/` stays free of platform imports
(NFR-6) and is the shared asset; everything below it is written twice, natively.

**Rejected:** the SRS's v1.0 = iOS-only scoping, with Android deferred to v2 (Appendix D).

**Why:** three reasons, in order of weight.

1. **Android is where the VIP feature can actually exist** (D-008). On iOS it is capped at
   a digest reminder forever.
2. **Android carries none of the entitlement risk.** R-1 — Family Controls entitlement not
   granted — is rated as making the enforcement core unshippable. Android needs no Apple
   approval, so a working blocker exists regardless of how R-1 resolves.
3. **Android can do the thing iOS refuses to.** An `AccessibilityService` can send
   Instagram to the background the instant it foregrounds. That is much closer to the
   original "kill Instagram when I open it" than iOS's shield, and it is fully supported.

**Cost:** two enforcement implementations to maintain, and a real risk of the platforms
drifting apart in behaviour. Mitigated by keeping every rule in Dart and treating the
native layers as dumb actuators — the same discipline as D-002, applied twice.

**Note on Play Store policy:** `AccessibilityService` and `NotificationListenerService`
both have restrictive Play policies for non-accessibility use. This build is sideloaded to
one phone, so neither applies. If distribution is ever considered, revisit — the policies
are the binding constraint, not the APIs.

---

## 2026-08-12 — D-006: P0 ships as a standalone native spike, not a Flutter app

**Chosen:** `ios-spike/` is a small pure-SwiftUI target with no Flutter in it at all.

**Rejected:** running `flutter create` first and doing the spike inside the Runner target.

**Why:** P0 answers exactly four questions — does the entitlement resolve, does
authorization succeed, does the picker return tokens, does the shield actually block. None
of them involve Dart. Putting Flutter underneath adds a build system, a plugin registrant
and a platform channel between us and the answer, and every one of those is a place a
failure can hide. When P0 passes, the same Swift files move into `ios/Runner` and
`ios/*Extension` essentially unchanged, because they are already written against the App
Group rather than against the app.

**Cost:** the spike's Xcode project is throwaway. Accepted — it is ~20 minutes of GUI work.

---

## 2026-08-12 — D-005: Sub-15-minute grants are implemented with `warningTime`, not banned

**Chosen:** every grant is backed by a `DeviceActivitySchedule` of at least 15 minutes.
Grants shorter than that set `warningTime` so `intervalWillEndWarning(for:)` fires early,
and we re-shield in that callback.

**Rejected:** the kickoff brief's rule "do not offer 5-minute grants, they will silently
fail", and its Rung-0 proposal of an in-app timer plus reconciliation on next foreground.

**Why:** `DeviceActivitySchedule.init(intervalStart:intervalEnd:repeats:warningTime:)`
exists precisely for this, and Apple's own `startMonitoring` documentation recommends it
as the fix for tightly-scheduled activities: *"To avoid errors, reduce the number of
unique, tightly-scheduled activities. For example, consider using the `warningTime`
property of an activity's schedule."* The in-app-timer alternative is not merely weaker,
it is unsound: if the user never returns to our app, the un-shield never gets reversed and
a 3-minute grant becomes unlimited. That is the exact failure the product exists to
prevent.

**Cost:** the early callback is best-effort, so a short grant is approximate. The 15-minute
schedule still runs underneath as a backstop, so the worst case is that the block returns
late, never that it fails to return. Documented in LIMITATIONS.md.

---

## 2026-08-12 — D-004: The shield button opens our app directly on iOS 26.5+; Shortcuts is the fallback

> **Superseded in part on 2026-08-12 by D-009.** The device is on iOS 26.4.1, so
> `.openParentalControlsApp` is *not* available and Shortcuts remains the primary route to
> the Gate. The code path stays — it is version-gated and costs nothing — but the
> architecture ships on the fallback. Read D-009 with this entry.

**Chosen:** `ShieldActionExtension` returns `.openParentalControlsApp` where available,
falling back to a tapped local notification, falling back to `.close` plus the Shortcuts
automation.

**Rejected:** the kickoff brief's Path A / Path B split, which treats "a shield button
cannot launch our app" as a fixed constraint and makes the user-created Shortcuts
automation the *only* route to the Gate screen.

**Why:** that constraint was true when the brief was written and is no longer true.
`ShieldActionResponse.openParentalControlsApp` was introduced in **iOS 26.5** and does
exactly what the brief says is impossible. This matters more than any other finding in the
spike, because the brief calls the Path A/B split "the single most important design
decision in the project" and builds the whole gate architecture on it. With 26.5 the two
paths collapse into one: the shield blocks, its button opens our Gate, the Gate issues the
permit, the permit lifts the shield.

Shortcuts stays, demoted from primary mechanism to redundancy — it is the only route on
iOS < 26.5, and it still fires in cases the shield does not (see the open question in
`P0_SPIKE.md` about whether an App Opened automation fires at all while an app is
shielded).

**Cost:** a version fork in the extension, and a real dependency on the user's iOS being
26.5+ for the good path. Confirm the device's exact version before committing to it.

---

## 2026-08-12 — D-003: One named `ManagedSettingsStore`, toggled with `isActive`

**Chosen:** a single store, `ManagedSettingsStore(named: .instaKiller)`. Granting a permit
sets `store.isActive = false` on iOS 26.5+; expiry sets it back to `true`.

**Rejected:** clearing `store.shield.applications = nil` on grant and re-assigning the
token set on expiry.

**Why:** the assign/clear approach makes the token set itself the mutable state, so an
extension that is killed mid-write can leave us with no record of what to restore. With
`isActive` the token set is written once and never touched during normal operation; the
grant is a single boolean. Recovery after a crash is "set isActive = true", which is safe
to run any number of times.

**Cost:** `isActive` is iOS 26.5+. Below that we fall back to assign/clear, with the token
set mirrored in the App Group so the monitor extension can always restore it.

---

## 2026-08-12 — D-002: App Group is the only shared state; extensions hold no rules

**Chosen:** `group.com.aadarsh.instakiller` holds the encoded `FamilyActivitySelection`,
the active grant, quota and shield copy in `UserDefaults`, plus an append-only SQLite
event log. The three extensions read policy and append events. They decide nothing.

**Rejected:** duplicating quota logic into `ShieldActionExtension` so it can refuse a
permit without the app.

**Why:** NFR-5 requires the rules to live in testable Dart. Every rule copied into an
extension is a rule that can silently diverge, in a process with a hard memory ceiling and
no debugger attached. The one exception is unavoidable: the shield action extension must
decide *on its own* whether a permit may be issued, because the app is not running. That
decision is reduced to reading two integers written by the app (`permitsRemainingToday`,
`blockedUntilEpochMs`) and comparing them — no date maths, no schedule resolution.

**Cost:** if the app has not run since the day boundary, those two integers are stale. The
extension therefore fails *closed*: a stale quota is treated as exhausted.

---

## 2026-08-12 — D-001: SQLite in WAL mode for the event log, not a `UserDefaults` array

**Chosen:** shared SQLite file in the App Group container, WAL enabled.

**Rejected:** appending to an array in the shared `UserDefaults`.

**Why:** up to four processes (app + three extensions) can append concurrently. Shared
`UserDefaults` has no atomic append; read-modify-write from two extensions loses events,
and a blocked-attempt count that undercounts is precisely the number the product is
judged on. WAL lets the extensions append while the app reads.

**Cost:** WAL writes a `-wal` sidecar file that must live in the same App Group directory,
and the extensions need write access to it. Verified in P1, not P0.
