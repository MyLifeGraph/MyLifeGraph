package com.mylifegraph.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.Button
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.util.Locale
import java.util.concurrent.TimeUnit

class FocusBlockAccessibilityService : AccessibilityService() {
    private lateinit var manager: FocusProtectionManager
    private lateinit var windowManager: WindowManager
    private val handler = Handler(Looper.getMainLooper())
    private var overlay: View? = null
    private var blockScreen: BlockingScreenView? = null
    private val returnDelay = BlockReturnDelay()
    private val returnNavigation = BlockingReturnNavigation()
    private var homePackages: Set<String> = emptySet()
    private var lastForegroundPackage: String? = null
    private var lastForegroundObservedAt = 0L
    private var returnNavigationAt = 0L
    private var budgetForegroundPackage: String? = null
    private var budgetHost: String? = null
    private var emergencyArmRunnable: Runnable? = null
    private lateinit var plans: BlockingPlans
    private var currentHost: String? = null
    private var lastMeterAt = 0L
    private var lastRedirect = ""
    private var lastRedirectAt = 0L
    private var neutralBrowser: BrowserNeutralization? = null
    private val neutralTick = Runnable { advanceNeutralBrowser() }
    private var lastProtectionCheck = -1000L
    // Retain a bounded set of overlay IDs for removal events after a window
    // disappears. No package names, roots, titles or content are retained.
    private val transientWindows = BlockingTransientWindows()

    override fun onServiceConnected() {
        super.onServiceConnected()
        manager = FocusProtectionManager(applicationContext)
        plans = BlockingPlans(applicationContext)
        windowManager = getSystemService(WindowManager::class.java)
        homePackages = packageManager.queryIntentActivities(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
            PackageManager.MATCH_ALL,
        ).map { it.activityInfo.packageName }.toSet()
        runningService = WeakReference(this)
        updateBrowserSubscription()
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
        // Queued origin events must not resurrect a completed return attempt.
        if (event.eventTime < returnNavigationAt) return
        val foregroundPackage = event.packageName?.toString()
        // Opening our bounded address-bar editor may emit an IME event before
        // its window metadata is available. It is not an application switch.
        if (neutralBrowser != null && getSystemService(android.view.inputmethod.InputMethodManager::class.java)
                .inputMethodList.any { it.packageName == foregroundPackage }) {
            advanceNeutralBrowser(); return
        }
        if (FocusProtectionDecision.ignoreOverlayWindow(foregroundPackage,
                transientWindow(event.windowId))) return
        // Our overlay emits window events too. Keep the underlying package;
        // real entry into MyLifeGraph is reported by MainActivity.onResume.
        if (!FocusProtectionDecision.ignoreForegroundEvent(
                foregroundPackage, packageName,
            )
        ) {
            if (lastForegroundPackage != foregroundPackage) { currentHost = null; lastMeterAt = SystemClock.elapsedRealtime(); lastRedirect = "" }
            lastForegroundPackage = foregroundPackage
            lastForegroundObservedAt = System.currentTimeMillis() -
                (SystemClock.uptimeMillis() - event.eventTime).coerceAtLeast(0)
            budgetForegroundPackage = FocusProtectionDecision.budgetForeground(
                foregroundPackage, budgetForegroundPackage, packageName,
            )
        }
        checkBrowser()
        budgetHost = FocusProtectionDecision.budgetHost(foregroundPackage, currentHost, budgetHost, packageName)
        refreshOverlay()
        BlockingTimerNotifications.syncForeground(applicationContext, plans, budgetForegroundPackage, budgetHost, overlay == null)
    }

    @Suppress("DEPRECATION")
    private fun transientWindow(id: Int): Boolean {
        if (id < 0) return false
        // Metadata only: never call getRoot/getSource or inspect another app.
        val type = runCatching {
            val snapshot = windows
            try { snapshot.firstOrNull { it.id == id }?.type }
            finally { snapshot.forEach { it.recycle() } }
        }.getOrNull()
        val kind = when (type) {
            AccessibilityWindowInfo.TYPE_APPLICATION -> BlockingWindowKind.APPLICATION
            AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY,
            AccessibilityWindowInfo.TYPE_SYSTEM, AccessibilityWindowInfo.TYPE_INPUT_METHOD,
            AccessibilityWindowInfo.TYPE_SPLIT_SCREEN_DIVIDER,
            AccessibilityWindowInfo.TYPE_MAGNIFICATION_OVERLAY -> BlockingWindowKind.TRANSIENT
            else -> BlockingWindowKind.UNKNOWN
        }
        return transientWindows.observe(id, kind)
    }

