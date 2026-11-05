## Unreleased

- `trackBatch(events, onResult?)` sends up to 1000 events to `POST /v1/engage/track/batch`, reporting each event's outcome (`EngageBatchResult`, `EngageBatchRow`, `EngageBatchCallback`); `buildEvent(eventName, properties?)` builds the event `track` would send. New constants `ENGAGE_TRACK_BATCH_PATH`, `MAX_BATCH_SIZE`.

- Initial release: `LowcoAnalytics` (init, track, page, screen, identifyUser, captureAttribution, setLocation, setDeviceInfo, reset), persistent device id and 30-minute sessions, deep-link attribution with first-touch persistence, `autoTrack` page views per resumed activity, pluggable storage (`SharedPreferencesEngageStorage`, `InMemoryEngageStorage`) and transport.
- Credentials: an `lc_…` API key is sent as `X-Api-Key`, any other `apiKey` (an OAuth2 access token) as `Authorization: Bearer`. `orgId` is required (`X-Org-Id`); `appId` is optional (`X-Engage-App-Id`, the org's default app when absent).
