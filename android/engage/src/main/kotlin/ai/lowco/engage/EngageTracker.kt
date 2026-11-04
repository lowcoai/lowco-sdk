package ai.lowco.engage

import java.util.Collections
import java.util.UUID
import java.util.concurrent.Executor
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** One background thread that exits when idle, so events leave in order and nothing leaks. */
internal fun defaultExecutor(): Executor =
    ThreadPoolExecutor(1, 1, 30, TimeUnit.SECONDS, LinkedBlockingQueue()) { runnable ->
        Thread(runnable, "lowco-engage").apply { isDaemon = true }
    }.apply { allowCoreThreadTimeOut(true) }

/** Clock for event times and session expiry (epoch milliseconds). */
internal fun interface EngageClock {
    fun nowMillis(): Long
}

/**
 * The engage client behind [LowcoAnalytics], with no Android dependency.
 *
 * Construction restores (or creates) the device id, the session and the
 * first-touch attribution from [storage]. Every event is built on the calling
 * thread and POSTed on its own to `https://api.lowco.ai/v1/engage/track` from
 * [executor] (by default one background thread, so events leave in order).
 * Tracking is fire-and-forget: methods never throw, failures go to
 * [EngageConfig.onError]. Safe to call from any thread.
 *
 * @throws IllegalArgumentException when [EngageConfig.apiKey] or
 *   [EngageConfig.orgId] is blank.
 */
