package com.mylifegraph.app

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class PushBridge(private val activity: Activity) {
    private var permissionResult: MethodChannel.Result? = null
    private val prefs get() = preferences(activity)
    fun handle(call: MethodCall, result: MethodChannel.Result) {
      synchronized(PushBridge::class.java) {
        try {
            when (call.method) {
                "status" -> result.success(status())
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 && !permitted()) {
                        if (permissionResult != null) throw IllegalStateException("Permission request already active")
                        permissionResult = result
                        activity.requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), PERMISSION_REQUEST)
                    } else result.success(permitted())
                }
                "bind" -> {
                    val args = call.arguments as Map<*, *>
                    val owner = UUID.fromString(args["owner"] as String).toString()
                    val session = UUID.fromString(args["session_id"] as String).toString()
                    if (prefs.getString("owner", null) != owner || prefs.getString("session", null) != session) {
                        prefs.edit().putBoolean("active", false).putString("owner", owner)
                            .putString("session", session).putString("registration", UUID.randomUUID().toString())
                            .putBoolean("reset_token", true).remove("route").commit()
                        cancelNotifications(activity)
                    }
                    result.success(status())
                }
                "token" -> {
                    if (!permitted() || prefs.getString("owner", null) == null) throw IllegalStateException("Permission and account required")
                    if (FirebaseApp.initializeApp(activity) == null && FirebaseApp.getApps(activity).isEmpty()) {
                        throw IllegalStateException("Firebase client configuration missing")
                    }
                    getToken(result)
                }
                "activate" -> {
                    val args = call.arguments as Map<*, *>
                    if (args["registration_id"] != prefs.getString("registration", null) || !permitted()) {
                        throw IllegalStateException("Account or permission changed")
                    }
                    prefs.edit().putBoolean("active", true).commit()
                    result.success(null)
                }
                "pause" -> {
                    prefs.edit().putBoolean("active", false).commit()
                    cancelNotifications(activity)
                    result.success(null)
                }
                "clear" -> {
                    prefs.edit().putBoolean("active", false).remove("owner").remove("session")
                        .remove("registration").remove("route").commit()
                    cancelNotifications(activity)
                    if (FirebaseApp.getApps(activity).isNotEmpty()) {
                        FirebaseMessaging.getInstance().isAutoInitEnabled = false
                        FirebaseMessaging.getInstance().deleteToken().addOnCompleteListener { result.success(null) }
                    } else result.success(null)
                }
                "takeRoute" -> {
                    val route = prefs.getString("route", null)
                    prefs.edit().remove("route").apply()
                    result.success(if (route in setOf("/planner", "/insights")) route else null)
                }
                "openSettings" -> {
                    val intent = if (Build.VERSION.SDK_INT >= 26) {
                        Intent("android.settings.APP_NOTIFICATION_SETTINGS")
                            .putExtra("android.provider.extra.APP_PACKAGE", activity.packageName)
                    } else {
                        Intent("android.settings.APPLICATION_DETAILS_SETTINGS",
                            android.net.Uri.parse("package:${activity.packageName}"))
                    }
                    activity.startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("push_unavailable", "Android push is unavailable. Retry from Settings.", null)
        }
      }
    }
    private fun getToken(result: MethodChannel.Result) {
        val registration = prefs.getString("registration", null)
        fun fetch() {
            if (registration != prefs.getString("registration", null)) {
                result.error("push_session", "Account changed.", null)
                return
            }
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (task.isSuccessful && registration == prefs.getString("registration", null)) result.success(task.result)
                else result.error("push_token", "Push registration unavailable.", null)
            }
        }
        if (prefs.getBoolean("reset_token", false)) {
            FirebaseMessaging.getInstance().deleteToken().addOnCompleteListener { task ->
                if (task.isSuccessful && registration == prefs.getString("registration", null)) {
                    prefs.edit().putBoolean("reset_token", false).commit()
                    fetch()
                } else result.error("push_token", "Push registration unavailable.", null)
            }
        } else fetch()
    }
    fun onPermissionResult(code: Int) {
        if (code != PERMISSION_REQUEST) return
        permissionResult?.success(permitted())
        permissionResult = null
    }
    fun dispose() {
        permissionResult?.error("push_cancelled", "Permission request cancelled.", null)
        permissionResult = null
    }
    private fun permitted(): Boolean =
        (Build.VERSION.SDK_INT < 33 || activity.checkSelfPermission("android.permission.POST_NOTIFICATIONS") == PackageManager.PERMISSION_GRANTED) &&
            activity.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
    private fun status(): Map<String, Any?> {
        if (!prefs.contains("device")) prefs.edit().putString("device", UUID.randomUUID().toString()).commit()
        return mapOf("device_id" to prefs.getString("device", null),
            "registration_id" to prefs.getString("registration", null), "granted" to permitted(),
            "active" to prefs.getBoolean("active", false),
            "configured" to (activity.resources.getIdentifier("google_app_id", "string", activity.packageName) != 0))
    }
    companion object {
        const val CHANNEL = "com.mylifegraph.app/push"
        const val PERMISSION_REQUEST = 9302
        fun preferences(context: Context) = context.getSharedPreferences("mylifegraph_push_v1", Context.MODE_PRIVATE)
        fun cancelNotifications(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.activeNotifications.filter { it.tag == "mylifegraph-push" }.forEach { manager.cancel(it.tag, it.id) }
        }
        fun captureIntent(context: Context, intent: Intent?) {
            val route = intent?.getStringExtra("mylifegraph_push_route") ?: return
            if (route in setOf("/planner", "/insights")) preferences(context).edit().putString("route", route).apply()
            intent.removeExtra("mylifegraph_push_route")
        }
    }
}
