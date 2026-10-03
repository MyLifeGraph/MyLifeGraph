package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class BlockingTimerPolicyTest {
    private fun visible(enabled: Boolean = true, pause: Long = 0, end: Long = 2000,
                        now: Long = 1000, master: Boolean = true,
                        accessibility: Boolean = true, targets: Boolean = true) =
        BlockingTimerPolicy.visible(enabled, pause, end, now, master, accessibility, targets)

    @Test fun onlyFutureTimerHasCountdown() {
        assertTrue(visible()); assertFalse(visible(end = 0))
        assertFalse(visible(end = 1000)); assertFalse(visible(end = 999))
    }
    @Test fun disabledProtectionNeverClaimsRunningTimer() {
        assertFalse(visible(enabled = false)); assertFalse(visible(master = false))
        assertFalse(visible(accessibility = false)); assertFalse(visible(targets = false))
    }
    @Test fun pauseSuppressesUntilItsExclusiveEnd() {
        assertFalse(visible(pause = 1001)); assertTrue(visible(pause = 1000))
    }
    @Test fun overlappingPlansExpireIndependently() {
        assertFalse(visible(end = 1000)); assertTrue(visible(end = 2000))
        assertFalse(visible(end = 2000, now = 2000))
    }
    @Test fun absoluteTimeControlsExpiryAfterClockMoves() {
        assertTrue(visible(now = 500)); assertFalse(visible(now = 3000))
    }
}
