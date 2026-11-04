# ai.lowco:engage (Android)

Android analytics SDK for the **lowco engage** service, the native counterpart of [`@lowcoai/engage`](../../npm/engage) and [`lowcoai_engage`](../../flutter/engage): custom events, page / screen views, sessions, deep-link attribution and device info, sent to `https://api.lowco.ai/v1/engage/track`. Kotlin, `minSdk` 21, no dependencies.

```kotlin
// build.gradle.kts
dependencies {
    implementation("ai.lowco:engage:0.1.0")
}
```

Until it is published, build it into your local Maven repository with `./gradlew publishToMavenLocal` (from this folder) and add `mavenLocal()` to your repositories, or include this folder with `includeBuild("path/to/lowco-sdk/android/engage")`.

The manifest declares `android.permission.INTERNET`, which merges into your app.

## Quick start

```kotlin
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        LowcoAnalytics.init(
            this,
            EngageConfig(
                apiKey = "lc_…",    // API key (sent as X-Api-Key) or an OAuth2 access token
                orgId = "org_123",  // required
                appId = "app_123",  // optional: omit to track into the org's default app
                autoTrack = true,   // page_view per resumed activity + launch deep-link attribution
            ),
        )
    }
}

LowcoAnalytics.track("signup_completed", mapOf("plan" to "pro"))
LowcoAnalytics.screen("Pricing") // Compose / fragment navigation
LowcoAnalytics.identifyUser("user_123", mapOf("email" to "alice@example.com"))
```

From Java every method is static: `LowcoAnalytics.track("signup_completed", Map.of("plan", "pro"));`.

## Config

| Field       | Description |
| ----------- | ----------- |
| `apiKey`    | Required; never logged (`toString()` redacts it). An `lc_…` API key is sent as `X-Api-Key`; any other value (an OAuth2 access token) as `Authorization: Bearer …`. |
| `orgId`     | Required. Sent as the `X-Org-Id` header. |
| `appId`     | Optional. The engage app to track into, sent as `X-Engage-App-Id`. `null` or blank: the org's default app. |
| `autoTrack` | A `page_view` for every resumed activity and attribution from the deep link that launched an activity. Default `false`. |
| `onError`   | Receives every delivery and storage error. Without it errors are logged with `Log.w`. |

`init` throws `IllegalArgumentException` for a blank `apiKey` or `orgId`. `init(context, config, storage)` also takes an `EngageStorage` (default `SharedPreferencesEngageStorage`, file `lowco_engage`). Calling `init` again reconfigures the client and keeps the identified user.

### Credentials and apps

- **API key** (`lc_…`, generated in the admin portal): pass it as `apiKey`. It travels as `X-Api-Key`, the header the gateway reads API keys from. A key built into an APK can be extracted by anyone who has the app.
- **Access token**: a signed-in user's OAuth2 token travels as `Authorization: Bearer`.
- **Apps**: an org can have several engage apps, each with its own events and users. Set `appId` (engage → Settings → Apps) to track into one; leave it out and events land in the org's default app.

`HEADER_API_KEY`, `HEADER_ORG_ID`, `HEADER_ENGAGE_APP_ID`, `isApiKey(apiKey)` and `trackHeaders(config)` are exported (Java: `Engage.isApiKey(...)`).

## API

| Method | Event / effect |
| ------ | -------------- |
| `init(context, config, storage?)` | Configure; restore the device id and session. |
| `track(eventName, properties?)` | Custom event. |
| `page(properties?)` | `page_view`. |
| `screen(name, properties?)` | `page_view` with `{path: name, title: name}`, the properties the Flutter route observer sends. |
| `identifyUser(userId, properties?)` | Remember `userId` for later events and send `_lowco_identify`. Kept in memory only, like the browser SDK. |
| `captureAttribution(uri)` | Read `utm_*`, `gclid`, `fbclid`, `msclkid` from a deep link (query string, or the query part of a `#/route?…` fragment). |
| `setLocation(location?)` | `location` for later events; the SDK never reads the location itself. |
| `setDeviceInfo(deviceInfo)` | Replace the detected `device_info`. |
| `reset()` | Logout: forget the user id and start a new session. |
| `userId`, `deviceId`, `sessionId`, `isInitialized` | Current state. |

Calls made before `init` are dropped with a warning, except `captureAttribution`, which is applied when `init` runs.

## Automatic tracking

With `autoTrack = true` the SDK registers `ActivityLifecycleCallbacks`:

- every resumed activity sends `page_view` with `{path: <activity class simple name>, title: <activity title, or the class name>}`. R8 renames classes in release builds, so give activities a title, or call `screen(name)` for stable names (and for Compose / fragment navigation, where the activity does not change);
- the `intent.data` of a newly created activity is passed to `captureAttribution`. For deep links that reach a running activity, call `LowcoAnalytics.captureAttribution(intent.data)` from `onNewIntent`.

## Sessions, ids and attribution

Same rules and storage keys as the browser SDK:

- the device id (`lowco_uuid`) is a random UUID created once and persisted;
- a session (`lowco_session_id`, `lowco_session_last_event`) ends after 30 minutes without events;
- attribution parameters are merged into every event's `event_data`; the first time any are seen they are persisted as `first_touch` (`landing_url`, `referrer`, `captured_at`) and never overwritten.

`device_info` is detected from `Build`: `os` (`Android` + release), `device` (`mobile` / `tablet` by smallest width ≥ 600dp, maker, model), `cpu.architecture` and `ua` (`Android 15 (Google Pixel 9)`).

## Delivery and errors

Each event is built on the calling thread and POSTed on its own from one background thread (so events leave in order) with `HttpURLConnection` and a 30-second timeout. Methods never throw: invalid events (blank names, non-finite numbers), non-2xx answers (`EngageException` with `statusCode`, `message` and the raw `body`), network failures and storage failures go to `onError`. Events are not queued on disk or retried.

`EngageTracker`, the client behind `LowcoAnalytics`, has no Android dependency: construct it directly with your own `EngageStorage`, `EngageTransport` and `Executor` for tests or non-Android JVM code.

## Development

```bash
./gradlew testDebugUnitTest    # needs an Android SDK (ANDROID_HOME or local.properties)
./gradlew assembleRelease publishToMavenLocal
```
