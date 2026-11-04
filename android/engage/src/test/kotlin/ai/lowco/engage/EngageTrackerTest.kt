package ai.lowco.engage

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.IOException
import java.util.concurrent.Executor

class EngageTrackerTest {
    private class Sent(val url: String, val headers: Map<String, String>, val body: JSONObject)

    /** Records every request and answers with [respond]. */
    private class Recorder(var respond: (Sent) -> EngageResponse = { EngageResponse(202, "") }) : EngageTransport {
        val requests = mutableListOf<Sent>()

        override fun post(url: String, headers: Map<String, String>, body: ByteArray): EngageResponse {
            val sent = Sent(url, headers, JSONObject(String(body, Charsets.UTF_8)))
            requests += sent
            return respond(sent)
        }

        val last: Sent get() = requests.last()
    }

    private class Clock(var now: Long) : EngageClock {
        override fun nowMillis() = now
    }

    private val uuid = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    private val direct = Executor { it.run() }
    private val config = EngageConfig(apiKey = "key_secret", orgId = "org_1")

    private lateinit var rec: Recorder
    private lateinit var clock: Clock
    private lateinit var storage: InMemoryEngageStorage
    private lateinit var errors: MutableList<Throwable>

    @Before
    fun setUp() {
        rec = Recorder()
        clock = Clock(1_790_000_000_123L) // 2026-09-21T14:13:20.123Z
        storage = InMemoryEngageStorage()
        errors = mutableListOf()
    }

    private fun tracker(cfg: EngageConfig = config, store: EngageStorage = storage) =
        EngageTracker(cfg, store, null, rec, direct, clock, EngageErrorHandler { errors += it })

    @Test
    fun postsOneEventWithHeadersAndBody() {
        val t = tracker()
        t.track("signup_completed", mapOf("plan" to "pro", "seats" to 3))

        assertEquals(1, rec.requests.size)
        val sent = rec.last
        assertEquals("https://api.lowco.ai/v1/engage/track", sent.url)
        assertEquals(
            mapOf(
                "Content-Type" to "application/json",
                "Authorization" to "Bearer key_secret",
                "X-Org-Id" to "org_1",
            ),
            sent.headers,
        )
        val body = sent.body
        assertEquals("", body.getString("id"))
        assertEquals("signup_completed", body.getString("event_name"))
        assertEquals("pro", body.getJSONObject("event_data").getString("plan"))
        assertEquals(3, body.getJSONObject("event_data").getInt("seats"))
        assertFalse(body.has("user_id"))
        assertTrue(body.getString("device_id").matches(uuid))
        assertTrue(body.getString("session_id").matches(uuid))
        assertEquals("2026-09-21T14:13:20.123Z", body.getString("event_time"))
        assertTrue(errors.isEmpty())
    }

    @Test
    fun appIdIsSentAsEngageAppHeaderOnEveryEvent() {
        val t = tracker(EngageConfig(apiKey = "key_secret", orgId = "org_1", appId = " app_42 "))
        t.track("x")
        t.page()
        t.identifyUser("u1")
        assertEquals(listOf("app_42", "app_42", "app_42"), rec.requests.map { it.headers["X-Engage-App-Id"] })
    }

    @Test
    fun blankOrMissingAppIdMeansDefaultApp() {
        tracker(EngageConfig(apiKey = "k", orgId = "o", appId = "  ")).track("x")
        tracker(EngageConfig(apiKey = "k", orgId = "o")).track("y")
        assertTrue(rec.requests.none { "X-Engage-App-Id" in it.headers })
    }

    @Test
    fun lcApiKeyIsSentAsXApiKeyOnly() {
        tracker(EngageConfig(apiKey = " lc_secret ", orgId = "org_1", appId = "app_7")).track("x")
        assertEquals(
            mapOf(
                "Content-Type" to "application/json",
                "X-Api-Key" to "lc_secret",
                "X-Org-Id" to "org_1",
                "X-Engage-App-Id" to "app_7",
            ),
            rec.last.headers,
        )
    }

