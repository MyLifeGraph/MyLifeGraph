package com.mylifegraph.app

/** Pure receipt gate; native permission and the atomic account check remain required. */
internal object PushReceipt {
    fun accepts(data: Map<String, String>, active: Boolean, owner: String?,
                session: String?, registration: String?, nowSeconds: Long): Boolean {
        if (!active || owner == null || session == null || registration == null ||
            data["contract_version"] != "android-push-v1" || data["owner"] != owner ||
            data["session_id"] != session || data["registration_id"] != registration) return false
        val expiry = data["expires_epoch"]?.toLongOrNull() ?: return false
        if (expiry <= nowSeconds || expiry > nowSeconds + 900) return false
        val expectedRoute = when (data["kind"]) {
            "sleep", "pattern" -> "/insights"
            "deadlines" -> "/planner"
            else -> return false
        }
        if (data["destination"] != expectedRoute) return false
        return try {
            java.util.UUID.fromString(data["attempt_id"]).toString() == data["attempt_id"]
        } catch (_: Exception) { false }
    }
}
