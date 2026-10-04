package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class StrictScreenSessionTest {
    private fun rejected(session: StrictScreenSession) {
        try { session.requireVisible(); fail("Hidden Strict screen must reject unlock") }
        catch (_: IllegalStateException) { }
    }

    @Test fun newActivityCancelsPersistedWaitAndNeedsForegroundVisibleScreen() {
        var cancels = 0
        val session = StrictScreenSession { cancels++ }
        assertEquals(1, cancels)
        rejected(session)
        session.visibility(true)
        rejected(session)
        session.resumed()
        rejected(session)
        session.visibility(true)
        session.requireVisible()
        assertEquals(2, cancels)
    }

    @Test fun tabExitAndBackgroundResetWithoutAutoRestartOnReturn() {
        var pending = true
        val session = StrictScreenSession { pending = false }
        session.resumed(); session.visibility(true)
        pending = true
        session.visibility(false)
        assertFalse(pending); rejected(session)
        session.visibility(true)
        session.requireVisible(); assertFalse(pending)
        pending = true
        session.paused()
        assertFalse(pending); rejected(session)
        session.visibility(true) // A queued Flutter signal cannot reopen in background.
        rejected(session)
        session.resumed()
        rejected(session)
        session.visibility(true)
        session.requireVisible(); assertFalse(pending)
    }

    @Test fun repeatedVisibleSignalsPreservePendingRequestButRecreationDoesNot() {
        var pending = false
        val first = StrictScreenSession { pending = false }
        first.resumed(); first.visibility(true)
        pending = true
        repeat(100) { first.visibility(true); first.requireVisible() }
        assertTrue(pending)
        val recreated = StrictScreenSession { pending = false }
        assertFalse(pending); rejected(recreated)
    }
}
