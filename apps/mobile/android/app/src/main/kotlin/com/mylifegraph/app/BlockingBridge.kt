package com.mylifegraph.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.nfc.NfcAdapter
import android.os.Handler
import android.os.Looper
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
    private val strictSession = StrictScreenSession { plans.cancelUnlockRequest() }
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val nfcRequest = BlockingPendingRequest<MethodChannel.Result>()
    private var nfcGeneration = 0
    private val wifiRequest = BlockingPendingRequest<MethodChannel.Result>()
    private var disposed = false
    private fun fail(result: MethodChannel.Result, error: Throwable) =
        result.error("blocking_error", error.message ?: "Blocking unavailable", null)
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
                            (0 until plans.plans().length()).any { plans.plans().getJSONObject(it).optLong("untilEpochMs") > System.currentTimeMillis() }) {
                            activity.getSharedPreferences("mylifegraph_blocking_timer_ui", 0).edit().putBoolean("asked", true).apply()
                            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), TIMER_PERMISSION_REQUEST)
                        }
                    }
                }
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
                "strict" -> result.success(plans.setStrict(call.arguments as Map<*, *>))
                "strictVisibility" -> {
                    val visible = call.argument<Boolean>("visible") == true
                    strictSession.visibility(visible)
                    if (!visible) cancelNfc("Unlock wait reset.")
                    result.success(plans.status())
                }
                "requestUnlock" -> { strictSession.requireVisible(); result.success(plans.requestUnlock()) }
                "finishUnlock" -> { strictSession.requireVisible(); result.success(plans.finishUnlock()) }
                "relock" -> result.success(plans.relock())
                "nfc" -> {
                    val enroll = call.argument<Boolean>("enroll") == true
                    if (enroll) plans.requireEditable()
                    else strictSession.requireVisible()
                    val adapter = NfcAdapter.getDefaultAdapter(activity)
                    check(adapter != null && adapter.isEnabled) { "Enable NFC first." }
                    check(nfcRequest.pending == null) { "A tag scan is already running." }
                    val generation = ++nfcGeneration
                    var firstTag: String? = null
                    nfcRequest.launch(result) {
                      try { adapter.enableReaderMode(activity, { tag ->
                        handler.post {
                            if (generation != nfcGeneration) return@post
                            val response = nfcRequest.pending ?: return@post
                            val data = runCatching {
                                require(tag.id.isNotEmpty()) { "Use a tag with a stable identifier." }
                                val hash = MessageDigest.getInstance("SHA-256").digest(tag.id)
                                    .joinToString("") { "%02x".format(it) }
                                if (enroll && firstTag == null) {
                                    firstTag = hash
                                    android.widget.Toast.makeText(activity, "Remove the tag, then scan it again.", android.widget.Toast.LENGTH_LONG).show()
                                    return@post
                                }
                                require(!enroll || hash == firstTag) { "Use the same tag with a stable identifier." }
                                hash
                            }
                            // Consume the reply before cleanup, persistence or callback.
                            // Driver cleanup itself must not prevent a retry.
                            nfcRequest.take(); ++nfcGeneration
                            runCatching { adapter.disableReaderMode(activity) }
                            data.fold(onSuccess = { hash ->
                                runCatching { plans.acceptNfc(hash, enroll); plans.status() }
                                    .fold(onSuccess = response::success, onFailure = { fail(response, it) })
                            }, onFailure = { fail(response, it) })
                        }
                    }, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or
                        NfcAdapter.FLAG_READER_NFC_F or NfcAdapter.FLAG_READER_NFC_V or
                        NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK, null)
                      handler.postDelayed({ if (generation == nfcGeneration) cancelNfc("No tag scanned. Try again.") }, 30000)
                      } catch (error: Exception) {
                          ++nfcGeneration
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
                            val icon = runCatching {
                                val drawable = activity.packageManager.getApplicationIcon(pkg)
                                val bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
                                drawable.setBounds(0, 0, 64, 64); drawable.draw(Canvas(bitmap))
                                val bytes = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes); bitmap.recycle()
                                Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
                            }.getOrDefault("")
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
                            handler.post { if (!disposed) result.success(data) }
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
        val response = nfcRequest.take() ?: return
        runCatching { NfcAdapter.getDefaultAdapter(activity)?.disableReaderMode(activity) }
        response.error("blocking_error", message, null)
    }
    fun resumed() { strictSession.resumed() }
    fun paused() { strictSession.paused(); cancelNfc("Scan cancelled. Keep the app open.") }
    fun dispose() {
        strictSession.paused()
        disposed = true; cancelNfc("Scan cancelled.")
        wifiRequest.take()?.error("blocking_error", "Permission request cancelled", null)
        handler.removeCallbacksAndMessages(null); worker.shutdownNow()
    }
    companion object { const val CHANNEL = "com.mylifegraph.app/blocking_v2"; private const val WIFI_REQUEST = 9104; private const val TIMER_PERMISSION_REQUEST = 9105 }
}
