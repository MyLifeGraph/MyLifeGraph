package com.mylifegraph.app

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Build
import android.os.SystemClock
import android.provider.Settings

/** Device-local display of a canonical Focus timer. Never completes a Focus session. */
object FocusTimerNotifications {
    private const val PREFS="mylifegraph_focus_timer_v1"
    private const val RUNNING="mylifegraph-focus-countdown-v1"
    private const val ENDED="mylifegraph-focus-ended-v1"
    private const val TAG="mylifegraph-focus-session-timer"
    private const val ID=4111
    private const val OPEN="mylifegraph_focus_timer_open"
    const val PERMISSION_REQUEST=9110
    private var published=""
    private fun prefs(c:Context)=c.getSharedPreferences(PREFS,Context.MODE_PRIVATE)
    private fun boot(c:Context)=Settings.Global.getInt(c.contentResolver,Settings.Global.BOOT_COUNT,-1)
    @Synchronized fun setSession(c:Context,args:Map<*,*>) {
        val id=args["sessionId"] as? String
        if(id==null) { clear(c,null); return }
        require(id.matches(Regex("[A-Za-z0-9_-]{1,128}"))) { "Invalid Focus timer identity." }
        val start=(args["startedAtEpochMs"] as? Number)?.toLong() ?: error("Missing Focus start.")
        val end=(args["endsAtEpochMs"] as? Number)?.toLong() ?: error("Missing Focus end.")
        require(start>0 && end-start in 300_000..PhoneLockPolicy.MAX_TIMER_MS) { "Invalid Focus duration." }
        val p=prefs(c)
        if(p.getString("id",null)!=id) {
            val remaining=(end-System.currentTimeMillis()).coerceIn(0,end-start)
            check(p.edit().putString("id",id).putLong("end",end).putLong("start",start)
                .putLong("elapsedEnd",SystemClock.elapsedRealtime()+remaining).putInt("boot",boot(c))
                .putBoolean("notified",false).remove("open").commit()) { "Could not save Focus timer." }
            published=""
        } else require(p.getLong("end",0)==end && p.getLong("start",0)==start) { "Focus timer changed." }
        sync(c)
    }
    @Synchronized fun clear(c:Context,expected:String?) {
        val p=prefs(c)
        if(expected!=null && p.getString("id",null)!=expected) return
        check(p.edit().remove("id").remove("open").remove("end").remove("start").remove("elapsedEnd").remove("notified").commit())
        c.getSystemService(NotificationManager::class.java).cancel(TAG,ID)
        c.getSystemService(AlarmManager::class.java).cancel(alarm(c))
        published=""
    }
    fun permissionAllowed(c:Context):Boolean = (Build.VERSION.SDK_INT<33 ||
        c.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED) &&
        c.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
    fun requestPermission(activity:Activity) {
        val p=prefs(activity)
        if(Build.VERSION.SDK_INT<33 || permissionAllowed(activity) || p.getBoolean("asked",false)) return
        p.edit().putBoolean("pendingPermission",true).apply()
        askPending(activity)
    }
    fun askPending(activity:Activity) {
        val p=prefs(activity)
        if(Build.VERSION.SDK_INT<33 || !p.getBoolean("pendingPermission",false) ||
            activity.isFinishing || activity.isDestroyed || !activity.hasWindowFocus()) return
        if(activity is MainActivity && PhoneLockStore(activity).active()) {
            PhoneLockActivity.askPendingTimerPermission(); return
        }
        p.edit().putBoolean("pendingPermission",false).putBoolean("asked",true).apply()
        if(!permissionAllowed(activity)) activity.requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),PERMISSION_REQUEST)
    }
    @Synchronized fun sync(c:Context) {
        val p=prefs(c); val id=p.getString("id",null) ?: return
        val end=p.getLong("end",0); val duration=end-p.getLong("start",0)
        val remaining=PhoneLockPolicy.remaining(end,p.getLong("elapsedEnd",0),duration,p.getInt("boot",-2),boot(c),System.currentTimeMillis(),SystemClock.elapsedRealtime())
        if(remaining>0 && p.getInt("boot",-2)!=boot(c)) {
            check(p.edit().putInt("boot",boot(c)).putLong("elapsedEnd",SystemClock.elapsedRealtime()+remaining).commit())
        }
        val alarmManager=c.getSystemService(AlarmManager::class.java)
        if(remaining>0) alarmManager.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP,SystemClock.elapsedRealtime()+remaining,alarm(c))
        else alarmManager.cancel(alarm(c))
        val notifications=c.getSystemService(NotificationManager::class.java)
        if(!permissionAllowed(c)) { notifications.cancel(TAG,ID); published=""; return }
        if(Build.VERSION.SDK_INT>=26) {
            notifications.createNotificationChannel(NotificationChannel(RUNNING,"Focus countdown",NotificationManager.IMPORTANCE_LOW))
            notifications.createNotificationChannel(NotificationChannel(ENDED,"Focus timer finished",NotificationManager.IMPORTANCE_DEFAULT))
        }
        val done=remaining==0L
        val key="$id:$done"
        if(published==key && notifications.activeNotifications.any { it.tag==TAG && it.id==ID }) return
        if(done && p.getBoolean("notified",false)) return
        val intent=Intent(c,MainActivity::class.java).putExtra(OPEN,id)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending=PendingIntent.getActivity(c,ID,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val channel=if(done) ENDED else RUNNING
        val builder=if(Build.VERSION.SDK_INT>=26) Notification.Builder(c,channel) else Notification.Builder(c)
        builder.setSmallIcon(R.drawable.app_notification_mark)
            .setLargeIcon(BitmapFactory.decodeResource(c.resources,R.drawable.app_launcher_art))
            .setContentTitle(if(done) "Focus timer finished" else "Focus session")
            .setContentText(if(done) "Open your session to finish or reflect." else "Remaining · Tap to open your session")
            .setContentIntent(pending).setOngoing(!done).setAutoCancel(done).setOnlyAlertOnce(true)
            .setCategory(if(done) Notification.CATEGORY_REMINDER else Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
        if(!done) {
            builder.setWhen(System.currentTimeMillis()+remaining).setUsesChronometer(true).setChronometerCountDown(true)
                .setSound(null).setVibrate(longArrayOf(0)).setPriority(Notification.PRIORITY_LOW)
            if(Build.VERSION.SDK_INT>=26) builder.setTimeoutAfter(remaining)
        }
        val publicBuilder=if(Build.VERSION.SDK_INT>=26) Notification.Builder(c,channel) else Notification.Builder(c)
        builder.setPublicVersion(publicBuilder.setSmallIcon(R.drawable.app_notification_mark).setContentTitle("MyLifeGraph")
            .setContentText(if(done) "Focus timer finished" else "Focus timer active").build())
        runCatching { notifications.notify(TAG,ID,builder.build()) }.onSuccess {
            published=key
            if(done) p.edit().putBoolean("notified",true).apply()
        }
    }
    fun captureIntent(c:Context,intent:Intent?) {
        val id=intent?.getStringExtra(OPEN) ?: return
        if(id==prefs(c).getString("id",null)) prefs(c).edit().putString("open",id).apply()
        intent.removeExtra(OPEN)
    }
    fun takeOpen(c:Context):String? {
        val p=prefs(c); val id=p.getString("open",null); p.edit().remove("open").apply()
        return id?.takeIf { it==p.getString("id",null) && it.matches(Regex("[A-Za-z0-9_-]{1,128}")) }
    }
    private fun alarm(c:Context)=PendingIntent.getBroadcast(c,ID,Intent(c,FocusTimerReceiver::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
}
class FocusTimerReceiver:BroadcastReceiver() {
    override fun onReceive(context:Context,intent:Intent?) { runCatching { FocusTimerNotifications.sync(context) } }
}
