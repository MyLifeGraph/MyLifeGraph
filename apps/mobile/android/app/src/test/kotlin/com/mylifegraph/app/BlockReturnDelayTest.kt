package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class BlockReturnDelayTest {
    @Test fun strictMustBeOffForEmergencyButNeverBlocksNormalReturn() {
        BlockingEditPolicy.requireEmergencyAllowed(false)
        repeat(1000) {
            assertThrows(IllegalStateException::class.java) {
                BlockingEditPolicy.requireEmergencyAllowed(true)
            }
            val gate = BlockReturnDelay()
            gate.begin("app", 3, 1000)
            // Return is independent of Strict, including a temporary edit window.
            assertTrue(gate.complete(4000))
        }
    }
    @Test fun exactBoundariesAndAllDurations() {
        for (seconds in listOf(0, 1, 3, 5, 10, 15, 20, 60, 180, 300, 600, 900)) {
            val gate = BlockReturnDelay()
            assertTrue(gate.begin("app.one", seconds, 1000))
            assertEquals(seconds * 1000L, gate.remaining(1000))
            if (seconds > 0) {
                assertFalse(gate.complete(1000 + seconds * 1000L - 1))
                assertEquals(1, gate.remaining(1000 + seconds * 1000L - 1).toInt())
            }
            assertTrue(gate.complete(1000 + seconds * 1000L))
            assertNull(gate.target)
            assertFalse(gate.complete(Long.MAX_VALUE))
        }
    }
    @Test fun homeAndRepeatedEventsCannotRestartOrExtendTheWait() {
        val gate = BlockReturnDelay()
        gate.begin("app.one", 15, 1000)
        repeat(10000) {
            assertFalse(gate.begin("app.two", 900, 2000))
            assertTrue(gate.retain(true, false, true))
            assertEquals(14000L, gate.remaining(2000))
        }
        assertEquals("app.one", gate.target)
        assertTrue(gate.complete(16000))
        assertFalse(gate.retain(true, true, true))
    }
    @Test fun expiryMasterOffAndEssentialEscapesNeverRetainTheScreen() {
        val gate = BlockReturnDelay()
        gate.begin("app.one", 900, 0)
        for (foreground in listOf(false, true)) {
            assertFalse(gate.retain(false, foreground, true))
        }
        assertFalse(gate.retain(true, false, false))
        gate.clear()
        assertFalse(gate.retain(true, true, true))
        assertTrue(gate.begin("app.two", 1, 3000))
        assertTrue(gate.complete(4000))
    }
    @Test fun malformedDurationsAreBoundedAndClockRegressionCannotOverflow() {
        for (seconds in listOf(Int.MIN_VALUE, -1, 0, 900, Int.MAX_VALUE)) {
            val gate = BlockReturnDelay()
            gate.begin("app", seconds, 100)
            assertEquals(seconds.coerceIn(0, 900) * 1000L, gate.remaining(0))
            assertTrue(gate.complete(900100))
        }
    }
    @Test fun stressFiniteEntriesAndReleaseCannotResurrectAnAttempt() {
        val gate = BlockReturnDelay()
        repeat(20000) { entry ->
            val now = entry * 2000L
            assertTrue(gate.begin("app", 1, now))
            assertFalse(gate.complete(now + 999))
            assertTrue(gate.complete(now + 1000))
            assertFalse(gate.retain(true, false, true))
            assertEquals(0L, gate.remaining(now + 1001))
        }
    }
}
