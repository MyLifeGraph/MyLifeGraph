package com.mylifegraph.app

/** One physical contact is one scan; enrollment requires a removed tag between scans. */
class BlockingNfcContact(private val enroll: Boolean) {
    private var touching = false
    private var first: String? = null
    private var complete = false
    fun scanned(hash: String): Boolean? {
        if (touching || complete) return null
        require(hash.isNotEmpty()) { "Use a tag with a stable identifier." }
        touching = true
        if (enroll && first == null) { first = hash; return false }
        require(!enroll || first == hash) { "Use the same tag with a stable identifier." }
        complete = true
        return true
    }
    fun removed() { touching = false }
}

data class BlockingNfcTag(val id: String, val name: String, val hash: String)

/** Explicit owner-approved self-control recovery, not a generic edit/unlock bypass. */
object BlockingNfcRecoveryPolicy {
    fun requireAllowed(locked: Boolean, enabled: Boolean, needsNfc: Boolean, hasRevision: Boolean) {
        check(locked && enabled && needsNfc) { "NFC recovery is not available." }
        require(hasRevision) { "Missing settings revision." }
    }
}

object BlockingNfcTags {
    const val LIMIT = 8
    fun recover(tags: List<BlockingNfcTag>, tag: BlockingNfcTag, replaceId: String?): List<BlockingNfcTag> {
        if (tags.any { it.hash == tag.hash }) return tags
        require(replaceId == null || (tags.size == LIMIT && tags.any { it.id == replaceId })) {
            "Chip list changed. Reload and try again."
        }
        return add(if (replaceId == null) tags else tags.filterNot { it.id == replaceId }, tag)
    }
    fun add(tags: List<BlockingNfcTag>, tag: BlockingNfcTag): List<BlockingNfcTag> {
        if (tags.any { it.hash == tag.hash }) return tags
        require(tags.size < LIMIT) { "Up to 8 chips can be saved." }
        require(tag.name.trim().length in 1..40) { "Use a name of 1–40 characters." }
        return tags + tag.copy(name = tag.name.trim())
    }
    fun remove(tags: List<BlockingNfcTag>, id: String, nfcRequired: Boolean): List<BlockingNfcTag> {
        require(tags.any { it.id == id }) { "Chip no longer exists. Reload and try again." }
        check(!nfcRequired || tags.size > 1) { "Add a replacement chip or turn off the NFC requirement first." }
        return tags.filterNot { it.id == id }
    }
}
