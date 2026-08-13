package com.aadarsh.insta_killer

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * The enforcement core.
 *
 * Told the instant Instagram reaches the foreground, it puts our Gate in front of it.
 * This is the thing iOS cannot do at all — there, the OS draws a shield we barely control
 * and cannot route into our own UI without a Shortcuts automation the user can delete.
 *
 * Why an AccessibilityService rather than polling `UsageStatsManager`:
 *  - event-driven, so detection is immediate rather than up to a poll interval late
 *  - no wakelock, no foreground service, no battery cost from a 500ms loop
 *  - and critically, accessibility services are exempt from the background-activity-launch
 *    restrictions tightened since Android 10. A plain foreground service can no longer
 *    reliably `startActivity` from the background; this can.
 *
 * It decides nothing. Two booleans from [OfficeStore] tell it whether to act; everything
 * else — quota, schedule, whether a permit may be issued — is Dart's.
 */
class ForegroundWatcher : AccessibilityService() {

    companion object {
        private const val TAG = "ForegroundWatcher"

        /**
         * Instagram fires several `typeWindowStateChanged` events while it starts. Without
         * this the Gate launches three or four times per open, and `singleTop` alone does
         * not save us because each launch re-runs the four-second pause.
         */
        private const val DEBOUNCE_MS = 1500L
    }

    private var lastTriggerAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        OfficeStore(this).watcherHeartbeat = System.currentTimeMillis()
        Log.d(TAG, "Connected. Watching ${OfficeStore.INSTAGRAM} only.")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val packageName = event?.packageName?.toString() ?: return
        if (packageName != OfficeStore.INSTAGRAM) return

        val store = OfficeStore(this)

        // Proof of life for the watchdog, written before any early return — a watcher
        // that is alive but not acting must not look dead.
        store.watcherHeartbeat = System.currentTimeMillis()

        val now = SystemClock.elapsedRealtime()
        if (now - lastTriggerAt < DEBOUNCE_MS) return
        lastTriggerAt = now

        if (!store.blockingEnabled) return

        // A permit is running. Checked here rather than trusting an alarm to have
        // switched blocking back on, because a dropped alarm would otherwise mean
        // Instagram stays open forever.
        if (store.grantIsRunning()) return

        startActivity(
            Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION
                )
                putExtra(MainActivity.EXTRA_LAUNCH_REASON, MainActivity.REASON_GATE)
            }
        )
    }

    override fun onInterrupt() = Unit
}
