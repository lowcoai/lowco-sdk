package ai.lowco.engage

import org.junit.Assert.assertEquals
import org.junit.Test

class AttributionTest {
    @Test
    fun readsEveryKeyInOrder() {
        val url = "https://shop.example/landing?utm_source=google&utm_medium=cpc&utm_campaign=fall+sale" +
            "&utm_term=shoes&utm_content=ad%201&utm_id=42&gclid=g1&fbclid=f1&msclkid=m1&other=x"
        val found = attributionFromUrl(url)
        assertEquals(ATTRIBUTION_KEYS, found.keys.toList())
        assertEquals("fall sale", found["utm_campaign"])
        assertEquals("ad 1", found["utm_content"])
    }

    @Test
    fun readsTheFragmentQueryAndPrefersTheQueryString() {
        assertEquals(
            mapOf("utm_source" to "a", "gclid" to "g"),
            attributionFromUrl("myapp://open?utm_source=a#/promo?utm_source=b&gclid=g"),
        )
    }

    @Test
    fun skipsEmptyValuesBadEscapesAndKeepsTheFirstValue() {
        assertEquals(emptyMap<String, String>(), attributionFromUrl("myapp://open"))
        assertEquals(emptyMap<String, String>(), attributionFromUrl("myapp://open?utm_source=&x=1"))
        assertEquals(mapOf("utm_source" to "a"), attributionFromUrl("?utm_source=a&utm_source=b"))
        assertEquals(mapOf("gclid" to "g"), attributionFromUrl("?utm_source=%zz&gclid=g"))
    }
}
