# lowcoai_engage

Flutter analytics SDK for the **lowco engage** service — the app counterpart of the `@lowcoai/engage` browser SDK. Tracks custom events, page views, sessions, attribution and device info from iOS, Android, web and desktop apps, and sends them to `https://api.lowco.ai/v1/engage/track` with the same payload as the browser SDK.

```yaml
dependencies:
  lowcoai_engage: ^0.1.0
```

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:lowcoai_engage/lowcoai_engage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LowcoAnalytics.instance.init(
    // apiKey: the app's write key (engage → Settings → Apps).
    EngageConfig(apiKey: 'ewk_…', onError: (e) => debugPrint('$e')),
  );
  runApp(
    MaterialApp(
      navigatorObservers: [LowcoAnalyticsObserver()], // page_view per named route
      routes: {'/': (_) => const HomePage(), '/pricing': (_) => const PricingPage()},
    ),
  );
}

// Anywhere in the app:
LowcoAnalytics.instance.track('signup_completed', {'plan': 'pro'});
LowcoAnalytics.instance.identifyUser('user_123', {'email': 'alice@example.com'});
```

`await` the `init` call before tracking: calls made before it completes are dropped (with a `debugPrint` in debug builds), like the browser SDK's "not initialized" error.

## Config

| Field       | Description                                                                                          |
| ----------- | ---------------------------------------------------------------------------------------------------- |
| `apiKey`    | Sent as `Authorization: Bearer …`. Required; never logged (`toString()` redacts it). Use the app's write key (`ewk_…`). |
| `orgId`     | Sent as the `X-Org-Id` header. Not needed with a write key; required with any other key.            |
| `appId`     | Sent as the `X-Engage-App-Id` header, only when `apiKey` is not a write key. Defaults to the org's default app. |
| `autoTrack` | On web, capture attribution from the page URL (`Uri.base`) during `init`. Default `false`.           |
| `onError`   | Receives every delivery and storage error. Without it errors are only `debugPrint`ed in debug mode. |

### Write keys

Each engage app (a website, an iOS app, an Android app…) has a public **write key**, `ewk_` followed by 32 hex characters. Find it in engage under **Settings → Apps** and pass it as `apiKey` with no `orgId`: the key alone tells the service which organization and which app the events belong to.

- A write key only authorizes event tracking (`POST /v1/engage/track`). It is meant to ship inside your app; it cannot read data or call any other API.
- With a write key, `X-Engage-App-Id` is never sent, and the service ignores `X-Org-Id` if you also pass `orgId`.

Other keys (a user JWT or platform API key) still work. Then `orgId` is required (`init` throws `ArgumentError` without it) and `appId` picks the app; without `appId` events go to the org's default app:

```dart
EngageConfig(apiKey: '<jwt-or-api-key>', orgId: 'org_123', appId: '<app-id>')
```

`init(config, {storage, httpClient})` also takes an `EngageStorage` (default `SharedPreferencesEngageStorage`) and your own `http.Client` (never closed by the SDK). Calling `init` again reconfigures the client.

## API

| Method                                  | Event / effect                                                                  |
| --------------------------------------- | ------------------------------------------------------------------------------- |
| `track(name, [metadata])`               | Custom event.                                                                   |
| `page([properties])`                    | `page_view`.                                                                    |
| `identifyUser(userId, [properties])`    | `_lowco_identify`; later events carry `user_id` (kept in memory, as in the browser SDK — call again after a restart). |
| `reset()`                               | Logout: forgets the user id and starts a new session (device id is kept).      |
| `captureAttribution(uri)`               | Reads `utm_*` / click ids from a deep link or URL (see below).                  |
| `setLocation(LocationInfo?)`            | Location sent with later events.                                                |
| `setDeviceInfo(DeviceInfo)`             | Override the auto-detected `device_info` (e.g. with `device_info_plus` data).   |

Tracking is fire-and-forget: one `POST` per event, and the returned futures never throw (you may `await` them to know the request finished). Errors — non-2xx answers as `EngageException(statusCode, message, body)`, network failures, timeouts (30 s), storage failures — go to `onError`.

## Route tracking

`LowcoAnalyticsObserver` is the Flutter equivalent of the browser SDK's `autoTrack` history tracking. Add it to `MaterialApp.navigatorObservers` (or `CupertinoApp`, or a nested `Navigator`; with `go_router` pass it to `GoRouter(observers: [...])`). It sends `page_view` with `{path: <route name>, title: <route name>}` when a route is pushed, replaces another, or becomes visible again after a pop. Routes without a name — most dialogs, sheets and anonymous `MaterialPageRoute`s — are skipped; give pages a `RouteSettings(name: '/checkout')` to track them.

## Attribution

```dart
// e.g. with package:app_links
appLinks.uriLinkStream.listen(LowcoAnalytics.instance.captureAttribution);
```

`captureAttribution` extracts `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content`, `utm_id`, `gclid`, `fbclid` and `msclkid` from the query string (or the query part of a hash route, `/#/promo?utm_source=x`). They are merged into `event_data` of every later event, under the event's own metadata. The first time any are seen they are also persisted as `first_touch` (`{...params, landing_url, referrer: null, captured_at}`) under `lowco_first_touch`; it is never overwritten and is sent with every event. It may be called before `init` completes. On web, `autoTrack: true` does this for the page URL automatically.

## Sessions, ids and storage

The storage keys match the browser SDK's `localStorage` keys:

| Key                        | Content                                                               |
| -------------------------- | --------------------------------------------------------------------- |
| `lowco_uuid`               | Device (anonymous) id, a random UUID v4 created on first launch.     |
| `lowco_session_id`         | Session id (UUID v4). A new one starts after 30 minutes of inactivity. |
| `lowco_session_last_event` | Last event time, epoch milliseconds.                                  |
| `lowco_first_touch`        | First-touch attribution JSON.                                         |

`SharedPreferencesEngageStorage` (default) uses `shared_preferences`; `InMemoryEngageStorage` keeps nothing across restarts. Implement `EngageStorage` (`getString` / `setString` / `remove`) for anything else.

## Payload

```json
{
  "id": "",
  "event_name": "signup_completed",
  "event_data": { "utm_source": "google", "first_touch": { "...": "..." }, "plan": "pro" },
  "user_id": "user_123",
  "device_id": "3f1c…",
  "session_id": "9b0e…",
  "device_info": {
    "os": { "name": "iOS", "version": "17.4" },
    "device": { "type": "mobile", "vendor": "Apple" },
    "engine": { "name": "Flutter" },
    "ua": "Flutter (iOS 17.4)"
  },
  "location": null,
  "event_time": "2026-09-30T12:00:00.123Z"
}
```

`device_info` is detected without plugins: `os.name` uses the browser SDK's names (`Android`, `iOS`, `Mac OS`, `Windows`, `Linux`), `device.type` is `mobile` / `tablet` (shortest side ≥ 600 dp) / `desktop` / `web`. On web `browser` and `ua` come from `navigator.userAgent`. Android does not expose its OS release without a plugin, so `os.version` is omitted there — use `setDeviceInfo` to supply richer data. `location` is only sent after `setLocation` (the SDK never requests location permission).

## Testing

```dart
setUp(LowcoAnalytics.debugReset); // fresh singleton per test

await LowcoAnalytics.instance.init(
  config,
  storage: InMemoryEngageStorage(),
  httpClient: MockClient((req) async => http.Response('', 202)),
);
LowcoAnalytics.instance.now = () => fixedTime; // @visibleForTesting clock
```
