package ai.lowco.engage

import android.content.Context
import android.content.SharedPreferences

/** Default storage: a private [SharedPreferences] file (`lowco_engage`). */
class SharedPreferencesEngageStorage @JvmOverloads constructor(
    context: Context,
    name: String = DEFAULT_NAME,
) : EngageStorage {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(name, Context.MODE_PRIVATE)

    override fun getString(key: String): String? = prefs.getString(key, null)

    override fun setString(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }

    override fun remove(key: String) {
        prefs.edit().remove(key).apply()
    }

    companion object {
        /** Name of the preferences file. */
        const val DEFAULT_NAME = "lowco_engage"
    }
}
