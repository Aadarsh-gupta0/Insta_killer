package com.aadarsh.insta_killer

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.text.TextUtils

/**
 * The Kotlin half of the Pigeon contract.
 *
 * Everything here is either a system call Dart cannot make or a read/write of the two
 * flags the services act on. No branching on quota, no dates, no policy — see the note
 * on [OfficeStore].
 */
class OfficeHostApiImpl(
    private val context: Context,
    private val activityProvider: () -> Activity?,
) : OfficeHostApi {

    private val store = OfficeStore(context)

    /** Set by [MainActivity] from the launch intent before Dart first asks. */
    var launchReason: LaunchReason = LaunchReason.ICON

    override fun state(): NativeState = NativeState(
        blockingEnabled = store.blockingEnabled,
        grantEndsAtEpochMs = store.grantEndsAt,
        launchReason = launchReason,
        permissions = Permissions(
            accessibility = isAccessibilityEnabled(),
            notificationAccess = isNotificationAccessEnabled(),
            instagramInstalled = isInstagramInstalled(),
        ),
        lastWatcherHeartbeatEpochMs = store.watcherHeartbeat,
    )

    override fun setBlockingEnabled(enabled: Boolean) {
        store.blockingEnabled = enabled
    }

    override fun beginGrant(endsAtEpochMs: Long) {
        // Order matters. The timestamp is what actually suspends enforcement, so it is
        // written first; if the process dies between these two lines the permit still
        // holds and only the notification is lost.
        store.grantEndsAt = endsAtEpochMs
        GrantAlarms.schedule(context, endsAtEpochMs)
    }

    override fun endGrant() {
        store.grantEndsAt = 0L
        GrantAlarms.cancel(context)
    }

    override fun read(key: String): String? = store.readBlob(key)

    override fun write(key: String, value: String) = store.writeBlob(key, value)

    override fun openAccessibilitySettings() {
        launchSettings(Settings.ACTION_ACCESSIBILITY_SETTINGS)
    }

    override fun openNotificationAccessSettings() {
        launchSettings(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
    }

    override fun leaveToHome() {
        // Home, not `finish()`. Finishing would reveal whatever is underneath — which,
        // when the Gate was opened because Instagram was, is Instagram.
        context.startActivity(
            Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
        )
        activityProvider()?.finish()
    }

    private fun launchSettings(action: String) {
        val intent = Intent(action)
        val host = activityProvider()
        if (host != null) {
            host.startActivity(intent)
        } else {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    private fun isInstagramInstalled(): Boolean = try {
        context.packageManager.getPackageInfo(OfficeStore.INSTAGRAM, 0)
        true
    } catch (e: Exception) {
        // Also false when the <queries> element is missing from the manifest on Android
        // 11+, which looks identical to "not installed". Check the manifest first.
        false
    }

    private fun isAccessibilityEnabled(): Boolean {
        val expected = ComponentName(context, ForegroundWatcher::class.java)
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        // Compared by component rather than by string: Settings has stored both the
        // flattened ("pkg/pkg.Class") and short ("pkg/.Class") forms across versions, and
        // a string compare silently reports "off" while the toggle is visibly on.
        return splitter.any { ComponentName.unflattenFromString(it) == expected }
    }

    private fun isNotificationAccessEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false

        return enabled.split(":").any {
            ComponentName.unflattenFromString(it)?.packageName == context.packageName
        }
    }
}
