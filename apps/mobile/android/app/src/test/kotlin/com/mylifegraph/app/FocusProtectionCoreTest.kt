package com.mylifegraph.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class FocusProtectionCoreTest {
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
