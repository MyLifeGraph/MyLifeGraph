package com.mylifegraph.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test

class BlockingBrowserAddressTest {
    @Test fun neutralPageCompletionUsesTheSameObservedAnnotation() {
        assertTrue(BlockingBrowserAddress.isNeutral("com.android.chrome", "about:blank"))
        assertTrue(BlockingBrowserAddress.isNeutral("com.android.chrome", "about:blank. Connection is not secure"))
        assertFalse(BlockingBrowserAddress.isNeutral("com.android.chrome", "https://example.com/about:blank"))
        assertFalse(BlockingBrowserAddress.isNeutral("com.android.chrome", "about:blank. Unknown message"))
        assertFalse(BlockingBrowserAddress.isNeutral("org.mozilla.firefox", "about:blank. Connection is not secure"))
    }
    @Test fun chromeSecurityAnnotationStillIdentifiesTheVisitedHost() {
        // Actual unfocused com.android.chrome:id/url_bar text, Android 17.
        assertEquals("qa-blocked.invalid", BlockingBrowserAddress.host(
            "com.android.chrome", "qa-blocked.invalid. Connection is not secure"))
        assertEquals("instagram.com", BlockingBrowserAddress.host(
            "com.android.chrome", "http://instagram.com. Connection is not secure"))
    }

    @Test fun ordinaryAddressAndDomainEntryValidationRemainUnchanged() {
        for (browser in listOf("com.android.chrome", "org.mozilla.firefox", "com.sec.android.app.sbrowser")) {
            assertEquals("example.com", BlockingBrowserAddress.host(browser, "https://example.com/path?q=1"))
        }
        assertNull(BlockingDomains.host("example.com. Connection is not secure"))
    }

    @Test fun noGenericWhitespaceOrSearchTextHeuristicIsIntroduced() {
        for (value in listOf("Search example.com", "example.com search query", "example.com. Unknown message",
            "https://user@example.com. Connection is not secure", "javascript:example.com. Connection is not secure",
            "example.com. Connection is not secure@other.com")) {
            assertNull(BlockingBrowserAddress.host("com.android.chrome", value))
        }
        assertNull(BlockingBrowserAddress.host("org.mozilla.firefox", "example.com. Connection is not secure"))
    }
}
