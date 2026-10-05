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
        session.visibility(false)
        rejected(session)
        session.visibility(true)
        rejected(session)
        session.focus(true)
        session.requireVisible()
        assertEquals(2, cancels)
    }

    @Test fun tabExitAndBackgroundResetWithoutAutoRestartOnReturn() {
        var pending = true
        val session = StrictScreenSession { pending = false }
        session.resumed(); session.visibility(true); session.focus(true)
        pending = true
        session.visibility(false)
        assertFalse(pending); rejected(session)
        session.visibility(true)
        session.requireVisible(); assertFalse(pending)
        pending = true
        session.stopped()
        assertFalse(pending); rejected(session)
        session.visibility(true) // A queued Flutter signal cannot reopen in background.
        rejected(session)
        session.resumed()
        rejected(session)
        session.visibility(true)
        session.focus(true)
        session.requireVisible(); assertFalse(pending)
    }

    @Test fun repeatedVisibleSignalsPreservePendingRequestButRecreationDoesNot() {
        var pending = false
        val first = StrictScreenSession { pending = false }
        first.resumed(); first.visibility(true); first.focus(true)
        pending = true
        repeat(100) { first.visibility(true); first.requireVisible() }
        assertTrue(pending)
        val recreated = StrictScreenSession { pending = false }
        assertFalse(pending); rejected(recreated)
    }

    @Test fun notificationShadeSuspendsCompletionAndResumePreservesRequest() {
        var pending = false
        val session = StrictScreenSession { pending = false }
        session.resumed(); session.visibility(true); session.focus(true)
        pending = true
        session.focus(false)
        rejected(session); assertTrue(pending)
        session.paused()
        session.visibility(true) // Inactive Flutter still owns the Strict route.
        assertTrue(pending); rejected(session)
        session.resumed()
        rejected(session)
        session.focus(true)
        session.requireVisible(); assertTrue(pending)
    }

    @Test fun stopAndScreenLockCancelEvenIfWindowFocusWasOnlyTemporarilyLost() {
        var pending = false
        val session = StrictScreenSession { pending = false }
        session.resumed(); session.visibility(true); session.focus(true)
        pending = true
        session.focus(false); session.stopped()
        assertFalse(pending); rejected(session)
        session.resumed(); session.focus(true)
        rejected(session)
        session.visibility(true); session.requireVisible()
        assertFalse(pending)
    }
}
