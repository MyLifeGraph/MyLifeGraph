package com.mylifegraph.app

/** System UI can suspend completion without abandoning the user's visible Strict route. */
internal class StrictScreenSession(
    private val stayOnScreen: () -> Boolean = { true },
    private val cancel: () -> Unit,
) {
    private var foreground = false
    private var visible = false
    private var focused = false
    init { if (stayOnScreen()) cancel() }
    fun resumed() { foreground = true }
    fun visibility(value: Boolean) {
        visible = value
        if (!visible && stayOnScreen()) cancel()
    }
    fun focus(value: Boolean) { focused = value }
    fun paused() { foreground = false; focused = false }
    fun stopped() { paused(); visible = false; if (stayOnScreen()) cancel() }
    fun canComplete(): Boolean = foreground && visible && focused
    fun canFinishUnlock(): Boolean = !stayOnScreen() || canComplete()
    fun requireVisible() { check(canComplete()) { "Open Discipline to unlock." } }
    /** At deliberate requests, use current host facts rather than stale callbacks.
     * Route visibility remains independently owned by the Flutter screen. */
    fun requireVisible(hostResumed: Boolean, hostFocused: Boolean) {
        foreground = hostResumed
        focused = hostFocused
        requireVisible()
    }
}
