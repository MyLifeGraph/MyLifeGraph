package com.mylifegraph.app

/** System UI can suspend completion without abandoning the user's visible Strict route. */
internal class StrictScreenSession(private val cancel: () -> Unit) {
    private var foreground = false
    private var visible = false
    private var focused = false
    init { cancel() } // Persisted elapsed time never survives a new Activity/session.
    fun resumed() { foreground = true }
    fun visibility(value: Boolean) {
        visible = value
        if (!visible) cancel()
    }
    fun focus(value: Boolean) { focused = value }
    fun paused() { foreground = false; focused = false }
    fun stopped() { paused(); visible = false; cancel() }
    fun canComplete(): Boolean = foreground && visible && focused
    fun requireVisible() { check(canComplete()) { "Stay on the Strict screen to unlock." } }
}
