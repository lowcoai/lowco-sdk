## Unreleased

- App write keys: pass the app's write key (`ewk_…`, engage → Settings → Apps) as `EngageConfig.apiKey` and omit `orgId`. `orgId` is now optional with a write key and still required with any other key; `X-Org-Id` is sent only when it is set.
- `EngageConfig.appId` selects the engage app for non-write keys (sent as `X-Engage-App-Id`); without it events go to the org's default app. New exports: `headerAppId`, `writeKeyPrefix`.

## 0.1.0

- Initial release: `LowcoAnalytics` (track, page, identifyUser, reset), persistent device id and 30-minute sessions, deep-link / URL attribution with first-touch persistence, `LowcoAnalyticsObserver` for route page views, pluggable storage (`SharedPreferencesEngageStorage`, `InMemoryEngageStorage`).
