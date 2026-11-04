package ai.lowco.engage

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Date

class JsonTest {
    @Test
    fun encodesLikeJsonStringify() {
        val value = linkedMapOf(
            "s" to "café \"q\" \\ \n\t\u0001</b>",
            "n" to 3,
            "l" to 9_007_199_254_740_993L,
            "d" to 1.5,
            "b" to true,
            "nil" to null,
            "list" to listOf(1, "a", null),
            "nested" to mapOf("k" to arrayOf(false)),
            "at" to Date(0),
        )
        assertEquals(
            """{"s":"café \"q\" \\ \n\t\u0001</b>","n":3,"l":9007199254740993,"d":1.5,"b":true,"nil":null,""" +
                """"list":[1,"a",null],"nested":{"k":[false]},"at":"1970-01-01T00:00:00.000Z"}""",
            jsonEncode(value),
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsNonFiniteNumbers() {
        jsonEncode(mapOf("x" to Double.POSITIVE_INFINITY))
    }

    @Test
    fun isoTimestampTruncatesToMilliseconds() {
        assertEquals("2026-01-02T03:04:05.678Z", isoTimestamp(1_767_323_045_678L))
    }

    @Test
    fun decodesObjectsOnly() {
        assertEquals(mapOf("a" to listOf(1, null), "b" to mapOf("c" to "d")), jsonDecodeObject("""{"a":[1,null],"b":{"c":"d"}}"""))
        assertNull(jsonDecodeObject("[1]"))
        assertNull(jsonDecodeObject("nope"))
    }
}
