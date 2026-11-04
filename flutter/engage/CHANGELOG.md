## 0.2.0

- `EngageConfig.appId` (optional) selects the engage app, sent as `X-Engage-App-Id`; without it events go to the org's default app.
- An `lc_…` API key is sent as `X-Api-Key`; any other `apiKey` (an OAuth2 access token) still as `Authorization: Bearer`.
- New exports: `headerApiKey`, `headerEngageAppId`, `isApiKey`, `trackHeaders`.

## 0.1.0

- Initial release: `LowcoAnalytics` (track, page, identifyUser, reset), persistent device id and 30-minute sessions, deep-link / URL attribution with first-touch persistence, `LowcoAnalyticsObserver` for route page views, pluggable storage (`SharedPreferencesEngageStorage`, `InMemoryEngageStorage`).
