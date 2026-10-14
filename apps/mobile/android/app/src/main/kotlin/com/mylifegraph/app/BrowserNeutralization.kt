package com.mylifegraph.app

/** Finite, current-window-only navigation. No rule release or arbitrary URL. */
class BrowserNeutralization(val packageName: String, val host: String, val windowId: Int, private val startedAt: Long) {
    enum class Action { FOCUS, REPLACE, SUBMIT, WAIT, COMPLETE, ABORT }
    private var phase = Action.FOCUS
    fun expired(now: Long): Boolean = now < startedAt || now - startedAt >= 5000
    fun next(now: Long, currentPackage: String?, currentWindow: Int, eligible: Boolean,
        visible: Boolean, editable: Boolean, focused: Boolean, observedHost: String?,
        isBlank: Boolean, canSubmit: Boolean, emptyEditor: Boolean = false): Action {
        if (!eligible || currentPackage != packageName || currentWindow != windowId ||
            expired(now) || !visible) return Action.ABORT
        return when (phase) {
            Action.FOCUS -> if (focused && editable || observedHost != host) Action.ABORT else Action.FOCUS
            Action.REPLACE -> if (!focused || !editable) Action.WAIT
                else if (observedHost != host && !emptyEditor || !canSubmit) Action.ABORT else Action.REPLACE
            Action.SUBMIT -> if (!focused || !editable || !isBlank || !canSubmit) Action.ABORT else Action.SUBMIT
            Action.WAIT -> if (isBlank && !(focused && editable)) Action.COMPLETE
                else if (observedHost != null && observedHost != host) Action.ABORT else Action.WAIT
            else -> Action.ABORT
        }
    }
    fun performed(action: Action, accepted: Boolean) {
        phase = if (!accepted) Action.ABORT else when (action) {
            Action.FOCUS -> Action.REPLACE
            Action.REPLACE -> Action.SUBMIT
            Action.SUBMIT -> Action.WAIT
            else -> Action.ABORT
        }
    }
}
