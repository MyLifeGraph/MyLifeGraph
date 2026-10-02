package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class BlockingPolicyTest {
    @Test fun revokedWebsiteConsentLeavesOnlyRealAppTargetsEffective() {
        assertTrue(BlockingRulePolicy.hasEffectiveTargets(1, 1, false))
        assertFalse(BlockingRulePolicy.hasEffectiveTargets(0, 1, false))
        assertTrue(BlockingRulePolicy.hasEffectiveTargets(0, 1, true))
        assertFalse(BlockingRulePolicy.hasEffectiveTargets(0, 0, true))
        // Essential packages are excluded by the native status adapter before
        // counting app targets; its remaining zero cannot report Active.
        assertFalse(BlockingRulePolicy.hasEffectiveTargets(0, 0, false))
    }

    @Test fun siteMeteringRequiresBothConsentsAndGrantedUsage() {
        for (website in listOf(false, true)) for (usage in listOf(false, true)) {
            assertEquals(website && usage, BlockingConsentPolicy.siteUsageAllowed(website, usage))
        }
    }

    @Test fun firstMigrationRetainsOverOneHundredIndependentLegacySelections() {
        val legacy = (1..101).map { "legacy:package.app$it" }
        assertTrue(BlockingMigrationPolicy.countAllowed(legacy, legacy.toSet()))
        assertTrue(BlockingMigrationPolicy.countAllowed(legacy.dropLast(1), legacy.toSet()))
        assertFalse(BlockingMigrationPolicy.countAllowed(legacy + "new-plan", legacy.toSet()))
        assertFalse(BlockingMigrationPolicy.countAllowed(legacy.dropLast(1) + "new-plan", legacy.toSet()))
        assertFalse(BlockingMigrationPolicy.countAllowed(legacy, emptySet()))
        assertTrue(BlockingMigrationPolicy.countAllowed(List(100) { "new-$it" }, emptySet()))
    }

    @Test fun migrationRetainsLongLabelsIdsAndPackagesWithoutTruncation() {
        val packageName = "example." + "a".repeat(201)
        val id = "legacy:$packageName"
        val name = "An installed application with a long, descriptive display name " + "x".repeat(60)
        assertTrue(BlockingMigrationPolicy.idAllowed(id, id))
        assertTrue(BlockingMigrationPolicy.nameAllowed(name, name))
        assertTrue(BlockingMigrationPolicy.appAllowed(packageName, setOf(packageName)))
        assertFalse(BlockingMigrationPolicy.idAllowed(id, null))
        assertFalse(BlockingMigrationPolicy.nameAllowed(name, null))
        assertFalse(BlockingMigrationPolicy.appAllowed(packageName, emptySet()))
        assertFalse(BlockingMigrationPolicy.nameAllowed(name + " changed", name))
        assertTrue(BlockingMigrationPolicy.nameAllowed("Shorter name", name))
        assertFalse(BlockingMigrationPolicy.nameAllowed(" ", " "))
    }

    @Test fun strictChangesShareActiveFocusAndStrictConfigurationGuard() {
        BlockingEditPolicy.requireEditable(false, false)
        for ((locked, focus) in listOf(true to false, false to true, true to true)) {
            try {
                BlockingEditPolicy.requireEditable(locked, focus)
                fail("Must reject protected configuration changes")
            } catch (_: IllegalStateException) { /* expected */ }
        }
    }

    @Test fun permissionLaunchFailureClearsReplyAndAllowsRetry() {
        val requests = BlockingPendingRequest<Any>()
        val failed = Any()
        try {
            requests.launch(failed) { throw SecurityException("permission launch failed") }
            fail("Expected launch exception")
        } catch (_: SecurityException) { /* expected */ }
        assertNull(requests.pending)
        assertNull(requests.take()) // pause/dispose must not answer failed request again
        val retry = Any()
        requests.launch(retry) { }
        assertSame(retry, requests.take())
        assertNull(requests.take())
    }

    @Test fun replyIsConsumedBeforeCallbackAndAnExistingRequestCannotBeReplaced() {
        val requests = BlockingPendingRequest<Any>()
        val first = Any()
        requests.launch(first) { }
        try {
            requests.launch(Any()) { fail("Must not launch a duplicate") }
            fail("Expected duplicate rejection")
        } catch (_: IllegalStateException) { /* expected */ }
        assertSame(first, requests.pending)
        assertSame(first, requests.take())
        assertNull(requests.pending)
        assertNull(requests.take())
    }

    @Test fun nativeCustomizationUsesTheSameFixedSymbolsAndThemePairs() {
        assertEquals(listOf("◇", "▣", "✥", "◎", "☾", "▤"),
            listOf("shield", "work", "games", "social", "sleep", "study").map(BlockingScreenIcon::symbol))
        assertEquals("#08110F" to "#F2F6F3", BlockingScreenIcon.colors("dark"))
        assertEquals("#F6F6F1" to "#15201C", BlockingScreenIcon.colors("light"))
        assertEquals("#070814" to "#F6F3FF", BlockingScreenIcon.colors("space"))
        assertEquals("#080A0E" to "#E5E9EF", BlockingScreenIcon.colors("glass"))
        assertEquals(BlockingScreenIcon.colors("glass"), BlockingScreenIcon.colors("unknown"))
    }

    @Test fun revokedConsentAllowsRetainedPlansAndReductionsButNoNewAccess() {
        val existing = listOf(setOf("x.com"), setOf("instagram.com"))
        // Retaining both, or deleting either, must not make the other unsaveable.
        for (sites in existing) {
            assertTrue(BlockingConsentPolicy.sitesAllowed(sites, sites, false))
            assertTrue(BlockingConsentPolicy.sitesAllowed(emptySet(), sites, false))
            assertFalse(BlockingConsentPolicy.sitesAllowed(sites + "new.com", sites, false))
        }
        val apps = setOf("game.app")
        assertTrue(BlockingConsentPolicy.budgetAllowed(45, 45, apps, apps, existing[0], existing[0], false))
        assertTrue(BlockingConsentPolicy.budgetAllowed(15, 45, apps, apps, emptySet(), existing[0], false))
        assertTrue(BlockingConsentPolicy.budgetAllowed(0, 45, apps, apps, existing[0], existing[0], false))
        assertFalse(BlockingConsentPolicy.budgetAllowed(60, 45, apps, apps, existing[0], existing[0], false))
        assertFalse(BlockingConsentPolicy.budgetAllowed(45, 45, apps + "new.app", apps, existing[0], existing[0], false))
        assertFalse(BlockingConsentPolicy.budgetAllowed(45, 0, apps, emptySet(), emptySet(), emptySet(), false))
        assertTrue(BlockingConsentPolicy.sitesAllowed(existing[0], emptySet(), true))
    }
    @Test fun domainsRetainOnlyHostsAndRejectSpoofedOrCredentialUrls() {
        assertEquals("instagram.com", BlockingDomains.host("https://INSTAGRAM.com/a?secret=value#x"))
        assertEquals("example.com", BlockingDomains.host("example.com."))
        assertEquals("xn--bcher-kva.de", BlockingDomains.host("https://bücher.de/path"))
        assertNull(BlockingDomains.host("https://instagram.com@evil.com/"))
        assertNull(BlockingDomains.host("javascript:alert(1)"))
        assertNull(BlockingDomains.host("https://example.com%40evil.com"))
        assertNull(BlockingDomains.host("search terms here"))
        assertTrue(BlockingDomains.matches("www.instagram.com", "instagram.com"))
        assertFalse(BlockingDomains.matches("notinstagram.com", "instagram.com"))
        assertFalse(BlockingDomains.matches("instagram.com.evil.com", "instagram.com"))
    }
    @Test fun cooldownUsesMonotonicTimeAndRebootsDoNotUnlock() {
        assertEquals(180000L, BlockingUnlockPolicy.remaining(180, -1, 3, 3, 999999))
        assertEquals(180000L, BlockingUnlockPolicy.remaining(180, 1000, 3, 4, 999999))
        assertEquals(180000L, BlockingUnlockPolicy.remaining(180, 1000, 3, 3, 999))
        assertEquals(1L, BlockingUnlockPolicy.remaining(180, 1000, 3, 3, 180999))
        assertEquals(0L, BlockingUnlockPolicy.remaining(180, 1000, 3, 3, 181000))
        assertEquals(0L, BlockingUnlockPolicy.remaining(0, -1, 3, 3, 0))
    }
    @Test fun strictConditionsAreAndNotOr() {
        for (power in listOf(false, true)) for (wifi in listOf(false, true)) for (nfc in listOf(false, true)) {
            assertEquals(power && wifi && nfc, BlockingUnlockPolicy.ready(0, true, power, true, wifi, true, nfc))
        }
        assertFalse(BlockingUnlockPolicy.ready(1, false, true, false, true, false, true))
        assertTrue(BlockingUnlockPolicy.ready(0, false, false, false, false, false, false))
    }
    private fun active(enabled: Boolean = true, paused: Long = 0, always: Boolean = false,
        until: Long = 0, focus: Boolean = false, lease: Boolean = false, window: Boolean = false,
        budget: Int = 0, access: Boolean = true, used: Long = 0) = BlockingRulePolicy.active(
        enabled, paused, 1000, always, until, focus, lease, window, budget, access, used)
    @Test fun rulesCombineAndEachPlanPauseOnlyAffectsThatPlan() {
        assertTrue(active(focus = true, lease = true))
        assertFalse(active(focus = true, lease = false))
        assertTrue(active(focus = true, lease = false, window = true))
        assertTrue(active(until = 1001))
        assertFalse(active(until = 1000))
        assertFalse(active(enabled = false, always = true))
        assertFalse(active(paused = 1001, always = true))
        assertTrue(active(paused = 1000, always = true))
        assertTrue(listOf(active(paused = 1001, always = true), active(window = true)).any { it })
    }
    @Test fun budgetsRequireRealUsageAccessAndBlockAtExactThreshold() {
        assertFalse(active(budget = 45, used = 2699999))
        assertTrue(active(budget = 45, used = 2700000))
        assertFalse(active(budget = 45, access = false, used = 9999999))
        assertFalse(active(budget = 0, used = 9999999))
        assertTrue(active(always = true, budget = 45, access = false))
    }
    @Test fun foregroundIntervalsIgnoreStaleActivityPausesAndClampDayBoundaries() {
        val usage = BlockingUsageReducer(100, 600)
        usage.resume("app", "one", 50)
        usage.resume("app", "two", 200)
        usage.pause("app", "one", 210)
        usage.pause("app", "two", 400)
        usage.resume("other", "three", 450)
        usage.screenOff(550)
        assertEquals(mapOf("app" to 300L, "other" to 100L), usage.result())
        assertEquals(mapOf("app" to 300L, "other" to 100L), usage.result())
    }
}
