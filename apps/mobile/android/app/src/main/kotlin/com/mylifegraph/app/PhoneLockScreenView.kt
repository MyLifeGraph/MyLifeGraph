package com.mylifegraph.app

import android.content.Context
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.*
import org.json.JSONObject

/** Shared renderer for the real Accessibility overlay and its native control screen. */
class PhoneLockScreenView(context: Context, custom: JSONObject, private val onControl: (String) -> Unit) : FrameLayout(context) {
    private val tone = custom.optString("tone", "glass")
    private val colors = BlockingScreenIcon.colors(tone)
    private val regularFont = runCatching { Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/InstrumentSans-Regular.ttf") }.getOrDefault(Typeface.DEFAULT)
    private val boldFont = runCatching { Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/InstrumentSans-SemiBold.ttf") }.getOrDefault(Typeface.DEFAULT_BOLD)
    private val ink = Color.parseColor(colors.second)
    private val accent = Color.parseColor(when(tone) { "light" -> "#315E8A"; "dark" -> "#82CBB4"; "space" -> "#B2A3EA"; else -> "#A9BDD5" })
    private val column = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; setPadding(dp(24), dp(28), dp(24), dp(28))
    }
    private val ring = Ring(context)
    private val time = label("", 42f, true)
    private val timeLabel = label("remaining", 16f)
    private val heading = label("Time to focus", 26f, true)
    private val explanation = label("Unlocks when your timer ends.", 16f)
    private val scan = button("Scan NFC chip", true) { onControl("scan") }
    private val recovery = button("Recovery options", false) { onControl("recovery") }
    private var scanning = false
    init {
        setBackgroundColor(Color.parseColor(colors.first)); setWillNotDraw(false)
        val scroll = ScrollView(context).apply { isFillViewport = true }
        val center = FrameLayout(context)
        center.addView(column, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        scroll.addView(center)
        addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        column.addView(label("Phone lock", 24f, true), row(0))
        column.addView(ring, LinearLayout.LayoutParams(dp(168), dp(168)).apply { topMargin = dp(28); bottomMargin = dp(16) })
        column.addView(time, row(0)); column.addView(timeLabel, row(0)); column.addView(heading, row(20))
        column.addView(explanation, row(12))
        column.addView(button("Allowed apps  ›", false) { onControl("apps") }, row(24))
        column.addView(scan, row(12))
        column.addView(button("Phone / Emergency", false) { onControl("phone") }, row(12))
        column.addView(recovery, row(12))
        recovery.background = null
        recovery.setTextColor(accent)
        column.addView(label("Calls, alarms and essential Android functions stay available.", 14f), row(20))
        setOnApplyWindowInsetsListener { _, insets ->
            @Suppress("DEPRECATION")
            setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop,
                insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            insets
        }
    }
    fun update(state: Map<String, Any?>) {
        val nfc = state["mode"] == "nfc"
        ring.nfc = nfc
        val recoveryStarted = state["recoveryStarted"] == true
        val remaining = (state[if(recoveryStarted) "recoveryRemainingMs" else "remainingMs"] as? Number)?.toLong() ?: 0
        val seconds = (remaining.coerceAtLeast(0) + 999) / 1000
        time.text = "%02d:%02d".format(java.util.Locale.ROOT, seconds / 60, seconds % 60)
        time.visibility = if (!nfc || recoveryStarted) VISIBLE else GONE
        timeLabel.visibility = time.visibility
        timeLabel.text = if(recoveryStarted) "recovery remaining" else "remaining"
        heading.text = if(nfc) "Phone lock is on" else "Time to focus"
        if (!scanning) explanation.text = if(nfc) "Scan a saved chip to unlock." else "Unlocks when your timer ends."
        scan.visibility = if(nfc) VISIBLE else GONE
        val total = (state["durationMs"] as? Number)?.toLong() ?: 0
        ring.fraction = if(nfc || total <= 0) 0f else (remaining.toFloat() / total).coerceIn(0f, 1f)
        ring.invalidate()
        recovery.isEnabled = !scanning
    }
    fun scanMessage(message: String?, active: Boolean) {
        scanning = active
        if(message != null) explanation.text = message
        scan.text = if(active) "Cancel scan" else "Scan NFC chip"
    }
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w,h,oldw,oldh)
        column.layoutParams = LayoutParams((w-paddingLeft-paddingRight).coerceAtMost(dp(560)), LayoutParams.WRAP_CONTENT, Gravity.CENTER)
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if(tone != "glass" && tone != "space") return
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.shader = RadialGradient(width*.9f, height*.4f, width.coerceAtLeast(1).toFloat(),
            Color.parseColor(if(tone=="space") "#20244A" else "#1C2939"), Color.TRANSPARENT, Shader.TileMode.CLAMP)
        canvas.drawRect(0f,0f,width.toFloat(),height.toFloat(),p)
    }
    private fun button(value: String, filled: Boolean, action: () -> Unit) = Button(context).apply {
        text = value; textSize = 16f; isAllCaps = false; minimumHeight = dp(50)
        typeface = regularFont
        setPadding(dp(18),dp(12),dp(18),dp(12)); setTextColor(if(filled) Color.parseColor(colors.first) else ink)
        background = GradientDrawable().apply {
            setColor(if(filled) accent else Color.TRANSPARENT); cornerRadius = dp(28).toFloat()
            if(!filled) setStroke(dp(1).coerceAtLeast(1), (ink and 0x00ffffff) or 0x55000000)
        }
        setOnClickListener { action() }
    }
    private fun label(value: String, size: Float, bold: Boolean = false) = TextView(context).apply {
        text=value; textSize=size; setTextColor(ink); gravity=Gravity.CENTER
        typeface=if(bold) boldFont else regularFont
        if(bold && android.os.Build.VERSION.SDK_INT>=28) isAccessibilityHeading=true
    }
    private fun row(top: Int) = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin=dp(top) }
    private fun dp(v:Int)=(v*resources.displayMetrics.density).toInt()
    private inner class Ring(context: Context): View(context) {
        var fraction=0f
        var nfc=false
        override fun onDraw(c:Canvas) {
            val s=minOf(width,height).toFloat(); val p=Paint(Paint.ANTI_ALIAS_FLAG).apply { style=Paint.Style.STROKE; strokeWidth=dp(8).toFloat(); strokeCap=Paint.Cap.ROUND }
            p.color=(accent and 0x00ffffff) or 0x44000000
            val r=RectF(dp(6).toFloat(),dp(6).toFloat(),s-dp(6),s-dp(6)); c.drawOval(r,p)
            p.color=accent; if(fraction>0) c.drawArc(r,-90f,fraction*360,false,p)
            p.strokeWidth=dp(2).toFloat()
            val center=s/2; val unit=s/8
            if(nfc) {
                val path=Path().apply {
                    moveTo(center-unit,center-unit*.6f); lineTo(center,center-unit*1.4f)
                    lineTo(center+unit,center-unit*.6f); lineTo(center+unit,center+unit*1.3f)
                    lineTo(center-unit,center+unit*1.3f); close()
                }
                c.drawPath(path,p)
                c.drawArc(RectF(center-unit*.72f,center,center+unit*.72f,center+unit*1.2f),215f,110f,false,p)
                c.drawArc(RectF(center-unit*.40f,center+unit*.35f,center+unit*.40f,center+unit*1.05f),215f,110f,false,p)
                p.style=Paint.Style.FILL; c.drawCircle(center,center+unit*.85f,dp(1).toFloat(),p)
                return
            }
            c.drawRoundRect(center-unit,center-unit*.2f,center+unit,center+unit*1.3f,dp(3).toFloat(),dp(3).toFloat(),p)
            c.drawArc(RectF(center-unit*.65f,center-unit*1.3f,center+unit*.65f,center+unit*.7f),180f,180f,false,p)
            c.drawLine(center,center+unit*.4f,center,center+unit*.7f,p)
        }
    }
}
