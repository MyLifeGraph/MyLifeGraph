package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class BlockingNfcRecoveryPolicyTest {
    private fun tag(i: Int) = BlockingNfcTag("id$i", "Chip $i", "hash$i")
    private fun rejected(action: () -> Unit) {
        try { action(); fail("Must reject unsafe recovery") }
        catch (_: IllegalStateException) { }
        catch (_: IllegalArgumentException) { }
    }
    @Test fun onlyLockedNfcModeWithRevisionAllowsRecovery() {
        BlockingNfcRecoveryPolicy.requireAllowed(true, true, true, true)
        rejected { BlockingNfcRecoveryPolicy.requireAllowed(false, true, true, true) }
        rejected { BlockingNfcRecoveryPolicy.requireAllowed(true, false, true, true) }
        rejected { BlockingNfcRecoveryPolicy.requireAllowed(true, true, false, true) }
        rejected { BlockingNfcRecoveryPolicy.requireAllowed(true, true, true, false) }
    }
    @Test fun addPreservesExistingChipsAndTrimsName() {
        val old = listOf(tag(1))
        val result = BlockingNfcTags.recover(old, tag(2).copy(name=" Backup "), null)
        assertEquals(old.first(), result.first())
        assertEquals("Backup", result.last().name)
        rejected { BlockingNfcTags.recover(old, tag(2).copy(name=" "), null) }
    }
    @Test fun fullListRequiresExplicitExistingReplacement() {
        val full = (1..8).map(::tag)
        rejected { BlockingNfcTags.recover(full, tag(9), null) }
        rejected { BlockingNfcTags.recover(full, tag(9), "missing") }
        val result = BlockingNfcTags.recover(full, tag(9), "id3")
        assertEquals(8, result.size)
        assertFalse(result.any { it.id == "id3" })
        assertTrue(result.containsAll(full.filterNot { it.id == "id3" }))
        rejected { BlockingNfcTags.recover(full.take(7), tag(9), "id3") }
    }
    @Test fun duplicateScanNeverDeletesSelectedReplacement() {
        val full = (1..8).map(::tag)
        assertEquals(full, BlockingNfcTags.recover(full, tag(1), "id3"))
    }
    @Test fun enrollmentRequiresRemovalAndMatchingSecondContact() {
        val contact = BlockingNfcContact(true)
        assertEquals(false, contact.scanned("same"))
        assertNull(contact.scanned("same"))
        contact.removed()
        assertEquals(true, contact.scanned("same"))
        assertNull(contact.scanned("same"))
        val mismatch = BlockingNfcContact(true)
        mismatch.scanned("first")
        mismatch.removed()
        rejected { mismatch.scanned("other") }
    }
}
