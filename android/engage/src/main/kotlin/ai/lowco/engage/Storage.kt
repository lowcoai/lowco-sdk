package ai.lowco.engage

import java.util.concurrent.ConcurrentHashMap

/**
 * Key/value persistence for the device id, the session and first-touch
 * attribution. The keys are the browser SDK's `localStorage` keys:
 * `lowco_uuid`, `lowco_session_id`, `lowco_session_last_event` and
 * `lowco_first_touch`.
 */
interface EngageStorage {
    /** Returns the stored value for [key], or `null` when absent. */
    fun getString(key: String): String?

    /** Stores [value] under [key]. */
    fun setString(key: String, value: String)

    /** Removes [key]. */
    fun remove(key: String)
}

/** Storage that lives as long as the process (tests, or no persistence wanted). */
class InMemoryEngageStorage : EngageStorage {
    private val values = ConcurrentHashMap<String, String>()

    override fun getString(key: String): String? = values[key]

    override fun setString(key: String, value: String) {
        values[key] = value
    }

    override fun remove(key: String) {
        values.remove(key)
    }
}
