package com.aadarsh.insta_killer

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * The VIP probe (FR-31), and the clearest reason this product is on Android.
 *
 * iOS has no notification-listener API at all, and the only route to per-sender Instagram
 * alerts there runs through a Professional account and Meta App Review — a path closed by
 * decision (D-008). Here it is one permission and a string.
 *
 * Instagram puts the sender in `EXTRA_TITLE` and the preview in `EXTRA_TEXT`, which is
 * the shape FR-31's per-handle rules need. **Whether that holds for every notification
 * type is still unverified on device** — see Q3 in `docs/P0_SPIKE_ANDROID.md`. Until it
 * is, this only records what arrives; it matches nothing and suppresses nothing.
 */
class NotificationProbe : NotificationListenerService() {

    private companion object {
        const val TAG = "NotificationProbe"

        /** Read by Dart. Capped, because this is a probe and not a message archive. */
        const val BLOB_KEY = "vip.samples"
        const val MAX_SAMPLES = 20
        const val PREVIEW_LIMIT = 100
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn ?: return
        if (notification.packageName != OfficeStore.INSTAGRAM) return

        // Group summaries carry no per-sender information — "3 new messages" is exactly
        // the case the VIP feature cannot act on — so they are dropped rather than stored.
        if ((notification.notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return

        val extras = notification.notification.extras
        val sender = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val preview = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()

        record(sender, preview, notification.postTime)
        Log.d(TAG, "Instagram notification recorded")

        // Nothing is cancelled, suppressed or forwarded. Silently swallowing someone's
        // notifications is a far larger promise to the user than showing a gate, and it
        // needs its own argument before it is made.
    }

    /**
     * NFR-3 keeps this local and small: handle, timestamp, and a truncated preview. The
     * same ceiling the SRS puts on the Rung-1 backend applies to the on-device probe.
     */
    private fun record(sender: String?, preview: String?, postedAt: Long) {
        val store = OfficeStore(this)
        val samples = try {
            JSONArray(store.readBlob(BLOB_KEY) ?: "[]")
        } catch (e: Exception) {
            JSONArray()
        }

        samples.put(
            JSONObject().apply {
                put("at", postedAt)
                put("sender", sender ?: "")
                put("preview", preview?.take(PREVIEW_LIMIT) ?: "")
            }
        )

        val trimmed = JSONArray()
        val first = maxOf(0, samples.length() - MAX_SAMPLES)
        for (i in first until samples.length()) trimmed.put(samples.get(i))

        store.writeBlob(BLOB_KEY, trimmed.toString())
    }

    override fun onListenerConnected() {
        Log.d(TAG, "Connected.")
    }
}
