@file:JvmName("Engage")

package ai.lowco.engage

/** The fixed API host every lowco SDK talks to. */
const val LOWCO_BASE_URL = "https://api.lowco.ai"

/** Path of the event ingestion endpoint. */
const val ENGAGE_TRACK_PATH = "/v1/engage/track"

/** Header carrying an `lc_` API key; other credentials travel as `Authorization: Bearer`. */
const val HEADER_API_KEY = "X-Api-Key"

/** Header carrying the organization id. */
const val HEADER_ORG_ID = "X-Org-Id"

/** Header selecting the engage app; absent means the org's default app. */
const val HEADER_ENGAGE_APP_ID = "X-Engage-App-Id"

/** Storage key of the persistent device (anonymous) id. */
const val DEVICE_ID_STORAGE_KEY = "lowco_uuid"

/** Storage key of the current session id. */
const val SESSION_ID_STORAGE_KEY = "lowco_session_id"

/** Storage key of the last event time (epoch milliseconds, as a string). */
const val SESSION_LAST_EVENT_STORAGE_KEY = "lowco_session_last_event"

/** Storage key of the first-touch attribution JSON. */
const val FIRST_TOUCH_STORAGE_KEY = "lowco_first_touch"

/** A session ends after this much inactivity (same as the browser SDK). */
const val SESSION_TIMEOUT_MS = 30L * 60 * 1000

/** Event name sent by `page` and `screen`. */
const val PAGE_VIEW_EVENT = "page_view"

/** Event name sent by `identifyUser`. */
const val IDENTIFY_EVENT = "_lowco_identify"

/** Whether [apiKey] is a Lowco API key (`lc_…`) rather than an access token. */
fun isApiKey(apiKey: String): Boolean = apiKey.trim().startsWith("lc_")

/**
 * The headers of a track request: the credential (`X-Api-Key` for an `lc_`
 * API key, otherwise `Authorization: Bearer`), `X-Org-Id`, and
 * `X-Engage-App-Id` when [EngageConfig.appId] is set.
 */
fun trackHeaders(config: EngageConfig): Map<String, String> {
    val apiKey = config.apiKey.trim()
    val headers = linkedMapOf("Content-Type" to "application/json")
    if (isApiKey(apiKey)) {
        headers[HEADER_API_KEY] = apiKey
    } else {
        headers["Authorization"] = "Bearer $apiKey"
    }
    headers[HEADER_ORG_ID] = config.orgId
    val appId = config.appId?.trim()
    if (!appId.isNullOrEmpty()) {
        headers[HEADER_ENGAGE_APP_ID] = appId
    }
    return headers
}
