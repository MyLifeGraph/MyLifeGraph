package com.mylifegraph.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.lang.ref.WeakReference
import java.util.Locale
import java.util.concurrent.TimeUnit

class FocusBlockAccessibilityService : AccessibilityService() {
    private lateinit var manager: FocusProtectionManager
    private lateinit var windowManager: WindowManager
    private val handler = Handler(Looper.getMainLooper())
    private var overlay: View? = null
    private var remainingText: TextView? = null
    private var lastForegroundPackage: String? = null
    private var emergencyArmRunnable: Runnable? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        manager = FocusProtectionManager(applicationContext)
        windowManager = getSystemService(WindowManager::class.java)
        runningService = WeakReference(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        lastForegroundPackage = event.packageName?.toString()
        refreshOverlay()
    }

    override fun onInterrupt() {
        hideOverlay()
    }

    override fun onDestroy() {
        if (runningService?.get() === this) runningService = null
        handler.removeCallbacksAndMessages(null)
        hideOverlay()
        super.onDestroy()
    }

    private fun refreshOverlay() {
        if (!manager.shouldBlock(lastForegroundPackage)) {
            hideOverlay()
            return
        }
        if (overlay == null) showOverlay()
        updateRemainingTime()
    }

    private fun showOverlay() {
        val root = ScrollView(this).apply {
            setBackgroundColor(Color.rgb(17, 24, 39))
            isFillViewport = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(48), dp(24), dp(48))
        }
        root.addView(
            content,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        content.addView(textView("Focus protection", 30f, true))
        content.addView(
            textView(
                "This app is blocked until the planned Focus time ends.",
                18f,
                false,
            ).withTopMargin(16),
        )
        remainingText = textView("", 40f, true).also {
            it.contentDescription = "Focus time remaining"
            content.addView(it.withTopMargin(24))
        }
        content.addView(
            Button(this).apply {
                text = "Return to MyLifeGraph"
                textSize = 18f
                contentDescription = "Return to MyLifeGraph"
                setOnClickListener { returnToMyLifeGraph() }
            }.withTopMargin(32),
        )
        content.addView(
            emergencyButton().withTopMargin(16),
        )
        content.addView(
            textView(
                "Settings, phone, alarms, and essential Android functions remain available.",
                15f,
                false,
            ).withTopMargin(24),
        )
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            title = "MyLifeGraph Focus protection"
        }
        runCatching { windowManager.addView(root, params) }
            .onSuccess { overlay = root }
        scheduleRemainingTick()
    }

    private fun emergencyButton(): Button {
        var awaitingConfirmation = false
        var confirmationPress = false
        val releaseGate = EmergencyReleaseGate(HOLD_DURATION_MS)
        val button = Button(this).apply {
            text = "Hold 5 seconds for emergency release"
            textSize = 17f
            isLongClickable = false
            contentDescription =
                "Emergency release. Press and hold for five seconds, then activate again to confirm."
        }
        fun armRelease() {
            emergencyArmRunnable = null
            awaitingConfirmation = true
            button.text = "Confirm emergency release"
            button.contentDescription =
                "Emergency release ready. Activate again to confirm."
            button.announceForAccessibility(
                "Emergency release ready. Activate again to confirm.",
            )
        }
        fun beginCountdown() {
            if (!releaseGate.start(SystemClock.elapsedRealtime())) return
            button.text = "Keep holding for 5 seconds"
            button.announceForAccessibility(
                "Emergency release countdown started. Confirm after five seconds.",
            )
            val runnable = Runnable {
                if (releaseGate.tryArm(SystemClock.elapsedRealtime())) armRelease()
            }
            emergencyArmRunnable = runnable
            handler.postDelayed(runnable, HOLD_DURATION_MS)
        }
        fun cancelCountdown() {
            emergencyArmRunnable?.let(handler::removeCallbacks)
            emergencyArmRunnable = null
            releaseGate.cancel()
            button.text = "Hold 5 seconds for emergency release"
        }
        button.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    if (awaitingConfirmation) {
                        confirmationPress = true
                    } else {
                        beginCountdown()
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (confirmationPress) {
                        confirmationPress = false
                        button.performClick()
                    } else if (!awaitingConfirmation) {
                        cancelCountdown()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    confirmationPress = false
                    if (!awaitingConfirmation) cancelCountdown()
                    true
                }
                else -> true
            }
        }
        button.setOnClickListener {
            if (awaitingConfirmation) {
                if (releaseGate.confirm()) releaseCurrentLease()
            } else {
                // Accessibility ACTION_CLICK starts the same five-second gate;
                // a second action can confirm only after the timer arms it.
                beginCountdown()
            }
        }
        return button
    }

    private fun releaseCurrentLease() {
        val sessionId = manager.activeLease()?.sessionId ?: return
        manager.emergencyRelease(sessionId)
        hideOverlay()
        returnToMyLifeGraph()
    }

    private fun returnToMyLifeGraph() {
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            startActivity(it)
        }
    }

    private fun updateRemainingTime() {
        val lease = manager.activeLease()
        if (lease == null) {
            hideOverlay()
            return
        }
        val remainingMs = (lease.endsAtEpochMs - System.currentTimeMillis()).coerceAtLeast(0)
        val totalSeconds = TimeUnit.MILLISECONDS.toSeconds(remainingMs)
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        remainingText?.text = String.format(Locale.ROOT, "%02d:%02d", minutes, seconds)
        if (remainingMs <= 0) {
            manager.expireIfNeeded()
            hideOverlay()
        }
    }

    private fun scheduleRemainingTick() {
        handler.removeCallbacks(remainingTick)
        handler.post(remainingTick)
    }

    private val remainingTick = object : Runnable {
        override fun run() {
            if (overlay == null) return
            updateRemainingTime()
            if (overlay != null) handler.postDelayed(this, 1_000L)
        }
    }

    private fun hideOverlay() {
        handler.removeCallbacks(remainingTick)
        emergencyArmRunnable?.let(handler::removeCallbacks)
        emergencyArmRunnable = null
        overlay?.let { view -> runCatching { windowManager.removeView(view) } }
        overlay = null
        remainingText = null
    }

    private fun textView(value: String, sizeSp: Float, heading: Boolean): TextView =
        TextView(this).apply {
            text = value
            textSize = sizeSp
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            if (heading) {
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                if (android.os.Build.VERSION.SDK_INT >= 28) {
                    isAccessibilityHeading = true
                }
            }
        }

    private fun <T : View> T.withTopMargin(margin: Int): T {
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(margin) }
        return this
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val HOLD_DURATION_MS = 5_000L
        private var runningService: WeakReference<FocusBlockAccessibilityService>? = null

        fun refreshOverlayIfRunning(context: Context) {
            // The context parameter keeps callers explicit about process locality.
            context.applicationContext
            runningService?.get()?.refreshOverlay()
        }
    }
}
