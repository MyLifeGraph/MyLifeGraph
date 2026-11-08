package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class PhoneLockPolicyTest {
    @Test fun sleepAndBackgroundConsumeTimeWithoutFollowingWallClockChanges() {
        fun left(wall: Long, elapsed: Long) = PhoneLockPolicy.remaining(3_600_000, 3_000_000,
            2_700_000, 8, 8, wall, elapsed)
        assertEquals(1_200_000, left(1,1_800_000))
        assertEquals(1_200_000, left(Long.MAX_VALUE,1_800_000))
        assertEquals(0, left(1,3_000_000))
        assertEquals(0, left(1,4_000_000))
    }
    @Test fun restartUsesOnlyBoundedRemainingDeadlineAndExpiredNeverRevives() {
        assertEquals(600_000, PhoneLockPolicy.remaining(3_600_000,3_000_000,2_700_000,8,9,3_000_000,10))
        assertEquals(0, PhoneLockPolicy.remaining(3_600_000,3_000_000,2_700_000,8,9,3_600_000,10))
        assertEquals(2_700_000, PhoneLockPolicy.remaining(3_600_000,3_000_000,2_700_000,8,9,0,10))
    }
    @Test fun corruptDeadlineCannotCreateUnboundedTimer() {
        for(duration in listOf(-1L,0L,PhoneLockPolicy.MAX_TIMER_MS+1,Long.MAX_VALUE)) {
            assertEquals(0,PhoneLockPolicy.remaining(Long.MAX_VALUE,Long.MAX_VALUE,duration,1,1,0,0))
        }
    }
    @Test fun phoneAndSystemEscapeAlwaysWinAcrossBroadBlocking() {
        val essential=setOf("com.samsung.android.dialer","com.android.phone","com.android.systemui","com.android.settings")
        val optional=setOf("org.example.calendar")
        for(pkg in essential+optional) assertFalse(PhoneLockPolicy.blocks(pkg,essential,optional))
        assertTrue(PhoneLockPolicy.blocks("com.instagram.android",essential,optional))
        assertTrue(PhoneLockPolicy.blocks("newly.installed.app",essential,optional))
        assertFalse(PhoneLockPolicy.blocks(null,essential,optional))
        assertFalse(PhoneLockPolicy.blocks("",essential,optional))
    }
    @Test fun lateRecoveryCannotAffectReplacementLock() {
        PhoneLockPolicy.requireCurrent("first","first")
        for(stale in listOf(null,"","first")) {
            try { PhoneLockPolicy.requireCurrent(stale,"replacement"); fail("Stale request accepted") }
            catch(_: IllegalStateException) { /* required */ }
        }
    }
    @Test fun recoveryCanFinishInBackgroundAndIsFiniteAfterBoot() {
        val duration=PhoneLockPolicy.RECOVERY_MS
        assertEquals(duration,PhoneLockPolicy.remaining(10_000+duration,5_000+duration,duration,4,4,10_000,5_000))
        assertEquals(0,PhoneLockPolicy.remaining(10_000+duration,5_000+duration,duration,4,4,0,5_000+duration))
        assertEquals(120_000,PhoneLockPolicy.remaining(10_000+duration,5_000+duration,duration,4,5,10_000+duration-120_000,1))
    }
}
