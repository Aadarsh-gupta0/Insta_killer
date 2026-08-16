# What Insta_killer cannot do

Plain language. No hedging. This file ships with the build and is linked from Settings.

Last verified: **12 August 2026**.

> **The app currently ships on Android only** (D-012). The iOS sections below are kept
> because they are accurate and because resuming is a decision away — but nothing on
> iPhone is being built right now. If you are reading this as a user of the Android
> build, the sections that apply to you are *"On Android, your phone may switch the
> block off without telling you"* and *"The block is only as strong as your ability to
> delete this app"*.

---

## The big one: this app cannot close Instagram

iOS gives no app the ability to quit another app. There is no public API, and no
private API that would survive review or a device restart.

What actually happens is different and worth understanding: we ask iOS to **refuse to
open** the apps you picked. iOS then draws its own block screen — a *shield* — in
place of the app. Instagram never gets to the foreground. The effect you wanted is
achieved, but by a different mechanism than "killing" it, and that difference shows up
in a few places below.

## We cannot tell that the app you blocked is Instagram

When you pick apps, iOS hands us an opaque `ApplicationToken`. It is deliberately
unreadable. We cannot learn the app's name, its bundle ID, or its icon. We cannot
verify you actually picked Instagram, and we cannot pre-select it for you.

Consequences you will see in the UI:

- Onboarding has to *tell* you to pick Instagram and trust that you did.
- The Blocklist screen can show a count ("3 apps blocked") in normal text, but the
  names and icons can only be drawn by a small native view that Apple provides. That
  is why that part of the screen looks slightly different from the rest of the app.
- This is a privacy protection, not a bug.

**Tokens can also expire.** As of iOS 26.5 Apple posts a notification when the tokens
in our store go stale, and we have to refresh them. If that ever fails silently, a
block could stop applying. We check for this on every foreground.

## We cannot see anything you do inside Instagram

No screen reading, no content access, no history. The app has no idea whether you
scrolled for the full 15 minutes or opened it and closed it immediately.

## On iPhone, we cannot read Instagram's notifications. On Android, we can.

This is the one place where the two versions of this app are genuinely unequal, and it is
worth being blunt about it.

**iPhone.** iOS has no notification-listener API of any kind. "Tell me when a specific
person messages me" cannot be done by watching notifications, and no amount of engineering
changes that. The only legitimate route is Meta's official API, which requires your
Instagram account to be a **Professional/Business** account, plus a Meta developer app,
plus Meta's App Review approval, plus a backend of ours.

Your account is personal and staying personal, so **on iPhone the VIP feature is a digest
reminder, permanently.** It notes what you said you were going for when you open a VIP
check, and reminds you of it. It does not watch anything. The screen says `Digest only`
and will never say anything else on this device.

**Android.** `NotificationListenerService` lets us read Instagram's notifications on the
phone, including who they are from. Per-person VIP alerts work there for real, with no
Meta API, no backend, no App Review and no account conversion. This is the feature you
originally asked for, and it exists on exactly one of your two phones.

We will never ask for your Instagram password, never scrape the site, and never
automate a logged-in session, on either platform. Those break Meta's terms and put your
account at risk.

## The shortest enforced block is 15 minutes

`DeviceActivity`, the framework that re-applies the block on a timer, has a documented
**minimum interval of 15 minutes**. Anything shorter is rejected or unreliable.

We work around it where it matters: a schedule's `warningTime` gives us a callback
*before* the interval ends, so a shorter-feeling grant is possible — but it is built on
a 15-minute schedule underneath, and if the callback is late the block comes back late.
A 3-minute permit is therefore *approximately* 3 minutes, not exactly.

## On Android, your phone may switch the block off without telling you

This one is specific to the OnePlus and it is the most likely way the Android version
fails you.

On iPhone, the block is enforced by iOS itself. Our app can be closed, killed, or never
opened for a month, and Instagram stays blocked. On Android there is no such system — **the
block is our app running.** If OxygenOS decides to kill our background services to save
battery, the block stops, and nothing on screen tells you.

OnePlus is unusually aggressive about this, and is known to quietly undo the
"don't optimise this app" setting days after you grant it. So we do two things:

- Onboarding walks you through four settings, including locking the app in the Recents
  list, which is the step that stops the others being reverted.
