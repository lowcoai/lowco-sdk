# @lowcoai/engage

Browser analytics SDK for the **lowco engage** service. Captures page views, custom events, attribution, device, and (with permission) location info, and forwards them to `https://api.lowco.ai/v1/engage/track`.

```bash
npm install @lowcoai/engage
```

## Quick start (npm)

```ts
import LowcoAnalytics from "@lowcoai/engage";

LowcoAnalytics.init({
  apiKey: "lc_…", // API key from the admin portal, or an OAuth2 access token
  orgId: "org_123",
  appId: "app_123", // optional: the engage app; omit for the org's default app
  autoTrack: true, // auto page-view + history events
});

LowcoAnalytics.track("signup_completed", { plan: "pro" });
LowcoAnalytics.identifyUser("user_123", { email: "alice@example.com" });
```

## Quick start (HTML)

Drop the IIFE bundle into your page:

```html
<script src="https://unpkg.com/@lowcoai/engage/script"></script>
<script>
  LowcoAnalytics.init({ apiKey: "<api-key>", orgId: "org_123", autoTrack: true });
  LowcoAnalytics.track("signup_completed");
</script>
```

Events are always sent to `https://api.lowco.ai`.

## Config

| Field        | Description                                                                                                  |
| ------------ | ------------------------------------------------------------------------------------------------------------ |
| `apiKey`     | Required. An `lc_…` API key is sent as `X-Api-Key`; any other value (an OAuth2 access token) as `Authorization: Bearer …`. |
| `orgId`      | Required. Sent as the `X-Org-Id` header.                                                                     |
| `appId`      | Optional. The engage app to track into, sent as `X-Engage-App-Id`. Omitted: the org's default app.           |
| `autoTrack`  | Auto-track page views and `history.pushState` / `replaceState`.                                              |

### Credentials and apps

- **API key** (`lc_…`, generated in the admin portal): pass it as `apiKey`. It travels as `X-Api-Key`, the header the gateway reads API keys from. Anything in a web page is visible to its visitors, this key included.
- **Access token** (a signed-in user's OAuth2 token, as the Lowco apps send): pass it as `apiKey`; it travels as `Authorization: Bearer`.
- **Apps:** an org can have several engage apps, each with its own events and users. Set `appId` to the app's id (engage → Settings → Apps) to track into it; leave it out and events land in the org's default app.

`HEADER_API_KEY`, `HEADER_ORG_ID`, `HEADER_ENGAGE_APP_ID` and `isApiKey(apiKey)` are exported for callers that build their own requests.

## API

- `init(config)` — configure and start session tracking.
- `track(eventName, metadata?)` — fire a custom event.
- `page(properties?)` — fire a `page_view` event.
- `identifyUser(userId, properties?)` — bind a user id to the device id and emit `_lowco_identify`.

## Sessions & attribution

- Session id is stored under `lowco_session_id` (30-minute inactivity timeout).
- Device id is stored under `lowco_uuid`.
- First-touch attribution (UTM, gclid, fbclid, msclkid) is captured under `lowco_first_touch` and merged into every event.

## Snippet helpers

```ts
import { createInlineSnippet, createEmbedSnippet } from "@lowcoai/engage/snippet";

createEmbedSnippet({
  scriptSrc: "https://cdn.example.com/lowco-analytics.js",
  apiKey: "lc_…",
  orgId: "org_123",
  appId: "app_123", // optional
  eventName: "signup_completed",
});
```
