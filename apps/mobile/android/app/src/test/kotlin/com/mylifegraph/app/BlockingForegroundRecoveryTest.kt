package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class BlockingForegroundRecoveryTest {
    private val own = "com.mylifegraph.app"
    @Test fun coldConnectionRestoresAlreadyResumedApp() {
        val usage = BlockingUsageReducer(100, 500)
        usage.resume("game", "Main", 50)
        assertEquals("game", FocusProtectionDecision.recoverForeground(null, 0,
            usage.foregroundPackage, usage.foregroundChangedAt, own))
        assertEquals(400L, usage.result()["game"])
    }
    @Test fun missedNewAppEventRecoversButOlderSnapshotsCannotUndoEvents() {
        assertEquals("new", FocusProtectionDecision.recoverForeground("old", 100, "new", 200, own))
        assertEquals("new", FocusProtectionDecision.recoverForeground("new", 200, "old", 100, own))
        assertEquals("new", FocusProtectionDecision.recoverForeground("new", 200, "old", 200, own))
    }
    @Test fun actualOwnAppAndShadeEventsAreNotUndoneByOldUsage() {
        assertEquals(own, FocusProtectionDecision.recoverForeground(own, 300, "game", 200, own))
        assertEquals("com.android.systemui", FocusProtectionDecision.recoverForeground("com.android.systemui", 300, "game", 200, own))
        assertEquals("game", FocusProtectionDecision.recoverForeground("game", 100, own, 200, own))
        assertEquals("game", FocusProtectionDecision.recoverForeground("game", 100, "com.android.systemui", 200, own))
    }
    @Test fun unknownEvidenceDoesNotInventForegroundOrUnlock() {
        for (candidate in listOf(null, "", " ")) assertEquals("game",
            FocusProtectionDecision.recoverForeground("game", 10, candidate, 20, own))
        assertNull(FocusProtectionDecision.recoverForeground(null, 0, "game", 0, own))
    }
    @Test fun pauseAndScreenOffClearOnlyTheActualResumedSet() {
        val usage = BlockingUsageReducer(0, 100)
        usage.resume("game", "Main", 10); usage.resume("game", "Dialog", 20)
        usage.pause("game", "Dialog", 30)
        assertEquals("game", usage.foregroundPackage)
        usage.pause("game", "Main", 40)
        assertNull(usage.foregroundPackage); assertEquals(40L, usage.foregroundChangedAt)
        usage.resume("other", "Main", 50); usage.screenOff(60)
        assertNull(usage.foregroundPackage); assertEquals(60L, usage.foregroundChangedAt)
        assertEquals(mapOf("game" to 30L, "other" to 10L), usage.result())
    }
    @Test fun repeatedRecoveryHasNoUsageInflation() {
        repeat(500) {
            assertEquals("game", FocusProtectionDecision.recoverForeground("game", 100, "game", 200, own))
        }
    }
}
