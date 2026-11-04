package ai.lowco.engage

/** Receives delivery and storage errors. Tracking never throws into the app. */
fun interface EngageErrorHandler {
    fun onError(error: Throwable)
}

/**
 * Configuration for [LowcoAnalytics.init] (`Config` in the TS SDK).
 *
 * @property apiKey Credential. Required; never logged. An `lc_…` API key is
 *   sent as `X-Api-Key`; anything else (an OAuth2 access token) as
 *   `Authorization: Bearer <apiKey>`.
 * @property orgId Organization id, sent as the `X-Org-Id` header. Required.
 * @property appId Engage app to track into, sent as `X-Engage-App-Id`.
 *   Optional: when `null` or blank, events go to the org's default app.
 * @property autoTrack Send a `page_view` for every resumed activity and
 *   capture attribution from the deep link that launched an activity.
 * @property onError Receives every delivery and storage error. Without it,
 *   [LowcoAnalytics] logs them with `Log.w`.
 */
class EngageConfig @JvmOverloads constructor(
    val apiKey: String,
    val orgId: String,
    val appId: String? = null,
    val autoTrack: Boolean = false,
    val onError: EngageErrorHandler? = null,
) {
    override fun toString(): String =
        "EngageConfig(orgId=$orgId, appId=$appId, autoTrack=$autoTrack, apiKey=<redacted>)"
}
