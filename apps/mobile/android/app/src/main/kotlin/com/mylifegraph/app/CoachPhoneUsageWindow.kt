package com.mylifegraph.app

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

internal object CoachPhoneUsageWindow {
    private fun midnight(now: Long, zone: TimeZone) = Calendar.getInstance(zone).apply {
        timeInMillis = now
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }
    fun ranges(now: Long, zone: TimeZone) = (6 downTo 0).map { offset ->
        val dateAtNoon = Calendar.getInstance(zone).apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, 12)
            add(Calendar.DAY_OF_MONTH, -offset)
        }
        val day = midnight(dateAtNoon.timeInMillis, zone)
        val start = day.timeInMillis
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply { timeZone = zone }.format(day.time)
        dateAtNoon.add(Calendar.DAY_OF_MONTH, 1)
        Triple(date, start, minOf(now, midnight(dateAtNoon.timeInMillis, zone).timeInMillis))
    }

    fun attemptsAvailable(now: Long, profileZone: TimeZone, deviceZone: TimeZone): Boolean =
        midnight(now, profileZone).timeInMillis == midnight(now, deviceZone).timeInMillis
}
