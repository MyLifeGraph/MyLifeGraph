package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class BlockingReturnNavigationTest {
    @Test fun returnRequiresElapsedDelayAndAcceptedHomeBeforeDismissing() {
        val delay = BlockReturnDelay()
        val steps = mutableListOf<String>()
        delay.begin("denied.app", 3, 0)
        assertFalse(delay.exitViaHome(2999, { steps.add("home"); true }, { steps.add("return") }))
        assertTrue(steps.isEmpty())
        assertFalse(delay.exitViaHome(3000, { steps.add("failed-home"); false }, { steps.add("return") }))
        assertEquals("denied.app", delay.target)
        assertTrue(delay.exitViaHome(3000, {
            assertEquals("denied.app", delay.target); steps.add("home"); true
        }, { assertNull(delay.target); steps.add("return") }))
        assertEquals(listOf("failed-home", "home", "return"), steps)
        assertFalse(delay.exitViaHome(3001, { fail("No repeated navigation"); true }, {}))
    }

    @Test fun reenteringDeniedAppStartsFreshEntryWithoutChangingBlockingRules() {
        val delay = BlockReturnDelay()
        repeat(1000) { visit ->
            val now = visit * 10L
            assertTrue(delay.begin("denied.app", 0, now))
            assertTrue(delay.exitViaHome(now, { true }, {}))
            assertNull(delay.target)
        }
    }
    @Test fun queuedOriginEventsCannotResurrectARequestedReturn() {
        val navigation = BlockingReturnNavigation()
        repeat(1000) {
            navigation.begin("denied.app")
            repeat(20) { assertEquals(BlockingReturnNavigation.Destination.WAIT,
                navigation.destination("denied.app", "own.app", setOf("home.app"))) }
            assertEquals(BlockingReturnNavigation.Destination.WAIT,
                navigation.destination("com.android.systemui", "own.app", setOf("home.app")))
            assertEquals(BlockingReturnNavigation.Destination.HOME,
                navigation.destination("home.app", "own.app", setOf("home.app")))
            assertEquals(BlockingReturnNavigation.Destination.OWN,
                navigation.destination("own.app", "own.app", setOf("home.app")))
            assertEquals(BlockingReturnNavigation.Destination.OTHER,
                navigation.destination("safe.app", "own.app", setOf("home.app")))
            assertEquals(BlockingReturnNavigation.Destination.OTHER,
                navigation.destination("denied.app", "own.app", setOf("home.app"), false))
            navigation.clear(); assertNull(navigation.source)
        }
    }
}
