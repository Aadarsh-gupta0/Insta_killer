package com.aadarsh.insta_killer

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.provider.Settings
import android.text.TextUtils
import java.io.ByteArrayOutputStream

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

    /** The package whose launch was intercepted, if any. */
    var blockedPackage: String? = null

    override fun state(): NativeState = NativeState(
        blockingEnabled = store.blockingEnabled,
        grantEndsAtEpochMs = store.grantEndsAt,
        launchReason = launchReason,
        permissions = Permissions(
            accessibility = isAccessibilityEnabled(),
            notificationAccess = isNotificationAccessEnabled(),
            deviceAdmin = AdminReceiver.isActive(context),
        ),
        lastWatcherHeartbeatEpochMs = store.watcherHeartbeat,
        blockedApp = blockedPackage?.let(::describeApp),
    )

    /** Label and icon for one package. Null when it has been uninstalled since. */
    private fun describeApp(packageName: String): InstalledApp? = runCatching {
        val pm = context.packageManager
        val info = pm.getApplicationInfo(packageName, 0)
        InstalledApp(
            packageName = packageName,
            label = pm.getApplicationLabel(info).toString(),
            icon = runCatching { encodeIcon(pm.getApplicationIcon(info)) }.getOrNull(),
        )
    }.getOrNull()

    override fun installedApps(): List<InstalledApp> {
        val pm = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)

        return pm.queryIntentActivities(launcher, 0)
            .asSequence()
            // Only apps with a launcher entry: the user cannot "open" a service or a
            // provider, so blocking one would be meaningless.
            .map { it.activityInfo.applicationInfo }
            .distinctBy { it.packageName }
            .filter { it.packageName != context.packageName }
            .map { info ->
                InstalledApp(
                    packageName = info.packageName,
                    label = pm.getApplicationLabel(info).toString(),
                    icon = runCatching { encodeIcon(pm.getApplicationIcon(info)) }.getOrNull(),
                )
            }
            .sortedBy { it.label.lowercase() }
            .toList()
    }

    /**
     * Rasterises an icon to a small PNG.
     *
     * Capped at 96px because these cross a Pigeon channel in one message: a few hundred
     * apps at full adaptive-icon resolution is megabytes of binder traffic and a visible
     * stall when the Blocklist opens.
     */
    private fun encodeIcon(drawable: Drawable, size: Int = 96): ByteArray {
        val bitmap = (drawable as? BitmapDrawable)?.bitmap
            ?.let { if (it.width <= size) it else Bitmap.createScaledBitmap(it, size, size, true) }
            ?: Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also { bmp ->
                // Adaptive icons are not BitmapDrawables; they have to be drawn.
                Canvas(bmp).let { canvas ->
                    drawable.setBounds(0, 0, size, size)
                    drawable.draw(canvas)
                }
            }

        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
    }

    override fun setWatchedPackages(packageNames: List<String>) {
        store.watchedPackages = packageNames.toSet()
        // Push it to the live service so an edit takes effect now rather than at the next
        // service restart. Null instance is fine — it re-reads the store on connect.
        ForegroundWatcher.instance?.applyWatchList()
    }

    override fun requestDeviceAdmin() {
        if (AdminReceiver.isActive(context)) return

        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
            putExtra(
                DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                AdminReceiver.component(context),
            )
            putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "Makes Android refuse to uninstall Insta_killer until you deactivate " +
                    "this first. It asks for no other powers — it cannot lock, wipe or " +
                    "watch anything.",
            )
        }

        val host = activityProvider()
        if (host != null) {
            host.startActivity(intent)
        } else {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    override fun releaseDeviceAdmin() {
        if (!AdminReceiver.isActive(context)) return
        context.getSystemService(DevicePolicyManager::class.java)
            ?.removeActiveAdmin(AdminReceiver.component(context))
    }

    override fun lastAdminEvent(): String = store.lastAdminEvent ?: ""

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
