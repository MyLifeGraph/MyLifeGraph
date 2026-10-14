package com.mylifegraph.app

/** A finite per-entry delay. All arithmetic uses the caller's monotonic clock. */
class BlockReturnDelay {
    var target: String? = null
        private set
    var durationMs = 0L
        private set
    private var startedAt = 0L

    fun begin(packageName: String, seconds: Int, now: Long): Boolean {
        if (target != null) return false
        require(packageName.isNotBlank())
        target = packageName
        durationMs = seconds.coerceIn(0, 900) * 1000L
        startedAt = now
        return true
    }

    fun remaining(now: Long): Long =
        if (target == null) 0 else (durationMs - (now - startedAt).coerceAtLeast(0)).coerceIn(0, durationMs)

    fun complete(now: Long): Boolean {
        if (target == null || remaining(now) > 0) return false
        clear()
        return true
    }

    fun exitViaHome(now: Long, navigateHome: () -> Boolean, returnToApp: () -> Unit): Boolean {
        if (target == null || remaining(now) > 0 || !navigateHome()) return false
        if (!complete(now)) return false
        returnToApp()
        return true
    }

    fun clear() { target = null; durationMs = 0; startedAt = 0 }

    fun retain(sourceStillBlocked: Boolean, foregroundBlocked: Boolean, homeOrOwn: Boolean): Boolean =
        target != null && sourceStillBlocked && (foregroundBlocked || homeOrOwn)
}

/** A requested Home transition is not a confirmed foreground change. */
class BlockingReturnNavigation {
    enum class Destination { WAIT, HOME, OWN, OTHER }
    var source: String? = null
        private set
    fun begin(packageName: String) { require(packageName.isNotBlank()); source = packageName }
    fun destination(foreground: String?, own: String, homes: Set<String>, sourceStillBlocked: Boolean = true): Destination = when {
        !sourceStillBlocked -> Destination.OTHER
        foreground == null || foreground == source || foreground == "com.android.systemui" -> Destination.WAIT
        foreground in homes -> Destination.HOME
        foreground == own -> Destination.OWN
        else -> Destination.OTHER
    }
    fun clear() { source = null }
}
