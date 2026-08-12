package com.aadarsh.instakiller.spike

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Q3: the VIP feature, and the clearest demonstration of why Android and iOS are not
 * equivalent products.
 *
 * On iOS there is no notification-listener API at all, and the only route to per-sender
 * Instagram alerts runs through a Professional account and Meta App Review — a path
 * closed to us by decision (D-008). Here it is thirty lines and one permission.
 *
 * What we get: Instagram writes the sender into EXTRA_TITLE and the message preview into
 * EXTRA_TEXT. That is exactly the shape FR-31 needs — match the title against the VIP
 * list, ignore everything else.
 *
 * What P0 must establish is whether that holds in practice, because Instagram controls
 * the format and it varies by notification type:
 *   - a DM is usually "username" / "message text"
 *   - a like or comment is often "username liked your photo" with an empty text
 *   - grouped notifications may summarise as "3 new messages" with no usable sender
 *
 * If the sender is not reliably extractable, the VIP feature degrades to "something from
 * Instagram happened", which is not worth building.
 */
class NotificationProbe : NotificationListenerService() {

    private companion object {
        const val TAG = "NotificationProbe"
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn ?: return
        if (notification.packageName != ForegroundWatcher.INSTAGRAM) return

        val extras = notification.notification.extras
        val sender = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val preview = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()

        // Group summaries carry no per-sender information and would pollute the readout.
        val isGroupSummary =
            (notification.notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0
        if (isGroupSummary) {
            Log.d(TAG, "Skipped a group summary.")
            return
        }

        SpikeStore.recordNotification(this, sender, preview)
        Log.d(TAG, "Instagram notification — title=$sender")

        // Note what we are NOT doing: nothing is cancelled, suppressed or forwarded. P0
        // observes only. Suppressing a VIP-irrelevant notification is a P4 decision and
        // needs its own argument, since silently swallowing notifications is a far bigger
        // promise to the user than showing a gate.
    }

    override fun onListenerConnected() {
        Log.d(TAG, "Connected.")
    }
}
