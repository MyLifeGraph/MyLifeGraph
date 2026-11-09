package com.mylifegraph.app

import android.content.Context
import android.os.SystemClock
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject

/** Device-only policy, deliberately independent from Focus leases and Discipline. */
class PhoneLockStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("mylifegraph_phone_lock_v1", Context.MODE_PRIVATE)
    private fun boot() = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
    private fun read() = JSONObject(prefs.getString("lock", "{}") ?: "{}")
    private fun write(value: JSONObject) {
        check(prefs.edit().putString("lock", value.toString()).commit()) { "Could not save Phone lock." }
    }
    private fun remaining(value: JSONObject, prefix: String): Long {
        val result = PhoneLockPolicy.remaining(value.optLong("${prefix}Wall"), value.optLong("${prefix}Elapsed"),
            value.optLong("${prefix}Duration"), value.optInt("${prefix}Boot", -2), boot(),
            System.currentTimeMillis(), SystemClock.elapsedRealtime())
        if (result > 0 && value.optInt("${prefix}Boot", -2) != boot()) {
            value.put("${prefix}Boot", boot()).put("${prefix}Elapsed", SystemClock.elapsedRealtime() + result)
            .put("${prefix}Duration", result)
            write(value)
        }
        return result
    }
    fun current(): JSONObject = synchronized(MUTEX) {
        val value = read()
        if (value.optBoolean("active") &&
            ((value.optString("mode") == "timer" && remaining(value, "end") == 0L) ||
                (value.has("recoveryWall") && remaining(value, "recovery") == 0L))) {
            value.put("active", false)
            write(value)
        }
        value
    }
    fun active() = current().optBoolean("active")
    fun status(): Map<String, Any?> {
        val value = current()
        val config = FocusProtectionStore(context).readConfiguration()
        val manager = context.getSystemService(android.view.accessibility.AccessibilityManager::class.java)
        val service = manager.getEnabledAccessibilityServiceList(android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { it.resolveInfo.serviceInfo.name == FocusBlockAccessibilityService::class.java.name &&
                it.resolveInfo.serviceInfo.packageName == context.packageName }
        val tags = BlockingPlans(context).phoneLockNfcHashes()
        val phoneAvailable = PhoneLockSafety.phoneAvailable(context)
        return mapOf("contractVersion" to BlockingPlans.CONTRACT_VERSION,
            "active" to value.optBoolean("active"), "id" to value.optString("id"),
            "mode" to value.optString("mode", "timer"),
            "remainingMs" to (if (value.optString("mode") == "timer" && value.optBoolean("active")) remaining(value, "end") else 0L),
            "durationMs" to value.optLong("durationMs"),
            "recoveryStarted" to value.has("recoveryWall"),
            "recoveryRemainingMs" to (if (value.optBoolean("active") && value.has("recoveryWall")) remaining(value, "recovery") else 0L),
            "allowedApps" to BlockingPlans.strings(value.optJSONArray("allowedApps") ?: JSONArray()).toList(),
            "ready" to (config.enabled && config.blockSelectedApps && service && phoneAvailable),
            "protectionEnabled" to (config.enabled && config.blockSelectedApps),
            "accessibilityEnabled" to service,
            "phoneAvailable" to phoneAvailable,
            "nfcEnrolled" to tags.isNotEmpty(),
            "nfcAvailable" to (android.nfc.NfcAdapter.getDefaultAdapter(context)?.isEnabled == true))
    }
    fun start(args: Map<*, *>): Map<String, Any?> = synchronized(MUTEX) {
        val id = (args["requestId"] as? String)?.takeIf { it.length in 1..128 } ?: error("Missing Phone lock request.")
        val previous = current()
        // Exact retries can never extend a live timer or resurrect a completed request.
        if (previous.optString("id") == id) return@synchronized status()
        check(!previous.optBoolean("active")) { "Phone lock is already active." }
        check(status()["ready"] == true) { "Enable app protection and Accessibility first." }
        val mode = args["mode"] as? String
        require(mode in setOf("timer", "nfc")) { "Choose Timer or NFC chip." }
        val minutes = (args["minutes"] as? Number)?.toLong() ?: 45L
        require(minutes in 5..240) { "Choose between 5 and 240 minutes." }
        val allowed = (args["allowedApps"] as? List<*>)?.map {
            require(it is String && it.length in 1..240 && it.matches(Regex("[A-Za-z0-9_.]+"))) { "Invalid allowed app." }
            it
        }?.toSet() ?: emptySet()
        require(allowed.size <= 500) { "Too many allowed apps." }
        val tags = BlockingPlans(context).phoneLockNfcHashes()
        if (mode == "nfc") {
            check(status()["nfcAvailable"] == true && tags.isNotEmpty()) { "Enable NFC and save a chip in Unlock settings first." }
            check(args["recoveryAccepted"] == true) { "Review NFC recovery before starting." }
        }
        val duration = if (mode == "timer") {
            val focusEnd = (args["endsAtEpochMs"] as? Number)?.toLong()
            if (focusEnd != null) (focusEnd - System.currentTimeMillis()).also {
                require(it in 1..PhoneLockPolicy.MAX_TIMER_MS) { "This Focus timer has ended or changed." }
            } else minutes * 60_000
        } else 0L
        val value = JSONObject().put("active", true).put("id", id).put("mode", mode)
            .put("allowedApps", JSONArray(allowed.toList())).put("durationMs", duration)
            .put("tags", JSONArray(tags)).put("endWall", System.currentTimeMillis() + duration)
            .put("endElapsed", SystemClock.elapsedRealtime() + duration).put("endDuration", duration).put("endBoot", boot())
        write(value)
        status()
    }
    fun recover(expected: String?): Map<String, Any?> = synchronized(MUTEX) {
        val value = current()
        PhoneLockPolicy.requireCurrent(expected, value.optString("id"))
        check(value.optBoolean("active") && value.optString("mode") == "nfc") { "No NFC lock is active." }
        if (!value.has("recoveryWall")) {
            value.put("recoveryWall", System.currentTimeMillis() + PhoneLockPolicy.RECOVERY_MS)
                .put("recoveryElapsed", SystemClock.elapsedRealtime() + PhoneLockPolicy.RECOVERY_MS)
                .put("recoveryDuration", PhoneLockPolicy.RECOVERY_MS).put("recoveryBoot", boot())
            write(value)
        }
        status()
    }
    fun unlockNfc(expected: String?, hash: String) = synchronized(MUTEX) {
        val value = current()
        PhoneLockPolicy.requireCurrent(expected, value.optString("id"))
        check(value.optBoolean("active") && value.optString("mode") == "nfc") { "No NFC lock is active." }
        check(hash in BlockingPlans.strings(value.getJSONArray("tags"))) { "This chip was not saved when Phone lock started." }
        write(value.put("active", false))
    }
    companion object { private val MUTEX = Any() }
}
