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
         * The connected instance, so the app can re-scope the watch list the moment the
         * user edits the Blocklist rather than at the next service restart.
         *
         * A static reference to a Service is normally a leak; this one is cleared in
         * [onUnbind] and [onDestroy], and the service is a singleton the system owns for
         * as long as the permission is granted.
         */
        @Volatile
        var instance: ForegroundWatcher? = null
            private set

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
        instance = this
        OfficeStore(this).watcherHeartbeat = System.currentTimeMillis()
        applyWatchList()
    }

    /**
     * Narrows the service to exactly the packages the user picked.
     *
     * The manifest's `packageNames` is only a starting value; this is the real one. An
     * empty selection is left as a single impossible package name rather than null,
     * because null means *every app on the device* — the opposite of what "nothing is
     * blocked" should do, and a privacy promise we have no reason to break.
     */
    fun applyWatchList() {
        val watched = OfficeStore(this).watchedPackages
        serviceInfo = serviceInfo?.apply {
            packageNames = if (watched.isEmpty()) {
                arrayOf("com.aadarsh.insta_killer.none")
            } else {
                watched.toTypedArray()
            }
        }
        Log.d(TAG, "Watching ${watched.size} package(s)")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val packageName = event?.packageName?.toString() ?: return

        val store = OfficeStore(this)

        // Proof of life for the watchdog, written before any early return — a watcher
        // that is alive but not acting must not look dead.
        store.watcherHeartbeat = System.currentTimeMillis()

        // Belt and braces: serviceInfo already filters to the watched set, but a filter
        // that has not been re-applied since an edit would otherwise gate an app the user
        // just unblocked.
        if (packageName !in store.watchedPackages) return

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
                // So the Gate can name the app it just turned away.
                putExtra(MainActivity.EXTRA_BLOCKED_PACKAGE, packageName)
            }
        )
    }

    override fun onInterrupt() = Unit
}
