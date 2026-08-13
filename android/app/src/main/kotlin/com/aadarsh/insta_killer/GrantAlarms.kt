package com.aadarsh.insta_killer

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * FR-19 — two minutes before expiry, and at expiry.
 *
 * Worth being clear about what these alarms are *not* for. They do not re-enable
 * blocking: [ForegroundWatcher] compares against [OfficeStore.grantEndsAt] on every
 * event, so enforcement resumes the moment the timestamp passes whether or not any alarm
 * ever fires. These only tell the user. An alarm dropped by Doze or by OxygenOS costs a
 * notification, never the block.
 */
object GrantAlarms {

    private const val TAG = "GrantAlarms"
    const val CHANNEL_ID = "permits"

    private const val REQUEST_WARNING = 2001
    private const val REQUEST_EXPIRY = 2002

    const val ACTION_WARNING = "com.aadarsh.insta_killer.PERMIT_WARNING"
    const val ACTION_EXPIRY = "com.aadarsh.insta_killer.PERMIT_EXPIRY"

    private val warningLeadMs = 2 * 60 * 1000L

    fun schedule(context: Context, endsAtEpochMs: Long) {
        cancel(context)
        ensureChannel(context)

        val warningAt = endsAtEpochMs - warningLeadMs
        if (warningAt > System.currentTimeMillis()) {
            setAlarm(context, warningAt, ACTION_WARNING, REQUEST_WARNING)
        }
        setAlarm(context, endsAtEpochMs, ACTION_EXPIRY, REQUEST_EXPIRY)
    }

    fun cancel(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        manager.cancel(pending(context, ACTION_WARNING, REQUEST_WARNING))
        manager.cancel(pending(context, ACTION_EXPIRY, REQUEST_EXPIRY))
    }

    private fun setAlarm(context: Context, atEpochMs: Long, action: String, code: Int) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = pending(context, action, code)

        // Exact alarms need a permission on Android 12+ that the user can refuse, and on
        // 14+ it is not granted by default. Degrade rather than crash: an inexact alarm
        // means the two-minute warning may arrive late, which is a worse notification and
        // not a broken block.
        val canBeExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            manager.canScheduleExactAlarms()

        try {
            if (canBeExact) {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atEpochMs, intent)
            } else {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atEpochMs, intent)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Exact alarm refused, falling back to inexact", e)
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atEpochMs, intent)
        }
    }

    private fun pending(context: Context, action: String, code: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            code,
            Intent(context, GrantAlarmReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Permits",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Warnings before a permit expires."
                setShowBadge(false)
            }
        )
    }

    /** Clerical, unsentimental, and it states the fact rather than nagging. */
    fun notify(context: Context, title: String, body: String, id: Int) {
        ensureChannel(context)
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        manager.notify(
            id,
            Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
                .setContentTitle(title)
                .setContentText(body)
                .setContentIntent(open)
                .setAutoCancel(true)
                .setOnlyAlertOnce(true)
                .build()
        )
    }
}

class GrantAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            GrantAlarms.ACTION_WARNING -> GrantAlarms.notify(
                context,
                "Permit ends in 2 minutes",
                "Instagram will close itself at the end of the permit.",
                id = 1
            )

            GrantAlarms.ACTION_EXPIRY -> {
                // Clearing the timestamp is belt-and-braces: the watcher already treats a
                // past timestamp as expired. This just keeps the stored state tidy.
                OfficeStore(context).grantEndsAt = 0L
                GrantAlarms.notify(
                    context,
                    "Permit expired",
                    "Instagram is closed again.",
                    id = 2
                )
            }
        }
    }
}

/**
 * A permit that outlives a reboot must not outlive it *silently*.
 *
 * The watcher restores itself — accessibility services are restarted by the system — and
 * `grantEndsAt` survives in SharedPreferences, so enforcement is already correct after a
 * restart. Alarms do not survive, so they are rebuilt here.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val store = OfficeStore(context)
        if (store.grantIsRunning()) {
            GrantAlarms.schedule(context, store.grantEndsAt)
        } else {
            store.grantEndsAt = 0L
        }
    }
}
