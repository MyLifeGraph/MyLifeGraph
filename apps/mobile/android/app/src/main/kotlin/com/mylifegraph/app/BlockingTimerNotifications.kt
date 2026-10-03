package com.mylifegraph.app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.os.SystemClock
import android.view.accessibility.AccessibilityManager
import android.accessibilityservice.AccessibilityServiceInfo

/** Display-only rule: never starts, finishes or weakens a blocking plan. */
object BlockingTimerPolicy {
    fun visible(enabled: Boolean, pausedUntil: Long, end: Long, now: Long,
                master: Boolean, accessibility: Boolean, targets: Boolean): Boolean =
        master && accessibility && targets && enabled && pausedUntil <= now && end > now
}

/** Android renders the ticking clock; only lifecycle changes issue a notification. */
object BlockingTimerNotifications {
    private const val CHANNEL = "mylifegraph-blocking-timers-v1"
    private const val PREFIX = "mylifegraph-blocking-timer:"
    private data class Timer(val id: String, val name: String, val end: Long)
    private var published = emptyList<Timer>()
    private var alarmAt = 0L
    private var lastWall = 0L
    private var lastElapsed = 0L
    private var lastInputs = ""
    private var nextDecisionAt = 0L
    private var channelCreated = false

    // This optional UI must never turn a durable plan save into a failed save.
    fun sync(context: Context) { runCatching { reconcile(context.applicationContext) } }

    @Synchronized private fun reconcile(context: Context) {
        val now = System.currentTimeMillis()
        val elapsed = SystemClock.elapsedRealtime()
        val clockChanged = lastWall != 0L && kotlin.math.abs((now - lastWall) - (elapsed - lastElapsed)) > 2000
        lastWall = now; lastElapsed = elapsed
        val manager = context.getSystemService(NotificationManager::class.java)
        val plans = BlockingPlans(context)
        val config = FocusProtectionStore(context).readConfiguration()
        if (Build.VERSION.SDK_INT >= 26 && !channelCreated) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Blocking timers", NotificationManager.IMPORTANCE_LOW).apply {
                    setSound(null, null); enableVibration(false); setShowBadge(false)
                })
            channelCreated = true
        }
        val allowed = manager.areNotificationsEnabled() && (Build.VERSION.SDK_INT < 33 ||
            context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED) &&
            (Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
        val accessibility = context.getSystemService(AccessibilityManager::class.java)
            .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { it.resolveInfo.serviceInfo.packageName == context.packageName &&
                it.resolveInfo.serviceInfo.name == FocusBlockAccessibilityService::class.java.name }
        val values = plans.plans()
        val inputs = "${config.enabled}|${config.blockSelectedApps}|$accessibility|$allowed|${plans.websiteConsent()}|$values"
        if (!clockChanged && inputs == lastInputs && (nextDecisionAt == 0L || now < nextDecisionAt)) return
        val essential = FocusProtectionManager(context).essentialPackages()
        val timers = mutableListOf<Timer>()
        var nextBoundary = Long.MAX_VALUE
        for (i in 0 until values.length()) {
            val p = values.getJSONObject(i)
            val end = p.optLong("untilEpochMs")
            val pause = p.optLong("pausedUntil")
            val targets = BlockingRulePolicy.hasEffectiveTargets(
                BlockingPlans.strings(p.getJSONArray("apps")).count { it !in essential },
                p.getJSONArray("sites").length(), plans.websiteConsent())
            if (BlockingTimerPolicy.visible(p.optBoolean("enabled", true), pause, end, now,
                    config.enabled && config.blockSelectedApps, accessibility, targets)) {
                timers += Timer(p.getString("id"), p.getString("name"), end)
            }
            if (end > now && p.optBoolean("enabled", true) && config.enabled && config.blockSelectedApps && accessibility && targets) {
                nextBoundary = minOf(nextBoundary, end)
                if (pause in (now + 1) until end) nextBoundary = minOf(nextBoundary, pause)
            }
        }
        nextDecisionAt = if (nextBoundary == Long.MAX_VALUE) 0 else nextBoundary
        schedule(context, if (allowed) nextDecisionAt else 0, clockChanged)
        val wanted = if (allowed) timers else emptyList()
        val active = manager.activeNotifications.filter { it.tag?.startsWith(PREFIX) == true }
        val wantedTags = wanted.map { PREFIX + it.id }.toSet()
        active.filter { it.tag !in wantedTags }.forEach { manager.cancel(it.tag, it.id) }
        for (timer in wanted) {
            if (!clockChanged && timer in published && active.any { it.tag == PREFIX + timer.id }) continue
            val intent = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val pending = PendingIntent.getActivity(context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context)
            builder.setSmallIcon(R.drawable.app_notification_mark)
                .setLargeIcon(BitmapFactory.decodeResource(context.resources, R.drawable.app_launcher_art))
                .setContentTitle(timer.name).setContentText("App blocking · remaining")
                .setWhen(timer.end).setUsesChronometer(true).setChronometerCountDown(true)
                .setContentIntent(pending).setOngoing(true).setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_PROGRESS).setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPriority(Notification.PRIORITY_LOW).setSound(null).setVibrate(longArrayOf(0))
                .setPublicVersion((if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context))
                    .setSmallIcon(R.drawable.app_notification_mark).setContentTitle("MyLifeGraph")
                    .setContentText("Blocking timer active").build())
            if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter((timer.end - now).coerceAtLeast(1))
            manager.notify(PREFIX + timer.id, 1, builder.build())
        }
        published = wanted.toList()
        lastInputs = inputs
    }

    private fun schedule(context: Context, at: Long, force: Boolean) {
        if (at == alarmAt && !force) return
        val alarm = context.getSystemService(AlarmManager::class.java)
        val pending = PendingIntent.getBroadcast(context, 9105,
            Intent(context, BlockingTimerReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        alarm.cancel(pending)
        if (at > 0) alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        alarmAt = at
    }

    @Synchronized fun disconnected(context: Context) {
        runCatching {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.activeNotifications.filter { it.tag?.startsWith(PREFIX) == true }
                .forEach { manager.cancel(it.tag, it.id) }
        }
        published = emptyList()
        lastInputs = ""
    }
}

class BlockingTimerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) { BlockingTimerNotifications.sync(context) }
}
