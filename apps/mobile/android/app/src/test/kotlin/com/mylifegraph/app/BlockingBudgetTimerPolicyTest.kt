package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class BlockingBudgetTimerPolicyTest {
    private fun left(enabled: Boolean = true, pause: Long = 0, budget: Int = 45,
                     used: Long = 1000, match: Boolean = true, available: Boolean = true) =
        BlockingBudgetTimerPolicy.remaining(enabled, pause, 1000, budget, used, match, available)
    @Test fun countdownIsUsageAllowanceNotWallTimer() {
        assertEquals(2699000L, left())
        assertEquals(2500L, left(budget = 1, used = 57500))
    }
    @Test fun onlySelectedAvailableForegroundAppCanShow() {
        assertNull(left(match = false)); assertNull(left(available = false))
        assertNull(left(enabled = false)); assertNull(left(pause = 1001))
        assertNotNull(left(pause = 1000))
    }
    @Test fun zeroOrExhaustedBudgetsNeverShow() {
        assertNull(left(budget = 0)); assertNull(left(budget = 1, used = 60000))
        assertNull(left(budget = 1, used = 60001))
        assertEquals(60000L, left(budget = 1, used = -1))
    }
}
