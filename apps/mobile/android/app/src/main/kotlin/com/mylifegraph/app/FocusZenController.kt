package com.mylifegraph.app

import android.annotation.TargetApi
import android.app.AutomaticZenRule
import android.app.NotificationManager
import android.app.NotificationManager.INTERRUPTION_FILTER_PRIORITY
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.service.notification.Condition
import android.service.notification.ZenPolicy

class FocusZenController(
    private val context: Context,
    private val store: FocusProtectionStore,
) {
    private val notificationManager =
        context.getSystemService(NotificationManager::class.java)
    private val conditionId = FocusZenConditionProviderService.conditionId(context)
    private val owner = ComponentName(context, FocusZenConditionProviderService::class.java)

    fun isPolicyAccessGranted(): Boolean =
        notificationManager.isNotificationPolicyAccessGranted

    /**
     * Reconciles either a fresh lease trigger or a persisted, not-yet-published
     * activation. An ordinary replay with an already published condition never
     * sends TRUE again, so it cannot undo a user's per-session Zen override.
     */
    fun activate(
        allowRuleCreation: Boolean,
        freshTrigger: Boolean,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !isPolicyAccessGranted()) {
            return false
        }
        return try {
            if (store.isZenCleanupPending()) {
                deactivate()
                if (store.isZenCleanupPending()) return false
            }
            if (!freshTrigger && !store.isZenActivationPending()) {
                return isRuleEffectivelyActive()
            }
            val ruleId = usableRuleId(allowRuleCreation) ?: run {
                deactivate()
                return false
            }
            if (!store.isZenActivationPending() && !store.beginZenActivation()) {
                store.setNativeFailure(true)
                return false
            }
            if (Build.VERSION.SDK_INT >= 35 && !store.completeZenActivation()) {
                store.setNativeFailure(true)
                return false
            }
            val published = publishCondition(ruleId, active = true)
            if (published) store.setNativeFailure(false)
            published
        } catch (_: Throwable) {
            store.beginZenCleanup()
            store.setNativeFailure(true)
            false
        }
    }

    /**
     * Persists a FALSE transition before attempting the Android call. A killed
     * process therefore leaves a retry marker instead of an unowned active rule.
     */
    fun deactivate(): Boolean {
        if (!store.beginZenCleanup()) {
            store.setNativeFailure(true)
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            store.completeZenCleanup()
            return true
        }
        if (!isPolicyAccessGranted()) {
            store.setNativeFailure(true)
            return false
        }
        val ruleId = store.zenRuleId()
        if (ruleId == null || readRule(ruleId) == null) {
            store.completeZenCleanup()
            return true
        }
        return try {
            val published = publishCondition(ruleId, active = false)
            val completed = published &&
                (Build.VERSION.SDK_INT < 35 || store.completeZenCleanup())
            store.setNativeFailure(!completed)
            completed
        } catch (_: Throwable) {
            store.setNativeFailure(true)
            false
        }
    }

    fun needsCleanup(): Boolean {
        if (store.isZenConditionActive() ||
            store.isZenActivationPending() ||
            store.isZenCleanupPending()
        ) {
            return true
        }
        if (Build.VERSION.SDK_INT < 35 || !isPolicyAccessGranted()) return false
        val ruleId = store.zenRuleId() ?: return false
        return runCatching {
            FocusZenApi35.getRuleState(notificationManager, ruleId) == Condition.STATE_TRUE
        }.getOrDefault(false)
    }

    fun isRuleConfiguredAndUsable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !isPolicyAccessGranted()) {
            return false
        }
        val ruleId = store.zenRuleId() ?: return false
        return isRuleUsable(readRule(ruleId))
    }

    fun isRuleEffectivelyActive(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !isPolicyAccessGranted()) {
            return false
        }
        if (!store.isZenConditionActive() ||
            store.isZenActivationPending() ||
            store.isZenCleanupPending()
        ) {
            return false
        }
        val ruleId = store.zenRuleId() ?: return false
        if (!isRuleUsable(readRule(ruleId))) return false
        // Android exposes an authoritative per-rule state only from API 35.
        // The global interruption filter could belong to another app's rule.
        if (Build.VERSION.SDK_INT < 35) return false
        return runCatching {
            FocusZenApi35.getRuleState(notificationManager, ruleId) == Condition.STATE_TRUE
        }.getOrDefault(false)
    }

    /**
     * A deliberate off -> on configuration change may recover from a deleted
     * rule on the next fresh session. Disabled or edited rules remain owned by
     * system settings and are never silently replaced.
     */
    fun prepareForExplicitRuleEnable() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !isPolicyAccessGranted()) return
        val ruleId = store.zenRuleId() ?: return
        if (readRule(ruleId) == null) store.clearZenRuleId()
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun publishCondition(ruleId: String, active: Boolean): Boolean {
        return if (Build.VERSION.SDK_INT >= 35) {
            FocusZenApi35.setRuleState(
                notificationManager,
                ruleId,
                Condition(
                    conditionId,
                    if (active) "Focus session active" else "Focus session inactive",
                    if (active) Condition.STATE_TRUE else Condition.STATE_FALSE,
                ),
            )
            true
        } else {
            FocusZenConditionProviderService.publishDesiredState(context)
        }
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun usableRuleId(allowRuleCreation: Boolean): String? {
        val existingId = store.zenRuleId()
        if (existingId != null) {
            return existingId.takeIf { isRuleUsable(readRule(it)) }
        }
        if (!allowRuleCreation) return null
        val created = notificationManager.addAutomaticZenRule(buildRule()) ?: return null
        if (!store.saveZenRuleId(created)) {
            runCatching { notificationManager.removeAutomaticZenRule(created) }
            store.setNativeFailure(true)
            return null
        }
        return created.takeIf { isRuleUsable(readRule(it)) }
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun readRule(ruleId: String): AutomaticZenRule? = runCatching {
        notificationManager.getAutomaticZenRule(ruleId)
    }.getOrNull()

    @TargetApi(Build.VERSION_CODES.Q)
    private fun isRuleUsable(rule: AutomaticZenRule?): Boolean {
        val exactDefinition = rule?.name == RULE_NAME &&
            rule.owner == owner &&
            rule.conditionId == conditionId &&
            rule.interruptionFilter == INTERRUPTION_FILTER_PRIORITY &&
            rule.zenPolicy == buildZenPolicy()
        return FocusZenRuleDecision.canPublish(
            ruleExists = rule != null,
            ruleEnabled = rule?.isEnabled == true,
            exactDefinition = exactDefinition,
        )
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun buildRule(): AutomaticZenRule = AutomaticZenRule(
        RULE_NAME,
        owner,
        null,
        conditionId,
        buildZenPolicy(),
        INTERRUPTION_FILTER_PRIORITY,
        true,
    )

    @TargetApi(Build.VERSION_CODES.Q)
    private fun buildZenPolicy(): ZenPolicy {
        val spec = FocusZenPolicySpec()
        val builder = ZenPolicy.Builder()
            .allowAlarms(spec.allowAlarms)
            .allowCalls(
                if (spec.allowFavoriteCalls) {
                    ZenPolicy.PEOPLE_TYPE_STARRED
                } else {
                    ZenPolicy.PEOPLE_TYPE_NONE
                },
            )
            .allowRepeatCallers(spec.allowRepeatCallers)
            .allowMedia(spec.allowMedia)
            .allowSystem(false)
            .allowMessages(ZenPolicy.PEOPLE_TYPE_NONE)
            .allowEvents(spec.allowEvents)
            .allowReminders(spec.allowReminders)
            .showPeeking(spec.showPeeking)
            .showBadges(spec.showBadges)
            .showStatusBarIcons(spec.showStatusBarIcons)
            .showInAmbientDisplay(spec.showAmbientDisplay)
            .showInNotificationList(spec.showNotificationList)
            .showFullScreenIntent(false)
            .showLights(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.allowConversations(ZenPolicy.CONVERSATION_SENDERS_NONE)
        }
        if (Build.VERSION.SDK_INT >= 35) {
            FocusZenApi35.disallowPriorityChannels(builder)
        }
        return builder.build()
    }

    companion object {
        private const val RULE_NAME = "MyLifeGraph Focus"
    }
}
