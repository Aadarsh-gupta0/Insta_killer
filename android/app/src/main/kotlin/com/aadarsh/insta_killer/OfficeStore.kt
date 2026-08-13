package com.aadarsh.insta_killer

import android.content.Context
import android.content.SharedPreferences

/**
 * The one place native state lives.
 *
 * Two kinds of thing are in here and they are not the same:
 *
 *  - **Flags the services act on** — [blockingEnabled], [grantEndsAt], the heartbeat.
 *    Small, typed, and written by Dart. A service reads them and does as it is told.
 *  - **Opaque JSON** written through [readBlob]/[writeBlob]. Kotlin never parses it.
 *    Rules, quota, the event log and the schedule all live in `packages/domain`, and the
 *    only way to keep them there is to make it impossible to read them from here.
 *
 * If you are about to add a third kind — a rule, a threshold, a date calculation — put it
 * in the domain package and have Dart write the answer into the first kind instead.
 */
class OfficeStore(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    companion object {
        private const val PREFS = "insta_killer"

        private const val KEY_BLOCKING = "blocking_enabled"
        private const val KEY_GRANT_ENDS_AT = "grant_ends_at"
        private const val KEY_WATCHER_HEARTBEAT = "watcher_heartbeat"
        private const val BLOB_PREFIX = "blob."

        const val INSTAGRAM = "com.instagram.android"
    }

    /** Off until onboarding finishes. Installing the app changes nothing on its own. */
    var blockingEnabled: Boolean
        get() = prefs.getBoolean(KEY_BLOCKING, false)
        set(value) = prefs.edit().putBoolean(KEY_BLOCKING, value).apply()

    /** Epoch millis; 0 when no permit is running. */
    var grantEndsAt: Long
        get() = prefs.getLong(KEY_GRANT_ENDS_AT, 0L)
        set(value) = prefs.edit().putLong(KEY_GRANT_ENDS_AT, value).apply()

    /**
     * True while a permit is in force.
     *
     * The watcher consults this on every event rather than relying on an alarm to switch
     * blocking back on. Alarms get dropped — by Doze, by OxygenOS, by a reboot — and a
     * dropped alarm here would mean Instagram stays open indefinitely. Comparing two
     * numbers cannot be dropped.
     */
    fun grantIsRunning(now: Long = System.currentTimeMillis()): Boolean {
        val endsAt = grantEndsAt
        return endsAt > 0L && now < endsAt
    }

    /**
     * D-010's watchdog. Written whenever [ForegroundWatcher] proves it is alive; read by
     * Dart, which decides what staleness means — that judgement is a rule, so it does not
     * belong in Kotlin.
     */
    var watcherHeartbeat: Long
        get() = prefs.getLong(KEY_WATCHER_HEARTBEAT, 0L)
        set(value) = prefs.edit().putLong(KEY_WATCHER_HEARTBEAT, value).apply()

    fun readBlob(key: String): String? = prefs.getString(BLOB_PREFIX + key, null)

    fun writeBlob(key: String, value: String) {
        prefs.edit().putString(BLOB_PREFIX + key, value).apply()
    }
}
