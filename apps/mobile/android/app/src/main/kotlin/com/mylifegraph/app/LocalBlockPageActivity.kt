package com.mylifegraph.app

import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.Build
import android.text.TextUtils
import android.view.Gravity
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout

/** Offline document in our own task. No local server, JS, network, bridge or browser mutation. */
class LocalBlockPageActivity : ComponentActivity() {
    private var web: WebView? = null
    private val handler = Handler(Looper.getMainLooper())
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() { returnHome() }
        })
        val custom = BlockingPlans(this).custom()
        val colors = BlockingScreenIcon.colors(custom.optString("tone", "glass"))
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            val side = (24 * resources.displayMetrics.density).toInt()
            val vertical = (32 * resources.displayMetrics.density).toInt()
            setPadding(side, vertical, side, vertical)
            setOnApplyWindowInsetsListener { view, insets ->
                if (Build.VERSION.SDK_INT >= 30) {
                    val bars = insets.getInsets(android.view.WindowInsets.Type.systemBars() or android.view.WindowInsets.Type.displayCutout())
                    view.setPadding(side + bars.left, vertical + bars.top, side + bars.right, vertical + bars.bottom)
                } else {
                    @Suppress("DEPRECATION")
                    view.setPadding(side + insets.systemWindowInsetLeft, vertical + insets.systemWindowInsetTop,
                        side + insets.systemWindowInsetRight, vertical + insets.systemWindowInsetBottom)
                }
                insets
            }
            setBackgroundColor(Color.parseColor(colors.first))
        }
        val target = intent.getStringExtra("target").orEmpty().take(253)
        val count = BlockingPlans(this).attempts("web:$target")
        val view = WebView(this).apply {
            settings.javaScriptEnabled = false; settings.blockNetworkLoads = true
            settings.allowFileAccess = false; settings.allowContentAccess = false
            webViewClient = object : WebViewClient() {
                @Deprecated("Deprecated in Java")
                override fun shouldOverrideUrlLoading(view: WebView?, url: String?) = true
                override fun shouldOverrideUrlLoading(view: WebView?, request: android.webkit.WebResourceRequest?) = true
            }
            setBackgroundColor(Color.TRANSPARENT)
            val title = TextUtils.htmlEncode(custom.optString("title", "Stay focused"))
            val message = TextUtils.htmlEncode(custom.optString("message", "Take a breath. Choose your next step."))
            val safeTarget = TextUtils.htmlEncode(target)
            loadDataWithBaseURL("https://blocking.mylifegraph.invalid/", """
                <!doctype html><html><meta name="viewport" content="width=device-width,initial-scale=1">
                <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
                <style>body{background:transparent;color:${colors.second};font-family:system-ui;text-align:center;padding:20px;margin:0}
                .card{padding:32px 16px;border:1px solid #75819855;border-radius:20px;background:#75819818}
                h1{font-size:30px}p{line-height:1.6}small{opacity:.75}</style>
                <div class="card"><div>${BlockingScreenIcon.svg(custom.optString("icon", "shield"))}</div><h1>$title</h1><p>$message</p><p>$safeTarget</p>
                <small>${count.first} today · ${count.second} total</small></div></html>
            """.trimIndent(), "text/html", "utf-8", null)
        }
        web = view
        root.addView(view, LinearLayout.LayoutParams(-1, 0, 1f))
        val deadline = (state?.getLong("deadline") ?: (SystemClock.elapsedRealtime() + custom.optInt("waitSeconds") * 1000L))
        val button = Button(this).apply { setOnClickListener { returnHome() } }
        root.addView(button, LinearLayout.LayoutParams(-1, -2)); setContentView(root)
        val tick = object : Runnable {
            override fun run() {
                val seconds = ((deadline - SystemClock.elapsedRealtime()).coerceAtLeast(0) + 999) / 1000
                button.isEnabled = seconds == 0L
                button.text = if (seconds > 0) "Return in ${seconds}s" else "Return home"
                if (seconds > 0) handler.postDelayed(this, 250)
            }
        }
        savedDeadline = deadline; tick.run()
    }
    private var savedDeadline = 0L
    override fun onResume() { super.onResume(); FocusBlockAccessibilityService.onAppResumed(this) }
    override fun onSaveInstanceState(out: Bundle) { out.putLong("deadline", savedDeadline); super.onSaveInstanceState(out) }
    private fun returnHome() {
        if (SystemClock.elapsedRealtime() < savedDeadline) return
        startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null); web?.destroy(); web = null; super.onDestroy() }
}
