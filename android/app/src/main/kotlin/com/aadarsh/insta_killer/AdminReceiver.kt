package com.aadarsh.insta_killer

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * FR-28 — uninstall protection, and an honest account of how much of it there is.
 *
 * **What an active device admin actually does.** Android refuses to uninstall an app while
 * it is an active device administrator. You get sent to Settings to deactivate it first.
 * That is a real, deliberate extra step at the moment it matters, and it is all a plain
 * device admin can do — the app cannot veto its own deactivation.
 *
 * **What it does not do.** `setUninstallBlocked` — the API that genuinely prevents removal —
 * requires *device owner* or *profile owner*, which is a provisioning step
 * (`adb shell dpm set-device-owner`) on a device with no accounts configured. Not something
 * to enable behind a toggle; documented in LIMITATIONS.md as the tier above this one.
 *
 * We request **no policies at all**. An admin with an empty policy set still blocks
 * uninstall, and asking for the power to wipe the device or watch failed passwords when we
 * use neither would be indefensible for what this app does.
 */
class AdminReceiver : DeviceAdminReceiver() {

    companion object {
        private const val TAG = "AdminReceiver"

        fun component(context: Context) =
            ComponentName(context.applicationContext, AdminReceiver::class.java)

        fun isActive(context: Context): Boolean =
            context.getSystemService(DevicePolicyManager::class.java)
                ?.isAdminActive(component(context)) ?: false
    }

    /**
     * The last thing shown before the protection comes off.
     *
     * Android displays this verbatim on the deactivation screen. It cannot stop the
     * deactivation — nothing can — so it states the consequence rather than pleading.
     */
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        "Turning this off makes Insta_killer removable again. If you are here to " +
            "uninstall it during a bad moment, that is exactly the moment this was " +
            "meant to slow down."

    override fun onEnabled(context: Context, intent: Intent) {
        OfficeStore(context).recordAdminEvent("enabled")
        Log.d(TAG, "Device admin enabled")
    }

    /**
     * Recorded rather than resisted.
     *
     * By the time this fires, the protection is already off — the app has no say. What it
     * can do is leave a mark, so the Record shows when it happened and the app never
     * claims a protection it no longer has.
     */
    override fun onDisabled(context: Context, intent: Intent) {
        OfficeStore(context).recordAdminEvent("disabled")
        Log.d(TAG, "Device admin disabled")
    }
}
