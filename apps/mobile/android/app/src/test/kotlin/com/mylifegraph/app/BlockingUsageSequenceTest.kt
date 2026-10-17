package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

/** Deterministic event traces, not a claim about OEM event delivery. */
class BlockingUsageSequenceTest {
    @Test fun rapidAppChangesDuplicatesAndLatePausesNeverLoseOrDoubleCountTime() {
        val reducer = BlockingUsageReducer(0, 600_000)
        val expected = mutableMapOf<String, Long>()
        repeat(1000) { index ->
            val app = "qa.app${index % 7}"
            val start = index * 600L
            reducer.resume(app, "Main", start)
            reducer.resume(app, "Main", start + 10)
            reducer.resume(app, "Dialog", start + 20)
            reducer.pause(app, "Dialog", start + 30)
            reducer.pause("qa.unrelated", "Main", start + 40)
            reducer.pause(app, "Main", start + 500)
            reducer.pause(app, "Main", start + 510)
            expected[app] = (expected[app] ?: 0L) + 500
        }
        assertEquals(expected, reducer.result())
        assertEquals(expected, reducer.result())
    }

    @Test fun usageClipsAtCalendarDayBoundsIncludingShortAndLongDays() {
        for (hours in listOf(23, 24, 25)) {
            val start = 86_400_000L
            val end = start + hours * 3_600_000L
            val reducer = BlockingUsageReducer(start, end)
            reducer.resume("qa.app", "Main", start - 1000)
            reducer.resume("qa.app", "Dialog", start + 1000)
            reducer.pause("qa.app", "Dialog", start + 2000)
            assertEquals(mapOf("qa.app" to (end - start)), reducer.result())
        }
    }

    @Test fun screenOffAndShutdownStopUsageUntilAnotherResume() {
        val reducer = BlockingUsageReducer(0, 10_000)
        reducer.resume("qa.app", "Main", 0)
        reducer.screenOff(1000)
        reducer.screenOff(2000)
        reducer.pause("qa.app", "Main", 3000)
        reducer.resume("qa.app", "Main", 7000)
        reducer.screenOff(8000)
        assertEquals(mapOf("qa.app" to 2000L), reducer.result())
    }

    @Test fun oldUsageEvidenceCannotRestoreAnAppAfterConfirmedHomeOrOwnEntry() {
        repeat(1000) { index ->
            val at = 10_000L + index
            for (current in listOf("qa.home", "own.app", "qa.other")) {
                assertEquals(current, FocusProtectionDecision.recoverForeground(
                    current, at, "qa.blocked", at - 1, "own.app"))
                assertEquals(current, FocusProtectionDecision.recoverForeground(
                    current, at, "qa.blocked", at, "own.app"))
            }
        }
    }
}
