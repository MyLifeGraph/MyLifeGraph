package com.mylifegraph.app

import org.junit.Assert.*
import org.junit.Test

class BlockingNfcPolicyTest {
    @Test fun heldTagCannotConfirmEnrollment() {
        val contact = BlockingNfcContact(true)
        assertEquals(false, contact.scanned("a"))
        repeat(100) { assertNull(contact.scanned("a")) }
        contact.removed()
        assertEquals(true, contact.scanned("a"))
        contact.removed()
        assertNull(contact.scanned("a"))
    }
    @Test fun verificationOnlyCompletesOnceEvenAfterRemoval() {
        val contact = BlockingNfcContact(false)
        assertEquals(true, contact.scanned("a"))
        repeat(100) { assertNull(contact.scanned("a")) }
        contact.removed()
        assertNull(contact.scanned("a"))
    }
    @Test fun changedIdentifierFailsEnrollment() {
        val contact = BlockingNfcContact(true)
        contact.scanned("a"); contact.removed()
        try { contact.scanned("b"); fail("Changing ID accepted") } catch (_: IllegalArgumentException) { }
    }
    @Test fun duplicateDoesNotReplaceOrRenameExistingChip() {
        val main = BlockingNfcTag("old", "Main chip", "hash")
        assertEquals(listOf(main), BlockingNfcTags.add(listOf(main), BlockingNfcTag("new", "Other", "hash")))
    }
    @Test fun backupCanReplaceLostChipButRequiredLastChipCannotBeRemoved() {
        val main = BlockingNfcTag("main", "Main", "a")
        val backup = BlockingNfcTag("backup", "Backup", "b")
        val tags = BlockingNfcTags.add(listOf(main), backup)
        assertEquals(listOf(backup), BlockingNfcTags.remove(tags, "main", true))
        try { BlockingNfcTags.remove(listOf(backup), "backup", true); fail("Last required chip removed") }
        catch (_: IllegalStateException) { }
        assertTrue(BlockingNfcTags.remove(listOf(backup), "backup", false).isEmpty())
    }
    @Test fun boundedNamesAndChipCount() {
        for (name in listOf("", "x".repeat(41))) {
            try { BlockingNfcTags.add(emptyList(), BlockingNfcTag("id", name, "hash")); fail("Bad name") }
            catch (_: IllegalArgumentException) { }
        }
        val tags = (1..8).map { BlockingNfcTag("$it", "Chip $it", "$it") }
        try { BlockingNfcTags.add(tags, BlockingNfcTag("9", "Ninth", "9")); fail("Unbounded list") }
        catch (_: IllegalArgumentException) { }
    }
}
