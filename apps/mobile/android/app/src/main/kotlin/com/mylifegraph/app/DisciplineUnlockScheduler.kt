package com.mylifegraph.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock

/** Reconciles only a deliberate, same-boot request; never starts one or waives conditions. */
internal object DisciplineUnlockScheduler {
    private var scheduledAt = 0L
    fun reconcile(context: Context) {
        val plans = BlockingPlans(context)
        plans.finishBackgroundUnlock()
        val pending = plans.backgroundUnlockPending()
        val alarm = context.getSystemService(AlarmManager::class.java)
        val intent = PendingIntent.getBroadcast(context, 9106,
            Intent(context, DisciplineUnlockReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        if (!pending) {
            alarm.cancel(intent)
            scheduledAt = 0L
            return
        }
        val status = plans.status()
        val now = SystemClock.elapsedRealtime()
        val remaining = status["remainingMs"] as Long
        if (remaining == 0L && scheduledAt > now) return
        // Native service ticks normally finish at zero. The inexact alarm is a fallback
        // when Android suspends/kills that service; Doze/OEM policy can delay delivery.
        val next = now + if (remaining > 0) remaining else 60000L
        if (scheduledAt > now && kotlin.math.abs(scheduledAt - next) < 1000L) return
        alarm.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, next, intent)
        scheduledAt = next
    }
    fun delivered(context: Context) { scheduledAt = 0L; reconcile(context) }
}

class DisciplineUnlockReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        runCatching { DisciplineUnlockScheduler.delivered(context) }
    }
}
