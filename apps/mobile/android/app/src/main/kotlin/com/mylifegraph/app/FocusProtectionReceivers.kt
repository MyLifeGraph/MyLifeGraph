package com.mylifegraph.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class FocusLeaseExpiryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        FocusProtectionManager(context.applicationContext).expireIfNeeded()
    }
}

class FocusProtectionBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            runCatching { PhoneLockExpiryReceiver.reconcile(context) }
            runCatching { FocusTimerNotifications.sync(context) }
            FocusProtectionManager(context.applicationContext).rescheduleAfterBoot()
            BlockingTimerNotifications.sync(context)
        }
    }
}
