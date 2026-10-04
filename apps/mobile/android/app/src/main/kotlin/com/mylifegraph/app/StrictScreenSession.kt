package com.mylifegraph.app

/** A pending Strict wait belongs to one continuously visible foreground screen. */
internal class StrictScreenSession(private val cancel: () -> Unit) {
    private var foreground = false
    private var visible = false
    init { cancel() } // Persisted elapsed time never survives a new Activity/session.
    fun resumed() { foreground = true }
    fun visibility(value: Boolean) {
        visible = value && foreground
        if (!visible) cancel()
    }
    fun paused() { foreground = false; visible = false; cancel() }
    fun requireVisible() { check(foreground && visible) { "Stay on the Strict screen to unlock." } }
}
