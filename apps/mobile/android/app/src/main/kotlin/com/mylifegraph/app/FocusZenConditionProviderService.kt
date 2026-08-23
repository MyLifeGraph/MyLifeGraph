package com.mylifegraph.app

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Build
import android.service.notification.Condition
import android.service.notification.ConditionProviderService
import java.lang.ref.WeakReference

class FocusZenConditionProviderService : ConditionProviderService() {
    private lateinit var store: FocusProtectionStore
    private lateinit var expectedConditionId: Uri

    override fun onCreate() {
        super.onCreate()
        store = FocusProtectionStore(applicationContext)
        expectedConditionId = conditionId(applicationContext)
        runningService = WeakReference(this)
    }

    override fun onConnected() {
        publishPendingTransition()
    }

    override fun onSubscribe(conditionId: Uri?) {
        if (conditionId == expectedConditionId) publishPendingTransition()
    }

    override fun onUnsubscribe(conditionId: Uri?) = Unit

    override fun onDestroy() {
        if (runningService?.get() === this) runningService = null
        super.onDestroy()
    }

    private fun publishPendingTransition(): Boolean {
        val now = System.currentTimeMillis()
        val configuration = store.readConfiguration()
        val lease = store.readLease()
        val shouldRequestZen = FocusProtectionDecision.shouldRequestZen(
            protectionEnabled = configuration.enabled,
            silenceNotifications = configuration.silenceNotifications,
            lease = lease,
            nowEpochMs = now,
        )
        val cleanupRequired = store.isZenCleanupPending() ||
            !shouldRequestZen &&
            (store.isZenConditionActive() || store.isZenActivationPending())
        if (cleanupRequired) {
            if (!store.isZenCleanupPending() && !store.beginZenCleanup()) return false
            notifyCondition(condition(active = false))
            val completed = store.completeZenCleanup()
            store.setNativeFailure(!completed)
            return completed
        }
        if (!shouldRequestZen ||
            !store.isZenConditionActive() ||
            !store.isZenActivationPending()
        ) {
            return false
        }
        val controller = FocusZenController(applicationContext, store)
        if (!controller.isRuleConfiguredAndUsable()) {
            controller.deactivate()
            return false
        }
        // Clear the one-shot marker before publishing TRUE. A process restart
        // can then never replay TRUE over a later user snooze.
        if (!store.completeZenActivation()) return false
        notifyCondition(condition(active = true))
        store.setNativeFailure(false)
        return true
    }

    private fun condition(active: Boolean): Condition = Condition(
        expectedConditionId,
        if (active) "Focus session active" else "Focus session inactive",
        if (active) Condition.STATE_TRUE else Condition.STATE_FALSE,
    )

    companion object {
        private var runningService: WeakReference<FocusZenConditionProviderService>? = null

        fun conditionId(context: Context): Uri =
            Uri.parse("condition://${context.packageName}/focus-protection-v1")

        fun publishDesiredState(context: Context): Boolean {
            runningService?.get()?.let { return it.publishPendingTransition() }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                @Suppress("DEPRECATION")
                requestRebind(
                    ComponentName(context, FocusZenConditionProviderService::class.java),
                )
            }
            return false
        }
    }
}
