package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class StrictScreenSessionTest {
    @Test fun deliberateRequestReconcilesStaleHostCallbacksWithoutTrustingRouteAlone() {
        val session = StrictScreenSession({ false }) { }
        session.visibility(true)
        // Host resumed behind keyguard, then gained focus without another
        // resume callback: cached foreground is still false.
        session.focus(true)
        rejected(session)
        session.requireVisible(hostResumed = true, hostFocused = true)
        assertTrue(session.canComplete())
        for ((resumed, focused) in listOf(false to true, true to false, false to false)) {
            try {
                session.requireVisible(resumed, focused)
                fail("A hidden/unfocused host must not start unlock")
            } catch (_: IllegalStateException) { }
        }
        session.visibility(false)
        try {
            session.requireVisible(true, true)
            fail("Current host facts must not override hidden Discipline route")
        } catch (_: IllegalStateException) { }
    }
    @Test fun backgroundPolicyRetainsRequestAcrossTabStopAndRecreation() {
        var pending = true
        val session = StrictScreenSession({ false }) { pending = false }
        assertTrue(pending)
        session.resumed(); session.visibility(true); session.focus(true)
        session.visibility(false); session.stopped()
        assertTrue(pending)
        assertTrue(session.canFinishUnlock())
        rejected(session) // Starting a request/scanning still requires this visible screen.
        StrictScreenSession({ false }) { pending = false }
        assertTrue(pending)
    }

    @Test fun stayPolicyRequiresVisibleForegroundForCompletion() {
        val session = StrictScreenSession({ true }) { }
        assertFalse(session.canFinishUnlock())
        session.resumed(); session.visibility(true); session.focus(true)
        assertTrue(session.canFinishUnlock())
        session.focus(false)
        assertFalse(session.canFinishUnlock())
    }
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
