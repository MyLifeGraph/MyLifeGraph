package com.mylifegraph.app

data class LocalFocusLease(
    val sessionId: String,
    val startedAtEpochMs: Long,
    val endsAtEpochMs: Long,
    val state: String = STATE_ACTIVE,
) {
    fun isActive(nowEpochMs: Long): Boolean =
        state == STATE_ACTIVE && endsAtEpochMs > nowEpochMs

    companion object {
        const val STATE_ACTIVE = "active"
        const val STATE_EXPIRED = "expired"
        const val STATE_EMERGENCY_RELEASED = "emergency_released"
    }
}

object FocusProtectionDecision {
    fun reconcileActivation(
        currentLease: LocalFocusLease?,
        suppressedSessionId: String?,
        candidate: LocalFocusLease,
        nowEpochMs: Long,
    ): LocalFocusLease? {
        if (candidate.endsAtEpochMs <= nowEpochMs) {
            return currentLease?.takeIf { it.isActive(nowEpochMs) }
        }
        if (currentLease?.isActive(nowEpochMs) == true) {
            if (currentLease.sessionId == candidate.sessionId) {
                return currentLease
            }
            if (currentLease.startedAtEpochMs >= candidate.startedAtEpochMs) {
                return currentLease
            }
        }
        if (suppressedSessionId == candidate.sessionId) {
            return candidate.copy(state = LocalFocusLease.STATE_EMERGENCY_RELEASED)
        }
        return candidate
    }

    fun shouldRequestZen(
        protectionEnabled: Boolean,
        silenceNotifications: Boolean,
        lease: LocalFocusLease?,
        nowEpochMs: Long,
    ): Boolean = protectionEnabled &&
        silenceNotifications &&
        lease?.isActive(nowEpochMs) == true

    fun shouldBlockPackage(
        protectionEnabled: Boolean,
        blockingEnabled: Boolean,
        accessibilityEnabled: Boolean,
        selectedPackages: Set<String>,
        essentialPackages: Set<String>,
        foregroundPackage: String?,
        lease: LocalFocusLease?,
        nowEpochMs: Long,
    ): Boolean {
        val packageName = foregroundPackage?.trim().orEmpty()
        return protectionEnabled &&
            blockingEnabled &&
            accessibilityEnabled &&
            packageName.isNotEmpty() &&
            lease?.isActive(nowEpochMs) == true &&
            packageName in selectedPackages &&
            packageName !in essentialPackages
    }

    fun selectablePackages(
        launchablePackages: Set<String>,
        essentialPackages: Set<String>,
    ): Set<String> = launchablePackages - essentialPackages
}

object FocusZenRuleDecision {
    fun canPublish(
        ruleExists: Boolean,
        ruleEnabled: Boolean,
        exactDefinition: Boolean,
    ): Boolean = ruleExists && ruleEnabled && exactDefinition
}

class EmergencyReleaseGate(
    private val holdDurationMs: Long,
) {
    private var startedAtElapsedMs: Long? = null
    var isArmed: Boolean = false
        private set

    fun start(nowElapsedMs: Long): Boolean {
        if (startedAtElapsedMs != null || isArmed) return false
        startedAtElapsedMs = nowElapsedMs
        return true
    }

    fun cancel() {
        if (!isArmed) startedAtElapsedMs = null
    }

    fun tryArm(nowElapsedMs: Long): Boolean {
        val startedAt = startedAtElapsedMs ?: return false
        if (nowElapsedMs - startedAt < holdDurationMs) return false
        isArmed = true
        return true
    }

    fun confirm(): Boolean {
        if (!isArmed) return false
        isArmed = false
        startedAtElapsedMs = null
        return true
    }
}

data class FocusZenPolicySpec(
    val allowAlarms: Boolean = true,
    val allowFavoriteCalls: Boolean = true,
    val allowRepeatCallers: Boolean = true,
    val allowMedia: Boolean = true,
    val allowMessages: Boolean = false,
    val allowConversations: Boolean = false,
    val allowEvents: Boolean = false,
    val allowReminders: Boolean = false,
    val showPeeking: Boolean = false,
    val showBadges: Boolean = false,
    val showStatusBarIcons: Boolean = false,
    val showLockscreen: Boolean = false,
    val showAmbientDisplay: Boolean = false,
    val showNotificationList: Boolean = false,
)
