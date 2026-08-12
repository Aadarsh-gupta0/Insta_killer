package com.aadarsh.instakiller.spike

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.CountDownTimer
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher

/**
 * The gate, reduced to its skeleton: a forced pause, then a way out.
 *
 * P0 is only asking whether this can get on screen over Instagram at all. The breathing
 * beat, the user's own declaration, the typed reason and the permit pad are P2/P3 and
 * will be Flutter. Nothing here is meant to survive.
 */
class GateActivity : Activity() {

    private companion object {
        /** FR-13: a non-skippable pause of at least 4 seconds. */
        const val PAUSE_MS = 4_000L

        val LEDGER = Color.parseColor("#E4E9DC")
        val INK = Color.parseColor("#16211C")
        val STAMP = Color.parseColor("#B32E1B")
    }

    private var timer: CountDownTimer? = null
    private var backCallback: OnBackInvokedCallback? = null

    /** Gates every exit. FR-13 is only real while this is false. */
    private var pauseComplete = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SpikeStore.recordGateShown(this)
        interceptBackGesture()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(LEDGER)
            setPadding(64, 64, 64, 64)
            // targetSdk 35+ draws edge-to-edge by default, so without this the title
            // slides under the status bar on the OnePlus's punch-hole display.
            fitsSystemWindows = true
        }

        val title = TextView(this).apply {
            text = "INSTAGRAM IS CLOSED"
            setTextColor(INK)
            textSize = 26f
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
            gravity = Gravity.CENTER
            letterSpacing = 0.08f
        }

        val subtitle = TextView(this).apply {
            text = "Under your own instruction."
            setTextColor(INK)
            textSize = 15f
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 48)
        }

        val countdown = TextView(this).apply {
            setTextColor(STAMP)
            textSize = 40f
            typeface = Typeface.MONOSPACE
            gravity = Gravity.CENTER
        }

        val leave = Button(this).apply {
            text = "LEAVE"
            isEnabled = false
            setOnClickListener { leave() }
        }

        val proceed = Button(this).apply {
            text = "REQUEST A PERMIT"
            isEnabled = false
            setOnClickListener {
                // P1: quota check, typed reason, then lift the block for 15 minutes.
                // For P0 it only has to prove the button is reachable.
                text = "P1 will issue a permit here"
                isEnabled = false
            }
        }

        listOf(title, subtitle, countdown, leave, proceed).forEach {
            root.addView(
                it,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                )
            )
        }
        setContentView(root)

        timer = object : CountDownTimer(PAUSE_MS, 100) {
            override fun onTick(msLeft: Long) {
                countdown.text = String.format("%.1f", msLeft / 1000.0)
            }

            override fun onFinish() {
                countdown.text = "0.0"
                pauseComplete = true
                leave.isEnabled = true
                proceed.isEnabled = true
            }
        }.start()
    }

    /** The honest way out: home, not back into Instagram underneath us. */
    private fun leave() {
        startActivity(
            Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
        )
        finish()
    }

    /**
     * FR-13 has to mean something: without this, back-out-and-retry skips the pause, and
     * the pause is the entire mechanism.
     *
     * On Android 13+ this cannot be done by overriding `onBackPressed`. For apps targeting
     * SDK 36 running on Android 16 — which is exactly this phone — predictive back is on
     * by default, `onBackPressed()` is never called and `KEYCODE_BACK` is never
     * dispatched. The legacy override below is dead code on the target device and is kept
     * only for API < 33.
     *
     * PRIORITY_OVERLAY so we sit above anything else that might claim the gesture.
     */
    private fun interceptBackGesture() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return

        val callback = OnBackInvokedCallback {
            // Before the pause completes, swallow it entirely. After, back is a
            // synonym for LEAVE — the one exit we actually want people to take.
            if (pauseComplete) leave()
        }
        onBackInvokedDispatcher.registerOnBackInvokedCallback(
            OnBackInvokedDispatcher.PRIORITY_OVERLAY,
            callback
        )
        backCallback = callback
    }

    @Suppress("DEPRECATION", "MissingSuperCall")
    override fun onBackPressed() {
        // API < 33 only. Deliberately no super call while the pause is running.
        if (pauseComplete) leave()
    }

    override fun onDestroy() {
        timer?.cancel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            backCallback?.let { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }
        }
        super.onDestroy()
    }
}
