package com.mylifegraph.app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/** Android owns every decision and persists it before returning to Flutter. No Cloud calls. */
class BlockingPlans(private val context: Context) {
    private val prefs = context.getSharedPreferences("mylifegraph_blocking_v2", Context.MODE_PRIVATE)
    private val legacy = FocusProtectionStore(context)
    private fun now() = System.currentTimeMillis()
    private fun boot() = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
    private fun commit(editor: android.content.SharedPreferences.Editor) {
        check(editor.commit()) { "Could not save blocking settings." }
    }
    fun migrated() = prefs.contains("plans")
    fun plans(): JSONArray {
        if (migrated()) return JSONArray(prefs.getString("plans", "[]"))
        val config = legacy.readConfiguration()
        return JSONArray(config.selectedPackages.sorted().map { pkg ->
            val rule = config.appRules[pkg] ?: AppBlockingRule(
                config.blockingSchedule.mode == "focus", config.blockingSchedule.mode == "weekly",
                config.blockingSchedule.mode == "always", config.blockingSchedule, 0)
            JSONObject().put("id", "legacy:$pkg").put("name", runCatching {
                context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(pkg, 0)).toString()
            }.getOrDefault(pkg).ifBlank { pkg }).put("icon", "shield").put("apps", JSONArray(listOf(pkg)))
                .put("sites", JSONArray()).put("focus", rule.focus).put("always", rule.always)
                .put("windows", JSONArray(if (rule.weekly) listOf(JSONObject(rule.toMap())) else emptyList<JSONObject>()))
                .put("untilEpochMs", rule.untilEpochMs).put("budgetMinutes", 0)
                .put("enabled", true).put("pausedUntil", 0)
        })
    }
    private fun settings(key: String) = JSONObject(prefs.getString(key, "{}") ?: "{}")
    fun custom() = settings("custom")
    fun strict() = settings("strict")
    private fun released(): Boolean = prefs.getInt("release_boot", -2) == boot() &&
        prefs.getLong("release_until", 0) > SystemClock.elapsedRealtime()
    fun locked(): Boolean = strict().optBoolean("enabled") && !released()
    fun requireEditable() {
        BlockingEditPolicy.requireEditable(locked(), legacy.readLease()?.isActive(now()) == true)
    }
    fun websiteConsent() = prefs.getBoolean("website_consent", false)
    fun usageConsent() = prefs.getBoolean("usage_consent", false)
    fun usageGranted(): Boolean {
        val ops = context.getSystemService(AppOpsManager::class.java)
        @Suppress("DEPRECATION")
        return usageConsent() && ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(), context.packageName) == AppOpsManager.MODE_ALLOWED
    }
    private fun startOfDay(instant: Long): Long = Calendar.getInstance().apply {
        timeInMillis = instant; set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }.timeInMillis
    private fun day() = startOfDay(now()).toString()
    fun recordAttempt(target: String) {
        val counts = settings("attempts")
        val item = counts.optJSONObject(target) ?: JSONObject()
        item.put("total", item.optLong("total") + 1)
        item.put("today", (if (item.optString("day") == day()) item.optLong("today") else 0) + 1)
        item.put("day", day()); counts.put(target, item)
        commit(prefs.edit().putString("attempts", counts.toString()))
    }
    fun attempts(target: String): Pair<Long, Long> {
        val item = settings("attempts").optJSONObject(target) ?: JSONObject()
        return (if (item.optString("day") == day()) item.optLong("today") else 0) to item.optLong("total")
    }
    /** Meter foreground website seconds only; caller supplies elapsed time, not wall-clock time. */
    private var meteredSites: JSONObject? = null
    private var lastSiteFlush = 0L
    fun meterSite(host: String, browser: String, milliseconds: Long) {
        if (!BlockingConsentPolicy.siteUsageAllowed(websiteConsent(), usageGranted()) ||
            milliseconds !in 1..5000) return
        val selected = plans()
        if (!(0 until selected.length()).any { index ->
                val p = selected.getJSONObject(index)
                p.optInt("budgetMinutes") > 0 && strings(p.getJSONArray("sites")).any { BlockingDomains.matches(host, it) }
            }) return
        val values = meteredSites ?: settings("web_usage").also { meteredSites = it }
        val key = "${day()}|$browser|$host"
        values.put(key, values.optLong(key) + milliseconds)
        // Keep at most 32 days; never retain URL paths or query strings.
        val cutoff = now() - 32L * 86400000
        values.keys().asSequence().toList().filter { (it.substringBefore('|').toLongOrNull() ?: 0) < cutoff }
            .forEach { values.remove(it) }
        if (SystemClock.elapsedRealtime() - lastSiteFlush >= 5000) flushSiteUsage()
    }
    fun flushSiteUsage() {
        meteredSites?.let { commit(prefs.edit().putString("web_usage", it.toString())) }
        lastSiteFlush = SystemClock.elapsedRealtime()
    }
    fun appUsage(start: Long, end: Long): Map<String, Long> {
        if (!usageGranted()) return emptyMap()
        val service = context.getSystemService(UsageStatsManager::class.java)
        val events = service.queryEvents((start - 86400000).coerceAtLeast(0), end) ?: return emptyMap()
        val reducer = BlockingUsageReducer(start, end)
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            // UsageEvents exposes the activity class publicly, not an instance id.
            val activity = event.className.orEmpty()
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    reducer.resume(event.packageName, activity, event.timeStamp)
                }
                UsageEvents.Event.ACTIVITY_PAUSED -> reducer.pause(event.packageName, activity, event.timeStamp)
                UsageEvents.Event.SCREEN_NON_INTERACTIVE, UsageEvents.Event.DEVICE_SHUTDOWN -> {
                    reducer.screenOff(event.timeStamp)
                }
            }
        }
        return reducer.result()
    }
    // Memoize briefly; Accessibility events must not rescan a whole day's history per event.
    private var usageAt = -1L
    private var usageDay = 0L
    private var todayUsage: Map<String, Long> = emptyMap()
    private fun todayApps(): Map<String, Long> {
        val elapsed = SystemClock.elapsedRealtime(); val date = startOfDay(now())
        if (elapsed - usageAt > 5000 || date != usageDay || elapsed < usageAt) {
            todayUsage = appUsage(date, now()); usageAt = elapsed; usageDay = date
        }
        return todayUsage
    }
    fun used(plan: JSONObject): Long {
        if (!usageGranted()) return 0
        val apps = strings(plan.getJSONArray("apps")).toSet()
        var total = apps.sumOf { todayApps()[it] ?: 0 }
        val sites = strings(plan.getJSONArray("sites"))
        val web = meteredSites ?: settings("web_usage")
        for (key in web.keys()) {
            val parts = key.split('|')
            if (websiteConsent() && parts.size == 3 && parts[0] == day() && parts[1] !in apps &&
                sites.any { BlockingDomains.matches(parts[2], it) }) total += web.getLong(key)
        }
        return total
    }
    private fun active(plan: JSONObject): Boolean {
        val instant = now()
        val windows = plan.getJSONArray("windows")
        var windowActive = false
        for (i in 0 until windows.length()) {
            val w = windows.getJSONObject(i)
            if (AppBlockingSchedule("weekly", ints(w.getJSONArray("weekdays")).toSet(),
                    w.getInt("startMinute"), w.getInt("endMinute")).active(instant, false)) { windowActive = true; break }
        }
        val budget = plan.optInt("budgetMinutes")
        return BlockingRulePolicy.active(plan.optBoolean("enabled", true), plan.optLong("pausedUntil"),
            instant, plan.optBoolean("always"), plan.optLong("untilEpochMs"), plan.optBoolean("focus"),
            legacy.readLease()?.isActive(instant) == true, windowActive, budget, usageGranted(),
            if (budget > 0) used(plan) else 0)
    }
    fun blocked(app: String?, host: String? = null): JSONObject? {
        val config = legacy.readConfiguration()
        if (!config.enabled || !config.blockSelectedApps || app == null) return null
        val values = plans()
        for (i in 0 until values.length()) {
            val p = values.getJSONObject(i)
            val appMatch = app in strings(p.getJSONArray("apps"))
            val siteMatch = websiteConsent() && host != null &&
                strings(p.getJSONArray("sites")).any { BlockingDomains.matches(host, it) }
            if ((appMatch || siteMatch) && active(p)) return p
        }
        return null
    }
    fun hasWebsiteTargets(): Boolean {
        val values = plans()
        return websiteConsent() && (0 until values.length()).any { values.getJSONObject(it).getJSONArray("sites").length() > 0 }
    }
    fun websiteObservationEnabled(): Boolean {
        val config = legacy.readConfiguration()
        return config.enabled && config.blockSelectedApps && hasWebsiteTargets()
    }
    fun activeWebsitePlan(): Boolean {
        val config = legacy.readConfiguration()
        if (!config.enabled || !config.blockSelectedApps || !websiteConsent()) return false
        val values = plans()
        return (0 until values.length()).any {
            val plan = values.getJSONObject(it)
            plan.getJSONArray("sites").length() > 0 && active(plan)
        }
    }
    fun status(): Map<String, Any?> {
        val values = plans()
        val config = legacy.readConfiguration()
        val granted = context.getSystemService(android.view.accessibility.AccessibilityManager::class.java)
            .getEnabledAccessibilityServiceList(android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { it.resolveInfo.serviceInfo.packageName == context.packageName &&
                it.resolveInfo.serviceInfo.name == FocusBlockAccessibilityService::class.java.name }
        val essential = FocusProtectionManager(context).essentialPackages()
        for (i in 0 until values.length()) {
            val p = values.getJSONObject(i)
            val targetsAvailable = BlockingRulePolicy.hasEffectiveTargets(
                strings(p.getJSONArray("apps")).count { it !in essential },
                p.getJSONArray("sites").length(), websiteConsent())
            p.put("active", config.enabled && config.blockSelectedApps && granted && targetsAvailable && active(p))
                .put("usedMs", if (p.optInt("budgetMinutes") > 0) used(p) else 0)
        }
        val s = strict()
        val remaining = BlockingUnlockPolicy.remaining(s.optInt("waitSeconds", 180),
            prefs.getLong("unlock_start", -1), prefs.getInt("unlock_boot", -2), boot(), SystemClock.elapsedRealtime())
        val counts = settings("attempts")
        var today = 0L; var total = 0L
        for (key in counts.keys()) { val pair = attempts(key); today += pair.first; total += pair.second }
        return mapOf("contractVersion" to CONTRACT_VERSION, "revision" to prefs.getLong("revision", 0), "plans" to arrayMap(values),
            "strict" to jsonMap(s), "locked" to locked(), "remainingMs" to remaining,
            "unlockStarted" to (prefs.getInt("unlock_boot", -2) == boot() && prefs.getLong("unlock_start", -1) >= 0),
            "releaseRemainingMs" to (if (released()) (prefs.getLong("release_until", 0) - SystemClock.elapsedRealtime()).coerceAtLeast(0) else 0),
            "custom" to jsonMap(custom()), "websiteConsent" to websiteConsent(),
            "usageConsent" to usageConsent(), "usageGranted" to usageGranted(),
            "nfcAvailable" to (context.packageManager.hasSystemFeature("android.hardware.nfc")),
            "nfcEnrolled" to prefs.contains("nfc_hash"), "wifiReady" to currentWifi().isNotEmpty(),
            "attemptsToday" to today, "attemptsTotal" to total,
            "browsers" to BrowserAddressBars.adapters.keys.toList())
    }
    fun save(arguments: Map<*, *>): Map<String, Any?> {
        requireEditable()
        require((arguments["revision"] as? Number)?.toLong() == prefs.getLong("revision", 0)) {
            "Settings changed. Reload and try again."
        }
        val incoming = arguments["plans"] as? List<*> ?: error("Missing plans")
        val essential = FocusProtectionManager(context).essentialPackages()
        val ids = mutableSetOf<String>()
        val values = JSONArray()
        val retained = plans().let { old -> (0 until old.length()).associate {
            old.getJSONObject(it).getString("id") to old.getJSONObject(it)
        } }
        val incomingIds = incoming.map { (it as? Map<*, *>)?.get("id") as? String ?: error("Invalid plan") }
        require(BlockingMigrationPolicy.countAllowed(incomingIds, retained.keys)) { "Remove a plan before adding another." }
        for (raw in incoming) {
            val p = JSONObject(raw as? Map<*, *> ?: error("Invalid plan"))
            val previous = retained[p.getString("id")]
            require(BlockingMigrationPolicy.idAllowed(p.getString("id"), previous?.getString("id")) && ids.add(p.getString("id")))
            require(BlockingMigrationPolicy.nameAllowed(p.getString("name"), previous?.getString("name")))
            require(p.getString("icon") in setOf("shield", "work", "games", "social", "sleep", "study"))
            p.getBoolean("enabled")
            require(p.getInt("budgetMinutes") in 0..1440 && p.getLong("untilEpochMs") >= 0 && p.getLong("pausedUntil") >= 0)
            val apps = strings(p.getJSONArray("apps"))
            val previousApps = previous?.let { strings(it.getJSONArray("apps")).toSet() } ?: emptySet()
            require(apps.size <= 500 && apps.all { BlockingMigrationPolicy.appAllowed(it, previousApps) && it !in essential })
            val sites = strings(p.getJSONArray("sites"))
            require(sites.size <= 500 && sites.all { BlockingDomains.host(it) == it })
            require(apps.isNotEmpty() || sites.isNotEmpty())
            val previousSites = previous?.let { strings(it.getJSONArray("sites")).toSet() } ?: emptySet()
            require(BlockingConsentPolicy.sitesAllowed(sites.toSet(), previousSites, websiteConsent())) {
                "Allow website protection first."
            }
            require(BlockingConsentPolicy.budgetAllowed(p.getInt("budgetMinutes"), previous?.optInt("budgetMinutes") ?: 0,
                apps.toSet(), previousApps, sites.toSet(), previousSites, usageGranted())) {
                "Allow usage access first."
            }
            val windows = p.getJSONArray("windows"); require(windows.length() <= 12)
            for (i in 0 until windows.length()) {
                val w = windows.getJSONObject(i)
                AppBlockingSchedule("weekly", ints(w.getJSONArray("weekdays")).toSet(),
                    w.getInt("startMinute"), w.getInt("endMinute"))
            }
            require(p.getBoolean("focus") || p.getBoolean("always") || windows.length() > 0 ||
                p.getInt("budgetMinutes") > 0 || p.getLong("untilEpochMs") > 0) { "Choose a rule." }
            p.remove("active"); p.remove("usedMs"); values.put(p)
        }
        val appearance = JSONObject(arguments["custom"] as? Map<*, *> ?: emptyMap<String, Any>())
        require(appearance.optString("title", "Stay focused").length <= 60 &&
            appearance.optString("message", "Take a breath. Choose your next step.").length <= 200)
        require(appearance.optInt("waitSeconds") in 0..900)
        require(appearance.optString("tone", "glass") in setOf("glass", "dark", "light", "space"))
        require(appearance.optString("icon", "shield") in setOf("shield", "work", "games", "social", "sleep", "study"))
        commit(prefs.edit().putString("plans", values.toString()).putString("custom", appearance.toString())
            .putLong("revision", prefs.getLong("revision", 0) + 1))
        FocusBlockAccessibilityService.refreshOverlayIfRunning(context)
        return status()
    }
    fun consent(kind: String, allowed: Boolean = true): Map<String, Any?> {
        requireEditable(); require(kind in setOf("website", "usage"))
        commit(prefs.edit().putBoolean("${kind}_consent", allowed)
            .putLong("revision", prefs.getLong("revision", 0) + 1))
        return status()
    }
    fun setStrict(arguments: Map<*, *>): Map<String, Any?> {
        requireEditable()
        require((arguments["revision"] as? Number)?.toLong() == prefs.getLong("revision", 0)) {
            "Settings changed. Reload and try again."
        }
        val s = JSONObject(arguments)
        s.remove("revision")
        require(s.optInt("waitSeconds", 180) in 0..900)
        val enabled = s.getBoolean("enabled")
        if (enabled) {
            check(boot() >= 0) { "Android boot identity is unavailable." }
            check(legacy.readConfiguration().enabled && legacy.readConfiguration().blockSelectedApps) { "Enable app blocking first." }
            check(FocusProtectionManager(context).readStatus()["accessibilityEnabled"] == true) { "Enable Android protection first." }
            require(!s.optBoolean("nfc") || prefs.contains("nfc_hash")) { "Set up NFC first." }
            require(!s.optBoolean("wifi") || currentWifi().isNotEmpty()) { "Allow Wi-Fi access and connect first." }
            if (s.optBoolean("wifi")) s.put("wifiName", currentWifi())
        }
        commit(prefs.edit().putString("strict", s.toString()).putLong("revision", prefs.getLong("revision", 0) + 1).remove("unlock_start")
            .remove("release_until").remove("nfc_verified"))
        return status()
    }
    fun requestUnlock(): Map<String, Any?> {
        check(locked()) { "Strict mode is not locked." }
        if (prefs.getInt("unlock_boot", -2) != boot() || prefs.getLong("unlock_start", -1) < 0) {
            commit(prefs.edit().putLong("unlock_start", SystemClock.elapsedRealtime()).putInt("unlock_boot", boot()))
        }
        return status()
    }
    fun finishUnlock(): Map<String, Any?> {
        check(prefs.getInt("unlock_boot", -2) == boot() && prefs.getLong("unlock_start", -1) >= 0) { "Start unlocking first." }
        val s = strict()
        val remaining = status()["remainingMs"] as Long
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val power = (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
        val verified = prefs.getLong("nfc_verified", -1)
        val nfcOk = prefs.getInt("nfc_boot", -2) == boot() && verified >= 0 &&
            SystemClock.elapsedRealtime() - verified in 0..60000
        check(locked() && BlockingUnlockPolicy.ready(remaining, s.optBoolean("power"), power,
            s.optBoolean("wifi"), currentWifi().isNotEmpty() && currentWifi() == s.optString("wifiName"),
            s.optBoolean("nfc"), nfcOk)) { "Unlock conditions are not met yet." }
        commit(prefs.edit().putLong("release_until", SystemClock.elapsedRealtime() + 15 * 60000)
            .putInt("release_boot", boot()).remove("unlock_start").remove("nfc_verified"))
        return status()
    }
    fun relock(): Map<String, Any?> {
        commit(prefs.edit().remove("release_until").remove("unlock_start").remove("nfc_verified"))
        return status()
    }
    fun acceptNfc(hash: String, enroll: Boolean) {
        if (enroll) { requireEditable(); commit(prefs.edit().putString("nfc_hash", hash)) }
        else {
            check(locked() && hash == prefs.getString("nfc_hash", null)) { "This is not your saved tag." }
            check(prefs.getInt("unlock_boot", -2) == boot() && prefs.getLong("unlock_start", -1) >= 0) { "Start unlocking first." }
            commit(prefs.edit().putLong("nfc_verified", SystemClock.elapsedRealtime()).putInt("nfc_boot", boot()))
        }
    }
    @Suppress("DEPRECATION")
    fun currentWifi(): String = runCatching {
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val network = connectivity.activeNetwork ?: return ""
        val caps = connectivity.getNetworkCapabilities(network) ?: return ""
        if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return ""
        fun ssid(info: WifiInfo?): String = info?.ssid?.trim('"')
            ?.takeUnless { it == WifiManager.UNKNOWN_SSID }.orEmpty()
        val current = ssid(if (android.os.Build.VERSION.SDK_INT >= 29) caps.transportInfo as? WifiInfo else null)
        if (current.isNotEmpty()) current else ssid(context.getSystemService(WifiManager::class.java).connectionInfo)
    }.getOrDefault("")
    fun insights(days: Int): Map<String, Any?> {
        require(days in setOf(1, 7, 30)); val end = now()
        val start = Calendar.getInstance().apply { timeInMillis = startOfDay(end); add(Calendar.DAY_OF_MONTH, 1 - days) }.timeInMillis
        val usage = appUsage(start, end)
        val calendar = Calendar.getInstance().apply { timeInMillis = start }
        val daily = mutableListOf<Map<String, Any>>()
        repeat(days) {
            val from = calendar.timeInMillis; calendar.add(Calendar.DAY_OF_MONTH, 1)
            daily += mapOf("dateEpochMs" to from, "milliseconds" to appUsage(from, minOf(calendar.timeInMillis, end)).values.sum())
        }
        return mapOf("available" to usageGranted(), "daily" to daily,
            "apps" to usage.entries.filter { it.key != context.packageName }
                .sortedByDescending { it.value }.take(20).map { entry ->
                    mapOf("packageName" to entry.key, "milliseconds" to entry.value,
                        "label" to runCatching { context.packageManager.getApplicationLabel(
                            context.packageManager.getApplicationInfo(entry.key, 0)).toString() }.getOrDefault(entry.key))
                })
    }
    companion object {
        const val CONTRACT_VERSION = "blocking-plans-v2"
        fun strings(a: JSONArray) = (0 until a.length()).map { a.getString(it) }
        fun ints(a: JSONArray) = (0 until a.length()).map { a.getInt(it) }
        fun jsonMap(o: JSONObject): Map<String, Any?> = o.keys().asSequence().associateWith { key -> convert(o.get(key)) }
        fun arrayMap(a: JSONArray): List<Any?> = (0 until a.length()).map { convert(a.get(it)) }
        private fun convert(value: Any?): Any? = when (value) {
            is JSONObject -> jsonMap(value); is JSONArray -> arrayMap(value); JSONObject.NULL -> null; else -> value
        }
    }
}
