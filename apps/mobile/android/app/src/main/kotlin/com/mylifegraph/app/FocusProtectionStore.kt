package com.mylifegraph.app

import android.content.Context

data class LocalFocusConfiguration(
    val enabled: Boolean,
    val blockSelectedApps: Boolean,
    val silenceNotifications: Boolean,
    val selectedPackages: Set<String>,
    val consentVersions: Map<String, Int>,
)

class FocusProtectionStore(context: Context) {
    private val preferences = context.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    fun readConfiguration(): LocalFocusConfiguration = LocalFocusConfiguration(
        enabled = preferences.getBoolean(KEY_ENABLED, false),
        blockSelectedApps = preferences.getBoolean(KEY_BLOCK_APPS, true),
        silenceNotifications = preferences.getBoolean(KEY_SILENCE_NOTIFICATIONS, true),
        selectedPackages = preferences.getStringSet(KEY_SELECTED_PACKAGES, emptySet())
            ?.toSet()
            ?: emptySet(),
        consentVersions = CONSENT_KEYS.mapNotNull { kind ->
            val value = preferences.getInt("$KEY_CONSENT_PREFIX$kind", 0)
            if (value > 0) kind to value else null
        }.toMap(),
    )

    fun saveConfiguration(configuration: LocalFocusConfiguration): Boolean {
        val editor = preferences.edit()
            .putBoolean(KEY_ENABLED, configuration.enabled)
            .putBoolean(KEY_BLOCK_APPS, configuration.blockSelectedApps)
            .putBoolean(KEY_SILENCE_NOTIFICATIONS, configuration.silenceNotifications)
            .putStringSet(KEY_SELECTED_PACKAGES, configuration.selectedPackages)
        CONSENT_KEYS.forEach { kind ->
            val value = configuration.consentVersions[kind] ?: 0
            if (value > 0) {
                editor.putInt("$KEY_CONSENT_PREFIX$kind", value)
            } else {
                editor.remove("$KEY_CONSENT_PREFIX$kind")
            }
        }
        return editor.commit()
    }

    fun readLease(): LocalFocusLease? {
        val sessionId = preferences.getString(KEY_LEASE_SESSION_ID, null) ?: return null
        val startedAt = preferences.getLong(KEY_LEASE_STARTED_AT, 0L)
        val endsAt = preferences.getLong(KEY_LEASE_ENDS_AT, 0L)
        val state = preferences.getString(
            KEY_LEASE_STATE,
            LocalFocusLease.STATE_ACTIVE,
        ) ?: LocalFocusLease.STATE_ACTIVE
        if (sessionId.isBlank() || startedAt <= 0L || endsAt <= startedAt) return null
        return LocalFocusLease(sessionId, startedAt, endsAt, state)
    }

    fun saveLease(lease: LocalFocusLease): Boolean =
        preferences.edit()
            .putString(KEY_LEASE_SESSION_ID, lease.sessionId)
            .putLong(KEY_LEASE_STARTED_AT, lease.startedAtEpochMs)
            .putLong(KEY_LEASE_ENDS_AT, lease.endsAtEpochMs)
            .putString(KEY_LEASE_STATE, lease.state)
            .commit()

    fun saveEmergencyRelease(lease: LocalFocusLease): Boolean =
        preferences.edit()
            .putString(KEY_LEASE_SESSION_ID, lease.sessionId)
            .putLong(KEY_LEASE_STARTED_AT, lease.startedAtEpochMs)
            .putLong(KEY_LEASE_ENDS_AT, lease.endsAtEpochMs)
            .putString(KEY_LEASE_STATE, LocalFocusLease.STATE_EMERGENCY_RELEASED)
            .putString(KEY_SUPPRESSED_SESSION_ID, lease.sessionId)
            .commit()

    fun clearLease(): Boolean =
        preferences.edit()
            .remove(KEY_LEASE_SESSION_ID)
            .remove(KEY_LEASE_STARTED_AT)
            .remove(KEY_LEASE_ENDS_AT)
            .remove(KEY_LEASE_STATE)
            .commit()

