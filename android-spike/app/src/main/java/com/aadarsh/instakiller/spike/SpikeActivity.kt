package com.aadarsh.instakiller.spike

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView

/**
 * The diagnostic panel. Mirrors the checklist in docs/P0_SPIKE_ANDROID.md, so a
 * screenshot of this screen is a complete P0 report.
 *
 * Ugly on purpose — the Permit Office design system is P2 and will be Flutter.
 */
class SpikeActivity : Activity() {

    private lateinit var container: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 64, 48, 64)
        }
        setContentView(ScrollView(this).apply { addView(container) })
    }

    override fun onResume() {
        super.onResume()
        // Everything here is state owned by other processes or by Settings, so it can only
        // be trusted as of right now. Rebuild the whole panel on every resume.
        render()
    }

    private fun render() {
        container.removeAllViews()

        heading("Environment")
        row("Android", "${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})")
        row("Device", "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}")
        row("Instagram installed", yesNo(isInstagramInstalled()), isInstagramInstalled())

        heading("Permissions")
        val a11y = isAccessibilityEnabled()
        val listener = isNotificationListenerEnabled()
        row("Accessibility service", yesNo(a11y), a11y)
        button("Open accessibility settings") {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }
        row("Notification listener", yesNo(listener), listener)
        button("Open notification access settings") {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
        if (!a11y) {
            note(
                "If the toggle is greyed out with \"Restricted setting\", this is Android 13+ " +
                    "blocking sideloaded apps. Settings → Apps → InstaKiller P0 → ⋮ → " +
                    "Allow restricted settings, then come back."
            )
        }

        heading("Blocking")
        val enabled = SpikeStore.isBlockEnabled(this)
        container.addView(Switch(this).apply {
            text = if (enabled) "Blocking is ON" else "Blocking is OFF"
            isChecked = enabled
            textSize = 16f
            setOnCheckedChangeListener { _, checked ->
                SpikeStore.setBlockEnabled(this@SpikeActivity, checked)
                render()
            }
        })
        note("Turn this on, then open Instagram. The gate should appear over it.")

        heading("Q1 + Q2 — detection and the gate")
        row("Detections", SpikeStore.detectionCount(this).toString())
        mono(SpikeStore.lastDetection(this) ?: "Nothing detected yet.")
        row("Gate last shown", SpikeStore.lastGateShown(this) ?: "never")

        heading("Q3 — the VIP probe")
        row("Instagram notifications seen", SpikeStore.notificationCount(this).toString())
        mono(SpikeStore.lastNotification(this) ?: "None captured yet.")
        note(
            "Get someone to DM you, or send yourself one from another account. The line " +
                "above must show a usable sender name — that is the whole VIP feature."
        )

        heading("Reset")
        button("Reset counters") {
            SpikeStore.reset(this)
            render()
        }
    }

    // --- permission checks --------------------------------------------------------

    private fun isInstagramInstalled(): Boolean = try {
        packageManager.getPackageInfo(ForegroundWatcher.INSTAGRAM, 0)
        true
    } catch (e: Exception) {
        // Also returns false if the <queries> element is missing from the manifest on
        // Android 11+, which looks identical to "not installed". Check the manifest first.
        false
    }

    private fun isAccessibilityEnabled(): Boolean {
        val expected = ComponentName(this, ForegroundWatcher::class.java).flattenToString()
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        // SimpleStringSplitter implements Iterable<String>, so the stdlib `any` applies.
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        return splitter.any { it.equals(expected, ignoreCase = true) }
    }

    /**
     * The component string Settings stores is the *flattened* name, and it has bitten
     * every Android blocker at least once: `ComponentName.flattenToString()` produces
     * "pkg/pkg.Class" while `flattenToShortString()` produces "pkg/.Class", and Settings
     * has used both across versions. If the accessibility row reads ❌ while the toggle is
     * visibly on, this comparison is why — try matching on package name alone.
     */

    private fun isNotificationListenerEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        return enabled.split(":").any {
            ComponentName.unflattenFromString(it)?.packageName == packageName
        }
    }

    // --- tiny view helpers --------------------------------------------------------

    private fun heading(text: String) {
        container.addView(TextView(this).apply {
            this.text = text.uppercase()
            textSize = 12f
            letterSpacing = 0.12f
            setTextColor(Color.parseColor("#6B7A66"))
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
            setPadding(0, 48, 0, 12)
        })
    }

    private fun row(label: String, value: String, ok: Boolean? = null) {
        container.addView(TextView(this).apply {
            val mark = when (ok) {
                true -> "✅  "
                false -> "❌  "
                null -> ""
            }
            text = "$mark$label: $value"
            textSize = 15f
            setPadding(0, 6, 0, 6)
        })
    }

    private fun mono(text: String) {
        container.addView(TextView(this).apply {
            this.text = text
            typeface = Typeface.MONOSPACE
            textSize = 13f
            setPadding(0, 8, 0, 8)
        })
    }

    private fun note(text: String) {
        container.addView(TextView(this).apply {
            this.text = text
            textSize = 13f
            setTextColor(Color.parseColor("#6B7A66"))
            setPadding(0, 8, 0, 8)
        })
    }

    private fun button(label: String, onClick: () -> Unit) {
        container.addView(
            Button(this).apply {
                text = label
                setOnClickListener { onClick() }
            },
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
    }

    private fun yesNo(value: Boolean): String = if (value) "YES" else "NO"
}
