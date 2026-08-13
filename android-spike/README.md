# android-spike — superseded, kept on purpose

**This is no longer the code that runs.** `ForegroundWatcher` and `NotificationProbe` now
live in the Flutter app at `android/app/src/main/kotlin/com/aadarsh/insta_killer/`, wired
to the Dart rules through a Pigeon bridge.

It is still here for one reason: **this version has been verified on the device and the
merged version has not.** Nothing in this repository has ever been compiled for Android —
the build environment has no SDK — so until the real app runs on the OnePlus, the spike is
the only known-good reference for what the enforcement path looks like when it works.

Delete this directory once the merged build has been confirmed working on device. Until
then, if the app misbehaves, this is what to diff against.

## What changed in the move

| | Spike | App |
|---|---|---|
| Gate screen | throwaway `GateActivity`, programmatic views | the real Flutter Gate — 4s pause, declaration, reason field |
| Decisions | none; it always showed the gate | quota, schedule and Strict Mode, all in `packages/domain` |
| Permit | not implemented | `grantEndsAt` timestamp the watcher checks on every event |
| Notification data | stored a single sample string | capped JSON array, read by Dart |
| Back gesture | handled in `GateActivity` | handled once in `MainActivity` |

The debounce, the `packageNames` scoping, the accessibility config and the
`ComponentName` comparison all came across unchanged — those were the parts the device
test actually exercised.
