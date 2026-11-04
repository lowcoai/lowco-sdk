# engage (Go)

Server-side Go client for the **lowco engage** event-tracking service, the backend counterpart of the browser SDK [`@lowcoai/engage`](../../npm/engage). Every call sends one event to `POST https://api.lowco.ai/v1/engage/track`. No dependencies outside the standard library.

```bash
go get github.com/lowcoai/lowco-sdk/go/engage
```

## Quick start

```go
package main

import (
	"context"
	"log"

	"github.com/lowcoai/lowco-sdk/go/engage"
)

func main() {
	ctx := context.Background()

	client, err := engage.NewClient(engage.Config{
		APIKey: "lc_…",    // required: an API key, or an OAuth2 access token
		OrgID:  "org_123", // required
		AppID:  "app_123", // optional: omit to track into the org's default app
	})
	if err != nil {
		log.Fatal(err)
	}

	err = client.Track(ctx, "signup_completed", engage.Metadata{"plan": "pro"},
		&engage.EventOptions{UserID: "user_123"})
	if err != nil {
		log.Fatal(err)
	}

	_ = client.Page(ctx, engage.Metadata{"path": "/pricing", "title": "Pricing"},
		&engage.EventOptions{UserID: "user_123"})
	_ = client.IdentifyUser(ctx, "user_123", engage.Metadata{"email": "alice@example.com"}, nil)
}
```

Create the client once and share it: it is safe for concurrent use.

## Config

| Field        | Description |
| ------------ | ----------- |
| `APIKey`     | Required. An `lc_…` API key is sent as `X-Api-Key`; any other value (an OAuth2 access token) as `Authorization: Bearer <APIKey>`. |
| `OrgID`      | Required. Sent as the `X-Org-Id` header. |
| `AppID`      | Optional. The engage app to track into, sent as `X-Engage-App-Id`. Empty (or blank): the org's default app. |
| `DeviceID`   | `device_id` of events that do not set one. Defaults to a random UUID per client. |
| `TimeoutMS`  | Timeout of the default HTTP client in milliseconds (30s when zero). Not applied to `HTTPClient`. |
| `HTTPClient` | Your own `*http.Client` (proxies, retries, test transports). |

`NewClient` returns `ErrMissingAPIKey` / `ErrMissingOrgID` when either required field is blank.

### Credentials and apps

- **API key** (`lc_…`, generated in the admin portal): the usual credential for a server. It travels as `X-Api-Key`, the header the gateway reads API keys from.
- **Access token**: a user's OAuth2 token travels as `Authorization: Bearer`.
- **Apps**: an org can have several engage apps, each with its own events and users. Set `AppID` (engage → Settings → Apps) to track into one; leave it empty and events land in the org's default app. `client.AppID()` returns the configured app (`""` for the default).

`HeaderAPIKey`, `HeaderOrgID`, `HeaderAppID` and `IsAPIKey(apiKey)` are exported.

## Surface

| Method | Event name | Notes |
| ------ | ---------- | ----- |
| `Track(ctx, eventName, properties, opts)` | `eventName` | Custom event. Returns `ErrMissingEventName` for a blank name. |
| `Page(ctx, properties, opts)` | `page_view` | Put `path`, `url`, `title`, `referrer`, `search` in `properties` like the browser SDK does. |
| `IdentifyUser(ctx, userID, properties, opts)` | `_lowco_identify` | Links `userID` to the device id. Not remembered. Returns `ErrMissingUserID` for a blank id. |

`opts` (`*EventOptions`, may be `nil`) carries `UserID`, `DeviceID`, `SessionID`, `DeviceInfo`, `Location` and `EventTime` (defaults to now). `client.DeviceID()` returns the default device id.

## Stateless by design

A server handles many users at once, so the client remembers nothing between calls:

- `IdentifyUser` sends `_lowco_identify` but does **not** bind later events to that user. Set `EventOptions.UserID` on every event that should be attributed to a user.
- No session handling: set `SessionID` if you have one (for example forwarded from the browser SDK's `lowco_session_id`).
- No device / location capture: set `DeviceInfo` / `Location` when you know them. `LocationInfo` coordinates are pointers so `0` is sent; use `engage.Float64(v)`. `IPAddress` is the field a server usually knows.
- To tie server events to a browser visitor, forward the browser's `lowco_uuid` as `EventOptions.DeviceID`.

Each call sends exactly one event and returns once the service has answered. To keep tracking off the request path, call it from a goroutine or a worker.

## Data shape

The request body is the JSON the browser SDK sends (snake_case keys); empty optional fields are left out:

```json
{
  "id": "",
  "event_name": "signup_completed",
  "event_data": {"plan": "pro"},
  "user_id": "user_123",
  "device_id": "5f0c…",
  "session_id": "…",
  "event_time": "2026-09-30T12:34:56.789Z"
}
```

`event_time` is ISO-8601 UTC with milliseconds and a `Z` suffix (JavaScript `toISOString`). Values in `properties` are encoded with `encoding/json`; a value it cannot encode (such as `NaN`) fails the call before any request is sent.

## Attribution

```go
attribution := engage.AttributionFromURL(r.URL.String()) // full URL, "/path?query", "?query" or "a=b&c=d"
props := engage.Metadata{"plan": "pro"}
for k, v := range attribution {
	props[k] = v
}
_ = client.Track(ctx, "signup_completed", props, &engage.EventOptions{UserID: user.ID})
```

Returns the keys the browser SDK captures (`engage.AttributionKeys`): `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content`, `utm_id`, `gclid`, `fbclid`, `msclkid`. Empty values and anything after `#` are ignored; the first value of a repeated key wins.

## Errors

A non-2xx response, or a network or timeout failure (`Status` 0), returns `*engage.Error`:

```go
var e *engage.Error
if errors.As(err, &e) {
	log.Println(e.Status, e.Message, e.Code)
}
```

When the service answers with an opaque platform code (`"AAS-00400"`) as the message, `Message` carries the human-readable `error.details` and `Code` the platform code. `Body` is the raw response. Transport errors unwrap, so `errors.Is(err, context.DeadlineExceeded)` works.