    fun clearLeaseAndSuppression(sessionId: String): Boolean {
        val editor = preferences.edit()
            .remove(KEY_LEASE_SESSION_ID)
            .remove(KEY_LEASE_STARTED_AT)
            .remove(KEY_LEASE_ENDS_AT)
            .remove(KEY_LEASE_STATE)
        if (suppressedSessionId() == sessionId) {
            editor.remove(KEY_SUPPRESSED_SESSION_ID)
        }
        return editor.commit()
    }

    fun suppressedSessionId(): String? =
        preferences.getString(KEY_SUPPRESSED_SESSION_ID, null)

    fun clearSuppressedSession(): Boolean =
        preferences.edit().remove(KEY_SUPPRESSED_SESSION_ID).commit()

    fun zenRuleId(): String? = preferences.getString(KEY_ZEN_RULE_ID, null)

    fun saveZenRuleId(ruleId: String): Boolean =
        preferences.edit().putString(KEY_ZEN_RULE_ID, ruleId).commit()

    fun clearZenRuleId(): Boolean =
        preferences.edit().remove(KEY_ZEN_RULE_ID).commit()

    fun isZenConditionActive(): Boolean =
        preferences.getBoolean(KEY_ZEN_CONDITION_ACTIVE, false)

    fun isZenActivationPending(): Boolean =
        preferences.getBoolean(KEY_ZEN_ACTIVATION_PENDING, false)

    fun isZenCleanupPending(): Boolean =
        preferences.getBoolean(KEY_ZEN_CLEANUP_PENDING, false)

    fun beginZenActivation(): Boolean = preferences.edit()
        .putBoolean(KEY_ZEN_CONDITION_ACTIVE, true)
        .putBoolean(KEY_ZEN_ACTIVATION_PENDING, true)
        .putBoolean(KEY_ZEN_CLEANUP_PENDING, false)
        .commit()

    fun completeZenActivation(): Boolean = preferences.edit()
        .putBoolean(KEY_ZEN_ACTIVATION_PENDING, false)
        .commit()

    fun beginZenCleanup(): Boolean = preferences.edit()
        .putBoolean(KEY_ZEN_CONDITION_ACTIVE, false)
        .putBoolean(KEY_ZEN_ACTIVATION_PENDING, false)
        .putBoolean(KEY_ZEN_CLEANUP_PENDING, true)
        .commit()

    fun completeZenCleanup(): Boolean = preferences.edit()
        .putBoolean(KEY_ZEN_CLEANUP_PENDING, false)
        .commit()

    fun setNativeFailure(failed: Boolean): Boolean =
        preferences.edit().putBoolean(KEY_NATIVE_FAILURE, failed).commit()

    fun hasNativeFailure(): Boolean = preferences.getBoolean(KEY_NATIVE_FAILURE, false)

    companion object {
        const val PREFERENCES_NAME = "mylifegraph_focus_protection_v1"
        const val CONSENT_APP_CATALOG = "app_catalog"
        const val CONSENT_ACCESSIBILITY = "accessibility"
        const val CONSENT_NOTIFICATION_POLICY = "notification_policy"
        const val CONSENT_VERSION = 1

        private val CONSENT_KEYS = setOf(
            CONSENT_APP_CATALOG,
            CONSENT_ACCESSIBILITY,
            CONSENT_NOTIFICATION_POLICY,
        )
        private const val KEY_ENABLED = "enabled"
        private const val KEY_BLOCK_APPS = "block_selected_apps"
        private const val KEY_SILENCE_NOTIFICATIONS = "silence_notifications"
        private const val KEY_SELECTED_PACKAGES = "selected_packages"
        private const val KEY_CONSENT_PREFIX = "consent_version_"
        private const val KEY_LEASE_SESSION_ID = "lease_session_id"
        private const val KEY_LEASE_STARTED_AT = "lease_started_at"
        private const val KEY_LEASE_ENDS_AT = "lease_ends_at"
        private const val KEY_LEASE_STATE = "lease_state"
        private const val KEY_SUPPRESSED_SESSION_ID = "suppressed_session_id"
        private const val KEY_ZEN_RULE_ID = "zen_rule_id"
        private const val KEY_ZEN_CONDITION_ACTIVE = "zen_condition_active"
        private const val KEY_ZEN_ACTIVATION_PENDING = "zen_activation_pending"
        private const val KEY_ZEN_CLEANUP_PENDING = "zen_cleanup_pending"
        private const val KEY_NATIVE_FAILURE = "native_failure"
    }
}