class EngageTracker internal constructor(
    val config: EngageConfig,
    private val storage: EngageStorage,
    deviceInfo: DeviceInfo?,
    private val transport: EngageTransport,
    private val executor: Executor,
    private val clock: EngageClock,
    private val fallbackOnError: EngageErrorHandler?,
) {
    @JvmOverloads
    constructor(
        config: EngageConfig,
        storage: EngageStorage = InMemoryEngageStorage(),
        deviceInfo: DeviceInfo? = null,
        transport: EngageTransport = HttpUrlConnectionTransport(),
        executor: Executor = defaultExecutor(),
    ) : this(config, storage, deviceInfo, transport, executor, EngageClock(System::currentTimeMillis), null)

    private val lock = Any()
    private val headers: Map<String, String>

    /** The persistent anonymous device id (`lowco_uuid`). */
    val deviceId: String

    /** The user id set by [identifyUser], sent with every later event. */
    var userId: String? = null
        get() = synchronized(lock) { field }
        internal set(value) = synchronized(lock) { field = value }

    /** The current session id (`lowco_session_id`). */
    var sessionId: String? = null
        get() = synchronized(lock) { field }
        private set

    private var lastEventTime: Long? = null

    /** The `device_info` sent with events. */
    var deviceInfo: DeviceInfo? = deviceInfo
        get() = synchronized(lock) { field }
        set(value) = synchronized(lock) { field = value }

    /** The `location` sent with events; the SDK never reads it itself. */
    var location: LocationInfo? = null
        get() = synchronized(lock) { field }
        set(value) = synchronized(lock) { field = value }

    private var attribution: Map<String, String> = emptyMap()
    private var firstTouch: Map<String, Any?>? = null

    init {
        require(config.apiKey.isNotBlank()) { "LowcoAnalytics: apiKey is required" }
        require(config.orgId.isNotBlank()) { "LowcoAnalytics: orgId is required" }
        headers = trackHeaders(config)
        deviceId = read(DEVICE_ID_STORAGE_KEY)?.takeIf { it.isNotEmpty() }
            ?: UUID.randomUUID().toString().also { write(DEVICE_ID_STORAGE_KEY, it) }
        initializeSession(read(SESSION_ID_STORAGE_KEY), read(SESSION_LAST_EVENT_STORAGE_KEY))
        firstTouch = read(FIRST_TOUCH_STORAGE_KEY)?.let(::decodeFirstTouch)
    }

    /** Attribution parameters from the last [captureAttribution] call. */
    val currentAttribution: Map<String, String>
        get() = synchronized(lock) { attribution }

    /** The persisted first-touch attribution, if any. */
    val currentFirstTouch: Map<String, Any?>?
        get() = synchronized(lock) { firstTouch }

    /**
     * Sends a custom event. [properties] are merged over the attribution
     * context (`utm_*`, click ids and `first_touch`) into `event_data`.
     */
    @JvmOverloads
    fun track(eventName: String, properties: Map<String, Any?>? = null) {
        if (eventName.isBlank()) {
            report(IllegalArgumentException("engage: eventName is required"))
            return
        }
        emit(eventName, properties)
    }

    /** Sends a `page_view` event. */
    @JvmOverloads
    fun page(properties: Map<String, Any?>? = null) = emit(PAGE_VIEW_EVENT, properties)

    /**
     * Sends a `page_view` for the screen [name] (`{path: name, title: name}`,
     * the properties the Flutter SDK's route observer sends), merged with
     * [properties].
     */
    @JvmOverloads
    fun screen(name: String, properties: Map<String, Any?>? = null) =
        emit(PAGE_VIEW_EVENT, mapOf<String, Any?>("path" to name, "title" to name) + properties.orEmpty())

    /**
     * Remembers [userId] for every later event and sends `_lowco_identify`
     * with [properties]. The id is kept in memory only (like the browser SDK):
     * call it again after the process restarts.
     */
    @JvmOverloads
    fun identifyUser(userId: String, properties: Map<String, Any?>? = null) {
        if (userId.isBlank()) {
            report(IllegalArgumentException("engage: userId is required"))
            return
        }
        emit(IDENTIFY_EVENT, properties, userId)
    }

    /**
     * Captures attribution from a deep link or web URL: `utm_source`,
     * `utm_medium`, `utm_campaign`, `utm_term`, `utm_content`, `utm_id`,
     * `gclid`, `fbclid` and `msclkid`.
     *
     * The parameters are added to every later event. The first time any are
     * seen they are also persisted as first-touch attribution
     * (`lowco_first_touch`, with `landing_url`, `referrer` and `captured_at`),
     * which is never overwritten.
     */
    fun captureAttribution(url: String) {
        val found = attributionFromUrl(url)
        val encoded = synchronized(lock) {
            attribution = found
            if (firstTouch != null || found.isEmpty()) return
            val captured = LinkedHashMap<String, Any?>(found).apply {
                put("landing_url", url)
                put("referrer", null)
                put("captured_at", isoTimestamp(clock.nowMillis()))
            }
            firstTouch = Collections.unmodifiableMap(captured)
            jsonEncode(captured)
        }
        write(FIRST_TOUCH_STORAGE_KEY, encoded)
    }

    /** Logout: forgets the user id and starts a new session. The device id and attribution are kept. */
    fun reset() {
        synchronized(lock) {
            userId = null
            startNewSession(clock.nowMillis())
        }
    }

    // --- Sessions (same rules as the browser SDK) ---------------------------

    private fun initializeSession(storedId: String?, storedLastEvent: String?) {
        val now = clock.nowMillis()
        val last = storedLastEvent?.trim()?.toDoubleOrNull()?.toLong()
        if (!storedId.isNullOrEmpty() && last != null && now - last <= SESSION_TIMEOUT_MS) {
            sessionId = storedId
            lastEventTime = last
            return
        }
        startNewSession(now)
    }

    private fun startNewSession(timestamp: Long) {
        sessionId = UUID.randomUUID().toString()
        lastEventTime = timestamp
        persistSession()
    }

    private fun ensureActiveSession(eventTimestamp: Long) {
        val last = lastEventTime
        if (sessionId == null || last == null || eventTimestamp - last > SESSION_TIMEOUT_MS) {
            startNewSession(eventTimestamp)
            return
        }
        lastEventTime = eventTimestamp
        persistSession()
    }

    private fun persistSession() {
        write(SESSION_ID_STORAGE_KEY, sessionId!!)
        write(SESSION_LAST_EVENT_STORAGE_KEY, lastEventTime.toString())
    }

    // --- Delivery -------------------------------------------------------------

    private fun emit(eventName: String, properties: Map<String, Any?>?, identifiedUser: String? = null) {
        val body = synchronized(lock) {
            if (identifiedUser != null) userId = identifiedUser
            val now = clock.nowMillis()
            ensureActiveSession(now)
            val data = LinkedHashMap<String, Any?>(attribution)
            firstTouch?.let { data["first_touch"] = it }
            properties?.let { data.putAll(it) }
            val event = EngageEvent(
                eventName = eventName,
                eventData = data,
                userId = userId,
                deviceId = deviceId,
                sessionId = sessionId,
                deviceInfo = deviceInfo,
                location = location,
                eventTime = now,
            )
            try {
                jsonEncode(event.toJson()).toByteArray(Charsets.UTF_8)
            } catch (e: IllegalArgumentException) {
                report(e)
                return
            }
        }
        try {
            executor.execute { deliver(body) }
        } catch (e: RejectedExecutionException) {
            report(e)
        }
    }

    private fun deliver(body: ByteArray) {
        try {
            val response = transport.post(TRACK_URL, headers, body)
            if (response.statusCode !in 200..299) throw httpError(response)
        } catch (e: Exception) {
            report(e)
        }
    }

    // --- Helpers --------------------------------------------------------------

    private fun decodeFirstTouch(raw: String): Map<String, Any?>? {
        if (raw.isEmpty()) return null
        val decoded = jsonDecodeObject(raw)
        if (decoded == null) report(IllegalStateException("engage: unreadable $FIRST_TOUCH_STORAGE_KEY"))
        return decoded?.let(Collections::unmodifiableMap)
    }

    private fun read(key: String): String? =
        try {
            storage.getString(key)
        } catch (e: Exception) {
            report(e)
            null
        }

    private fun write(key: String, value: String) {
        try {
            storage.setString(key, value)
        } catch (e: Exception) {
            report(e)
        }
    }

    private fun report(error: Throwable) {
        val handler = config.onError ?: fallbackOnError ?: return
        try {
            handler.onError(error)
        } catch (_: Throwable) {
            // A failing handler must not break tracking.
        }
    }

    private companion object {
        const val TRACK_URL = LOWCO_BASE_URL + ENGAGE_TRACK_PATH

        fun httpError(response: EngageResponse): EngageException {
            val text = response.body
            var message = text.trim()
            val parsed = jsonDecodeObject(text)
            if (parsed != null) {
                val error = parsed["error"]
                if (error is Map<*, *> && error["message"] is String) {
                    message = (error["message"] as String).trim()
                    val details = (error["details"] as? String)?.trim()
                    if (!details.isNullOrEmpty() && PLATFORM_CODE.matches(message)) message = details
                } else if (error is String && error.isNotEmpty()) {
                    message = error
                } else if (parsed["message"] is String) {
                    message = parsed["message"] as String
                }
            }
            return EngageException(response.statusCode, message, text)
        }

        /** Opaque platform error codes such as AAS-00105. */
        val PLATFORM_CODE = Regex("^[A-Z][A-Z0-9]*-\\d+$")
    }
}
