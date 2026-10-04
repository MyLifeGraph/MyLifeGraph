package com.mylifegraph.app

import java.time.Instant
import java.time.ZoneId
import java.util.TimeZone
import org.junit.Assert.*
import org.junit.Test

class CoachPhoneUsageWindowTest {
    @Test fun windowIsSevenProfileDaysAndEndsAtCapture() {
        for (id in listOf("UTC", "Europe/Berlin", "America/New_York", "Pacific/Kiritimati")) {
            val now = Instant.parse("2026-10-04T00:30:00Z")
            val zone = ZoneId.of(id)
            val ranges = CoachPhoneUsageWindow.ranges(now.toEpochMilli(), TimeZone.getTimeZone(id))
            assertEquals(7, ranges.size)
            assertEquals(now.atZone(zone).toLocalDate().toString(), ranges.last().first)
            assertEquals(now.toEpochMilli(), ranges.last().third)
            ranges.zipWithNext().forEach { (a,b) -> assertEquals(a.third,b.second) }
        }
    }
    @Test fun daylightSavingUsesRealDayLengths() {
        val zone = TimeZone.getTimeZone("Europe/Berlin")
        for ((capture, date, hours) in listOf(
            Triple("2026-03-30T12:00:00Z", "2026-03-29", 23L),
            Triple("2026-10-26T12:00:00Z", "2026-10-25", 25L))) {
            val day = CoachPhoneUsageWindow.ranges(Instant.parse(capture).toEpochMilli(),zone).single { it.first==date }
            assertEquals(hours*3600000, day.third-day.second)
        }
    }
    @Test fun attemptsNeedMatchingDayBoundaryNotJustDate() {
        val now = Instant.parse("2026-10-04T14:00:00Z").toEpochMilli()
        assertFalse(CoachPhoneUsageWindow.attemptsAvailable(now,TimeZone.getTimeZone("Europe/Berlin"),TimeZone.getTimeZone("America/New_York")))
        assertTrue(CoachPhoneUsageWindow.attemptsAvailable(now,TimeZone.getTimeZone("Europe/Berlin"),TimeZone.getTimeZone("Europe/Paris")))
        assertTrue(CoachPhoneUsageWindow.attemptsAvailable(now,TimeZone.getTimeZone("UTC"),TimeZone.getTimeZone("Etc/UTC")))
    }
    @Test fun midnightDstGapDoesNotShiftFollowingMidnight() {
        val ranges = CoachPhoneUsageWindow.ranges(Instant.parse("2026-09-08T12:00:00Z").toEpochMilli(),TimeZone.getTimeZone("America/Santiago"))
        for (range in ranges) {
            val date = java.time.LocalDate.parse(range.first)
            val zone = ZoneId.of("America/Santiago")
            assertEquals(date.atStartOfDay(zone).toInstant().toEpochMilli(),range.second)
            if(range.first!="2026-09-08") assertEquals(date.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli(),range.third)
        }
    }
    @Test fun reducersSplitMidnightAndIgnoreEventsBeyondRange() {
        val first = BlockingUsageReducer(100,200)
        val second = BlockingUsageReducer(200,300)
        for (r in listOf(first,second)) {
            r.resume("old","A",20); r.pause("old","A",50)
            r.resume("cross","A",150); r.pause("cross","A",250)
            r.resume("later","A",350); r.pause("later","A",400)
        }
        assertEquals(mapOf("cross" to 50L),first.result())
        assertEquals(mapOf("cross" to 50L),second.result())
    }
    @Test fun screenOffClampsCarryInWithoutDoubleCounting() {
        val r = BlockingUsageReducer(100,200)
        r.resume("app","A",0); r.screenOff(125); r.screenOff(300)
        assertEquals(mapOf("app" to 25L),r.result())
    }
}
