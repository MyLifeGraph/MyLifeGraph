package com.mylifegraph.app

import android.annotation.TargetApi
import android.app.NotificationManager
import android.service.notification.Condition
import android.service.notification.ZenPolicy

@TargetApi(35)
internal object FocusZenApi35 {
    fun getRuleState(
        notificationManager: NotificationManager,
        ruleId: String,
    ): Int = notificationManager.getAutomaticZenRuleState(ruleId)

    fun setRuleState(
        notificationManager: NotificationManager,
        ruleId: String,
        condition: Condition,
    ) {
        notificationManager.setAutomaticZenRuleState(ruleId, condition)
    }

    fun disallowPriorityChannels(builder: ZenPolicy.Builder) {
        builder.allowPriorityChannels(false)
    }
}