    override fun onInterrupt() {
        returnNavigation.clear()
        cancelNeutralBrowser()
        BlockingTimerNotifications.disconnected(applicationContext)
        if (::plans.isInitialized) plans.flushSiteUsage()
        hideOverlay()
    }

    override fun onDestroy() {
        returnNavigation.clear()
        cancelNeutralBrowser()
        BlockingTimerNotifications.disconnected(applicationContext)
        if (::plans.isInitialized) plans.flushSiteUsage()
        if (runningService?.get() === this) runningService = null
        handler.removeCallbacksAndMessages(null)
        hideOverlay()
        super.onDestroy()
    }

    private fun refreshOverlay() {
        updateBrowserSubscription()
        if (returnNavigation.source != null) {
            val destination = returnNavigation.destination(lastForegroundPackage, packageName, homePackages,
                manager.shouldBlock(returnNavigation.source))
            if (destination == BlockingReturnNavigation.Destination.WAIT) return
            returnNavigation.clear()
            hideOverlay()
            if (destination == BlockingReturnNavigation.Destination.HOME) {
                handler.postDelayed({
                    if (lastForegroundPackage in homePackages) launchMyLifeGraph()
                }, 250)
            }
            if (destination != BlockingReturnNavigation.Destination.OTHER) return
        }
        val foregroundBlocked = manager.shouldBlock(lastForegroundPackage)
        val source = returnDelay.target
        if (source != null && !manager.shouldBlock(source)) returnDelay.clear()
        if (foregroundBlocked && returnDelay.target == null) {
            val target = lastForegroundPackage ?: return
            if (returnDelay.begin(target, plans.custom().optInt("waitSeconds"), SystemClock.elapsedRealtime())) {
                runCatching { plans.recordAttempt("app:$target") }
            }
        }
        val homeOrOwn = lastForegroundPackage == packageName || lastForegroundPackage in homePackages
        if (!returnDelay.retain(
                returnDelay.target?.let(manager::shouldBlock) == true,
                foregroundBlocked,
                homeOrOwn,
            )) {
            // System UI remains reachable without resetting the finite attempt.
            // Settings/phone/alarms and other apps are genuine safe escape routes.
            hideOverlay(clearAttempt = lastForegroundPackage != "com.android.systemui")
            return
        }
        if (overlay == null) showOverlay()
        updateRemainingTime()
    }

