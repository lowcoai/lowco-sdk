## 0.1.0

- Initial release: `LowcoEngage.shared` with `configure`, `track`, `identify` (`_lowco_identify`), `screen` (`page_view`), `reset`, `flush`, `setLocation` and `setDeviceInfo`.
- Events are queued in memory and on disk and sent in batches of 50 to `POST /v1/engage/track/batch` every 10 seconds, at 50 queued events, when the app goes to the background and on `flush()`; per-event results drop refused events and keep ones to send again; network errors, 408, 429 and 5xx retry with exponential backoff.
- Persistent device id (`lowco_uuid`), 30-minute sessions, `device_info` (OS, model, form factor) and `event_data.app_version`, with the Flutter SDK's wire format and headers (`X-Api-Key` for `lc_` keys, `X-Org-Id`, `X-Engage-App-Id`).
- Privacy manifest (`PrivacyInfo.xcprivacy`).
