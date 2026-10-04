package com.mylifegraph.app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Process
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/** Foreground, explicitly requested aggregate only. No URL/message/notification data. */
internal class CoachPhoneUsage(private val context: Context) {
    private val prefs = context.getSharedPreferences("mylifegraph_coach_phone", 0)
    @Suppress("DEPRECATION")
    private fun granted() = context.getSystemService(AppOpsManager::class.java)
        .checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName) == AppOpsManager.MODE_ALLOWED
    fun status(): Map<String, Any> {
        val id = prefs.getString("device_id", null) ?: UUID.randomUUID().toString().also {
            check(prefs.edit().putString("device_id", it).commit())
        }
        return mapOf("device_id" to id, "granted" to granted())
    }
    fun read(timezone: String): Map<String, Any?> {
        check(granted()) { "Allow Android usage access first." }
        require(timezone in TimeZone.getAvailableIDs()) { "Invalid profile timezone." }
        val zone = TimeZone.getTimeZone(timezone)
        val now = System.currentTimeMillis()
        val ranges = CoachPhoneUsageWindow.ranges(now, zone)
        val start = ranges.first().second
        val end = now
        val reducers = ranges.map { BlockingUsageReducer(it.second, it.third) }
        val events = context.getSystemService(UsageStatsManager::class.java).queryEvents(start - 86400000, end)
            ?: error("Usage unavailable")
        val event = UsageEvents.Event()
        var count = 0
        while (events.hasNextEvent()) {
            check(++count <= 250000) { "Usage history is too large." }
            events.getNextEvent(event)
            reducers.forEach { reducer ->
                when(event.eventType) {
                    UsageEvents.Event.ACTIVITY_RESUMED -> reducer.resume(event.packageName, event.className.orEmpty(), event.timeStamp)
                    UsageEvents.Event.ACTIVITY_PAUSED -> reducer.pause(event.packageName, event.className.orEmpty(), event.timeStamp)
                    UsageEvents.Event.SCREEN_NON_INTERACTIVE, UsageEvents.Event.DEVICE_SHUTDOWN -> reducer.screenOff(event.timeStamp)
                }
            }
        }
        check(granted()) { "Usage permission changed." }
        val totals = mutableMapOf<String, Long>()
        val days = ranges.zip(reducers).map { (range, reducer) ->
            val data = reducer.result().filterKeys { it != context.packageName }
            data.forEach { (app, value) -> totals[app] = (totals[app] ?: 0) + value }
            mapOf("date" to range.first.toString(), "minutes" to data.values.sum() / 60000)
        }
        val apps = totals.entries.sortedByDescending { it.value }.take(10).map { (pkg, ms) ->
            val label = runCatching { context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(pkg,0)).toString() }.getOrDefault(pkg)
            mapOf("name" to label.take(80), "minutes" to ms / 60000)
        }
        // Attempts are device-day counters; omit mismatched profile-day counts.
        val attempts = if (CoachPhoneUsageWindow.attemptsAvailable(now, zone, TimeZone.getDefault()))
            (BlockingPlans(context).status()["attemptsToday"] as? Number)?.toInt() else null
        val captured = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(now))
        return mapOf("timezone" to timezone, "captured_at" to captured, "days" to days,
            "apps" to apps, "attempts_today" to attempts)
    }
}