    private fun showOverlay() {
        val custom = plans.custom()
        val count = plans.attempts("app:${returnDelay.target.orEmpty()}")
        val root = BlockingScreenView(
            this, custom,
            JSONObject().put("today", count.first).put("total", count.second),
            manager.blockingSummary(), plans.strict().optBoolean("enabled"),
            { returnToMyLifeGraph() }, emergencyButton(),
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
            .onSuccess { overlay = root; blockScreen = root }
            .onFailure { root.dispose(); returnDelay.clear() }
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
        if (plans.strict().optBoolean("enabled")) return
        runCatching { manager.releaseAppBlocking() }
            .onSuccess {
                hideOverlay()
                launchMyLifeGraph()
            }
            .onFailure { refreshOverlay() }
    }

    private fun returnToMyLifeGraph() {
        // An accepted global action is asynchronous. Keep the screen until an
        // actual safe destination is observed, with the enabled button retryable.
        val source = returnNavigation.source ?: returnDelay.target ?: return
        if (returnNavigation.source != null) {
            performGlobalAction(GLOBAL_ACTION_HOME)
            return
        }
        returnDelay.exitViaHome(SystemClock.elapsedRealtime(), {
            // Put the denied app behind Home before removing its blocking screen.
            returnNavigationAt = SystemClock.uptimeMillis()
            performGlobalAction(GLOBAL_ACTION_HOME) || runCatching {
                startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }.isSuccess
        }, {
            // No lease, Strict setting or rule is released by this navigation.
            lastForegroundObservedAt = System.currentTimeMillis()
            returnNavigation.begin(source)
            refreshOverlay()
        })
    }

    private fun launchMyLifeGraph() {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val opened = launch != null && runCatching {
            startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
        }.isSuccess
        if (!opened) {
            runCatching {
                startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
    }

    private fun updateRemainingTime() {
        val elapsed = SystemClock.elapsedRealtime()
        blockScreen?.updateReturn(returnDelay.remaining(elapsed), returnDelay.durationMs)
        // Paint progress smoothly without polling package/rule authority at 10Hz.
        if (elapsed - lastProtectionCheck < 1000) return
        lastProtectionCheck = elapsed
        blockScreen?.updateStrictLocked(plans.strict().optBoolean("enabled"))
        if ((returnDelay.target ?: returnNavigation.source)?.let(manager::shouldBlock) != true) {
            returnNavigation.clear()
            hideOverlay()
            return
        }
        if (manager.blockingMode() != "focus") {
            blockScreen?.updateSummary(manager.blockingSummary())
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
        blockScreen?.updateSummary(String.format(Locale.ROOT, "%02d:%02d", minutes, remainingSeconds))
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
            if (overlay != null) handler.postDelayed(this, 100L)
        }
    }

    // Re-evaluate even if the user stays inside an app as a weekly window starts.
    // No wake lock, exact alarm or new service: one check per wall-clock minute.
    private val scheduleTick = object : Runnable {
        override fun run() {
            var foregroundRecovered = false
            if (::plans.isInitialized) {
                foregroundRecovered = recoverForegroundFromUsage()
                runCatching { DisciplineUnlockScheduler.reconcile(applicationContext) }
                BlockingTimerNotifications.sync(applicationContext)
                BlockingTimerNotifications.syncForeground(applicationContext, plans, budgetForegroundPackage, budgetHost, overlay == null)
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
            if (FocusProtectionDecision.refreshAfterForegroundCheck(manager.blockingMode(), foregroundRecovered)) {
                refreshOverlay()
            }
            handler.postDelayed(this, if (::plans.isInitialized && plans.migrated()) 1000L
                else 60_000L - System.currentTimeMillis() % 60_000L)
        }
    }

    private fun recoverForegroundFromUsage(): Boolean {
        if (!getSystemService(android.os.PowerManager::class.java).isInteractive ||
            getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked) return false
        val config = FocusProtectionStore(applicationContext).readConfiguration()
        if (!config.enabled || !config.blockSelectedApps) return false
        val observed = runCatching { plans.foregroundObservation() }.getOrNull() ?: return false
        val recovered = FocusProtectionDecision.recoverForeground(lastForegroundPackage,
            lastForegroundObservedAt, observed.first, observed.second, packageName)
        if (recovered == lastForegroundPackage) return false
        lastForegroundPackage = recovered
        lastForegroundObservedAt = observed.second
        budgetForegroundPackage = recovered
        currentHost = null; budgetHost = null; lastMeterAt = SystemClock.elapsedRealtime()
        return true
    }

    private val browserTick = Runnable { checkBrowser() }
    private fun updateBrowserSubscription() {
        val info = serviceInfo ?: return
        val enabled = plans.websiteObservationEnabled()
        val events = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
            if (enabled) AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED else 0
        val windowFlags = info.flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        val flags = if (enabled) windowFlags or AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            else windowFlags and AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS.inv()
        if (info.eventTypes != events || info.flags != flags) {
            info.eventTypes = events; info.flags = flags; serviceInfo = info
        }
        if (!enabled) currentHost = null
    }
    @Suppress("DEPRECATION")
    private fun checkBrowser() {
        if (!::plans.isInitialized) return
        if (neutralBrowser != null) { advanceNeutralBrowser(); return }
        if (!plans.websiteObservationEnabled()) { currentHost = null; budgetHost = null; return }
        val pkg = lastForegroundPackage ?: return
        if (pkg !in BrowserAddressBars.adapters) { currentHost = null; return }
        // Whole-browser app rules win; do not miscount their URL as a site attempt.
        if (manager.shouldBlock(pkg)) { currentHost = null; return }
        // Only query a known URL resource ID after explicit website consent.
        val root = rootInActiveWindow ?: run { currentHost = null; return }
        // Shade/notification roots are not the remembered browser. Preserve its
        // display-only host, but never meter or inspect those unrelated windows.
        if (root.packageName?.toString() != pkg) {
            root.recycle(); currentHost = null; return
        }
        val windowId = root.windowId
        val host = try { BrowserAddressBars.host(root, pkg) } finally { root.recycle() }
        currentHost = host
        budgetHost = host
        if (host == null || pkg in manager.essentialPackages() || plans.blocked(pkg, host) == null) return
        val key = "$pkg|$host"
        val elapsed = SystemClock.elapsedRealtime()
        if (key == lastRedirect && elapsed - lastRedirectAt < 3000) return
        lastRedirect = key; lastRedirectAt = elapsed
        plans.recordAttempt("web:$host")
        currentHost = null
        neutralBrowser = BrowserNeutralization(pkg, host, windowId, elapsed)
        advanceNeutralBrowser()
    }

    private fun cancelNeutralBrowser(clearDuplicate: Boolean = true) {
        handler.removeCallbacks(neutralTick)
        neutralBrowser = null
        if (clearDuplicate) lastRedirect = ""
    }

    @Suppress("DEPRECATION")
    private fun advanceNeutralBrowser() {
        val pending = neutralBrowser ?: return
        handler.removeCallbacks(neutralTick)
        if (!plans.websiteObservationEnabled() || lastForegroundPackage != pending.packageName ||
            manager.shouldBlock(pending.packageName) || plans.blocked(pending.packageName, pending.host) == null) {
            cancelNeutralBrowser(); return
        }
        val active = rootInActiveWindow
        if (active != null && (active.windowId != pending.windowId || active.packageName?.toString() != pending.packageName)) {
            active.recycle(); cancelNeutralBrowser(); return
        }
        val root = if (active != null) active else {
            val snapshot = windows
            try { snapshot.firstOrNull { it.id == pending.windowId &&
                it.type == AccessibilityWindowInfo.TYPE_APPLICATION && it.isActive }?.root }
            finally { snapshot.forEach { it.recycle() } }
        }
        if (root == null) {
            if (!pending.expired(SystemClock.elapsedRealtime())) handler.postDelayed(neutralTick, 80)
            else { cancelNeutralBrowser(false); openWebsiteBlock(pending.host) }
            return
        }
        val action = try {
            if (root.packageName?.toString() != pending.packageName || root.windowId != pending.windowId) {
                cancelNeutralBrowser(); return
            }
            runCatching { BrowserAddressBars.neutralStep(root, pending, SystemClock.elapsedRealtime()) }
                .getOrDefault(BrowserNeutralization.Action.ABORT)
        } finally { root.recycle() }
        when (action) {
            BrowserNeutralization.Action.WAIT -> handler.postDelayed(neutralTick, 80)
            BrowserNeutralization.Action.COMPLETE, BrowserNeutralization.Action.ABORT -> {
                cancelNeutralBrowser(false); currentHost = null; budgetHost = null
                openWebsiteBlock(pending.host)
            }
            else -> { cancelNeutralBrowser(false); openWebsiteBlock(pending.host) }
        }
    }

    private fun openWebsiteBlock(host: String) {
        runCatching {
            startActivity(Intent(this, LocalBlockPageActivity::class.java)
                .putExtra("target", host).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
        }.onFailure { performGlobalAction(GLOBAL_ACTION_HOME) }
    }

    private fun hideOverlay(clearAttempt: Boolean = true) {
        if (clearAttempt) returnDelay.clear()
        handler.removeCallbacks(remainingTick)
        emergencyArmRunnable?.let(handler::removeCallbacks)
        emergencyArmRunnable = null
        overlay?.let { view -> runCatching { windowManager.removeViewImmediate(view) } }
        blockScreen?.dispose()
        overlay = null
        blockScreen = null
    }

    companion object {
        private const val HOLD_DURATION_MS = 5_000L
        private var runningService: WeakReference<FocusBlockAccessibilityService>? = null

        fun onAppResumed(context: Context) {
            runningService?.get()?.let { service ->
                service.lastForegroundPackage = context.packageName
                service.lastForegroundObservedAt = System.currentTimeMillis()
                service.budgetForegroundPackage = context.packageName
                service.budgetHost = null
                service.currentHost = null
                if (service.returnNavigation.source != null) {
                    service.returnNavigation.clear()
                    service.hideOverlay()
                }
                service.cancelNeutralBrowser()
                // A real new browser entry must re-check the same denied host.
                service.lastRedirect = ""
                service.lastMeterAt = SystemClock.elapsedRealtime()
                service.plans.flushSiteUsage()
                service.refreshOverlay()
                BlockingTimerNotifications.syncForeground(context, service.plans, context.packageName, null, true)
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
