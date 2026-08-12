package com.aadarsh.instakiller.spike

import android.content.Context
import android.content.SharedPreferences
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The Android equivalent of the iOS App Group: the one place the services and the UI
 * agree. Real app replaces this with the shared SQLite event log (D-001); for P0 a
 * handful of keys is enough to prove each piece ran.
 */
object SpikeStore {

    private const val PREFS = "instakiller_spike"

    private const val KEY_BLOCK_ENABLED = "block_enabled"
    private const val KEY_LAST_DETECTION = "last_detection"
    private const val KEY_DETECTION_COUNT = "detection_count"
    private const val KEY_LAST_NOTIFICATION = "last_notification"
    private const val KEY_NOTIFICATION_COUNT = "notification_count"
    private const val KEY_GATE_SHOWN_AT = "gate_shown_at"

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private val stamp = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    private fun now(): String = stamp.format(Date())

    /** Master switch for the spike. Off by default so installing it changes nothing. */
    fun isBlockEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_BLOCK_ENABLED, false)

    fun setBlockEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_BLOCK_ENABLED, enabled).apply()
    }

    // --- Q1: foreground detection ------------------------------------------------

    fun recordDetection(context: Context, packageName: String, latencyMs: Long) {
        val p = prefs(context)
        p.edit()
            .putString(KEY_LAST_DETECTION, "${now()}  $packageName  (+${latencyMs}ms to gate)")
            .putInt(KEY_DETECTION_COUNT, p.getInt(KEY_DETECTION_COUNT, 0) + 1)
            .apply()
    }

    fun lastDetection(context: Context): String? =
        prefs(context).getString(KEY_LAST_DETECTION, null)

    fun detectionCount(context: Context): Int =
        prefs(context).getInt(KEY_DETECTION_COUNT, 0)

    // --- Q3: the VIP probe -------------------------------------------------------

    /**
     * Stores only what proves the mechanism works. Note this is exactly the data the iOS
     * build can never obtain (see D-008) — the sender is the whole point.
     */
    fun recordNotification(context: Context, sender: String?, preview: String?) {
        val p = prefs(context)
        val safeSender = sender?.takeIf { it.isNotBlank() } ?: "(no title)"
        val safePreview = preview?.take(60)?.takeIf { it.isNotBlank() } ?: "(no text)"
        p.edit()
            .putString(KEY_LAST_NOTIFICATION, "${now()}  from: $safeSender\n  \"$safePreview\"")
            .putInt(KEY_NOTIFICATION_COUNT, p.getInt(KEY_NOTIFICATION_COUNT, 0) + 1)
            .apply()
    }

    fun lastNotification(context: Context): String? =
        prefs(context).getString(KEY_LAST_NOTIFICATION, null)

    fun notificationCount(context: Context): Int =
        prefs(context).getInt(KEY_NOTIFICATION_COUNT, 0)

    // --- Q2: did the gate actually reach the screen? ------------------------------

    fun recordGateShown(context: Context) {
        prefs(context).edit().putString(KEY_GATE_SHOWN_AT, now()).apply()
    }

    fun lastGateShown(context: Context): String? =
        prefs(context).getString(KEY_GATE_SHOWN_AT, null)

    fun reset(context: Context) {
        prefs(context).edit().clear().apply()
    }
}
