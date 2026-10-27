package com.mylifegraph.app

import java.util.Random
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Test

/** Compare Calendar-based enforcement with a minute-of-week arithmetic oracle. */
class BlockingWeeklyGeneratedTest {
    @Test fun startDayOvernightAndExclusiveEndMatchCircularWeekOracle() {
        val seed = 2026102701L
        val random = Random(seed)
        val monday = 1791158400000L // 2026-10-05T00:00:00Z
        val zone = TimeZone.getTimeZone("UTC")
        val week = 7 * 1440
        repeat(500) { sample ->
            val days = (1..7).filter { random.nextBoolean() }.toSet().ifEmpty { setOf(7) }
            val start = random.nextInt(1440)
            var end = random.nextInt(1440)
            if (end == start) end = (end + 1) % 1440
            val duration = (end - start + 1440) % 1440
            val rule = AppBlockingSchedule("weekly", days, start, end)
            val instants = mutableListOf(random.nextInt(week))
            for (day in days) {
                val begin = (day - 1) * 1440 + start
                val finish = begin + duration
                instants.addAll(listOf(begin - 1, begin, begin + 1,
                    finish - 1, finish, finish + 1))
            }
            for (raw in instants) {
                val minute = (raw + week) % week
                val expected = days.any { day ->
                    val begin = (day - 1) * 1440 + start
                    (minute - begin + week) % week < duration
                }
                for (offset in listOf(0L, 7L * 86400000)) {
                    assertEquals("seed=$seed sample=$sample minute=$minute offset=$offset",
                        expected, rule.active(monday + minute * 60000L + offset, false, zone))
                }
            }
        }
    }
}
