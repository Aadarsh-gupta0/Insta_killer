# Decision log

One entry per architectural choice. Each records what was chosen, what was rejected, and
why. Newest first.

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
