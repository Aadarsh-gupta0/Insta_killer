package com.aadarsh.insta_killer

import android.content.Intent
import android.os.Bundle
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    companion object {
        const val EXTRA_LAUNCH_REASON = "launch_reason"
        const val EXTRA_BLOCKED_PACKAGE = "blocked_package"
        const val REASON_GATE = "gate"
    }

    private var hostApi: OfficeHostApiImpl? = null
    private var flutterApi: OfficeFlutterApi? = null
    private var backCallback: OnBackInvokedCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val api = OfficeHostApiImpl(applicationContext) { this }
        api.launchReason = reasonFrom(intent)
        hostApi = api

        OfficeHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, api)
        flutterApi = OfficeFlutterApi(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        interceptBackGesture()
        ensureNotificationPermission()
    }

    /**
     * FR-19's warnings are worthless without this on Android 13+, and declaring the
     * permission in the manifest is not enough — it has to be asked for. Failing to ask
     * would mean the two-minute warning silently never arrives, which reads as a bug in
     * the permit rather than a missing grant.
     *
     * Asked for here rather than during onboarding on purpose: this build is installed by
     * side-loading and will be reinstalled often, and a permission tied to a one-time
     * onboarding flow would be lost on every reinstall.
     */
    private fun ensureNotificationPermission() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU) return

        val granted = checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        if (granted) return

        requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1001)
    }

    /**
     * The Activity is `singleTask`, so a second launch while it is already up arrives
     * here rather than through [configureFlutterEngine]. Without this, opening Instagram
     * twice in a row would show whatever screen was left on display instead of the Gate.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val reason = reasonFrom(intent)
        hostApi?.launchReason = reason
        if (reason == LaunchReason.GATE) {
            flutterApi?.onGateRequested { }
        }
    }

    private fun reasonFrom(intent: Intent?): LaunchReason =
        if (intent?.getStringExtra(EXTRA_LAUNCH_REASON) == REASON_GATE) {
            LaunchReason.GATE
        } else {
            LaunchReason.ICON
        }

    /**
     * FR-13's pause has to survive the back gesture, and on Android 16 with targetSdk 36
     * predictive back is on by default: `onBackPressed()` is never called and
     * `KEYCODE_BACK` is never dispatched, so overriding either does nothing.
     *
     * Swallowing back unconditionally at the Activity level is deliberate. Dart decides
     * what leaving means — the Gate's own Leave button calls `leaveToHome`, and the Front
     * Desk has nothing to go back to — so there is no case where the system gesture
     * should quietly dismiss us. Notably it must not: dismissing the Gate would drop the
     * user straight back into Instagram, which is exactly what it exists to prevent.
     */
    private fun interceptBackGesture() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU) return

        val callback = OnBackInvokedCallback { /* swallowed */ }
        onBackInvokedDispatcher.registerOnBackInvokedCallback(
            OnBackInvokedDispatcher.PRIORITY_OVERLAY,
            callback
        )
        backCallback = callback
    }

    override fun onDestroy() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            backCallback?.let { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }
        }
        super.onDestroy()
    }
}
