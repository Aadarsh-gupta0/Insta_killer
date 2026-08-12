package com.aadarsh.instakiller.spike

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.os.CountDownTimer
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SpikeStore.recordGateShown(this)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(LEDGER)
            setPadding(64, 64, 64, 64)
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
            setOnClickListener {
                // The honest way out: send the user home rather than back to Instagram.
                // moveTaskToBack would just reveal Instagram again underneath us.
                startActivity(
                    android.content.Intent(android.content.Intent.ACTION_MAIN).apply {
                        addCategory(android.content.Intent.CATEGORY_HOME)
                        flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                )
                finish()
            }
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
                leave.isEnabled = true
                proceed.isEnabled = true
            }
        }.start()
    }

    /**
     * FR-13 has to mean something. Without this, back-out-and-retry skips the pause, and
     * the pause is the entire mechanism.
     */
    override fun onBackPressed() {
        // Intentionally does nothing until the timer has run. No super call.
    }

    override fun onDestroy() {
        timer?.cancel()
        super.onDestroy()
    }
}
