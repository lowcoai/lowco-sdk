@file:JvmName("Attribution")

package ai.lowco.engage

import java.net.URLDecoder

/** Query parameters captured as attribution (same order as the browser SDK). */
val ATTRIBUTION_KEYS: List<String> = listOf(
    "utm_source",
    "utm_medium",
    "utm_campaign",
    "utm_term",
    "utm_content",
    "utm_id",
    "gclid",
    "fbclid",
    "msclkid",
)

/**
 * Extracts the [ATTRIBUTION_KEYS] from [url]'s query string and from the query
 * part of its fragment (`myapp://open#/promo?utm_source=x`). Empty values are
 * skipped, the first value of a repeated key wins, and the query string wins
 * over the fragment.
 */
fun attributionFromUrl(url: String): Map<String, String> {
    val hash = url.indexOf('#')
    val beforeHash = if (hash >= 0) url.substring(0, hash) else url
    val fragment = if (hash >= 0) url.substring(hash + 1) else ""
    val query = parseQuery(beforeHash.substringAfter('?', ""))
    val fragmentQuery = parseQuery(fragment.substringAfter('?', ""))
    val out = linkedMapOf<String, String>()
    for (key in ATTRIBUTION_KEYS) {
        val value = (query[key] ?: fragmentQuery[key])?.firstOrNull()
        if (!value.isNullOrEmpty()) out[key] = value
    }
    return out
}

private fun parseQuery(query: String): Map<String, List<String>> {
    val out = linkedMapOf<String, MutableList<String>>()
    if (query.isEmpty()) return out
    for (pair in query.split('&')) {
        if (pair.isEmpty()) continue
        val eq = pair.indexOf('=')
        val key = decode(if (eq >= 0) pair.substring(0, eq) else pair) ?: continue
        val value = decode(if (eq >= 0) pair.substring(eq + 1) else "") ?: continue
        out.getOrPut(key) { mutableListOf() }.add(value)
    }
    return out
}

private fun decode(s: String): String? =
    try {
        @Suppress("DEPRECATION") // URLDecoder.decode(String, Charset) needs API 33.
        URLDecoder.decode(s, "UTF-8")
    } catch (_: IllegalArgumentException) {
        null
    }
