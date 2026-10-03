package com.mylifegraph.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import android.widget.Button
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject

/** Only consumes passed values. Never instantiates stores, rules or attempt tracking. */
class BlockingPreviewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val values = args as? Map<*, *> ?: emptyMap<Any, Any>()
        val custom = JSONObject(values["custom"] as? Map<*, *> ?: emptyMap<String, Any>())
        val counters = JSONObject(values["counters"] as? Map<*, *> ?: emptyMap<String, Any>())
        return Preview(context, custom, counters, values["strictLocked"] as? Boolean ?: false)
    }

    private class Preview(context: Context, custom: JSONObject, counters: JSONObject, strictLocked: Boolean) : PlatformView {
        private val handler = Handler(Looper.getMainLooper())
        private val totalMs = custom.optLong("waitSeconds").coerceIn(0L, 900L) * 1000L
        private var deadline = SystemClock.elapsedRealtime() + totalMs
        private var disposed = false
        private val screen = BlockingScreenView(
            context, custom, counters, "Preview", strictLocked,
            onReturn = {
                // Return simply restarts this independent preview; it cannot open a target.
                restart()
            },
            emergency = Button(context).apply {
                text = "Hold 5 seconds for emergency release"
                // Matching decoration and semantics only; no real release authority.
                setOnClickListener { }
            },
        )
        private val tick = object : Runnable {
            override fun run() {
                if (disposed || !screen.isAttachedToWindow) return
                val remaining = (deadline - SystemClock.elapsedRealtime()).coerceAtLeast(0L)
                screen.updateReturn(remaining, totalMs)
                if (remaining > 0L) handler.postDelayed(this, minOf(100L, remaining))
            }
        }
        private val attachment = object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) {
                handler.removeCallbacks(tick)
                handler.post(tick)
            }
            override fun onViewDetachedFromWindow(view: View) {
                handler.removeCallbacks(tick)
            }
        }

        init {
            screen.addOnAttachStateChangeListener(attachment)
            screen.updateReturn(totalMs, totalMs)
        }

        private fun restart() {
            if (disposed) return
            deadline = SystemClock.elapsedRealtime() + totalMs
            handler.removeCallbacks(tick)
            screen.updateReturn(totalMs, totalMs)
            if (screen.isAttachedToWindow && totalMs > 0L) handler.post(tick)
        }

        override fun getView(): View = screen
        override fun dispose() {
            disposed = true
            handler.removeCallbacksAndMessages(null)
            screen.removeOnAttachStateChangeListener(attachment)
            screen.dispose()
        }
    }

    companion object {
        const val VIEW_TYPE = "com.mylifegraph.app/blocking_preview"
    }
}
