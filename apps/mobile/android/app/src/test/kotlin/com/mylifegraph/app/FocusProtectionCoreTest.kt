package com.mylifegraph.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

class FocusProtectionCoreTest {
    private fun instant(day: Int, hour: Int, minute: Int, zone: String = "UTC"): Long =
        Calendar.getInstance(TimeZone.getTimeZone(zone)).apply {
            clear()
            set(2026, Calendar.SEPTEMBER, day, hour, minute)
        }.timeInMillis

    @Test
    fun weeklyScheduleHonorsDaysAndExclusiveEnd() {
        val schedule = AppBlockingSchedule("weekly", setOf(1, 3), 540, 1020)
        val zone = TimeZone.getTimeZone("UTC")
        assertFalse(schedule.active(instant(14, 8, 59), false, zone))
        assertTrue(schedule.active(instant(14, 9, 0), false, zone))
        assertTrue(schedule.active(instant(14, 16, 59), false, zone))
        assertFalse(schedule.active(instant(14, 17, 0), true, zone))
        assertFalse(schedule.active(instant(15, 12, 0), true, zone))
        assertTrue(schedule.active(instant(16, 12, 0), false, zone))
    }

    @Test
    fun overnightWindowUsesStartDayIncludingSundayRollover() {
        val schedule = AppBlockingSchedule("weekly", setOf(7), 22 * 60, 6 * 60)
        val zone = TimeZone.getTimeZone("Europe/Berlin")
        assertTrue(schedule.active(instant(13, 23, 0, zone.id), false, zone))
        assertTrue(schedule.active(instant(14, 5, 59, zone.id), false, zone))
        assertFalse(schedule.active(instant(14, 6, 0, zone.id), true, zone))
        assertFalse(schedule.active(instant(14, 23, 0, zone.id), true, zone))
    }

    @Test
    fun modesAreIndependentAndAlwaysStillHonorsMasterAndEssentialApps() {
        val now = instant(14, 12, 0)
        assertFalse(AppBlockingSchedule().active(now, false))
        assertTrue(AppBlockingSchedule().active(now, true))
        val always = AppBlockingSchedule("always")
        assertTrue(always.active(now, false))
        fun block(enabled: Boolean, essential: Set<String>) = FocusProtectionDecision.shouldBlockPackage(
            enabled, true, true, setOf("selected"), essential, "selected", null, now, always,
        )
        assertTrue(block(true, emptySet()))
        assertFalse(block(false, emptySet()))
        assertFalse(block(true, setOf("selected")))
        assertFalse(FocusProtectionDecision.shouldRequestZen(true, true, null, now))
    }

    @Test(expected = IllegalArgumentException::class)
    fun emptyWeekdaysAreRejected() { AppBlockingSchedule("weekly", emptySet()) }

