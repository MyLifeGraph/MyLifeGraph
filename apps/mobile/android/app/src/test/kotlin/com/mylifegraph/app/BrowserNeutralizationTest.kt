package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class BrowserNeutralizationTest {
    private fun next(p: BrowserNeutralization, now: Long = 100, pkg: String = "browser", window: Int = 1,
        eligible: Boolean = true, visible: Boolean = true, editable: Boolean = false,
        focused: Boolean = false, host: String? = "blocked.test", blank: Boolean = false,
        submit: Boolean = true) = p.next(now, pkg, window, eligible, visible, editable, focused, host, blank, submit)

    @Test fun neutralPageRequiresRealNavigationConfirmation() {
        val p = BrowserNeutralization("browser", "blocked.test", 1, 100)
        assertEquals(BrowserNeutralization.Action.FOCUS, next(p))
        p.performed(BrowserNeutralization.Action.FOCUS, true)
        assertEquals(BrowserNeutralization.Action.WAIT, next(p))
        assertEquals(BrowserNeutralization.Action.REPLACE, next(p, editable=true, focused=true))
        p.performed(BrowserNeutralization.Action.REPLACE, true)
        assertEquals(BrowserNeutralization.Action.SUBMIT, next(p, editable=true, focused=true, host=null, blank=true))
        p.performed(BrowserNeutralization.Action.SUBMIT, true)
        assertEquals(BrowserNeutralization.Action.WAIT, next(p, editable=true, focused=true, host=null, blank=true))
        assertEquals(BrowserNeutralization.Action.COMPLETE, next(p, host=null, blank=true))
    }
    @Test fun neverReplacesUserInputOrAnotherTabWindow() {
        val p = BrowserNeutralization("browser", "blocked.test", 1, 100)
        assertEquals(BrowserNeutralization.Action.ABORT, next(p, editable=true, focused=true))
        p.performed(BrowserNeutralization.Action.FOCUS, true)
        assertEquals(BrowserNeutralization.Action.ABORT, next(p, editable=true, focused=true, host="other.test"))
        assertEquals(BrowserNeutralization.Action.ABORT, next(p, window=2))
        assertEquals(BrowserNeutralization.Action.ABORT, next(p, pkg="other.app"))
    }
    @Test fun unsupportedSubmitCannotModifyTheAddress() {
        val p = BrowserNeutralization("browser", "blocked.test", 1, 100)
        p.performed(BrowserNeutralization.Action.FOCUS, true)
        assertEquals(BrowserNeutralization.Action.ABORT, next(p, editable=true, focused=true, submit=false))
        p.performed(BrowserNeutralization.Action.REPLACE, false)
        assertEquals(BrowserNeutralization.Action.ABORT, next(p))
    }
    @Test fun consentVisibilityTimeoutAndClockRollbackAbort() {
        val p = BrowserNeutralization("browser", "blocked.test", 1, 100)
        assertEquals(BrowserNeutralization.Action.ABORT, next(p, eligible=false))
        assertEquals(BrowserNeutralization.Action.ABORT, next(p, visible=false))
        assertEquals(BrowserNeutralization.Action.ABORT, next(p, now=5100))
        assertEquals(BrowserNeutralization.Action.ABORT, next(p, now=99))
    }
    @Test fun repeatedCallbacksStayFinite() {
        repeat(1000) {
            val p = BrowserNeutralization("browser", "blocked.test", 1, 0)
            p.performed(BrowserNeutralization.Action.FOCUS, true)
            for (time in 0L..4999L step 80) assertEquals(BrowserNeutralization.Action.WAIT, next(p, now=time))
            assertEquals(BrowserNeutralization.Action.ABORT, next(p, now=5000))
        }
    }
    @Test fun browserClearedEditorIsAllowedOnlyAfterOurOwnFocus() {
        val p = BrowserNeutralization("browser", "blocked.test", 1, 100)
        assertEquals(BrowserNeutralization.Action.ABORT,
            p.next(100,"browser",1,true,true,true,true,null,false,true,true))
        p.performed(BrowserNeutralization.Action.FOCUS,true)
        assertEquals(BrowserNeutralization.Action.REPLACE,
            p.next(100,"browser",1,true,true,true,true,null,false,true,true))
        assertEquals(BrowserNeutralization.Action.ABORT,
            p.next(100,"browser",1,true,true,true,true,null,false,false,true))
        // Nonempty user queries cannot use the browser-cleared-editor allowance.
        assertEquals(BrowserNeutralization.Action.ABORT,
            p.next(100,"browser",1,true,true,true,true,null,false,true,false))
        assertFalse(p.expired(5099)); assertTrue(p.expired(5100))
    }
}
