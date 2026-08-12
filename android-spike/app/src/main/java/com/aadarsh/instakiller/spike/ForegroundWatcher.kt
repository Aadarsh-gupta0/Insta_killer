package com.aadarsh.instakiller.spike

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * Q1 and Q2 of the Android spike, in one class.
 *
 * This is the piece iOS cannot match. Instead of asking the OS to refuse to open
 * Instagram and accepting whatever block screen it draws, we are told the instant
 * Instagram reaches the foreground and put our own full screen in front of it.
 *
 * Why an AccessibilityService rather than polling `UsageStatsManager`:
 *   - it is event-driven, so detection is immediate rather than up to a poll interval late
 *   - no wakelock, no foreground service, no battery drain from a 500ms loop
 *   - and critically, accessibility services are exempt from the background-activity-launch
 *     restrictions introduced in Android 10 and tightened since. A plain foreground service
 *     cannot reliably `startActivity` from the background any more; this can.
 *
 * The cost is a scary permission screen and, on Android 13+, the Restricted Settings
 * dance for sideloaded apps. Both are documented in P0_SPIKE_ANDROID.md.
 */
class ForegroundWatcher : AccessibilityService() {

    companion object {
        private const val TAG = "ForegroundWatcher"
        const val INSTAGRAM = "com.instagram.android"

        /**
         * Ignore repeat events inside this window. Instagram fires several
         * typeWindowStateChanged events while it starts up, and without this the gate
         * gets launched three or four times per open.
         */
        private const val DEBOUNCE_MS = 1500L
    }

    private var lastTriggerAt = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val packageName = event?.packageName?.toString() ?: return
        if (packageName != INSTAGRAM) return

        val startedAt = SystemClock.elapsedRealtime()
        if (startedAt - lastTriggerAt < DEBOUNCE_MS) return
        lastTriggerAt = startedAt

        if (!SpikeStore.isBlockEnabled(this)) {
            Log.d(TAG, "Instagram foregrounded, but blocking is off.")
            return
        }

        // Option A, taken here: put our gate in front of it.
        val intent = Intent(this, GateActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION
            )
        }
        startActivity(intent)

        // Option B, the closer analogue of "kill Instagram", left here deliberately so it
        // can be tried during P0. It sends the user straight home with no gate at all:
        //
        //     performGlobalAction(GLOBAL_ACTION_HOME)
        //
        // It works, and it is more abrupt than anything iOS permits. The open design
        // question is whether the gate persuades better than the bounce — the brief argues
        // for friction with a reason attached, which is option A.

        val latency = SystemClock.elapsedRealtime() - startedAt
        SpikeStore.recordDetection(this, packageName, latency)
        Log.d(TAG, "Instagram detected, gate launched in ${latency}ms")
    }

    override fun onInterrupt() = Unit

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "Connected. Watching $INSTAGRAM only.")
    }
}
