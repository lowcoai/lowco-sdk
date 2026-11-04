package ai.lowco.engage

/** `device_info.browser` (WebView-based apps only). */
data class BrowserInfo @JvmOverloads constructor(
    val name: String? = null,
    val version: String? = null,
    val major: String? = null,
) {
    internal fun toJson(): Map<String, Any?> = compact("name" to name, "version" to version, "major" to major)
}

/** `device_info.os`. */
data class OsInfo @JvmOverloads constructor(
    val name: String? = null,
    val version: String? = null,
) {
    internal fun toJson(): Map<String, Any?> = compact("name" to name, "version" to version)
}

/** `device_info.device`. [type] is `mobile` or `tablet`. */
data class DeviceDetails @JvmOverloads constructor(
    val type: String? = null,
    val vendor: String? = null,
    val model: String? = null,
) {
    internal fun toJson(): Map<String, Any?> = compact("type" to type, "vendor" to vendor, "model" to model)
}

/** `device_info.cpu`. */
data class CpuInfo @JvmOverloads constructor(val architecture: String? = null) {
    internal fun toJson(): Map<String, Any?> = compact("architecture" to architecture)
}

/** `device_info.engine`. */
data class EngineInfo @JvmOverloads constructor(
    val name: String? = null,
    val version: String? = null,
) {
    internal fun toJson(): Map<String, Any?> = compact("name" to name, "version" to version)
}

/** Device description attached to every event (`DeviceInfo` in the TS SDK, same keys). */
data class DeviceInfo @JvmOverloads constructor(
    val browser: BrowserInfo? = null,
    val os: OsInfo? = null,
    val device: DeviceDetails? = null,
    val cpu: CpuInfo? = null,
    val engine: EngineInfo? = null,
    val ua: String? = null,
) {
    internal fun toJson(): Map<String, Any?> = compact(
        "browser" to browser?.toJson(),
        "os" to os?.toJson(),
        "device" to device?.toJson(),
        "cpu" to cpu?.toJson(),
        "engine" to engine?.toJson(),
        "ua" to ua,
    )
}

/**
 * Location attached to events. The SDK does not read the location itself:
 * pass coordinates from your location provider to [LowcoAnalytics.setLocation].
 * On the wire the keys are snake_case (`altitude_accuracy`), which is what the
 * engage ingest model reads.
 */
data class LocationInfo @JvmOverloads constructor(
    val latitude: Double? = null,
    val longitude: Double? = null,
    /** Metres. */
    val accuracy: Double? = null,
    val altitude: Double? = null,
    val altitudeAccuracy: Double? = null,
    /** Degrees clockwise from true north. */
    val heading: Double? = null,
    /** Metres per second. */
    val speed: Double? = null,
) {
    internal fun toJson(): Map<String, Any?> = compact(
        "latitude" to latitude,
        "longitude" to longitude,
        "accuracy" to accuracy,
        "altitude" to altitude,
        "altitude_accuracy" to altitudeAccuracy,
        "heading" to heading,
        "speed" to speed,
    )
}

/**
 * One tracked event, as POSTed to `/v1/engage/track` (`Event` in the TS SDK).
 * Empty optional fields are left out of the JSON.
 */
data class EngageEvent(
    val eventName: String,
    val eventData: Map<String, Any?>,
    val userId: String?,
    val deviceId: String,
    val sessionId: String?,
    val deviceInfo: DeviceInfo?,
    val location: LocationInfo?,
    /** Epoch milliseconds; sent like JavaScript's `toISOString()`. */
    val eventTime: Long,
) {
    internal fun toJson(): Map<String, Any?> = linkedMapOf<String, Any?>(
        "id" to "",
        "event_name" to eventName,
        "event_data" to eventData,
    ).apply {
        if (userId != null) put("user_id", userId)
        put("device_id", deviceId)
        if (sessionId != null) put("session_id", sessionId)
        deviceInfo?.let { put("device_info", it.toJson()) }
        location?.let { put("location", it.toJson()) }
        put("event_time", isoTimestamp(eventTime))
    }
}

/** Delivery failure passed to [EngageConfig.onError] for a non-2xx answer. */
class EngageException(
    val statusCode: Int,
    message: String,
    /** The raw response body, for debugging. */
    val body: String = "",
) : Exception(message.ifEmpty { "engage: status=$statusCode" })

private fun compact(vararg pairs: Pair<String, Any?>): Map<String, Any?> =
    linkedMapOf<String, Any?>().apply { for ((k, v) in pairs) if (v != null) put(k, v) }
