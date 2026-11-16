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
| `forms`      | Show the app's live Engage forms by their display rules (see [Forms](#forms)).                               |
| `mirrorEventIds` | Opt-in. Also send each tracked event to the Meta pixel (`fbq`) and gtag when they are on the page, with the same `event_id` (see [Ad ids and event ids](#ad-ids-and-event-ids)). |

### Credentials and apps

- **API key** (`lc_…`, generated in the admin portal): pass it as `apiKey`. It travels as `X-Api-Key`, the header the gateway reads API keys from. Anything in a web page is visible to its visitors, this key included.
- **Access token** (a signed-in user's OAuth2 token, as the Lowco apps send): pass it as `apiKey`; it travels as `Authorization: Bearer`.
- **Apps:** an org can have several engage apps, each with its own events and users. Set `appId` to the app's id (engage → Settings → Apps) to track into it; leave it out and events land in the org's default app.

`HEADER_API_KEY`, `HEADER_ORG_ID`, `HEADER_ENGAGE_APP_ID` and `isApiKey(apiKey)` are exported for callers that build their own requests.

## API

- `init(config)` — configure and start session tracking.
- `track(eventName, metadata?)` — fire a custom event; returns its `event_id`.
- `page(properties?)` — fire a `page_view` event; returns its `event_id`.
- `identifyUser(userId, properties?)` — bind a user id to the device id and emit `_lowco_identify` (carrying the ad ids below, so they land on the profile).
- `reset()` — logout: forget the identified user and start a new anonymous id (`lowco_uuid`) and session.
- `showForm(id)` — show a live form now, whatever its rules; resolves `false` when it isn't live.
- `hideForms()` — close the SDK's form popups, slide-ins and bars and hold back pending triggers until the next page.
- `refreshForms()` — re-fetch the live forms (skipping the 60 s cache) and re-apply their rules.
- `trackBatch(events)` — send events through `POST /v1/engage/track/batch` (split into 1000s); resolves `{accepted, rejected, results}` with each event's outcome by its place. Missing fields default to what `track()` sends.

## Forms

Forms built in Engage (Engage → Forms: newsletter sign-ups, lead capture, NPS, CSAT, feedback, referral and preference forms) show on your site once forms are on:

```ts
LowcoAnalytics.init({ apiKey: "lc_…", orgId: "org_123", appId: "app_123", forms: true });
```

```html
<!-- inline forms render where you put their placeholder -->
<div data-engage-form="FORM_ID"></div>
```

- The SDK fetches the app's live forms (`GET /v1/engage/sdk/forms`) after `init` and again on SPA navigations (at most once a minute), and shows each by its display rules: **mode** (popup, slide-in, top bar, or inline into `data-engage-form` elements), **trigger** (immediately, after a delay, on scroll depth, on exit intent, or when you `track()` an event), **pages** (include/exclude path patterns with `*`), **audience** (anyone, anonymous, or identified visitors), and **frequency** (once, once per session, or always; `daysBetween` waits after a close). Closes, answers and per-session shows are remembered per form in `localStorage` (`lowco_forms`).
- Forms are plain, accessible DOM with one injected stylesheet scoped to `.lcf-root`: labelled fields, a focus trap and Escape for popups, focus returned on close, 44 px touch targets and 16 px inputs on phones, and `prefers-reduced-motion` respected. The `accent` colour styles the button.
- Required, email and phone answers are checked before sending; the server's field errors (422) show next to their fields. A hidden honeypot field is always sent. Hidden form fields take the page's query parameter of the same name (e.g. `utm_campaign`).
- Every display counts a view; an answer is sent with the identified user id (if any), the SDK's anonymous id, a submission id (a retry counts once) and the page URL. After it the form shows its success copy, or follows the form's redirect URL.
- `showForm(id)` works without `forms: true`, e.g. from a "Give feedback" button.

## Sessions & attribution

- Session id is GA4-compatible — `<client id>.<session start epoch seconds>`, the client id being GA4's (from the `_ga` cookie) when the page runs gtag, else the SDK's device id — and is stored under `lowco_session_id` / `lowco_session_start` (renewed after 30 minutes without an event).
- Device id is stored under `lowco_uuid`; `reset()` replaces it (and starts a new session).
- The current page's UTM parameters and click ids are merged into every event; first-touch attribution (UTM and click ids, landing URL, referrer) is captured once under `lowco_first_touch` and sent as `first_touch`.

## Ad ids and event ids

Every event (`track`, `page`, `identifyUser`) carries, when present, these properties — the names Engage reads to attribute visits and leads to ads and to forward conversions to Meta, Google and LinkedIn:

| Property | Source |
| --- | --- |
| `gclid`, `gbraid`, `wbraid`, `fbclid`, `li_fat_id`, `ttclid`, `msclkid` | Click ids on the landing URL, kept for the session (`lowco_session_ads`); the first value of each seen in a session is kept. |
| `click_id`, `click_id_kind` | The highest-ranked of those (gclid › gbraid › wbraid › fbclid › msclkid › ttclid › li_fat_id) and its parameter name. |
| `fbp` | Meta's `_fbp` cookie. |
| `fbc` | Meta's `_fbc` cookie; without it, derived from `fbclid` as `fb.1.<epoch ms>.<fbclid>` (stable for the session). |
| `ga_client_id` | GA4's client id from the `_ga` cookie (`GA1.1.<client id>` → `<client id>`). |
| `referrer` | `document.referrer`. |
| `url` | The page URL. |
| `event_id` | A UUID per event (also sent as the event's `id`). Pass your own `event_id` in the metadata to keep it, e.g. an order id. |

Properties you pass to `track()` win over these.

With `mirrorEventIds: true`, each tracked event (except `page_view`, which the pixel and `gtag('config')` send themselves) is also sent to `fbq` — as the matching standard event (`Lead`, `Purchase`, `CompleteRegistration`, `AddToCart`, `InitiateCheckout`, `ViewContent`, `Contact`, `Subscribe`, `Search`) or `trackCustom`, with `{ eventID }` — and to `gtag('event', name, { …, event_id })`, using only the event's scalar properties. Meta and Google then dedupe it against the same conversion Engage forwards server-side. Leave it off if your page already fires those events itself; instead pass the id `track()` returns to your own calls:

```ts
const eventId = LowcoAnalytics.track("lead_submitted", { form: "demo" });
fbq("track", "Lead", {}, { eventID: eventId });
```

The helpers (`readClickIds`, `collectAdIds`, `gaClientIdFromCookie`, `fbcFromFbclid`, `gaSessionId`, `createEventId`, `mirrorEventId`, `CLICK_ID_KEYS`) are exported.

## Development

```bash
npm run typecheck
npm test   # builds the library, then node --test test/*.test.mjs
```

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
