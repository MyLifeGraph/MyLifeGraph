package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class BlockingBudgetTimerPolicyTest {
    @Test fun delayedDismissalFromPreviousProcessCannotSuppressNewSession() {
        val oldSession = BlockingBudgetNotificationSession()
        oldSession.select("games:instagram")
        val oldToken = oldSession.dismissalToken()!!
        val restartedSession = BlockingBudgetNotificationSession()
        restartedSession.select("games:instagram")
        restartedSession.dismiss(oldToken)
        assertTrue(restartedSession.select("games:instagram"))
    }
    @Test fun delayedDismissalCannotSuppressLaterVisitToSameApp() {
        val session = BlockingBudgetNotificationSession()
        session.select("games:instagram")
        val oldToken = session.dismissalToken()!!
        session.select(null)
        session.select("games:instagram")
        session.dismiss(oldToken)
        assertTrue(session.select("games:instagram"))
    }
    @Test fun rapidTransitionsKeepOnlyCurrentVisitDismissible() {
        val session = BlockingBudgetNotificationSession()
        val oldTokens = mutableListOf<String>()
        repeat(500) { index ->
            val key = "plan:${index % 3}"
            assertTrue(session.select(key))
            oldTokens.forEach(session::dismiss)
            assertTrue(session.select(key))
            val current = session.dismissalToken()!!
            session.dismiss(current)
            repeat(3) { assertFalse(session.select(key)) }
            oldTokens.add(current)
            session.select(null)
        }
    }
    @Test fun explicitDismissalSurvivesTicksButNotNextAppVisit() {
        val session = BlockingBudgetNotificationSession()
        assertTrue(session.select("games:instagram"))
        repeat(100) { assertTrue(session.select("games:instagram")) }
        session.dismiss(session.dismissalToken()!!)
        repeat(100) { assertFalse(session.select("games:instagram")) }
        assertFalse(session.select(null))
        assertTrue(session.select("games:instagram"))
    }
    @Test fun delayedDismissalOfOldAppCannotDismissNewApp() {
        val session = BlockingBudgetNotificationSession()
        session.select("games:instagram")
        val oldToken = session.dismissalToken()!!
        assertTrue(session.select("games:game"))
        session.dismiss(oldToken)
        assertTrue(session.select("games:game"))
    }
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