- The app watches its own pulse. If the enforcement services have been dead, the Front
  Desk says so in red and names the setting to check. It will not show you a clean streak
  it did not earn.

Re-check those settings after any OxygenOS update. They get reset.

## What the Guardian actually protects against

If you pair a Guardian, loosening any rule needs both the 24-hour wait and a six-digit
code only they can produce. That is real friction and it works on the person it is meant
to work on — you, later, wanting the quota raised now.

It is not proof against you specifically, and it would be dishonest to say otherwise.
Both phones hold the same shared code, because your phone has to check their answer and
cannot do that without it. Somebody willing to root the phone and read the app's storage
could pull it out and generate their own approvals. That takes deliberate effort with
developer tools — which is exactly the kind of effort a weak moment does not involve — but
it is possible, and you should know it is.

Which is why the app makes them prove it. Pairing is not complete until their phone
answers a challenge correctly — so "I sent them the code" is never taken on trust, and a
Guardian who never installed the app is caught at pairing rather than a day into a
cooldown.

Two other things worth knowing:

- **The Guardian needs this app on their phone** to work out the codes. They need no
  account and nothing is sent anywhere, but they do need the app.
- **Delete your copy of the shared code once they have it.** If you keep it, you can
  answer your own requests. The app hides the Guardian tools on a phone that already has
  a Guardian, which stops the easy version, but a code sitting in your own messages is
  still a code you can use.
- **If they vanish, you are not trapped.** Removing a Guardian needs their approval like
  any other loosening, so a Guardian who loses their phone or stops replying could
  otherwise lock your settings forever. An unapproved removal therefore goes through on
  its own after seven days. Nothing else does.

## The block is only as strong as your ability to delete this app

Deleting Insta_killer removes its shields. There is no way around that. Anything we
build on top is friction, not a lock.

Real strength, weakest to strongest:

1. **Strict Mode + cooldowns** — loosening any setting waits 24 hours. Stops an impulse,
   not a plan.
2. **Guardian pairing** — a friend holds the code you need to loosen settings. Stops a
   plan, if the friend holds the line.
3. **Screen Time passcode set by someone else** — with *Content & Privacy Restrictions →
   Deleting Apps → Don't Allow*, you cannot delete this app without their passcode. This
   is the first option that is actually a lock.
4. **A supervised device** with a configuration profile. Strongest, most annoying to set
   up, and hard to undo on purpose.

We will tell you which of these you have active. We will not call the app "unbreakable"
at any tier.

## The Gate screen depends on things outside our control

The elaborate friction screen — breathing beat, your own declaration, the permit pad —
runs inside our app, and our app has to be brought to the foreground for you to see it.

There are two ways that happens, and both have caveats:

- **From the shield's button.** iOS 26.5 added a way for the block screen's button to
  open our app directly. **Your phone is on 26.4.1, so this does not exist for you yet.**
  The fallback is a notification you have to tap, which can be delayed by a Focus mode or
  by Apple Intelligence's notification summaries. Updating to iOS 26.5 or later would make
  this route reliable and is the single highest-value thing you could do to strengthen the
  app — but it is not required, and nothing is broken without it.
- **From a Shortcuts automation** you create during onboarding. This works on any
  version, but you can delete the automation. We check weekly that it still exists and
  say so if it doesn't. On 26.4.1 this is the *primary* route, not a backup.

One consequence we have not yet been able to test: it is not documented whether an "App
Opened" automation fires at all while an app is shielded. If it does not, then on 26.4.1
the Gate screen can only appear when enforcement is off. That would not weaken the block —
it would mean the elaborate friction screen and the hard block are alternatives rather than
a sequence. We will know after the first device test.

## Distribution

Blocking apps requires Apple's `com.apple.developer.family-controls` entitlement. A paid
developer account can use it for **development builds on your own device** immediately.
Putting it on the App Store requires a **separate written request to Apple** that can be
declined. Until then this is a personal build that has to be re-installed periodically as
the provisioning profile expires.

## Clock changes

Moving the device clock backwards could, naively, extend an active permit forever. We
store deadlines against a monotonic clock as well as wall time and always resolve a
disagreement toward *more* restriction. Expect an occasional permit that ends slightly
early after a timezone change. That is deliberate.
