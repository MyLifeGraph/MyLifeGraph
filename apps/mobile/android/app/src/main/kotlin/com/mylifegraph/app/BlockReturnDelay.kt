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

    fun clear() { target = null; durationMs = 0; startedAt = 0 }

    fun retain(sourceStillBlocked: Boolean, foregroundBlocked: Boolean, homeOrOwn: Boolean): Boolean =
        target != null && sourceStillBlocked && (foregroundBlocked || homeOrOwn)
}
