# @lowcoai/engage

Browser analytics SDK for the **lowco engage** service. Captures page views, custom events, attribution, device, and (with permission) location info, and forwards them to `https://api.lowco.ai/v1/engage/track`.

```bash
npm install @lowcoai/engage
```

## Quick start (npm)

```ts
import LowcoAnalytics from "@lowcoai/engage";

LowcoAnalytics.init({
  apiKey: "<api-key>",
  orgId: "org_123",
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

| Field        | Description                                                          |
| ------------ | -------------------------------------------------------------------- |
| `apiKey`     | API key used as `Authorization: Bearer …` header. Required.          |
| `orgId`      | Sent as `X-Org-Id` header.                                           |
| `autoTrack`  | Auto-track page views and `history.pushState` / `replaceState`.      |

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
  apiKey: "<api-key>",
  orgId: "org_123",
  eventName: "signup_completed",
});
```
