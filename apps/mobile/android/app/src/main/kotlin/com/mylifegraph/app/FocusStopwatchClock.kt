package com.mylifegraph.app

/** Monotone elapsed display within one boot; rebase from the canonical start after reboot. */
object FocusStopwatchClock {
    fun anchor(startedAt: Long, wallNow: Long, uptimeNow: Long): Long =
        uptimeNow - (wallNow - startedAt).coerceAtLeast(0)

    fun elapsed(startedAt: Long, savedAnchor: Long, savedBoot: Int, currentBoot: Int,
                wallNow: Long, uptimeNow: Long): Long =
        if (savedBoot == currentBoot) (uptimeNow - savedAnchor).coerceAtLeast(0)
        else (wallNow - startedAt).coerceAtLeast(0)
}
