package com.mylifegraph.app

import android.animation.ValueAnimator
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONObject
import androidx.core.graphics.PathParser
import kotlin.math.max

/** The same native rendering for the Accessibility overlay and read-only preview.
 * Callers own all persisted authority, return deadlines and emergency release gates.
 */
class BlockingScreenView(
    context: Context,
    private val custom: JSONObject,
    counters: JSONObject,
    summary: String,
    strictLocked: Boolean,
    onReturn: () -> Unit,
    private val emergency: View? = null,
) : FrameLayout(context) {
    private val tone = custom.optString("tone", "glass")
    private val colors = BlockingScreenIcon.colors(tone)
    private val backgroundColor = Color.parseColor(colors.first)
    private val textColor = Color.parseColor(colors.second)
    private val spacing = when (custom.optString("layout", "balanced")) {
        "compact" -> .7f
        "spacious" -> 1.3f
        else -> 1f
    }
    private val accentColor = Color.parseColor(when (custom.optString("accent", "theme")) {
        "mint" -> if (tone == "light") "#226A55" else "#82CBB4"
        "blue" -> if (tone == "light") "#315E8A" else "#90B7E7"
        "violet" -> if (tone == "light") "#65508F" else "#B2A3EA"
        "rose" -> if (tone == "light") "#894760" else "#DD9EB3"
        else -> colors.second
    })
    private val content = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        setPadding(dp(24), dp(32), dp(24), dp(32))
    }
    private val summaryText = text(summary, 24f, true)
    private val strictText = text("Discipline mode", 14f)
    private val returnButton = ReturnProgressButton(context)
    private var disposed = false

    init {
        setBackgroundColor(backgroundColor)
        setWillNotDraw(false)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        setOnApplyWindowInsetsListener { _, insets ->
            @Suppress("DEPRECATION")
            if (Build.VERSION.SDK_INT >= 30) {
                val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
                setPadding(bars.left, bars.top, bars.right, bars.bottom)
            } else if (Build.VERSION.SDK_INT >= 28) {
                val cutout = insets.displayCutout
                setPadding(
                    max(insets.systemWindowInsetLeft, cutout?.safeInsetLeft ?: 0),
                    max(insets.systemWindowInsetTop, cutout?.safeInsetTop ?: 0),
                    max(insets.systemWindowInsetRight, cutout?.safeInsetRight ?: 0),
                    max(insets.systemWindowInsetBottom, cutout?.safeInsetBottom ?: 0),
                )
            } else {
                setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop,
                    insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            }
            if (width > 0) updateContentWidth(width)
            insets
        }
        val scroll = ScrollView(context).apply { isFillViewport = true }
        val center = FrameLayout(context)
        center.addView(content, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        scroll.addView(center, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        content.addView(OutlineIconView(context, custom.optString("icon", "shield")).apply {
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(dp(48), dp(48)))
        content.addView(text(custom.optString("title", "Stay focused"), 30f, true), row(12))
        content.addView(text(custom.optString("message", "Take a breath. Choose your next step."), 18f), row(16))
        content.addView(summaryText, row(24))
        content.addView(strictText, row(8))
        returnButton.apply {
            isEnabled = false
            text = "Return to MyLifeGraph"
            setOnClickListener { if (!disposed && isEnabled) onReturn() }
        }
        content.addView(returnButton, row(24))
        val today = counters.optLong("today", counters.optLong("attemptsToday")).coerceAtLeast(0)
        val total = counters.optLong("total", counters.optLong("attemptsTotal")).coerceAtLeast(0)
        content.addView(text("$today today · $total total", 15f), row(16))
        emergency?.let {
            if (it is TextView) {
                it.setTextColor(textColor)
                it.textSize = 16f
                it.gravity = Gravity.CENTER
                it.setPadding(dp(16), dp(12), dp(16), dp(12))
                it.minimumHeight = dp(48)
                if (it is Button) it.isAllCaps = false
                it.background = GradientDrawable().apply {
                    setColor(backgroundColor)
                    cornerRadius = dp(24).toFloat()
                    setStroke(dp(1).coerceAtLeast(1), textColor)
                }
            }
            content.addView(it, row(16))
        }
        content.addView(text("Settings, phone, alarms, and essential Android functions remain available.", 15f), row(24))
        updateStrictLocked(strictLocked)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        updateContentWidth(w)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        requestApplyInsets()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        // Small stationary light pools only. Native Android has no Flutter glass compositor.
        if (tone != "glass" && tone != "space") return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val radius = minOf(width * .75f, dp(360).toFloat())
        if (radius <= 0) return
        val light = if (tone == "space") Color.parseColor("#20244A") else Color.parseColor("#141A22")
        paint.shader = RadialGradient(width * .15f, height * .15f, radius, light, Color.TRANSPARENT, Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        paint.shader = RadialGradient(width * .9f, height * .8f, radius * .75f, light, Color.TRANSPARENT, Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
    }

    fun updateSummary(value: String) {
        summaryText.text = value
    }

    fun updateStrictLocked(locked: Boolean) {
        strictText.visibility = if (locked) VISIBLE else GONE
        emergency?.let {
            if (locked) {
                it.isEnabled = false
                it.clearFocus()
                it.visibility = GONE
                (it.parent as? ViewGroup)?.removeView(it)
            } else {
                it.isEnabled = true
                it.visibility = VISIBLE
                if (it.parent == null) content.addView(it, content.childCount - 1, row(16))
            }
        }
    }

    fun updateReturn(remainingMs: Long, totalMs: Long) {
        if (disposed) return
        val remaining = remainingMs.coerceAtLeast(0)
        val seconds = (remaining + 999L) / 1000L
        returnButton.isEnabled = remaining == 0L
        returnButton.text = if (seconds > 0) "Return in ${duration(seconds)}" else "Return to MyLifeGraph"
        returnButton.progress(if (totalMs <= 0) 1f else (1.0 - remaining.toDouble() / totalMs).toFloat().coerceIn(0f, 1f))
    }

    fun dispose() {
        disposed = true
        returnButton.stopAnimation()
        returnButton.setOnClickListener(null)
    }

    override fun onDetachedFromWindow() {
        returnButton.stopAnimation()
        super.onDetachedFromWindow()
    }

    private fun duration(seconds: Long): String = when {
        seconds < 60 -> "${seconds}s"
        seconds % 60 == 0L -> "${seconds / 60}m"
        else -> "${seconds / 60}m ${seconds % 60}s"
    }

    private fun text(value: String, size: Float, heading: Boolean = false) = TextView(context).apply {
        text = value
        textSize = size
        gravity = Gravity.CENTER
        setTextColor(textColor)
        if (heading) {
            setTypeface(typeface, Typeface.BOLD)
            if (Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
        }
    }

    private fun row(top: Int = 0) = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
    ).apply { topMargin = (dp(top) * spacing).toInt() }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    private fun updateContentWidth(availableWidth: Int) {
        val width = (availableWidth - paddingLeft - paddingRight).coerceAtLeast(0).coerceAtMost(dp(560))
        if (content.layoutParams.width != width) {
            content.layoutParams = LayoutParams(width, LayoutParams.WRAP_CONTENT, Gravity.CENTER)
        }
    }

    private inner class OutlineIconView(context: Context, name: String) : View(context) {
        private val paths = BlockingScreenIcon.paths(name).map { PathParser.createPathFromPathData(it) }
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = accentColor
            style = Paint.Style.STROKE
            strokeWidth = 1.75f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val size = minOf(width, height).toFloat()
            val save = canvas.save()
            canvas.translate((width - size) / 2f, (height - size) / 2f)
            canvas.scale(size / 24f, size / 24f)
            paths.forEach { path -> if (path != null) canvas.drawPath(path, paint) }
            canvas.restoreToCount(save)
        }
    }

    private inner class ReturnProgressButton(context: Context) : Button(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private var fraction = 0f
        private var animator: ValueAnimator? = null
        private var initialized = false
        private val surface = Color.parseColor(when (tone) {
            "light" -> "#E7ECE7"
            "dark" -> "#1A2924"
            "space" -> "#20244A"
            else -> "#10141B"
        })
        private val fill = if (custom.optString("accent", "theme") != "theme")
            Color.argb(65, Color.red(accentColor), Color.green(accentColor), Color.blue(accentColor))
        else Color.parseColor(when (tone) {
            "light" -> "#D9F3EA"
            "dark" -> "#173B32"
            "space" -> "#292E5C"
            else -> "#26313F"
        })

        init {
            background = null
            minimumHeight = dp(60)
            minHeight = dp(60)
            textSize = 18f
            isAllCaps = false
            gravity = Gravity.CENTER
            setTextColor(textColor)
            setPadding(dp(24), dp(16), dp(24), dp(16))
        }

        fun progress(value: Float) {
            if (value == fraction && animator == null) return
            stopAnimation()
            // Readiness is exact and immediately visible. It cannot retain a
            // trailing interpolated fill or start an animation from 1 to 1.
            if (value <= 0f || value >= 1f) {
                fraction = value
                initialized = true
                invalidate()
                return
            }
            val scale = runCatching {
                Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
            }.getOrDefault(0f)
            if (!initialized || scale <= 0f || !isAttachedToWindow) {
                fraction = value
                initialized = true
                invalidate()
                return
            }
            animator = ValueAnimator.ofFloat(fraction, value).apply {
                // ValueAnimator itself applies the system duration scale.
                duration = 180L
                addUpdateListener { fraction = it.animatedValue as Float; invalidate() }
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        if (animator === animation) {
                            animator = null
                            fraction = value
                            invalidate()
                        }
                    }
                })
                start()
            }
        }

        fun stopAnimation() {
            val previous = animator
            animator = null
            previous?.removeAllListeners()
            previous?.removeAllUpdateListeners()
            previous?.cancel()
        }

        override fun onDraw(canvas: Canvas) {
            val rect = RectF(1f, 1f, width - 1f, height - 1f)
            val radius = height / 2f
            val path = Path().apply { addRoundRect(rect, radius, radius, Path.Direction.CW) }
            val save = canvas.save()
            canvas.clipPath(path)
            paint.style = Paint.Style.FILL
            paint.color = surface
            canvas.drawRect(rect, paint)
            paint.color = fill
            canvas.drawRect(0f, 0f, width * fraction, height.toFloat(), paint)
            canvas.restoreToCount(save)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = max(1f, resources.displayMetrics.density * if (isFocused) 2f else 1f)
            paint.color = textColor
            paint.alpha = if (isFocused) 255 else if (isPressed) 140 else 80
            canvas.drawRoundRect(rect, radius, radius, paint)
            paint.alpha = 255
            paint.style = Paint.Style.FILL
            super.onDraw(canvas)
        }
    }
}
