package com.mylifegraph.app

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.AlarmClock
import android.provider.Settings
import android.telecom.TelecomManager
import android.view.accessibility.AccessibilityManager

class FocusProtectionManager(private val context: Context) {
    private val store = FocusProtectionStore(context)
    private val zenController = FocusZenController(context, store)
    private val packageManager = context.packageManager
    private val handler = Handler(Looper.getMainLooper())
    private val handlerExpiry = Runnable { expireIfNeeded() }

    fun readStatus(): Map<String, Any?> {
        expireIfNeeded()
        val configuration = store.readConfiguration()
        val lease = store.readLease()
        val accessibilityEnabled = isAccessibilityEnabled()
        val policyGranted = zenController.isPolicyAccessGranted()
        val warnings = linkedSetOf<String>()
        val activeMechanisms = linkedSetOf<String>()
        val activeLease = lease?.isActive(System.currentTimeMillis()) == true
        val essential = if (configuration.blockSelectedApps) essentialPackages() else emptySet()
        val hasSelectableConfiguredApp = configuration.selectedPackages.any { packageName ->
            packageName !in essential &&
                runCatching { packageManager.getLaunchIntentForPackage(packageName) != null }
                    .getOrDefault(false)
        }

        if (configuration.enabled && configuration.blockSelectedApps) {
            if (!accessibilityEnabled) warnings += "accessibility_disabled"
            if (!hasSelectableConfiguredApp) warnings += "no_apps_selected"
            if (activeLease && accessibilityEnabled && hasSelectableConfiguredApp) {
                activeMechanisms += "app_blocking"
            }
        }
        if (configuration.enabled && configuration.silenceNotifications) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                warnings += "dnd_unsupported"
            } else if (!policyGranted) {
                warnings += "notification_policy_missing"
            } else if (activeLease) {
                val ruleUsable = zenController.isRuleConfiguredAndUsable()
                if (!ruleUsable) {
                    // A user-edited policy may be stricter than the disclosed
                    // alarm/caller boundary. Stop our condition; never repair it.
                    zenController.deactivate()
                    warnings += "zen_rule_missing_or_overridden"
                } else if (zenController.isRuleEffectivelyActive()) {
                    activeMechanisms += "silence_notifications"
                } else {
                    warnings += "zen_rule_missing_or_overridden"
                }
            } else if (store.zenRuleId() != null &&
                !zenController.isRuleConfiguredAndUsable()
            ) {
                warnings += "zen_rule_missing_or_overridden"
            }
        }
        if (store.hasNativeFailure()) warnings += "native_failure"

        return mapOf(
            "platformSupported" to true,
            "accessibilityEnabled" to accessibilityEnabled,
            "notificationPolicyGranted" to policyGranted,
            "configuration" to configuration.toChannelMap(),
            "lease" to lease?.toChannelMap(),
            "activeMechanisms" to activeMechanisms.toList(),
            "warnings" to warnings.toList(),
        )
    }

    fun listLaunchableApps(): List<Map<String, String>> {
        requireConsent(FocusProtectionStore.CONSENT_APP_CATALOG)
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val essential = essentialPackages()
        return packageManager.queryIntentActivities(intent, PackageManager.MATCH_ALL)
            .asSequence()
            .filter { it.activityInfo.enabled && it.activityInfo.exported }
            .map {
                val packageName = it.activityInfo.packageName
                val label = it.loadLabel(packageManager).toString().trim()
                packageName to label
            }
            .filter { (packageName, label) ->
                packageName.isNotBlank() && label.isNotBlank() && packageName !in essential
            }
            .distinctBy { it.first }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.second })
            .map { (packageName, label) ->
                mapOf("packageName" to packageName, "label" to label)
            }
            .toList()
    }

    fun saveConfiguration(arguments: Map<*, *>): Map<String, Any?> {
        val existingLease = store.readLease()
        check(existingLease?.isActive(System.currentTimeMillis()) != true) {
            "Focus protection configuration is locked during an active lease."
        }
        val selectedPackages = (arguments["selectedPackages"] as? List<*>)
            ?.map {
                (it as? String)?.trim()
                    ?.takeIf(String::isNotEmpty)
                    ?: throw IllegalArgumentException("Invalid selected package.")
            }
            ?.toSet()
            ?: throw IllegalArgumentException("Missing selected packages.")
        val rawConsents = arguments["consentVersions"] as? Map<*, *>
            ?: throw IllegalArgumentException("Missing consent versions.")
        val consentVersions = rawConsents.entries.associate { (rawKey, rawValue) ->
            val key = rawKey as? String
                ?: throw IllegalArgumentException("Invalid consent kind.")
            val value = (rawValue as? Number)?.toInt()
                ?: throw IllegalArgumentException("Invalid consent version.")
            require(value > 0) { "Invalid consent version." }
            key to value
        }
        val previousConfiguration = store.readConfiguration()
        val configuration = LocalFocusConfiguration(
            enabled = arguments["enabled"] as? Boolean
                ?: throw IllegalArgumentException("Missing enabled setting."),
            blockSelectedApps = arguments["blockSelectedApps"] as? Boolean
                ?: throw IllegalArgumentException("Missing app-blocking setting."),
            silenceNotifications = arguments["silenceNotifications"] as? Boolean
                ?: throw IllegalArgumentException("Missing notification setting."),
            selectedPackages = selectedPackages - essentialPackages(),
            consentVersions = consentVersions,
        )
        check(store.saveConfiguration(configuration)) {
            "Could not persist Focus protection configuration."
        }
        store.setNativeFailure(false)
        if (!previousConfiguration.silenceNotifications &&
            configuration.silenceNotifications
        ) {
            zenController.prepareForExplicitRuleEnable()
        }
        if (!configuration.enabled || !configuration.silenceNotifications) {
            zenController.deactivate()
        }
        return readStatus()
    }

    fun openAccessibilitySettings() {
        requireConsent(FocusProtectionStore.CONSENT_ACCESSIBILITY)
        context.startActivity(
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    fun openNotificationPolicySettings() {
        requireConsent(FocusProtectionStore.CONSENT_NOTIFICATION_POLICY)
        context.startActivity(
            Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    fun activateLease(arguments: Map<*, *>): Map<String, Any?> {
        val sessionId = (arguments["sessionId"] as? String)?.trim().orEmpty()
        val startedAt = (arguments["startedAtEpochMs"] as? Number)?.toLong()
            ?: throw IllegalArgumentException("Missing lease start.")
        val endsAt = (arguments["endsAtEpochMs"] as? Number)?.toLong()
            ?: throw IllegalArgumentException("Missing lease end.")
        require(sessionId.isNotEmpty() && startedAt > 0L && endsAt > startedAt) {
            "Invalid Focus protection lease."
        }
        expireIfNeeded()
        val configuration = store.readConfiguration()
        if (!configuration.enabled) return readStatus()
        val now = System.currentTimeMillis()
        store.setNativeFailure(false)
        val current = store.readLease()
        val candidate = LocalFocusLease(sessionId, startedAt, endsAt)
        val reconciled = FocusProtectionDecision.reconcileActivation(
            currentLease = current,
            suppressedSessionId = store.suppressedSessionId(),
            candidate = candidate,
            nowEpochMs = now,
        ) ?: return readStatus()
        if (reconciled.sessionId != sessionId) return readStatus()
        if (reconciled.state == LocalFocusLease.STATE_EMERGENCY_RELEASED) {
            if (current?.sessionId != sessionId && current?.isActive(now) == true) {
                if (!markLeaseInactive(current)) return readStatus()
            }
            if (!store.saveEmergencyRelease(reconciled)) {
                store.setNativeFailure(true)
                return readStatus()
            }
            zenController.deactivate()
            cancelExpiryAlarm()
            FocusBlockAccessibilityService.refreshOverlayIfRunning(context)
            return readStatus()
        }
        if (reconciled != candidate) {
            store.setNativeFailure(true)
            return readStatus()
        }
        val exactReplay = current == candidate
        if (!exactReplay && current?.isActive(now) == true && !markLeaseInactive(current)) {
            return readStatus()
        }
        if (!exactReplay && !store.saveLease(candidate)) {
            store.setNativeFailure(true)
            return readStatus()
        }
        if (store.suppressedSessionId() != null &&
            store.suppressedSessionId() != sessionId
        ) {
            if (!store.clearSuppressedSession()) store.setNativeFailure(true)
        }
        scheduleExpiryAlarm(candidate)
        if (configuration.silenceNotifications && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            zenController.activate(
                allowRuleCreation = store.zenRuleId() == null,
                freshTrigger = !exactReplay || !store.isZenConditionActive(),
            )
        } else if (zenController.needsCleanup()) {
            zenController.deactivate()
        }
        FocusBlockAccessibilityService.refreshOverlayIfRunning(context)
        return readStatus()
    }

    fun deactivateLease(sessionId: String): Map<String, Any?> {
        val normalized = sessionId.trim()
        require(normalized.isNotEmpty()) { "Missing session id." }
        val lease = store.readLease()
        if (lease?.sessionId == normalized) {
            if (lease.state == LocalFocusLease.STATE_ACTIVE &&
                !store.saveLease(lease.copy(state = LocalFocusLease.STATE_EXPIRED))
            ) {
                store.setNativeFailure(true)
                return readStatus()
            }
            zenController.deactivate()
            cancelExpiryAlarm()
            if (!store.clearLeaseAndSuppression(normalized)) {
                store.setNativeFailure(true)
            }
            FocusBlockAccessibilityService.refreshOverlayIfRunning(context)
        }
        return readStatus()
    }

    fun emergencyRelease(sessionId: String): Map<String, Any?> {
        val normalized = sessionId.trim()
        require(normalized.isNotEmpty()) { "Missing session id." }
        val lease = store.readLease()
        if (lease?.sessionId == normalized) {
            if (!store.saveEmergencyRelease(lease)) {
                store.setNativeFailure(true)
                return readStatus()
            }
            zenController.deactivate()
            cancelExpiryAlarm()
            FocusBlockAccessibilityService.refreshOverlayIfRunning(context)
        }
        return readStatus()
    }

    fun expireIfNeeded() {
        val now = System.currentTimeMillis()
        val configuration = store.readConfiguration()
        var lease = store.readLease()
        var leaseBecameInactive = false
        if (lease?.state == LocalFocusLease.STATE_ACTIVE && lease.endsAtEpochMs <= now) {
            val expired = lease.copy(state = LocalFocusLease.STATE_EXPIRED)
            if (store.saveLease(expired)) {
                lease = expired
                leaseBecameInactive = true
            } else {
                store.setNativeFailure(true)
            }
        }
        val shouldRequestZen = FocusProtectionDecision.shouldRequestZen(
            protectionEnabled = configuration.enabled,
            silenceNotifications = configuration.silenceNotifications,
            lease = lease,
            nowEpochMs = now,
        )
        if (store.isZenCleanupPending() ||
            !shouldRequestZen && zenController.needsCleanup()
        ) {
            zenController.deactivate()
        }
        if (lease?.state == LocalFocusLease.STATE_EXPIRED) {
            cancelExpiryAlarm()
            if (!store.clearLease()) store.setNativeFailure(true)
        } else if (lease?.state == LocalFocusLease.STATE_EMERGENCY_RELEASED) {
            cancelExpiryAlarm()
        }
        if (leaseBecameInactive) {
            FocusBlockAccessibilityService.refreshOverlayIfRunning(context)
        }
    }

    fun activeLease(): LocalFocusLease? {
        expireIfNeeded()
        return store.readLease()?.takeIf { it.isActive(System.currentTimeMillis()) }
    }

    fun shouldBlock(packageName: String?): Boolean {
        val configuration = store.readConfiguration()
        return FocusProtectionDecision.shouldBlockPackage(
            protectionEnabled = configuration.enabled,
            blockingEnabled = configuration.blockSelectedApps,
            accessibilityEnabled = true,
            selectedPackages = configuration.selectedPackages,
            essentialPackages = essentialPackages(),
            foregroundPackage = packageName,
            lease = activeLease(),
            nowEpochMs = System.currentTimeMillis(),
        )
    }

    fun rescheduleAfterBoot() {
        expireIfNeeded()
        val lease = activeLease() ?: return
        scheduleExpiryAlarm(lease)
        val configuration = store.readConfiguration()
        if (configuration.enabled &&
            configuration.silenceNotifications &&
            store.isZenActivationPending()
        ) {
            zenController.activate(
                allowRuleCreation = false,
                freshTrigger = false,
            )
        }
    }

    private fun markLeaseInactive(lease: LocalFocusLease): Boolean {
        if (!store.saveLease(lease.copy(state = LocalFocusLease.STATE_EXPIRED))) {
            store.setNativeFailure(true)
            return false
        }
        zenController.deactivate()
        cancelExpiryAlarm()
        return true
    }

    private fun isAccessibilityEnabled(): Boolean {
        val accessibilityManager =
            context.getSystemService(AccessibilityManager::class.java)
        return accessibilityManager
            .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { info ->
                val serviceInfo = info.resolveInfo.serviceInfo
                serviceInfo.packageName == context.packageName &&
                    serviceInfo.name == FocusBlockAccessibilityService::class.java.name
            }
    }

    fun essentialPackages(): Set<String> {
        val packages = linkedSetOf(
            context.packageName,
            "android",
            "com.android.settings",
            "com.android.systemui",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
        )
        val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        packageManager.queryIntentActivities(homeIntent, PackageManager.MATCH_ALL)
            .mapTo(packages) { it.activityInfo.packageName }
        listOf(
            Settings.ACTION_SETTINGS,
            Settings.ACTION_ACCESSIBILITY_SETTINGS,
            Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS,
        ).forEach { action ->
            packageManager.resolveActivity(
                Intent(action),
                PackageManager.MATCH_DEFAULT_ONLY,
            )?.activityInfo?.packageName?.let(packages::add)
        }
        runCatching {
            context.getSystemService(TelecomManager::class.java).defaultDialerPackage
        }.getOrNull()?.let(packages::add)
        packageManager.resolveActivity(
            Intent(AlarmClock.ACTION_SHOW_ALARMS),
            PackageManager.MATCH_DEFAULT_ONLY,
        )?.activityInfo?.packageName?.let(packages::add)
        packageManager.resolveActivity(
            Intent(AlarmClock.ACTION_SET_ALARM),
            PackageManager.MATCH_DEFAULT_ONLY,
        )?.activityInfo?.packageName?.let(packages::add)
        packageManager.resolveActivity(
            Intent(Intent.ACTION_INSTALL_PACKAGE).setDataAndType(
                Uri.parse("content://com.mylifegraph.app/package.apk"),
                "application/vnd.android.package-archive",
            ),
            PackageManager.MATCH_DEFAULT_ONLY,
        )?.activityInfo?.packageName?.let(packages::add)
        return packages.filter(String::isNotBlank).toSet()
    }

    private fun scheduleExpiryAlarm(lease: LocalFocusLease) {
        handler.removeCallbacks(handlerExpiry)
        handler.postDelayed(
            handlerExpiry,
            (lease.endsAtEpochMs - System.currentTimeMillis()).coerceAtLeast(0L),
        )
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            lease.endsAtEpochMs,
            expiryPendingIntent(),
        )
    }

    private fun cancelExpiryAlarm() {
        handler.removeCallbacks(handlerExpiry)
        context.getSystemService(AlarmManager::class.java).cancel(expiryPendingIntent())
    }

    private fun expiryPendingIntent(): PendingIntent = PendingIntent.getBroadcast(
        context,
        4107,
        Intent(context, FocusLeaseExpiryReceiver::class.java).setAction(ACTION_EXPIRE),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun requireConsent(kind: String) {
        check(
            (store.readConfiguration().consentVersions[kind] ?: 0) >=
                FocusProtectionStore.CONSENT_VERSION,
        ) { "Required in-app disclosure was not accepted." }
    }

    private fun LocalFocusConfiguration.toChannelMap(): Map<String, Any> = mapOf(
        "enabled" to enabled,
        "blockSelectedApps" to blockSelectedApps,
        "silenceNotifications" to silenceNotifications,
        "selectedPackages" to selectedPackages.sorted(),
        "consentVersions" to consentVersions,
    )

    private fun LocalFocusLease.toChannelMap(): Map<String, Any> = mapOf(
        "sessionId" to sessionId,
        "startedAtEpochMs" to startedAtEpochMs,
        "endsAtEpochMs" to endsAtEpochMs,
        "state" to state,
    )

    companion object {
        private const val ACTION_EXPIRE = "com.mylifegraph.app.EXPIRE_FOCUS_PROTECTION"
    }
}