    @Test
    fun repeatedDstHourFollowsDeviceWallTimeBothTimes() {
        val zone = TimeZone.getTimeZone("Europe/Berlin")
        val schedule = AppBlockingSchedule("weekly", setOf(7), 120, 180)
        fun utc(hour: Int) = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(2026, Calendar.OCTOBER, 25, hour, 30)
        }.timeInMillis
        assertTrue(schedule.active(utc(0), false, zone))
        assertTrue(schedule.active(utc(1), false, zone))
        assertFalse(schedule.active(utc(2), false, zone))
    }

    @Test(expected = IllegalArgumentException::class)
    fun equalClockTimesAreRejectedInsteadOfAccidentallyBlockingAllDay() {
        AppBlockingSchedule("weekly", setOf(1), 600, 600)
    }

    @Test
    fun ownOverlayEventsDoNotReplaceTheBlockedForegroundPackage() {
        var foreground = "com.instagram.android"
        for (eventPackage in listOf("com.mylifegraph.app", null, "", "com.instagram.android")) {
            if (!FocusProtectionDecision.ignoreForegroundEvent(eventPackage, "com.mylifegraph.app", true)) {
                foreground = eventPackage!!
            }
            assertEquals("com.instagram.android", foreground)
        }
        assertFalse(FocusProtectionDecision.ignoreForegroundEvent("com.android.settings", "com.mylifegraph.app", true))
        assertFalse(FocusProtectionDecision.ignoreForegroundEvent("launcher.app", "com.mylifegraph.app", true))
        assertFalse(FocusProtectionDecision.ignoreForegroundEvent("com.mylifegraph.app", "com.mylifegraph.app", false))
    }

    private val lease = LocalFocusLease(
        sessionId = "session-1",
        startedAtEpochMs = 1_000L,
        endsAtEpochMs = 61_000L,
    )

    @Test
    fun leaseExpiresFailOpenAtPersistedEnd() {
        assertTrue(lease.isActive(60_999L))
        assertFalse(lease.isActive(61_000L))
        assertFalse(lease.isActive(80_000L))
    }

    @Test
    fun exactActivationReplayIsIdempotent() {
        val result = FocusProtectionDecision.reconcileActivation(
            currentLease = lease,
            suppressedSessionId = null,
            candidate = lease,
            nowEpochMs = 2_000L,
        )
        assertSame(lease, result)
    }

    @Test
    fun emergencyReleasedSessionCannotBeReactivated() {
        val result = FocusProtectionDecision.reconcileActivation(
            currentLease = null,
            suppressedSessionId = lease.sessionId,
            candidate = lease,
            nowEpochMs = 2_000L,
        )
        assertEquals(LocalFocusLease.STATE_EMERGENCY_RELEASED, result?.state)
        assertFalse(result!!.isActive(2_000L))
    }

    @Test
    fun alreadyExpiredActivationIsRejected() {
        assertNull(
            FocusProtectionDecision.reconcileActivation(
                currentLease = null,
                suppressedSessionId = null,
                candidate = lease,
                nowEpochMs = lease.endsAtEpochMs,
            ),
        )
    }

    @Test
    fun expiredOrOlderCandidateCannotClearANewerActiveLease() {
        val newer = LocalFocusLease(
            sessionId = "session-2",
            startedAtEpochMs = 5_000L,
            endsAtEpochMs = 65_000L,
        )
        val expiredCandidate = LocalFocusLease(
            sessionId = "old-expired",
            startedAtEpochMs = 500L,
            endsAtEpochMs = 1_500L,
        )

        assertSame(
            newer,
            FocusProtectionDecision.reconcileActivation(
                currentLease = newer,
                suppressedSessionId = null,
                candidate = lease,
                nowEpochMs = 6_000L,
            ),
        )
        assertSame(
            newer,
            FocusProtectionDecision.reconcileActivation(
                currentLease = newer,
                suppressedSessionId = null,
                candidate = expiredCandidate,
                nowEpochMs = 6_000L,
            ),
        )
    }

    @Test
    fun replayCannotExtendTheSameSessionLease() {
        val extended = lease.copy(endsAtEpochMs = 120_000L)

        assertSame(
            lease,
            FocusProtectionDecision.reconcileActivation(
                currentLease = lease,
                suppressedSessionId = null,
                candidate = extended,
                nowEpochMs = 2_000L,
            ),
        )
    }

    @Test
    fun zenRequestRequiresConfigurationAndAnUnexpiredActiveLease() {
        assertTrue(
            FocusProtectionDecision.shouldRequestZen(
                protectionEnabled = true,
                silenceNotifications = true,
                lease = lease,
                nowEpochMs = 2_000L,
            ),
        )
        assertFalse(
            FocusProtectionDecision.shouldRequestZen(
                protectionEnabled = true,
                silenceNotifications = true,
                lease = null,
                nowEpochMs = 2_000L,
            ),
        )
        assertFalse(
            FocusProtectionDecision.shouldRequestZen(
                protectionEnabled = true,
                silenceNotifications = true,
                lease = lease,
                nowEpochMs = lease.endsAtEpochMs,
            ),
        )
    }

    @Test
    fun zenRuleMustExistBeEnabledAndMatchTheExactPolicy() {
        assertTrue(
            FocusZenRuleDecision.canPublish(
                ruleExists = true,
                ruleEnabled = true,
                exactDefinition = true,
            ),
        )
        assertFalse(
            FocusZenRuleDecision.canPublish(
                ruleExists = false,
                ruleEnabled = true,
                exactDefinition = true,
            ),
        )
        assertFalse(
            FocusZenRuleDecision.canPublish(
                ruleExists = true,
                ruleEnabled = false,
                exactDefinition = true,
            ),
        )
        assertFalse(
            FocusZenRuleDecision.canPublish(
                ruleExists = true,
                ruleEnabled = true,
                exactDefinition = false,
            ),
        )
    }

    @Test
    fun emergencyReleaseNeedsFiveSecondsAndASeparateConfirmation() {
        val gate = EmergencyReleaseGate(5_000L)

        assertTrue(gate.start(10_000L))
        assertFalse(gate.tryArm(14_999L))
        assertFalse(gate.confirm())
        assertTrue(gate.tryArm(15_000L))
        assertTrue(gate.isArmed)
        assertTrue(gate.confirm())
        assertFalse(gate.confirm())
    }

    @Test
    fun blockingRequiresEveryGuardAndNeverBlocksEssentialPackages() {
        val common = {
                foreground: String?,
                selected: Set<String>,
                essential: Set<String>,
            ->
            FocusProtectionDecision.shouldBlockPackage(
                protectionEnabled = true,
                blockingEnabled = true,
                accessibilityEnabled = true,
                selectedPackages = selected,
                essentialPackages = essential,
                foregroundPackage = foreground,
                lease = lease,
                nowEpochMs = 2_000L,
            )
        }
        assertTrue(common("video.app", setOf("video.app"), emptySet()))
        assertFalse(common("video.app", setOf("video.app"), setOf("video.app")))
        assertFalse(common("chat.app", setOf("video.app"), emptySet()))
        assertFalse(
            FocusProtectionDecision.shouldBlockPackage(
                protectionEnabled = false,
                blockingEnabled = true,
                accessibilityEnabled = true,
                selectedPackages = setOf("video.app"),
                essentialPackages = emptySet(),
                foregroundPackage = "video.app",
                lease = lease,
                nowEpochMs = 2_000L,
            ),
        )
    }

    @Test
    fun appCatalogRemovesEssentialAllowlist() {
        assertEquals(
            setOf("video.app"),
            FocusProtectionDecision.selectablePackages(
                launchablePackages = setOf("video.app", "dialer.app", "settings.app"),
                essentialPackages = setOf("dialer.app", "settings.app"),
            ),
        )
    }

    @Test
    fun zenPolicySpecMapsTheV1AttentionBoundary() {
        val policy = FocusZenPolicySpec()
        assertTrue(policy.allowAlarms)
        assertTrue(policy.allowFavoriteCalls)
        assertTrue(policy.allowRepeatCallers)
        assertTrue(policy.allowMedia)
        assertFalse(policy.allowMessages)
        assertFalse(policy.allowConversations)
        assertFalse(policy.allowEvents)
        assertFalse(policy.allowReminders)
        assertFalse(policy.showPeeking)
        assertFalse(policy.showBadges)
        assertFalse(policy.showStatusBarIcons)
        assertFalse(policy.showLockscreen)
        assertFalse(policy.showAmbientDisplay)
        assertFalse(policy.showNotificationList)
    }
}
