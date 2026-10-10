package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class DisciplineSettingsPolicyTest {
    @Test fun freshAndDisabledDefaultToBackground() {
        assertFalse(BlockingEditPolicy.stayOnScreen(null, false))
    }
    @Test fun activeLegacyModeRetainsItsOldProtectionUntilExplicitlyConfigured() {
        assertTrue(BlockingEditPolicy.stayOnScreen(null, true))
        assertFalse(BlockingEditPolicy.stayOnScreen(false, true))
        assertTrue(BlockingEditPolicy.stayOnScreen(true, false))
    }
    @Test fun temporaryReleaseIsNotPermissionToChangePolicy() {
        try {
            BlockingEditPolicy.requireStayPolicyEditable(true)
            fail("Enabled mode must reject changes even while temporarily unlocked")
        } catch (_: IllegalStateException) { }
        BlockingEditPolicy.requireStayPolicyEditable(false)
    }
}
