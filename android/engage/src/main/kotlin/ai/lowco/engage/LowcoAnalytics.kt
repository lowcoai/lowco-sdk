package ai.lowco.engage

import android.app.Application
import android.content.Context
import android.net.Uri
import android.util.Log

/**
 * Analytics for the lowco engage service: the process-wide client (the TS
 * SDK's default export).
 *
 * ```kotlin
 * class App : Application() {
 *     override fun onCreate() {
 *         super.onCreate()
 *         LowcoAnalytics.init(this, EngageConfig(apiKey = "lc_…", orgId = "org_123", appId = "app_123"))
 *     }
 * }
 *
 * LowcoAnalytics.track("signup_completed", mapOf("plan" to "pro"))
 * ```
 *
 * Every event is POSTed on its own to `https://api.lowco.ai/v1/engage/track`
 * from a background thread. Tracking is fire-and-forget: methods never throw,
 * failures go to [EngageConfig.onError] (or `Log.w` without one). Calls made
 * before [init] are dropped with a warning, except [captureAttribution], which
 * is applied when [init] runs.
 */
object LowcoAnalytics {
    private const val TAG = "LowcoAnalytics"

    @Volatile
    private var tracker: EngageTracker? = null
    private var autoTracker: ActivityAutoTracker? = null
    private var pendingAttributionUrl: String? = null

    /**
     * Configures the client and restores (or creates) the device id and the
     * session from [storage] (default: [SharedPreferencesEngageStorage]).
     * Call it from `Application.onCreate`. Calling it again reconfigures the
     * client; the user id set by [identifyUser] is kept.
     *
     * @throws IllegalArgumentException when [EngageConfig.apiKey] or
     *   [EngageConfig.orgId] is blank.
     */
    @JvmStatic
    @JvmOverloads
    fun init(context: Context, config: EngageConfig, storage: EngageStorage? = null) {
        val app = context.applicationContext
        val next = EngageTracker(
            config,
            storage ?: SharedPreferencesEngageStorage(app),
            detectDeviceInfo(app),
            HttpUrlConnectionTransport(),
            defaultExecutor(),
            EngageClock(System::currentTimeMillis),
            EngageErrorHandler { Log.w(TAG, "engage: $it") },
        )
        synchronized(this) {
            next.userId = tracker?.userId
            tracker = next
            autoTracker?.unregister()
            autoTracker = null
            if (config.autoTrack) {
                val application = app as? Application
                if (application == null) {
                    Log.w(TAG, "autoTrack needs an Application context; activities are not tracked")
                } else {
                    autoTracker = ActivityAutoTracker(application).also { it.register() }
                }
            }
            pendingAttributionUrl?.let(next::captureAttribution)
            pendingAttributionUrl = null
        }
    }

    /** Whether [init] has run. */
    @JvmStatic
    val isInitialized: Boolean
        get() = tracker != null

    /** The user id set by [identifyUser]. */
    @JvmStatic
    val userId: String?
        get() = tracker?.userId

    /** The persistent anonymous device id (`lowco_uuid`). */
    @JvmStatic
    val deviceId: String?
        get() = tracker?.deviceId

    /** The current session id (`lowco_session_id`). */
    @JvmStatic
    val sessionId: String?
        get() = tracker?.sessionId

    /** Sends a custom event; see [EngageTracker.track]. */
    @JvmStatic
    @JvmOverloads
    fun track(eventName: String, properties: Map<String, Any?>? = null) {
        current()?.track(eventName, properties)
    }

    /** Sends a `page_view` event. */
    @JvmStatic
    @JvmOverloads
    fun page(properties: Map<String, Any?>? = null) {
        current()?.page(properties)
    }

    /**
     * Sends a `page_view` for the screen [name]: use it for Compose / fragment
     * navigation, where activities do not change.
     */
    @JvmStatic
    @JvmOverloads
    fun screen(name: String, properties: Map<String, Any?>? = null) {
        current()?.screen(name, properties)
    }

    /** Remembers [userId] for every later event and sends `_lowco_identify`. */
    @JvmStatic
    @JvmOverloads
    fun identifyUser(userId: String, properties: Map<String, Any?>? = null) {
        current()?.identifyUser(userId, properties)
    }

    /**
     * Captures attribution from a deep link (`intent.data`); see
     * [EngageTracker.captureAttribution]. With `autoTrack` the launching deep
     * link is captured for you; call this from `onNewIntent` for links that
     * reach a running activity.
     */
    @JvmStatic
    fun captureAttribution(uri: Uri) = captureAttribution(uri.toString())

    /** Captures attribution from a URL string; see [EngageTracker.captureAttribution]. */
    @JvmStatic
    fun captureAttribution(url: String) {
        val current = synchronized(this) {
            tracker ?: run {
                pendingAttributionUrl = url
                return
            }
        }
        current.captureAttribution(url)
    }

    /** Sets (or clears) the location sent with later events. */
    @JvmStatic
    fun setLocation(location: LocationInfo?) {
        current()?.location = location
    }

    /** Replaces the detected `device_info`. */
    @JvmStatic
    fun setDeviceInfo(deviceInfo: DeviceInfo) {
        current()?.deviceInfo = deviceInfo
    }

    /** Logout: forgets the user id and starts a new session. */
    @JvmStatic
    fun reset() {
        current()?.reset()
    }

    private fun current(): EngageTracker? =
        tracker ?: run {
            Log.w(TAG, "LowcoAnalytics not initialized. Call init() first.")
            null
        }
}
