package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class BlockingUnlockIntentTest {
    @Test fun absentIntentRemainsTemporaryAndUnknownIntentFailsClosed() {
        assertEquals("temporary", BlockingUnlockPolicy.mode(null))
        assertEquals("off", BlockingUnlockPolicy.mode("off"))
        try { BlockingUnlockPolicy.mode("disable-all-plans"); fail("Unknown mode accepted") }
        catch (_: IllegalArgumentException) { }
    }

    @Test fun duplicateRequestCannotReplaceItsChosenIntent() {
        for (mode in listOf("temporary", "off")) {
            BlockingUnlockPolicy.requireSameIntent(mode, null)
            BlockingUnlockPolicy.requireSameIntent(mode, mode)
        }
        try { BlockingUnlockPolicy.requireSameIntent("off", "temporary"); fail("Intent replaced") }
        catch (_: IllegalStateException) { }
    }

    @Test fun permanentOffPreservesActiveFocusConfigurationGuard() {
        assertFalse(BlockingUnlockPolicy.completionAllowed("off", true))
        assertTrue(BlockingUnlockPolicy.completionAllowed("off", false))
        assertTrue(BlockingUnlockPolicy.completionAllowed("temporary", true))
    }

    @Test fun elapsedWaitStillNeedsEveryRequestedNativeCondition() {
        for (power in listOf(false, true)) for (wifi in listOf(false, true)) for (nfc in listOf(false, true)) {
            assertEquals(power && wifi && nfc,
                BlockingUnlockPolicy.ready(0, true, power, true, wifi, true, nfc))
            assertFalse(BlockingUnlockPolicy.ready(1, true, power, true, wifi, true, nfc))
        }
    }

    @Test fun reorderRetainsEveryDefinitionAndRejectsAddedRemovedOrDuplicateIds() {
        val current = listOf("a" to listOf("focus", "always"), "b" to listOf("timer"))
        assertEquals(current.reversed(), BlockingOrderPolicy.reorder(current, listOf("b", "a")) { it.first })
        assertEquals(current, BlockingOrderPolicy.reorder(current, listOf("a", "b")) { it.first })
        for (ids in listOf(listOf("a"), listOf("a", "a"), listOf("a", "c"), listOf("a", "b", "c"))) {
            try { BlockingOrderPolicy.reorder(current, ids) { it.first }; fail("Invalid permutation accepted") }
            catch (_: IllegalArgumentException) { }
        }
    }
}
