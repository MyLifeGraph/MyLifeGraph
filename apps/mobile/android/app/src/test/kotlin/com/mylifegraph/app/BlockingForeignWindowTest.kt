package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class BlockingForeignWindowTest {
    @Test fun removalEventsRetainOnlyPreviouslyConfirmedOverlayIds() {
        val windows = BlockingTransientWindows()
        assertFalse(windows.observe(5, BlockingWindowKind.UNKNOWN))
        assertTrue(windows.observe(5, BlockingWindowKind.TRANSIENT))
        assertTrue(windows.observe(5, BlockingWindowKind.UNKNOWN))
        assertFalse(windows.observe(6, BlockingWindowKind.UNKNOWN))
    }

    @Test fun applicationReuseClearsOverlayId() {
        val windows = BlockingTransientWindows()
        assertTrue(windows.observe(5, BlockingWindowKind.TRANSIENT))
        assertFalse(windows.observe(5, BlockingWindowKind.APPLICATION))
        assertFalse(windows.observe(5, BlockingWindowKind.UNKNOWN))
    }

    @Test fun metadataCacheIsBoundedAndInvalidIdsNeverSuppressApps() {
        val windows = BlockingTransientWindows()
        assertFalse(windows.observe(-1, BlockingWindowKind.TRANSIENT))
        for (id in 1..33) assertTrue(windows.observe(id, BlockingWindowKind.TRANSIENT))
        assertFalse(windows.observe(1, BlockingWindowKind.UNKNOWN))
        for (id in 2..33) assertTrue(windows.observe(id, BlockingWindowKind.UNKNOWN))
    }

    @Test fun foreignOverlayDoesNotReplaceAppOrAdvanceRecoveryTimestamp() {
        var app: String? = "instagram"
        var observedAt = 100L
        repeat(500) {
            if (!FocusProtectionDecision.ignoreOverlayWindow("other.blocker", true)) {
                app = "other.blocker"; observedAt = 200
            }
            assertEquals("instagram", app)
            assertEquals(100L, observedAt)
        }
        assertEquals("instagram", FocusProtectionDecision.recoverForeground(app, observedAt,
            "instagram", 100, "com.mylifegraph.app"))
    }

    @Test fun genuineOtherBlockerActivityAndUnknownWindowsRemainAppChanges() {
        for (pkg in listOf("other.blocker", "launcher", "com.android.settings", "game")) {
            assertFalse(FocusProtectionDecision.ignoreOverlayWindow(pkg, false))
            assertEquals(pkg, FocusProtectionDecision.budgetForeground(pkg, "instagram", "com.mylifegraph.app"))
        }
    }

    @Test fun systemUiKeepsItsSafeEscapeAndRememberedBudget() {
        assertFalse(FocusProtectionDecision.ignoreOverlayWindow("com.android.systemui", true))
        assertEquals("instagram", FocusProtectionDecision.budgetForeground("com.android.systemui",
            "instagram", "com.mylifegraph.app"))
        assertEquals("instagram.com", FocusProtectionDecision.budgetHost("com.android.systemui",
            null, "instagram.com", "com.mylifegraph.app"))
    }

    @Test fun noAppBlockPackageSpecificExemption() {
        assertTrue(FocusProtectionDecision.ignoreOverlayWindow("arbitrary.package", true))
        assertFalse(FocusProtectionDecision.ignoreOverlayWindow("arbitrary.package", false))
    }
}