    @Test
    fun isApiKeyAndTrackHeaders() {
        assertTrue(isApiKey("lc_abc"))
        assertTrue(isApiKey("  lc_abc"))
        assertFalse(isApiKey("eyJhbGciOi.token"))
        assertFalse(isApiKey("LC_abc"))
        assertEquals(
            mapOf("Content-Type" to "application/json", "Authorization" to "Bearer tok", HEADER_ORG_ID to "o"),
            trackHeaders(EngageConfig(apiKey = "tok", orgId = "o")),
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun apiKeyIsRequired() {
        tracker(EngageConfig(apiKey = " ", orgId = "o"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun orgIdIsRequired() {
        tracker(EngageConfig(apiKey = "k", orgId = ""))
    }

    @Test
    fun configToStringRedactsTheKey() {
        val text = EngageConfig(apiKey = "lc_secret", orgId = "o", appId = "a").toString()
        assertFalse(text.contains("lc_secret"))
        assertTrue(text.contains("appId=a"))
    }

    @Test
    fun deviceIdAndSessionArePersistedAndRestored() {
        val first = tracker()
        first.track("a")
        val second = tracker()
        assertEquals(first.deviceId, second.deviceId)
        assertEquals(first.sessionId, second.sessionId)
        assertEquals(first.deviceId, storage.getString(DEVICE_ID_STORAGE_KEY))
    }

    @Test
    fun sessionRollsOverAfterThirtyMinutesOfInactivity() {
        val t = tracker()
        t.track("a")
        val session = t.sessionId
        clock.now += SESSION_TIMEOUT_MS
        t.track("b")
        assertEquals(session, t.sessionId)
        clock.now += SESSION_TIMEOUT_MS + 1
        t.track("c")
        assertNotEquals(session, t.sessionId)
        assertEquals(clock.now.toString(), storage.getString(SESSION_LAST_EVENT_STORAGE_KEY))
    }

    @Test
    fun expiredStoredSessionIsReplaced() {
        storage.setString(SESSION_ID_STORAGE_KEY, "old")
        storage.setString(SESSION_LAST_EVENT_STORAGE_KEY, (clock.now - SESSION_TIMEOUT_MS - 1).toString())
        assertNotEquals("old", tracker().sessionId)
    }

    @Test
    fun identifyUserIsRememberedUntilReset() {
        val t = tracker()
        t.identifyUser("user_42", mapOf("email" to "ada@example.com"))
        assertEquals("_lowco_identify", rec.last.body.getString("event_name"))
        assertEquals("user_42", rec.last.body.getString("user_id"))
        t.track("after")
        assertEquals("user_42", rec.last.body.getString("user_id"))
        val session = t.sessionId
        t.reset()
        assertNull(t.userId)
        assertNotEquals(session, t.sessionId)
        t.track("logged_out")
        assertFalse(rec.last.body.has("user_id"))
    }

    @Test
    fun pageAndScreenSendPageViews() {
        val t = tracker()
        t.page(mapOf("path" to "/pricing"))
        assertEquals("page_view", rec.last.body.getString("event_name"))
        t.screen("Checkout", mapOf("step" to 2))
        val data = rec.last.body.getJSONObject("event_data")
        assertEquals("page_view", rec.last.body.getString("event_name"))
        assertEquals("Checkout", data.getString("path"))
        assertEquals("Checkout", data.getString("title"))
        assertEquals(2, data.getInt("step"))
    }

    @Test
    fun deviceInfoAndLocationAreSent() {
        val t = tracker()
        t.deviceInfo = DeviceInfo(os = OsInfo("Android", "15"), device = DeviceDetails("mobile", "Google", "Pixel 9"))
        t.location = LocationInfo(latitude = 0.0, longitude = 77.59, altitudeAccuracy = 3.5)
        t.track("x")
        val body = rec.last.body
        assertEquals("Pixel 9", body.getJSONObject("device_info").getJSONObject("device").getString("model"))
        assertEquals(0.0, body.getJSONObject("location").getDouble("latitude"), 0.0)
        assertEquals(3.5, body.getJSONObject("location").getDouble("altitude_accuracy"), 0.0)
        assertFalse(body.getJSONObject("location").has("heading"))
    }

    @Test
    fun attributionIsMergedAndFirstTouchPersistedOnce() {
        val t = tracker()
        t.captureAttribution("myapp://promo?utm_source=newsletter&utm_campaign=fall")
        t.track("x", mapOf("utm_campaign" to "override"))
        val data = rec.last.body.getJSONObject("event_data")
        assertEquals("newsletter", data.getString("utm_source"))
        assertEquals("override", data.getString("utm_campaign"))
        val firstTouch = data.getJSONObject("first_touch")
        assertEquals("myapp://promo?utm_source=newsletter&utm_campaign=fall", firstTouch.getString("landing_url"))
        assertTrue(firstTouch.isNull("referrer"))
        assertEquals("2026-09-21T14:13:20.123Z", firstTouch.getString("captured_at"))

        t.captureAttribution("myapp://other?utm_source=ads")
        t.track("y")
        val later = rec.last.body.getJSONObject("event_data")
        assertEquals("ads", later.getString("utm_source"))
        assertFalse(later.has("utm_campaign"))
        assertEquals("newsletter", later.getJSONObject("first_touch").getString("utm_source"))

        val restored = tracker()
        assertEquals("newsletter", restored.currentFirstTouch?.get("utm_source"))
    }

    @Test
    fun unreadableFirstTouchIsReportedAndIgnored() {
        storage.setString(FIRST_TOUCH_STORAGE_KEY, "{not json")
        val t = tracker()
        assertNull(t.currentFirstTouch)
        assertEquals(1, errors.size)
    }

    @Test
    fun errorResponsesGoToOnError() {
        rec.respond = {
            EngageResponse(400, """{"status":0,"error":{"message":"AAS-00400","code":400,"details":"bad event_time"}}""")
        }
        tracker().track("x")
        val error = errors.single() as EngageException
        assertEquals(400, error.statusCode)
        assertEquals("bad event_time", error.message)

        errors.clear()
        rec.respond = { EngageResponse(502, "Bad Gateway") }
        tracker().track("x")
        assertEquals("Bad Gateway", errors.single().message)

        errors.clear()
        rec.respond = { EngageResponse(401, "") }
        tracker().track("x")
        assertEquals("engage: status=401", errors.single().message)
    }

    @Test
    fun transportFailuresGoToOnError() {
        rec.respond = { throw IOException("offline") }
        tracker().track("x")
        assertEquals("offline", errors.single().message)
    }

    @Test
    fun invalidEventsAreReportedAndNotSent() {
        val t = tracker()
        t.track(" ")
        t.identifyUser("")
        t.track("x", mapOf("bad" to Double.NaN))
        assertTrue(rec.requests.isEmpty())
        assertEquals(3, errors.size)
        assertNull(t.userId)
    }

    @Test
    fun aThrowingErrorHandlerDoesNotEscape() {
        rec.respond = { EngageResponse(500, "") }
        EngageTracker(config, storage, null, rec, direct, clock, EngageErrorHandler { error("boom") }).track("x")
    }

    @Test
    fun storageFailuresAreReported() {
        val broken = object : EngageStorage {
            override fun getString(key: String): String? = throw IllegalStateException("locked")
            override fun setString(key: String, value: String) = throw IllegalStateException("disk full")
            override fun remove(key: String) = Unit
        }
        val t = tracker(store = broken)
        t.track("x")
        assertEquals(1, rec.requests.size)
        assertTrue(errors.isNotEmpty())
    }
}
