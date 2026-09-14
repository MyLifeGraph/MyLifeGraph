package com.mylifegraph.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class PushMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
      synchronized(PushBridge::class.java) {
        val data = message.data
        val prefs = PushBridge.preferences(this)
        if (!PushReceipt.accepts(data, prefs.getBoolean("active", false),
            prefs.getString("owner", null), prefs.getString("session", null),
            prefs.getString("registration", null), System.currentTimeMillis() / 1000)) return
        val destination = data["destination"]
        val copy = when (data["kind"]) {
            "deadlines" -> "Check today's deadlines" to "Open Planner to review what is still due today."
            "sleep" -> "Time to wind down?" to "Your observed sleep window is coming up. Review it in Insights."
            "pattern" -> "A useful pattern is ready" to "Review a consistent study-time observation in Insights."
            else -> return
        }
        val id = try { java.util.UUID.fromString(data["attempt_id"]).toString() } catch (_: Exception) { return }
        // Durable bounded receipt set protects against duplicate FCM delivery.
        synchronized(PushMessagingService::class.java) {
            val seen = prefs.getStringSet("seen", emptySet())!!.toMutableSet()
            if (id in seen) return
            if (seen.size >= 64) seen.clear()
            seen.add(id)
            prefs.edit().putStringSet("seen", seen).commit()
        }
        val manager = getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return
        val channel = "mylifegraph-important-v1"
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel(channel, "Important reminders", NotificationManager.IMPORTANCE_DEFAULT))
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra("mylifegraph_push_route", destination)
        val pending = PendingIntent.getActivity(this, id.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channel) else Notification.Builder(this)
        try {
            manager.notify("mylifegraph-push", id.hashCode(), builder
                .setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle(copy.first).setContentText(copy.second)
                .setStyle(Notification.BigTextStyle().bigText(copy.second)).setContentIntent(pending)
                .setAutoCancel(true).setVisibility(Notification.VISIBILITY_PRIVATE).build())
        } catch (_: SecurityException) { /* Permission revoked between checks. */ }
      }
    }
}
