package com.mylifegraph.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
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
    private lateinit var plans: BlockingPlans
    private var currentHost: String? = null
    private var lastMeterAt = 0L
    private var lastRedirect = ""
    private var lastRedirectAt = 0L
    private var returnButton: Button? = null
    private var returnDeadline = 0L
    private var textColor = Color.WHITE

    override fun onServiceConnected() {
        super.onServiceConnected()
        manager = FocusProtectionManager(applicationContext)
        plans = BlockingPlans(applicationContext)
        windowManager = getSystemService(WindowManager::class.java)
        runningService = WeakReference(this)
        handler.removeCallbacks(scheduleTick)
        handler.post(scheduleTick)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            if (plans.websiteConsent() && event.packageName?.toString() in BrowserAddressBars.adapters) {
                handler.removeCallbacks(browserTick); handler.postDelayed(browserTick, 150)
            }
            return
        }
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val foregroundPackage = event.packageName?.toString()
        // Our overlay emits window events too. Keep the underlying package;
        // real entry into MyLifeGraph is reported by MainActivity.onResume.
        if (!FocusProtectionDecision.ignoreForegroundEvent(
                foregroundPackage, packageName, overlay != null,
            )
        ) {
            if (lastForegroundPackage != foregroundPackage) { currentHost = null; lastMeterAt = SystemClock.elapsedRealtime() }
            lastForegroundPackage = foregroundPackage
        }
        checkBrowser()
        refreshOverlay()
    }

    override fun onInterrupt() {
        if (::plans.isInitialized) plans.flushSiteUsage()
        hideOverlay()
    }

    override fun onDestroy() {
        BlockingTimerNotifications.disconnected(applicationContext)
        if (::plans.isInitialized) plans.flushSiteUsage()
        if (runningService?.get() === this) runningService = null
        handler.removeCallbacksAndMessages(null)
        hideOverlay()
        super.onDestroy()
    }

    private fun refreshOverlay() {
        updateBrowserSubscription()
        if (!manager.shouldBlock(lastForegroundPackage)) {
            hideOverlay()
            return
        }
        if (overlay == null) showOverlay()
        updateRemainingTime()
    }

    private fun showOverlay() {
        val custom = plans.custom()
        val colors = BlockingScreenIcon.colors(custom.optString("tone", "glass"))
        textColor = Color.parseColor(colors.second)
        val base = Color.parseColor(colors.first)
        val background = when (custom.optString("tone", "glass")) {
            "light", "dark" -> intArrayOf(base, base)
            "space" -> intArrayOf(base, Color.parseColor("#171A38"))
            else -> intArrayOf(base, Color.parseColor("#141A22"), base)
        }
        val count = plans.attempts("app:${lastForegroundPackage.orEmpty()}")
        plans.recordAttempt("app:${lastForegroundPackage.orEmpty()}")
        val root = ScrollView(this).apply {
            this.background = GradientDrawable(GradientDrawable.Orientation.TL_BR, background)
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
        content.addView(textView(BlockingScreenIcon.symbol(custom.optString("icon", "shield")), 48f, false))
        content.addView(textView(custom.optString("title", "Stay focused"), 30f, true))
        content.addView(
            textView(
                custom.optString("message", "Take a breath. Choose your next step."),
                18f,
                false,
            ).withTopMargin(16),
        )
        remainingText = textView("", 40f, true).also {
            it.contentDescription = "Focus time remaining"
            content.addView(it.withTopMargin(24))
        }
        returnDeadline = SystemClock.elapsedRealtime() + custom.optInt("waitSeconds") * 1000L
        returnButton = Button(this).apply {
                text = "Return to MyLifeGraph"
                textSize = 18f
                contentDescription = "Return to MyLifeGraph"
                setOnClickListener { returnToMyLifeGraph() }
            }
        content.addView(returnButton!!.withTopMargin(32))
        content.addView(textView("${count.first + 1} today · ${count.second + 1} total", 15f, false).withTopMargin(16))
        if (!plans.locked()) content.addView(emergencyButton().withTopMargin(16))
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
        runCatching { manager.releaseAppBlocking() }
        refreshOverlay()
        returnToMyLifeGraph()
    }

    private fun returnToMyLifeGraph() {
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            startActivity(it)
        }
    }

    private fun updateRemainingTime() {
        val seconds = ((returnDeadline - SystemClock.elapsedRealtime()).coerceAtLeast(0) + 999) / 1000
        returnButton?.isEnabled = seconds == 0L
        returnButton?.text = if (seconds > 0) "Return in ${seconds}s" else "Return to MyLifeGraph"
        if (!manager.appBlockingActive(lastForegroundPackage)) {
            hideOverlay()
            return
        }
        if (manager.blockingMode() != "focus") {
            remainingText?.textSize = 24f
            remainingText?.text = manager.blockingSummary()
            remainingText?.contentDescription = manager.blockingSummary()
            return
        }
        val lease = manager.activeLease()
        if (lease == null) {
            hideOverlay()
            return
        }
        val remainingMs = (lease.endsAtEpochMs - System.currentTimeMillis()).coerceAtLeast(0)
        val totalSeconds = TimeUnit.MILLISECONDS.toSeconds(remainingMs)
        val minutes = totalSeconds / 60
        val remainingSeconds = totalSeconds % 60
        remainingText?.text = String.format(Locale.ROOT, "%02d:%02d", minutes, remainingSeconds)
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

    // Re-evaluate even if the user stays inside an app as a weekly window starts.
    // No wake lock, exact alarm or new service: one check per wall-clock minute.
    private val scheduleTick = object : Runnable {
        override fun run() {
            if (::plans.isInitialized) {
                BlockingTimerNotifications.sync(applicationContext)
                val elapsed = SystemClock.elapsedRealtime()
                val host = currentHost
                val browser = lastForegroundPackage
                if (host != null && browser != null && plans.websiteObservationEnabled() && overlay == null &&
                    getSystemService(android.os.PowerManager::class.java).isInteractive) {
                    plans.meterSite(host, browser, elapsed - lastMeterAt)
                }
                lastMeterAt = elapsed
                checkBrowser()
            }
            if (manager.blockingMode() != "focus") refreshOverlay()
            handler.postDelayed(this, if (::plans.isInitialized && plans.migrated()) 1000L
                else 60_000L - System.currentTimeMillis() % 60_000L)
        }
    }

    private val browserTick = Runnable { checkBrowser() }
    private fun updateBrowserSubscription() {
        val info = serviceInfo ?: return
        val enabled = plans.websiteObservationEnabled()
        val events = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
            if (enabled) AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED else 0
        val flags = if (enabled) info.flags or AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            else info.flags and AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS.inv()
        if (info.eventTypes != events || info.flags != flags) {
            info.eventTypes = events; info.flags = flags; serviceInfo = info
        }
        if (!enabled) currentHost = null
    }
    @Suppress("DEPRECATION")
    private fun checkBrowser() {
        if (!::plans.isInitialized) return
        if (!plans.websiteObservationEnabled()) { currentHost = null; return }
        val pkg = lastForegroundPackage ?: return
        if (pkg !in BrowserAddressBars.adapters) { currentHost = null; return }
        // Whole-browser app rules win; do not miscount their URL as a site attempt.
        if (manager.shouldBlock(pkg)) { currentHost = null; return }
        // Only query a known URL resource ID after explicit website consent.
        val root = rootInActiveWindow ?: run { currentHost = null; return }
        val host = try { BrowserAddressBars.host(root, pkg) } finally { root.recycle() }
        currentHost = host
        if (host == null || pkg in manager.essentialPackages() || plans.blocked(pkg, host) == null) return
        val key = "$pkg|$host"
        val elapsed = SystemClock.elapsedRealtime()
        if (key == lastRedirect && elapsed - lastRedirectAt < 3000) return
        lastRedirect = key; lastRedirectAt = elapsed
        plans.recordAttempt("web:$host")
        currentHost = null
        // Deliberately do not edit the browser URL or invent a reliable submit action.
        // Our offline page consumes Back by returning Home, never to the blocked tab.
        startActivity(Intent(this, LocalBlockPageActivity::class.java)
            .putExtra("target", host).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
    }

    private fun hideOverlay() {
        handler.removeCallbacks(remainingTick)
        emergencyArmRunnable?.let(handler::removeCallbacks)
        emergencyArmRunnable = null
        overlay?.let { view -> runCatching { windowManager.removeView(view) } }
        overlay = null
        remainingText = null
        returnButton = null
    }

    private fun textView(value: String, sizeSp: Float, heading: Boolean): TextView =
        TextView(this).apply {
            text = value
            textSize = sizeSp
            gravity = Gravity.CENTER
            setTextColor(textColor)
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

        fun onAppResumed(context: Context) {
            runningService?.get()?.let { service ->
                service.lastForegroundPackage = context.packageName
                service.currentHost = null
                service.lastMeterAt = SystemClock.elapsedRealtime()
                service.plans.flushSiteUsage()
                service.refreshOverlay()
            }
        }

        fun refreshOverlayIfRunning(context: Context) {
            // The context parameter keeps callers explicit about process locality.
            context.applicationContext
            BlockingTimerNotifications.sync(context)
            runningService?.get()?.refreshOverlay()
        }
    }
}
