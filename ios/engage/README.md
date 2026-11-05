# LowcoEngage (iOS / macOS)

Swift client for the **Lowco Engage** event-tracking service: the native counterpart of the browser SDK [`@lowcoai/engage`](../../npm/engage), the Flutter SDK [`lowcoai_engage`](../../flutter/engage) and the [Android SDK](../../android/engage). Events are queued in memory and on disk and sent in batches to `POST https://api.lowco.ai/v1/engage/track/batch`. No dependencies outside Foundation.

- iOS 14+ and macOS 12+ (Mac Catalyst and iOS-on-Mac report as `Mac OS`). Swift 5.9+.
- Thread-safe: every method returns at once and may be called from any thread.
- Offline-friendly: up to 1000 events wait on disk and go out when the network is back.

## Install

The package lives in a subfolder of the `lowco-sdk` repository (`ios/engage`). Swift Package Manager only resolves a remote URL whose repository has a `Package.swift` at its root, so until a root manifest (or a split `lowco-engage-ios` repository) is published, add it as a **local package**:

- **Xcode**: clone `lowco-sdk` (or add it as a git submodule), then *File → Add Package Dependencies… → Add Local…* and pick `lowco-sdk/ios/engage`. Add the `LowcoEngage` library to your app target.
- **Package.swift**:

  ```swift
  dependencies: [
      .package(path: "../lowco-sdk/ios/engage"),
  ],
  targets: [
      .target(name: "MyApp", dependencies: [.product(name: "LowcoEngage", package: "LowcoEngage")]),
  ]
  ```

## Quick start

```swift
import LowcoEngage

// Once, at launch (e.g. in application(_:didFinishLaunchingWithOptions:) or your App's init).
LowcoEngage.shared.configure(
    apiKey: "lc_…",       // required: an API key, or an OAuth2 access token
    orgId: "org_123",     // required
    appId: "app_123"      // optional: omit to track into the org's default app
)

LowcoEngage.shared.track("signup_completed", properties: ["plan": "pro", "seats": 3])

// After login: later events carry the user id (also across launches).
LowcoEngage.shared.identify(userId: "user_42", traits: ["email": "ana@example.com", "plan": "pro"])

// A screen view (a page_view with path and title set to the name).
LowcoEngage.shared.screen("Checkout", properties: ["cart_value": 1299])

// Logout.
LowcoEngage.shared.reset()

// Send what is queued now (e.g. before a test ends); completion runs on the main queue.
LowcoEngage.shared.flush { print("sent") }
```

## API

| Call | Sends | Notes |
| ---- | ----- | ----- |
| `configure(apiKey:orgId:appId:baseURL:)` | — | `baseURL` defaults to `https://api.lowco.ai`. Blank `apiKey` / `orgId` leave the client unconfigured (logged). Calling it again replaces the configuration. |
| `configure(_ configuration:)` | — | Every option (below). |
| `track(_ name:, properties:)` | `name` | `properties` become `event_data`. |
| `identify(userId:traits:)` | `_lowco_identify` | Remembers the user for every later event, saved in `UserDefaults` until `reset()`. |
| `screen(_ name:, properties:)` | `page_view` | `event_data` `{path: name, title: name}` merged with `properties` (same as the Android and Flutter SDKs). |
| `reset(newDeviceId:)` | — | Forgets the user and starts a new session. The device id is kept (like the Flutter and Android SDKs); `newDeviceId: true` also starts a new anonymous id, for shared devices. |
| `flush(completion:)` | — | Sends everything queued, ignoring the retry backoff for the first batch. |
| `setLocation(_:)` / `setDeviceInfo(_:)` | — | The SDK never reads the location itself; pass coordinates you already have. |
| `userId`, `deviceId`, `sessionId`, `deviceInfo`, `queuedEventCount`, `isConfigured` | — | Current state. |

Property values may be strings, numbers, booleans, `Date` (sent as ISO-8601 UTC), `URL`, `UUID`, arrays and dictionaries of them; `nil`, NaN and infinity are sent as `null`, anything else as its description.

### Configuration

