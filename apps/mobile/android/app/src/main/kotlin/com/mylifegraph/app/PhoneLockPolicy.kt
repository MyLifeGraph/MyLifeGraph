package com.mylifegraph.app

/** Pure policy: Android adapters own clocks, persistence and the essential-app set. */
object PhoneLockPolicy {
    const val RECOVERY_MS = 15L * 60_000
    const val MAX_TIMER_MS = 240L * 60_000

    fun remaining(endWall: Long, endElapsed: Long, duration: Long, savedBoot: Int,
                  currentBoot: Int, wall: Long, elapsed: Long): Long {
        if (duration !in 1..MAX_TIMER_MS) return 0
        // Same boot: elapsed time survives sleep and ignores wall-clock edits.
        // After reboot: bounded wall deadline, rebased by the persistence adapter.
        return (if (savedBoot >= 0 && savedBoot == currentBoot) endElapsed - elapsed
            else endWall - wall).coerceIn(0, duration)
    }

    fun blocks(packageName: String?, essential: Set<String>, allowed: Set<String>): Boolean =
        !packageName.isNullOrBlank() && packageName !in essential && packageName !in allowed

    fun requireCurrent(expected: String?, actual: String) {
        check(!expected.isNullOrBlank() && expected == actual) { "Phone lock changed. Review it and try again." }
    }
}
