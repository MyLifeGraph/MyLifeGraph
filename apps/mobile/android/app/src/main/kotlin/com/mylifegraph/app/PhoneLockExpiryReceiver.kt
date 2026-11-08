package com.mylifegraph.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock

class PhoneLockExpiryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        reconcile(context)
        FocusBlockAccessibilityService.refreshOverlayIfRunning(context)
    }
    companion object {
        fun reconcile(context: Context) {
            val state=PhoneLockStore(context).status()
            val alarm=context.getSystemService(AlarmManager::class.java)
            val pending=PendingIntent.getBroadcast(context,4110,
                Intent(context,PhoneLockExpiryReceiver::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val remaining=if(state["recoveryStarted"]==true) state["recoveryRemainingMs"] else state["remainingMs"]
            val delay=(remaining as? Number)?.toLong() ?: 0L
            if(state["active"]==true && delay>0) alarm.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP,SystemClock.elapsedRealtime()+delay,pending)
            else alarm.cancel(pending)
        }
    }
}
