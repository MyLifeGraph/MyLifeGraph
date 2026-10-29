package com.mylifegraph.app

import android.view.accessibility.AccessibilityNodeInfo
import android.os.Build
import android.os.Bundle

/** Known address bars only. Neutralization never inspects page content. */
object BrowserAddressBars {
    const val NEUTRAL_URL = "about:blank"
    val adapters = mapOf(
        "com.android.chrome" to listOf("com.android.chrome:id/url_bar"),
        "com.chrome.beta" to listOf("com.chrome.beta:id/url_bar"),
        "com.microsoft.emmx" to listOf("com.microsoft.emmx:id/url_bar"),
        "com.brave.browser" to listOf("com.brave.browser:id/url_bar"),
        "org.mozilla.firefox" to listOf("org.mozilla.firefox:id/mozac_browser_toolbar_url_view"),
        "com.sec.android.app.sbrowser" to listOf("com.sec.android.app.sbrowser:id/location_bar_edit_text"),
    )
    private fun editorIds(pkg: String) = adapters[pkg].orEmpty() +
        if (pkg == "org.mozilla.firefox") listOf("org.mozilla.firefox:id/mozac_browser_toolbar_edit_url_view") else emptyList()

    @Suppress("DEPRECATION")
    fun neutralStep(root: AccessibilityNodeInfo, pending: BrowserNeutralization, now: Long): BrowserNeutralization.Action {
        val nodes = editorIds(pending.packageName).flatMap { root.findAccessibilityNodeInfosByViewId(it) }
        try {
            val node = nodes.firstOrNull { it.isVisibleToUser && it.isFocused && it.isEditable }
                ?: nodes.firstOrNull { it.isVisibleToUser }
                ?: return BrowserNeutralization.Action.ABORT
            val canSubmit = Build.VERSION.SDK_INT >= 30 && node.actionList.any {
                it.id == AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id
            }
            val action = pending.next(now, root.packageName?.toString(), root.windowId, true,
                node.isVisibleToUser, node.isEditable, node.isFocused,
                BlockingBrowserAddress.host(pending.packageName, node.text?.toString().orEmpty()),
                BlockingBrowserAddress.isNeutral(pending.packageName, node.text?.toString().orEmpty()), canSubmit,
                node.text.isNullOrBlank() || Build.VERSION.SDK_INT >= 26 &&
                    node.hintText != null && node.text?.toString() == node.hintText?.toString())
            val accepted = when (action) {
                BrowserNeutralization.Action.FOCUS -> node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                BrowserNeutralization.Action.REPLACE -> node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,
                    Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, NEUTRAL_URL) })
                BrowserNeutralization.Action.SUBMIT -> if (Build.VERSION.SDK_INT >= 30)
                    node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id) else false
                else -> return action
            }
            pending.performed(action, accepted)
            return if (accepted) BrowserNeutralization.Action.WAIT else BrowserNeutralization.Action.ABORT
        } finally { nodes.forEach { it.recycle() } }
    }
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
                    BlockingBrowserAddress.host(packageName, node.text?.toString().orEmpty())?.let { return it }
                }
            } finally { nodes.forEach { it.recycle() } }
        }
        return null
    }
}
