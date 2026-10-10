package com.mylifegraph.app

import android.Manifest
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.app.KeyguardManager
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.nfc.NfcAdapter
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

class BlockingBridge(private val activity: FlutterActivity) {
    private val plans = BlockingPlans(activity)
    private val strictSession = StrictScreenSession(plans::stayOnScreen) { plans.cancelUnlockRequest() }
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val nfcRequest = BlockingPendingRequest<MethodChannel.Result>()
    private var nfcGeneration = 0
    private var nfcReaderActive = false
    private val wifiRequest = BlockingPendingRequest<MethodChannel.Result>()
    private var disposed = false
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF) stopped()
        }
    }
    init {
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            activity.registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(screenReceiver, filter)
        }
    }
    private fun screenUnlocked(): Boolean =
        activity.getSystemService(PowerManager::class.java).isInteractive &&
            !activity.getSystemService(KeyguardManager::class.java).isKeyguardLocked
    private fun requireStrictScreen() {
        if (!screenUnlocked()) stopped()
        strictSession.requireVisible()
    }
    private fun fail(result: MethodChannel.Result, error: Throwable) =
        result.error("blocking_error", error.message ?: "Blocking unavailable", null)
    private fun appIcon(packageName: String): String = runCatching {
        val drawable = activity.packageManager.getApplicationIcon(packageName)
        val bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
        try {
            drawable.setBounds(0, 0, 64, 64); drawable.draw(Canvas(bitmap))
            val bytes = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes)
            Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
        } finally { bitmap.recycle() }
    }.getOrDefault("")
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "status" -> result.success(plans.status())
                "phoneStatus" -> result.success(CoachPhoneUsage(activity).status())
                "phonePermission" -> { activity.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)); result.success(null) }
                "phoneData" -> {
                    check(call.argument<Boolean>("consented") == true) { "Phone sharing consent is required." }
                    val zone = requireNotNull(call.argument<String>("timezone"))
                    worker.execute {
                        val data = runCatching { CoachPhoneUsage(activity).read(zone) }
                        handler.post { if (!disposed) data.fold(onSuccess = result::success, onFailure = { fail(result, it) }) }
                    }
                }
                "save" -> {
                    result.success(plans.save(call.arguments as Map<*, *>))
                    // OS permission only: never enables FCM or changes Cloud consent.
                    runCatching {
                        if (android.os.Build.VERSION.SDK_INT >= 33 &&
                            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
                            !activity.getSharedPreferences("mylifegraph_blocking_timer_ui", 0).getBoolean("asked", false) &&
                            (0 until plans.plans().length()).any { plans.plans().getJSONObject(it).let { p ->
                                p.optLong("untilEpochMs") > System.currentTimeMillis() || p.optInt("budgetMinutes") > 0
                            } }) {
                            activity.getSharedPreferences("mylifegraph_blocking_timer_ui", 0).edit().putBoolean("asked", true).apply()
                            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), TIMER_PERMISSION_REQUEST)
                        }
                    }
                }
                "reorder" -> result.success(plans.reorder(call.arguments as Map<*, *>))
                "consent" -> {
                    result.success(plans.consent(call.argument<String>("kind") ?: "", call.argument<Boolean>("allowed") ?: true))
                    FocusBlockAccessibilityService.refreshOverlayIfRunning(activity)
                }
                "usageSettings" -> {
                    check(plans.usageConsent())
                    activity.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)); result.success(null)
                }
                "wifiPermission" -> {
                    plans.requireEditable()
                    check(wifiRequest.pending == null)
                    if (activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                        result.success(plans.status())
                    } else {
                        wifiRequest.launch(result) {
                            activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION), WIFI_REQUEST)
                        }
                    }
                }
                "strict" -> { result.success(plans.setStrict(call.arguments as Map<*, *>)); runCatching { DisciplineUnlockScheduler.reconcile(activity) } }
                "stayOnScreen" -> result.success(plans.setStayOnScreen(call.arguments as Map<*, *>))
                "cancelUnlock" -> { plans.cancelUnlockRequest(); runCatching { DisciplineUnlockScheduler.reconcile(activity) }; result.success(plans.status()) }
                "strictVisibility" -> {
                    val visible = call.argument<Boolean>("visible") == true
                    strictSession.visibility(visible)
                    if (!visible && nfcRequest.pending != null) cancelNfc("Unlock wait reset.")
                    result.success(plans.status())
                }
                "requestUnlock" -> { requireStrictScreen(); result.success(plans.requestUnlock(call.argument<String>("mode"))); runCatching { DisciplineUnlockScheduler.reconcile(activity) } }
                "finishUnlock" -> { requireStrictScreen(); result.success(plans.finishUnlock()) }
                "tryFinishUnlock" -> {
                    if (!screenUnlocked()) stopped()
                    result.success(if (strictSession.canFinishUnlock()) plans.finishUnlock(onlyIfReady = true) else plans.status())
                    runCatching { DisciplineUnlockScheduler.reconcile(activity) }
                }
                "relock" -> { result.success(plans.relock()); runCatching { DisciplineUnlockScheduler.reconcile(activity) } }
                "removeNfcTag" -> result.success(plans.removeNfcTag(
                    call.argument<String>("id") ?: "", call.argument<Number>("revision")))
                "nfc" -> {
                    val enroll = call.argument<Boolean>("enroll") == true
                    val recovery = call.argument<Boolean>("recovery") == true
                    val replaceId = call.argument<String>("replaceId")
                    require(!recovery || enroll) { "Choose chip enrollment." }
                    val revision = call.argument<Number>("revision")
                    val name = call.argument<String>("name") ?: "Main chip"
                    if (enroll) plans.requireNfcRevision(revision, recovery)
                    else requireStrictScreen()
                    if (recovery) requireStrictScreen()
                    val adapter = NfcAdapter.getDefaultAdapter(activity)
                    check(adapter != null && adapter.isEnabled) { "Enable NFC first." }
                    check(nfcRequest.pending == null) { "A tag scan is already running." }
                    check(!nfcReaderActive) { "Remove the chip before scanning again." }
                    val generation = ++nfcGeneration
                    val contact = BlockingNfcContact(enroll)
                    nfcRequest.launch(result) {
                      try { nfcReaderActive = true; adapter.enableReaderMode(activity, { tag ->
                        handler.post {
                            if (generation != nfcGeneration) return@post
                            val response = nfcRequest.pending ?: return@post
                            try {
                                require(tag.id.isNotEmpty()) { "Use a tag with a stable identifier." }
                                val hash = MessageDigest.getInstance("SHA-256").digest(tag.id)
                                    .joinToString("") { "%02x".format(it) }
                                val complete = contact.scanned(hash) ?: return@post
                                // Keep reader ownership while the chip is touching. Android's normal
                                // tag dispatch must not steal foreground and cancel a valid unlock.
                                val ignored = adapter.ignore(tag, 500, {
                                    handler.post removed@{
                                        if (generation != nfcGeneration) return@removed
                                        contact.removed()
                                        if (complete) cancelNfc("Scan finished.")
                                    }
                                }, handler)
                                check(ignored) { "Remove the chip and try again." }
                                if (!complete) {
                                    android.widget.Toast.makeText(activity, "Remove the tag, then scan it again.", android.widget.Toast.LENGTH_LONG).show()
                                    return@post
                                }
                                if (!enroll || recovery) requireStrictScreen()
                                plans.acceptNfc(hash, enroll, name, revision, recovery, replaceId)
                                // Complete ready requests in the same native turn as the proof.
                                // A remaining timer/other conditions still retain their normal guard.
                                if (!enroll && strictSession.canComplete()) plans.finishUnlock(onlyIfReady = true)
                                nfcRequest.take()
                                response.success(plans.status())
                                runCatching { android.widget.Toast.makeText(activity, "Chip recognized. Remove the chip.", android.widget.Toast.LENGTH_SHORT).show() }
                            } catch (error: Exception) {
                                nfcRequest.take()
                                cancelNfc("Scan failed.")
                                fail(response, error)
                            }
                        }
                    }, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or
                        NfcAdapter.FLAG_READER_NFC_F or NfcAdapter.FLAG_READER_NFC_V or
                        NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK, null)
                      handler.postDelayed({ if (generation == nfcGeneration && nfcRequest.pending != null) cancelNfc("No tag scanned. Try again.") }, 30000)
                      } catch (error: Exception) {
                          ++nfcGeneration
                          nfcReaderActive = false
                          runCatching { adapter.disableReaderMode(activity) }
                          throw error
                      }
                    }
                }
                "cancelNfc" -> { cancelNfc("Scan cancelled."); result.success(null) }
                "catalog" -> {
                    val list = FocusProtectionManager(activity).listLaunchableApps()
                    worker.execute {
                        val catalog = list.map { app ->
                            val pkg = app.getValue("packageName")
                            val icon = appIcon(pkg)
                            val category = runCatching {
                                if (android.os.Build.VERSION.SDK_INT < 26) return@runCatching "Other"
                                when (activity.packageManager.getApplicationInfo(pkg, 0).category) {
                                    android.content.pm.ApplicationInfo.CATEGORY_GAME -> "Games"
                                    android.content.pm.ApplicationInfo.CATEGORY_SOCIAL -> "Social"
                                    android.content.pm.ApplicationInfo.CATEGORY_VIDEO,
                                    android.content.pm.ApplicationInfo.CATEGORY_AUDIO -> "Entertainment"
                                    android.content.pm.ApplicationInfo.CATEGORY_PRODUCTIVITY -> "Work"
                                    else -> "Other"
                                }
                            }.getOrDefault("Other")
                            app + mapOf("icon" to icon, "category" to category)
                        }
                        handler.post { if (!disposed) result.success(catalog) }
                    }
                }
                "insights" -> {
                    val days = call.argument<Int>("days") ?: 7
                    worker.execute {
                        try {
                            val data = plans.insights(days)
                            val apps = (data["apps"] as List<*>).map { row ->
                                val app = row as Map<*, *>
                                app + mapOf("icon" to appIcon(app["packageName"] as String))
                            }
                            handler.post { if (!disposed) result.success(data + mapOf("apps" to apps)) }
                        } catch (e: Exception) { handler.post { if (!disposed) fail(result, e) } }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { fail(result, e) }
    }
    fun permissionResult(code: Int) {
        if (code == TIMER_PERMISSION_REQUEST) { BlockingTimerNotifications.sync(activity); return }
        if (code != WIFI_REQUEST) return
        val response = wifiRequest.take() ?: return
        runCatching { plans.status() }.fold(onSuccess = response::success,
            onFailure = { fail(response, it) })
    }
    private fun cancelNfc(message: String) {
        ++nfcGeneration
        val response = nfcRequest.take()
        if (nfcReaderActive) runCatching { NfcAdapter.getDefaultAdapter(activity)?.disableReaderMode(activity) }
        nfcReaderActive = false
        response?.error("blocking_error", message, null)
    }
    fun resumed() {
        if (screenUnlocked()) strictSession.resumed() else stopped()
    }
    fun windowFocusChanged(focused: Boolean) {
        if (!screenUnlocked()) stopped() else strictSession.focus(focused)
    }
    fun paused() { strictSession.paused(); cancelNfc("Scan cancelled. Keep the app open.") }
    fun stopped() { strictSession.stopped(); cancelNfc("Unlock wait reset.") }
    fun dispose() {
        strictSession.stopped()
        runCatching { activity.unregisterReceiver(screenReceiver) }
        disposed = true; cancelNfc("Scan cancelled.")
        wifiRequest.take()?.error("blocking_error", "Permission request cancelled", null)
        handler.removeCallbacksAndMessages(null); worker.shutdownNow()
    }
    companion object { const val CHANNEL = "com.mylifegraph.app/blocking_v2"; private const val WIFI_REQUEST = 9104; private const val TIMER_PERMISSION_REQUEST = 9105 }
}
