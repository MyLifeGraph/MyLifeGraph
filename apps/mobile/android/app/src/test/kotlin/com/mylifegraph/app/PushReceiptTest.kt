package com.mylifegraph.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PushReceiptTest {
    @Test fun streakKindsUseOnlyTodayAndRetainAllReceiptGuards() {
        for (kind in listOf("streak_10h", "streak_5h")) {
            val reminder = data + mapOf("kind" to kind, "destination" to "/dashboard")
            assertTrue(PushReceipt.accepts(reminder, true, "owner", "session", "registration", 1000))
            assertFalse(PushReceipt.accepts(reminder + mapOf("destination" to "/planner"), true, "owner", "session", "registration", 1000))
            assertFalse(PushReceipt.accepts(reminder, false, "owner", "session", "registration", 1000))
            assertFalse(PushReceipt.accepts(reminder, true, "other", "session", "registration", 1000))
            assertFalse(PushReceipt.accepts(reminder, true, "owner", "session", "registration", 1100))
        }
    }
    @Test fun notificationTapRetainsEverySupportedDestination() {
        for (route in listOf("/dashboard", "/planner", "/insights", "/morning-calibration", "/quick-mood-check-in")) {
            assertTrue(PushReceipt.allowsDestination(route))
        }
        assertFalse(PushReceipt.allowsDestination("https://example.test"))
        assertFalse(PushReceipt.allowsDestination("/settings"))
        assertFalse(PushReceipt.allowsDestination(null))
    }

    private val data = mapOf("contract_version" to "android-push-v1", "owner" to "owner",
        "session_id" to "session", "registration_id" to "registration", "expires_epoch" to "1100",
        "kind" to "sleep", "destination" to "/insights", "attempt_id" to "eb140000-0000-4000-8000-000000000001")

    @Test fun currentShortLivedReceiptIsAccepted() {
        assertTrue(PushReceipt.accepts(data, true, "owner", "session", "registration", 1000))
    }
    @Test fun checkinsRequireTheirOwnDestination() {
        for ((kind, route) in listOf("morning" to "/morning-calibration", "evening" to "/quick-mood-check-in")) {
            assertTrue(PushReceipt.accepts(data + mapOf("kind" to kind, "destination" to route), true, "owner", "session", "registration", 1000))
            assertFalse(PushReceipt.accepts(data + mapOf("kind" to kind), true, "owner", "session", "registration", 1000))
        }
    }
    @Test fun disabledAndChangedAccountCannotReceive() {
        assertFalse(PushReceipt.accepts(data, false, "owner", "session", "registration", 1000))
        assertFalse(PushReceipt.accepts(data, true, "other", "session", "registration", 1000))
        assertFalse(PushReceipt.accepts(data, true, "owner", "other", "registration", 1000))
        assertFalse(PushReceipt.accepts(data, true, "owner", "session", "other", 1000))
        assertFalse(PushReceipt.accepts(data, true, null, null, null, 1000))
    }
    @Test fun expiryAndUnexpectedPayloadFailClosed() {
        for (change in listOf(mapOf("expires_epoch" to "1000"), mapOf("expires_epoch" to "1901"),
            mapOf("expires_epoch" to "bad"), mapOf("destination" to "https://untrusted.example"),
            mapOf("destination" to "/planner"), mapOf("kind" to "other"),
            mapOf("contract_version" to "future"), mapOf("attempt_id" to "bad"))) {
            assertFalse(PushReceipt.accepts(data + change, true, "owner", "session", "registration", 1000))
        }
    }
}
