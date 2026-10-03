package com.mylifegraph.app

import java.net.IDN
import java.net.URI

/** Only hosts are retained: never URL paths, queries, page text or credentials. */
object BlockingDomains {
    fun host(value: String): String? = runCatching {
        val input = value.trim()
        val uri = URI(if (input.contains("://")) input else "https://$input")
        require(uri.scheme.lowercase() in setOf("https", "http") && uri.userInfo == null)
        val authority = uri.rawAuthority ?: error("Missing host")
        require(!authority.contains('@') && !authority.contains('%') && !authority.contains('['))
        val name = uri.host ?: authority.substringBefore(':').also {
            if (authority.contains(':')) require(authority.substringAfter(':').toIntOrNull() in 1..65535)
        }
        val host = IDN.toASCII(name, IDN.USE_STD3_ASCII_RULES).lowercase().trimEnd('.')
        require(host.length in 3..253 && host.contains('.') &&
            host.split('.').all { it.matches(Regex("[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?")) })
        host
    }.getOrNull()

    fun matches(host: String, domain: String): Boolean =
        host == domain || host.endsWith(".$domain")
}

/** Shared rule logic is pure so native tests exercise the same enforcement decision. */
object BlockingRulePolicy {
    fun hasEffectiveTargets(apps: Int, sites: Int, websiteConsent: Boolean): Boolean =
        apps > 0 || (sites > 0 && websiteConsent)

    fun active(enabled: Boolean, pausedUntil: Long, now: Long, always: Boolean,
        until: Long, focusSelected: Boolean, focusActive: Boolean, windowActive: Boolean,
        budgetMinutes: Int, usageAvailable: Boolean, usedMs: Long): Boolean =
        enabled && pausedUntil <= now && (always || until > now ||
            (focusSelected && focusActive) || windowActive ||
            (budgetMinutes > 0 && usageAvailable && usedMs >= budgetMinutes * 60000L))
}

/** Revocation stops observation, but must not trap users with retained plan definitions. */
object BlockingConsentPolicy {
    fun siteUsageAllowed(websiteConsent: Boolean, usageGranted: Boolean): Boolean =
        websiteConsent && usageGranted

    fun sitesAllowed(sites: Set<String>, previousSites: Set<String>, consent: Boolean): Boolean =
        consent || previousSites.containsAll(sites)

    fun budgetAllowed(budget: Int, previousBudget: Int, apps: Set<String>, previousApps: Set<String>,
        sites: Set<String>, previousSites: Set<String>, usageGranted: Boolean): Boolean =
        budget == 0 || usageGranted || (previousBudget > 0 && budget <= previousBudget &&
            previousApps.containsAll(apps) && previousSites.containsAll(sites))
}

/** V1 selections were not subject to V2 editor bounds. Retain them without
 * truncating labels/identities or silently discarding protected packages. */
object BlockingMigrationPolicy {
    fun countAllowed(ids: List<String>, previousIds: Set<String>): Boolean =
        ids.size <= 100 || (ids.size <= previousIds.size && previousIds.containsAll(ids))

    fun idAllowed(id: String, previousId: String?): Boolean =
        id.isNotEmpty() && (id.length <= 100 || id == previousId)

    fun nameAllowed(name: String, previousName: String?): Boolean =
        name.trim().isNotEmpty() && (name.trim().length <= 60 || name == previousName)

    fun appAllowed(app: String, previousApps: Set<String>): Boolean =
        app.isNotEmpty() && (app.length <= 200 || app in previousApps)
}

object BlockingEditPolicy {
    // A temporary editing window is not permission to release protection.
    fun requireEmergencyAllowed(strictEnabled: Boolean) {
        check(!strictEnabled) { "Turn off Strict mode first." }
    }

    fun requireEditable(locked: Boolean, focusActive: Boolean) {
        check(!locked) { "Unlock Strict mode first." }
        check(!focusActive) { "Finish the active Focus session first." }
    }
}

/** Main-thread reply slot. A launch failure clears before it propagates, and
 * completion consumes before replying so cancellation/retry cannot reply twice. */
class BlockingPendingRequest<T : Any> {
    var pending: T? = null
        private set

    fun launch(response: T, operation: () -> Unit) {
        check(pending == null) { "A request is already running." }
        pending = response
        try { operation() }
        catch (error: Exception) { if (pending === response) take(); throw error }
    }

    fun take(): T? = pending.also { pending = null }
}

/** Latest resumed activity owns the interval; stale pauses cannot clear a newer activity. */
class BlockingUsageReducer(private val start: Long, private val end: Long) {
    private var foreground: Pair<String, String>? = null
    private var since = start
    private val totals = mutableMapOf<String, Long>()
    private fun finish(at: Long) {
        val pkg = foreground?.first ?: return
        val amount = (at.coerceAtMost(end) - since.coerceAtLeast(start)).coerceAtLeast(0)
        totals[pkg] = (totals[pkg] ?: 0) + amount
    }
    fun resume(pkg: String, activity: String, at: Long) {
        if (foreground != (pkg to activity)) { finish(at); foreground = pkg to activity; since = at }
    }
    fun pause(pkg: String, activity: String, at: Long) {
        if (foreground == pkg to activity) { finish(at); foreground = null }
    }
    fun screenOff(at: Long) { finish(at); foreground = null }
    fun result(): Map<String, Long> { finish(end); foreground = null; return totals.filterValues { it > 0 }.toMap() }
}

/** Persist boot identity with monotonic timestamps. A reboot never completes a wait. */
object BlockingUnlockPolicy {
    fun started(started: Long, startBoot: Int, boot: Int, now: Long): Boolean =
        boot >= 0 && startBoot == boot && started >= 0 && now >= started

    fun remaining(waitSeconds: Int, started: Long, startBoot: Int, boot: Int, now: Long): Long =
        when {
            waitSeconds == 0 -> 0
            !started(started, startBoot, boot, now) -> waitSeconds * 1000L
            else -> (waitSeconds * 1000L - (now - started)).coerceAtLeast(0)
        }

    fun ready(remaining: Long, needsPower: Boolean, powered: Boolean,
        needsWifi: Boolean, wifiMatches: Boolean, needsNfc: Boolean, nfcMatches: Boolean): Boolean =
        remaining == 0L && (!needsPower || powered) && (!needsWifi || wifiMatches) &&
            (!needsNfc || nfcMatches)
}
