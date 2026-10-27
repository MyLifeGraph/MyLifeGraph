package com.mylifegraph.app

import java.util.Random
import org.junit.Assert.*
import org.junit.Test

/** Seeded chronological Android-like traces; this does not simulate OEM delivery. */
class BlockingUsageGeneratedTraceTest {
    @Test fun usageMatchesIndependentIntervalOracleAcrossMixedActivityTraces() {
        val seed = 20261027L
        val random = Random(seed)
        repeat(300) { trace ->
            val start = 1000L
            val end = 6000L
            val reducer = BlockingUsageReducer(start, end)
            val expected = mutableMapOf<String, Long>()
            var current: String? = null
            val activities = mutableSetOf<String>()
            var cursor = 0L
            var at = 0L
            repeat(240) {
                at += random.nextInt(40)
                if (at >= end) return@repeat
                // The oracle integrates every interval before applying an event,
                // unlike the production reducer's deferred finish/since approach.
                current?.let { app ->
                    val elapsed = (at - cursor.coerceAtLeast(start)).coerceAtLeast(0)
                    expected[app] = (expected[app] ?: 0L) + elapsed
                }
                cursor = at
                val app = "qa.app${random.nextInt(4)}"
                val activity = "Activity${random.nextInt(3)}"
                when (random.nextInt(7)) {
                    0, 1, 2, 3 -> {
                        reducer.resume(app, activity, at)
                        if (current != app) activities.clear()
                        activities.add(activity)
                        current = app
                    }
                    4, 5 -> {
                        reducer.pause(app, activity, at)
                        if (current == app) {
                            activities.remove(activity)
                            if (activities.isEmpty()) current = null
                        }
                    }
                    else -> {
                        reducer.screenOff(at)
                        activities.clear()
                        current = null
                    }
                }
            }
            current?.let { app ->
                expected[app] = (expected[app] ?: 0L) +
                    (end - cursor.coerceAtLeast(start)).coerceAtLeast(0)
            }
            val actual = reducer.result()
            assertEquals("seed=$seed trace=$trace", expected.filterValues { it > 0 }, actual)
            assertTrue("seed=$seed trace=$trace bounded", actual.values.sum() <= end - start)
            assertTrue(actual.values.all { it > 0 })
        }
    }

    @Test fun budgetBoundaryAndOtherOrRulesRemainIndependentAcrossAllowances() {
        for (budget in listOf(1, 15, 45, 1440)) {
            val limit = budget * 60000L
            for (used in listOf(0L, limit - 1, limit, limit + 1)) {
                for (usage in listOf(false, true)) {
                    val limited = BlockingRulePolicy.active(true, 0, 1000,
                        false, 0, false, false, false, budget, usage, used)
                    assertEquals("budget=$budget used=$used access=$usage",
                        usage && used >= limit, limited)
                    assertTrue(BlockingRulePolicy.active(true, 0, 1000,
                        false, 0, false, false, true, budget, usage, used))
                    assertFalse(BlockingRulePolicy.active(false, 0, 1000,
                        true, 2000, true, true, true, budget, usage, used))
                    assertFalse(BlockingRulePolicy.active(true, 1001, 1000,
                        true, 2000, true, true, true, budget, usage, used))
                }
            }
        }
    }
}
