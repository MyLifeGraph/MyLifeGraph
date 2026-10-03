package com.mylifegraph.app

/** Fixed 24-unit outline artwork. Native and offline renderers share these paths;
 * no font glyphs, user-provided markup, remote assets or new dependencies.
 */
object BlockingScreenIcon {
    fun paths(name: String): List<String> = when (name) {
        "work" -> listOf(
            "M8 6V4Q8 3 9 3H15Q16 3 16 4V6",
            "M4 6H20Q21 6 21 7V19Q21 20 20 20H4Q3 20 3 19V7Q3 6 4 6Z",
            "M3 11Q12 17 21 11M12 12V15",
        )
        "games" -> listOf(
            "M6 7H18Q21 7 22 17Q22 21 19 20L16 17H8L5 20Q2 21 2 17Q3 7 6 7Z",
            "M7 10V14M5 12H9M16 11H16.1M18 13H18.1",
        )
        "social" -> listOf(
            "M21 11Q21 18 12 18Q9 18 7 17L3 21V15Q2 13 2 11Q2 4 12 4Q21 4 21 11Z",
            "M7 10H17M7 13H14",
        )
        "sleep" -> listOf("M20.9 13.1A9 9 0 1 1 10.9 3.1A7 7 0 0 0 20.9 13.1Z")
        "study" -> listOf(
            "M2 9L12 4L22 9L12 14Z",
            "M6 11V17Q12 21 18 17V11M22 9V16",
        )
        else -> listOf("M12 3L21 7V12Q21 18 12 22Q3 18 3 12V7Z")
    }

    // All interpolated markup is fixed artwork, never the supplied icon name.
    fun svg(name: String): String = "<svg xmlns=\"http://www.w3.org/2000/svg\" " +
        "width=\"48\" height=\"48\" viewBox=\"0 0 24 24\" fill=\"none\" " +
        "stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" " +
        "stroke-linejoin=\"round\" aria-hidden=\"true\">" +
        paths(name).joinToString("") { "<path d=\"$it\"/>" } + "</svg>"

    // Exact background/text tokens from AppVisualTokens. The native screen is
    // independent of Flutter; keep these pairs aligned when theme tokens change.
    fun colors(tone: String): Pair<String, String> = when (tone) {
        "light" -> "#F6F6F1" to "#15201C"
        "space" -> "#070814" to "#F6F3FF"
        "dark" -> "#08110F" to "#F2F6F3"
        else -> "#080A0E" to "#E5E9EF"
    }
}
