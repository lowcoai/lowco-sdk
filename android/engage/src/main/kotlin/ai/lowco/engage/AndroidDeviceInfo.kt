package ai.lowco.engage

import android.content.Context
import android.os.Build

/**
 * The `device_info` of this device: OS release, maker and model, `mobile` or
 * `tablet` (smallest width of 600dp or more), and the CPU architecture.
 */
internal fun detectDeviceInfo(context: Context): DeviceInfo {
    val release = Build.VERSION.RELEASE
    val vendor = Build.MANUFACTURER
    val model = Build.MODEL
    val tablet = context.resources.configuration.smallestScreenWidthDp >= 600
    return DeviceInfo(
        os = OsInfo(name = "Android", version = release),
        device = DeviceDetails(type = if (tablet) "tablet" else "mobile", vendor = vendor, model = model),
        cpu = CpuInfo(architecture = System.getProperty("os.arch")),
        ua = "Android $release ($vendor $model)",
    )
}
