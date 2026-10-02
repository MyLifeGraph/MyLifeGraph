package com.mylifegraph.app

import android.view.accessibility.AccessibilityNodeInfo

/** Exact address-bar adapters only. No content traversal, page text or click automation. */
object BrowserAddressBars {
    val adapters = mapOf(
        "com.android.chrome" to listOf("com.android.chrome:id/url_bar"),
        "com.chrome.beta" to listOf("com.chrome.beta:id/url_bar"),
        "com.microsoft.emmx" to listOf("com.microsoft.emmx:id/url_bar"),
        "com.brave.browser" to listOf("com.brave.browser:id/url_bar"),
        "org.mozilla.firefox" to listOf("org.mozilla.firefox:id/mozac_browser_toolbar_url_view"),
        "com.sec.android.app.sbrowser" to listOf("com.sec.android.app.sbrowser:id/location_bar_edit_text"),
    )
    @Suppress("DEPRECATION")
    fun host(root: AccessibilityNodeInfo?, packageName: String): String? {
        if (root == null || root.packageName?.toString() != packageName) return null
        val ids = adapters[packageName] ?: return null
        for (id in ids) {
            val nodes = root.findAccessibilityNodeInfosByViewId(id)
            try {
                for (node in nodes) {
                    // Never treat a search/query currently being typed as a visited website.
                    if (!node.isVisibleToUser || node.isFocused && node.isEditable) continue
                    BlockingDomains.host(node.text?.toString().orEmpty())?.let { return it }
                }
            } finally { nodes.forEach { it.recycle() } }
        }
        return null
    }
}
