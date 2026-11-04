package ai.lowco.engage

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * ISO-8601 UTC with millisecond precision, like JavaScript's
 * `Date.prototype.toISOString()` (`2026-01-02T03:04:05.678Z`).
 */
internal fun isoTimestamp(epochMillis: Long): String =
    SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        .apply { timeZone = TimeZone.getTimeZone("UTC") }
        .format(Date(epochMillis))

/**
 * Compact JSON like `JSON.stringify`. Maps, iterables, arrays, strings,
 * numbers, booleans and null are encoded as such; a [Date] as an ISO string;
 * anything else as its `toString()`. A non-finite number throws
 * [IllegalArgumentException].
 */
internal fun jsonEncode(value: Any?): String = StringBuilder().also { writeJson(it, value) }.toString()

private fun writeJson(out: StringBuilder, value: Any?) {
    when (value) {
        null -> out.append("null")
        is String -> writeString(out, value)
        is Boolean -> out.append(value)
        is Double -> writeFloating(out, value)
        is Float -> writeFloating(out, value.toDouble())
        is Number -> out.append(value.toString())
        is Date -> writeString(out, isoTimestamp(value.time))
        is Map<*, *> -> {
            out.append('{')
            var first = true
            for ((k, v) in value) {
                if (!first) out.append(',')
                first = false
                writeString(out, k.toString())
                out.append(':')
                writeJson(out, v)
            }
            out.append('}')
        }
        is Iterable<*> -> writeArray(out, value.iterator())
        is Array<*> -> writeArray(out, value.iterator())
        is IntArray -> writeArray(out, value.iterator())
        is LongArray -> writeArray(out, value.iterator())
        is DoubleArray -> writeArray(out, value.iterator())
        is BooleanArray -> writeArray(out, value.iterator())
        is Enum<*> -> writeString(out, value.name)
        else -> writeString(out, value.toString())
    }
}

private fun writeFloating(out: StringBuilder, value: Double) {
    require(value.isFinite()) { "engage: $value is not valid JSON" }
    out.append(value.toString())
}

private fun writeArray(out: StringBuilder, items: Iterator<*>) {
    out.append('[')
    var first = true
    for (item in items) {
        if (!first) out.append(',')
        first = false
        writeJson(out, item)
    }
    out.append(']')
}

private fun writeString(out: StringBuilder, s: String) {
    out.append('"')
    for (c in s) {
        when (c) {
            '"' -> out.append("\\\"")
            '\\' -> out.append("\\\\")
            '\n' -> out.append("\\n")
            '\r' -> out.append("\\r")
            '\t' -> out.append("\\t")
            '\b' -> out.append("\\b")
            '\u000C' -> out.append("\\f")
            else -> if (c < ' ') out.append(String.format(Locale.US, "\\u%04x", c.code)) else out.append(c)
        }
    }
    out.append('"')
}

/** Decodes a JSON object, or returns `null` when [text] is not one. */
@Suppress("UNCHECKED_CAST")
internal fun jsonDecodeObject(text: String): Map<String, Any?>? =
    try {
        fromJson(JSONObject(text)) as Map<String, Any?>?
    } catch (_: JSONException) {
        null
    }

private fun fromJson(value: Any?): Any? = when {
    value == null || value == JSONObject.NULL -> null
    value is JSONObject -> linkedMapOf<String, Any?>().apply {
        val keys = value.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            put(key, fromJson(value.get(key)))
        }
    }
    value is JSONArray -> (0 until value.length()).map { fromJson(value.get(it)) }
    else -> value
}