```swift
var config = LowcoEngage.Configuration(apiKey: "lc_…", orgId: "org_123", appId: "app_123")
config.flushInterval = 10        // seconds between automatic flushes
config.flushAt = 50              // batch size, and the queue length that triggers a flush (max 1000)
config.maxQueueSize = 1000       // events kept while offline; the oldest are dropped first
config.appVersion = "2.3.0"      // default: CFBundleShortVersionString
config.onError = { error in print(error) }  // delivery problems, on the SDK's queue
LowcoEngage.shared.configure(config)
```

Also: `baseURL`, `deviceInfo` (replace the detected one), `userDefaults` (default `.standard`), `storageDirectory` (default `Application Support/<bundle id>/lowco-engage`) and `urlSessionConfiguration` (proxies, or `protocolClasses` for tests).

### Credentials and apps

- **API key** (`lc_…`): sent as `X-Api-Key`.
- **Access token**: anything else is sent as `Authorization: Bearer <token>`.
- `X-Org-Id` always; `X-Engage-App-Id` only when `appId` is set (blank means the org's default app).

## What is sent

Each event has the same JSON shape as the Flutter SDK's:

```json
{
  "id": "",
  "event_name": "signup_completed",
  "event_data": {"plan": "pro", "app_version": "2.3.0"},
  "user_id": "user_42",
  "device_id": "0b6c…",
  "session_id": "5f1e…",
  "device_info": {
    "os": {"name": "iOS", "version": "17.2"},
    "device": {"type": "mobile", "vendor": "Apple", "model": "iPhone15,2"},
    "cpu": {"architecture": "arm64"},
    "engine": {"name": "LowcoEngage", "version": "0.1.0"},
    "ua": "LowcoEngage (iOS 17.2)"
  },
  "location": null,
  "event_time": "2026-09-30T12:34:56.789Z"
}
```

- `device_id` is a random UUID kept in `UserDefaults` (`lowco_uuid`).
- `session_id` (`lowco_session_id`, `lowco_session_last_event`) changes after 30 minutes without an event, like every Lowco SDK.
- `app_version` goes in `event_data`, where the service reads an event's app version; the service derives the platform (`ios`, or `desktop` for macOS) from `device_info.os.name`.
- `device.type` is `tablet` for iPads, `mobile` for iPhones, `desktop` on a Mac.

## Queue, batching and retries

- Events are kept in memory and in a JSON file per org and app (excluded from iCloud backup), so they survive a restart.
- A batch of up to 50 events is sent every 10 seconds, as soon as 50 are waiting, when the app goes to the background (`UIApplication.didEnterBackgroundNotification`; `NSApplication.willResignActiveNotification` on macOS), and on `flush()`. One request is in flight at a time.
- The service answers per event: accepted events are removed, events it refused (no name, breaking a strict event definition) are dropped and reported to `onError`, and events it could not queue for a moment ("send it again") stay queued.
- Network errors, `408`, `429` and `5xx` keep the batch and back off exponentially: 2 s, 4 s, 8 s … up to 5 minutes (±20% jitter; a `Retry-After` header is honoured). Any other `4xx` drops the batch (it would never succeed) and is reported.
- When the queue holds more than `maxQueueSize` events the oldest are dropped.

Sending uses a regular `URLSession`; a request still running when iOS suspends the app finishes when it is resumed, and its events stay on disk until then.

## Privacy

- The SDK sends only what you track plus the device id, session id, `device_info` and app version. It never reads the location, the advertising identifier (IDFA) or contacts, and does not track across apps.
- The package ships a privacy manifest (`PrivacyInfo.xcprivacy`) declaring `UserDefaults` access (reason `CA92.1`) and the device ID, user ID and product-interaction data it collects for analytics, not tracking. Review it against what your app tracks and add anything else (for example email in `identify` traits) to your app's manifest.
- `reset()` on logout stops later events from carrying the user id; `reset(newDeviceId: true)` also starts a new anonymous id.

## Development

```bash
cd ios/engage
swift build
swift test
```

Tests use a `URLProtocol` stub and an injected clock; no network is needed.
