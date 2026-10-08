# @lowcoai/engage

Browser analytics SDK for the **lowco engage** service. Captures page views, custom events, attribution, device, and (with permission) location info, and forwards them to `https://api.lowco.ai/v1/engage/track`.

```bash
npm install @lowcoai/engage
```

## Quick start (npm)

```ts
import LowcoAnalytics from "@lowcoai/engage";

LowcoAnalytics.init({
  apiKey: "ewk_…", // the app's write key: engage → Settings → Apps
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
  LowcoAnalytics.init({ apiKey: "ewk_…", autoTrack: true });
  LowcoAnalytics.track("signup_completed");
</script>
```

Events are always sent to `https://api.lowco.ai`.

## Config

| Field        | Description                                                                                                   |
| ------------ | ------------------------------------------------------------------------------------------------------------- |
| `apiKey`     | Sent as `Authorization: Bearer …`. Required. Use the app's write key (`ewk_…`).                               |
| `orgId`      | Sent as `X-Org-Id`. Not needed with a write key; required with any other key.                                 |
| `appId`      | Sent as `X-Engage-App-Id`, only when `apiKey` is not a write key. Without it events go to the org's default app. |
| `autoTrack`  | Auto-track page views and `history.pushState` / `replaceState`.                                               |

## Authentication

Each engage app (a website, an iOS app, a backend…) has a public **write key**,
`ewk_` followed by 32 hex characters. Find it in engage under **Settings → Apps**
and pass it as `apiKey` with no `orgId`: the key alone tells the service which
org and which app the events belong to.

- A write key only authorizes event tracking (`POST /v1/engage/track`). It is
  meant to ship inside your app or page; it cannot read data or call any other
  API.
- With a write key, `X-Engage-App-Id` is never sent, and the service ignores
  `X-Org-Id` if you also pass `orgId`.

Legacy keys still work: with any other `apiKey` (a user JWT or platform API key),
`orgId` is required (`init` logs an error and does nothing without it) and
`appId` picks the app (the org's default app when omitted):

```ts
LowcoAnalytics.init({ apiKey: "<jwt-or-api-key>", orgId: "org_123", appId: "<app-id>" });
```

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
  apiKey: "ewk_…", // write key: the snippet passes apiKey only
  eventName: "signup_completed",
});
```

With a write key the generated `init` call contains `apiKey` (and `autoTrack`)
only. With any other key it also contains `orgId` (default placeholder
`YOUR_ORG_ID`) and, when given, `appId`.
