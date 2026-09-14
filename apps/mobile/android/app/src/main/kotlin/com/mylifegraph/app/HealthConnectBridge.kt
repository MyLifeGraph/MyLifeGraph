package com.mylifegraph.app

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.health.connect.AggregateRecordsRequest
import android.health.connect.AggregateRecordsResponse
import android.health.connect.HealthConnectException
import android.health.connect.HealthConnectManager
import android.health.connect.TimeInstantRangeFilter
import android.health.connect.datatypes.SleepSessionRecord
import android.health.connect.datatypes.StepsRecord
import android.os.Build
import android.os.OutcomeReceiver
import android.annotation.TargetApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/** Foreground-only, read-only Health Connect bridge. No health values are cached. */
class HealthConnectBridge(private val activity: Activity) {
    private var permissionResult: MethodChannel.Result? = null
    private var reading = false
    private var disposed = false

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 34) {
            if (call.method == "status") result.success(mapOf("supported" to false, "granted" to false))
            else result.error("unavailable", "Health Connect requires Android 14 or later.", null)
            return
        }
        try {
            when (call.method) {
                "status" -> result.success(status())
                "requestPermission" -> {
                    if (permissionResult != null) {
                        result.error("busy", "A permission request is already open.", null)
                    } else if (granted()) result.success(status())
                    else {
                        permissionResult = result
                        activity.requestPermissions(PERMISSIONS, PERMISSION_REQUEST)
                    }
                }
                "openSettings" -> {
                    activity.startActivity(Intent("android.health.connect.action.HEALTH_HOME_SETTINGS"))
                    result.success(null)
                }
                "readDays" -> {
                    check(granted()) { "Allow steps and sleep access in Health Connect first." }
                    check(!reading) { "Health Connect is already syncing." }
                    val zone = ZoneId.of(requireNotNull(call.argument<String>("timezone")))
                    val end = LocalDate.parse(requireNotNull(call.argument<String>("window_end")))
                    val now = Instant.now()
                    check(end == now.atZone(zone).toLocalDate()) { "The sync day changed. Please retry." }
                    reading = true
                    readDay(zone, end.minusDays(6), end, now, mutableListOf(), result)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            permissionResult = null
            reading = false
            result.error("health_connect_unavailable", "Health Connect could not complete this request. Check its permissions and retry.", null)
        }
    }

    fun onPermissionResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val result = permissionResult
        permissionResult = null
        if (Build.VERSION.SDK_INT >= 34 && !disposed) result?.success(status())
        return true
    }

    fun dispose() {
        disposed = true
        permissionResult?.error("cancelled", "Permission request was closed.", null)
        permissionResult = null
    }

    @TargetApi(34)
    private fun granted() = PERMISSIONS.all {
        activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    @TargetApi(34)
    private fun status(): Map<String, Any> {
        val preferences = activity.getSharedPreferences("mylifegraph_health_connect_v1", Activity.MODE_PRIVATE)
        val deviceId = preferences.getString("device_id", null) ?: UUID.randomUUID().toString().also {
            preferences.edit().putString("device_id", it).apply()
        }
        return mapOf("supported" to (activity.getSystemService(HealthConnectManager::class.java) != null),
            "granted" to granted(), "device_id" to deviceId)
    }

    @TargetApi(34)
    private fun readDay(zone: ZoneId, day: LocalDate, end: LocalDate, captured: Instant,
                        days: MutableList<Map<String, Any?>>, result: MethodChannel.Result) {
        if (disposed) return
        val manager = activity.getSystemService(HealthConnectManager::class.java)
        if (manager == null) {
            reading = false
            result.error("unavailable", "Health Connect is unavailable.", null)
            return
        }
        val start = day.atStartOfDay(zone).toInstant()
        val finish = minOf(day.plusDays(1).atStartOfDay(zone).toInstant(), captured)
        val range = TimeInstantRangeFilter.Builder().setStartTime(start).setEndTime(finish).build()
        val request = AggregateRecordsRequest.Builder<Long>(range)
            .addAggregationType(StepsRecord.STEPS_COUNT_TOTAL)
            .addAggregationType(SleepSessionRecord.SLEEP_DURATION_TOTAL).build()
        manager.aggregate(request, activity.mainExecutor,
            object : OutcomeReceiver<AggregateRecordsResponse<Long>, HealthConnectException> {
                override fun onResult(response: AggregateRecordsResponse<Long>) {
                    if (disposed) return
                    days.add(mapOf("date" to day.toString(),
                        "steps" to response.get(StepsRecord.STEPS_COUNT_TOTAL),
                        "sleep_minutes" to response.get(SleepSessionRecord.SLEEP_DURATION_TOTAL)?.div(60000.0),
                        "steps_sources" to response.getDataOrigins(StepsRecord.STEPS_COUNT_TOTAL).map { it.packageName }.sorted(),
                        "sleep_sources" to response.getDataOrigins(SleepSessionRecord.SLEEP_DURATION_TOTAL).map { it.packageName }.sorted()))
                    if (day == end) {
                        reading = false
                        result.success(mapOf("captured_at" to captured.toString(), "days" to days))
                    } else {
                        try { readDay(zone, day.plusDays(1), end, captured, days, result) }
                        catch (_: Exception) { onFailure(result) }
                    }
                }
                override fun onError(error: HealthConnectException) { onFailure(result) }
            })
    }

    private fun onFailure(result: MethodChannel.Result) {
        reading = false
        if (!disposed) result.error("read_failed", "Health Connect could not read the complete week. No partial sync was uploaded.", null)
    }

    companion object {
        const val CHANNEL = "com.mylifegraph.app/health_connect"
        const val PERMISSION_REQUEST = 9301
        private val PERMISSIONS = arrayOf("android.permission.health.READ_STEPS", "android.permission.health.READ_SLEEP")
    }
}
