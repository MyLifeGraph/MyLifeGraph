package com.mylifegraph.app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.telecom.TelecomManager

object PhoneLockSafety {
    fun phoneAvailable(context: Context): Boolean = context.packageManager.resolveActivity(
        Intent(Intent.ACTION_DIAL, Uri.parse("tel:")), PackageManager.MATCH_DEFAULT_ONLY) != null
    fun essential(context: Context): Set<String> {
        val pm = context.packageManager
        val homes = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), PackageManager.MATCH_ALL)
            .map { it.activityInfo.packageName }.toSet()
        val safe = (FocusProtectionManager(context).essentialPackages() - homes).toMutableSet()
        safe += context.packageName
        // Resolve dialer and call UI as essential even when they are not launcher apps.
        listOf(Intent(Intent.ACTION_DIAL, Uri.parse("tel:")), Intent("android.intent.action.DIAL_EMERGENCY"),
            Intent(Intent.ACTION_DIAL, Uri.parse("tel:112"))).forEach { intent ->
            pm.queryIntentActivities(intent, PackageManager.MATCH_ALL).mapTo(safe) { it.activityInfo.packageName }
        }
        pm.queryIntentServices(Intent("android.telecom.InCallService"), PackageManager.MATCH_ALL)
            .mapTo(safe) { it.serviceInfo.packageName }
        safe += setOf("com.android.phone", "com.android.server.telecom", "com.android.incallui",
            "com.samsung.android.incallui", "com.samsung.android.dialer", "com.google.android.dialer",
            "com.android.emergency", "com.samsung.android.app.telephonyui")
        context.getSystemService(android.view.inputmethod.InputMethodManager::class.java).inputMethodList
            .mapTo(safe) { it.packageName }
        return safe
    }
    fun openPhone(context: Context) {
        // Opens UI only. Never dials a number or places an emergency call automatically.
        val normal = Intent(Intent.ACTION_DIAL, Uri.parse("tel:")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(normal) }.onFailure {
            runCatching {
                val pkg = context.getSystemService(TelecomManager::class.java).defaultDialerPackage
                val launch = pkg?.let { context.packageManager.getLaunchIntentForPackage(it) }
                    ?: Intent("android.intent.action.DIAL_EMERGENCY")
                context.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
    }
}
