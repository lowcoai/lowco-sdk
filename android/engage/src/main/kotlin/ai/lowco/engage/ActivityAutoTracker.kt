package ai.lowco.engage

import android.app.Activity
import android.app.Application
import android.os.Bundle

/**
 * [EngageConfig.autoTrack]: a `page_view` for every resumed activity
 * (`{path: <class simple name>, title: <activity title or the class name>}`)
 * and attribution from the deep link that launched an activity.
 */
internal class ActivityAutoTracker(private val application: Application) :
    Application.ActivityLifecycleCallbacks {

    fun register() = application.registerActivityLifecycleCallbacks(this)

    fun unregister() = application.unregisterActivityLifecycleCallbacks(this)

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
        // A recreated activity (rotation, process restore) is not a new landing.
        if (savedInstanceState != null) return
        activity.intent?.data?.let { LowcoAnalytics.captureAttribution(it.toString()) }
    }

    override fun onActivityResumed(activity: Activity) {
        val name = activity.javaClass.simpleName
        val title = activity.title?.toString()?.takeIf { it.isNotBlank() } ?: name
        LowcoAnalytics.page(mapOf("path" to name, "title" to title))
    }

    override fun onActivityStarted(activity: Activity) = Unit

    override fun onActivityPaused(activity: Activity) = Unit

    override fun onActivityStopped(activity: Activity) = Unit

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

    override fun onActivityDestroyed(activity: Activity) = Unit
}
