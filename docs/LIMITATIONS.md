# What Insta_killer cannot do

Plain language. No hedging. This file ships with the build and is linked from Settings.

Last verified against Apple documentation: **12 August 2026**.

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

## We cannot read Instagram's notifications

iOS has no notification-listener API. Android has one; iOS does not, and it is not
close to shipping. So "tell me when a specific person messages me" cannot be done by
watching notifications on this phone.

The only legitimate route is Meta's official API, which requires:

- your Instagram account converted to a **Professional/Business** account,
- a Meta developer app,
- Meta's App Review approval for messaging permissions,
- and a small backend of ours to receive the webhooks and forward a push.

Until all four exist, the VIP feature runs in **Digest** mode and says so on screen. It
will never pretend to be watching something it isn't.

We will never ask for your Instagram password, never scrape the site, and never
automate a logged-in session. Those break Meta's terms and put your account at risk.

## The shortest enforced block is 15 minutes

`DeviceActivity`, the framework that re-applies the block on a timer, has a documented
**minimum interval of 15 minutes**. Anything shorter is rejected or unreliable.

We work around it where it matters: a schedule's `warningTime` gives us a callback
*before* the interval ends, so a shorter-feeling grant is possible — but it is built on
a 15-minute schedule underneath, and if the callback is late the block comes back late.
A 3-minute permit is therefore *approximately* 3 minutes, not exactly.

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
  open our app directly. On iOS 26.5 and later this is reliable. **On anything earlier
  it does not exist**, and the fallback is a notification you have to tap.
- **From a Shortcuts automation** you create during onboarding. This works on any
  version, but you can delete the automation. We check weekly that it still exists and
  say so if it doesn't.

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
