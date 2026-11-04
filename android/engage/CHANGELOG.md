## Unreleased

- Initial release: `LowcoAnalytics` (init, track, page, screen, identifyUser, captureAttribution, setLocation, setDeviceInfo, reset), persistent device id and 30-minute sessions, deep-link attribution with first-touch persistence, `autoTrack` page views per resumed activity, pluggable storage (`SharedPreferencesEngageStorage`, `InMemoryEngageStorage`) and transport.
- Credentials: an `lc_…` API key is sent as `X-Api-Key`, any other `apiKey` (an OAuth2 access token) as `Authorization: Bearer`. `orgId` is required (`X-Org-Id`); `appId` is optional (`X-Engage-App-Id`, the org's default app when absent).
