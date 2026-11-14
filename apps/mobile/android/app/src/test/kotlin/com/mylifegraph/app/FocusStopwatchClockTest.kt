package com.mylifegraph.app

import org.junit.Assert.assertEquals
import org.junit.Test

class FocusStopwatchClockTest {
    @Test fun elapsedSurvivesProcessResumeAndIgnoresWallClockChangesWithinBoot() {
        val anchor = FocusStopwatchClock.anchor(100_000, 700_000, 5_000)
        assertEquals(605_000L, FocusStopwatchClock.elapsed(100_000, anchor, 2, 2, 0, 10_000))
        assertEquals(605_000L, FocusStopwatchClock.elapsed(100_000, anchor, 2, 2, 9_000_000, 10_000))
    }
    @Test fun rebootUsesCanonicalStartAndFutureStartNeverProducesNegativeElapsed() {
        assertEquals(800_000L, FocusStopwatchClock.elapsed(100_000, -595_000, 2, 3, 900_000, 500))
        val anchor = FocusStopwatchClock.anchor(100_000, 90_000, 500)
        assertEquals(0L, FocusStopwatchClock.elapsed(100_000, anchor, 3, 3, 90_000, 500))
    }
}
