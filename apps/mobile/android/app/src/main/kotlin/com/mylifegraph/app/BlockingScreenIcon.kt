package com.mylifegraph.app

/** Fixed decorative symbols only; never user-provided HTML or downloaded assets. */
object BlockingScreenIcon {
    fun symbol(name: String): String = when (name) {
        "work" -> "▣"
        "games" -> "✥"
        "social" -> "◎"
        "sleep" -> "☾"
        "study" -> "▤"
        else -> "◇"
    }

    // Exact background/text tokens from AppVisualTokens. The native screen is
    // independent of Flutter; keep these pairs aligned when theme tokens change.
    fun colors(tone: String): Pair<String, String> = when (tone) {
        "light" -> "#F6F6F1" to "#15201C"
        "space" -> "#070814" to "#F6F3FF"
        "dark" -> "#08110F" to "#F2F6F3"
        else -> "#080A0E" to "#E5E9EF"
    }
}
