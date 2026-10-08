# lowcoai-engage

Server-side Python client for the **lowco engage** event-tracking service: the backend counterpart of the browser SDK [`@lowcoai/engage`](../../npm/engage). Sync and asyncio clients with the same surface, built on [httpx](https://www.python-httpx.org/). Python 3.10+.

```bash
pip install lowcoai-engage
```

## Quick start

```python
from lowcoai.engage import EngageClient

engage = EngageClient("<api-key>", "org_123")  # create once, share across requests

engage.track("signup_completed", {"plan": "pro"}, user_id="user_123")
engage.page({"path": "/pricing", "title": "Pricing"}, user_id="user_123")
engage.identify_user("user_123", {"email": "alice@example.com"})

engage.close()  # or use `with EngageClient(...) as engage:`
```

### asyncio

```python
from lowcoai.engage import AsyncEngageClient

async with AsyncEngageClient("<api-key>", "org_123") as engage:
    await engage.track("order_paid", {"amount": 4999, "currency": "INR"}, user_id="user_123")
```

`AsyncEngageClient` has the same methods as `EngageClient`; each one is a coroutine. Close it with `await engage.aclose()` if you don't use `async with`.

## Stateless by design

The browser SDK is a per-visitor singleton: it remembers the user id after `identifyUser`, keeps a 30-minute session in `localStorage`, generates a persistent device id, parses the user agent, asks for geolocation and merges first-touch attribution into every event.

A server handles many users at once, so this client remembers **nothing** between calls:

- `identify_user(...)` sends the `_lowco_identify` event but does **not** bind later events to that user. Pass `user_id=` on every call that should be attributed to a user.
- No session handling: pass `session_id=` if you have one (for example forwarded from the browser SDK's `lowco_session_id`).
- No device / location capture: pass `device_info=` / `location=` when you know them.
- `device_id` defaults to one uuid4 per client instance (the service requires one). To tie server events to a browser visitor, forward the browser's `lowco_uuid` value as `device_id=` per call, or set `device_id=` in the constructor.
- Attribution is not added automatically; use `attribution_from_url` (below).

Each call sends exactly one event (one HTTP request) and returns once the service has accepted it.

## Options

| Argument      | Description                                                                               |
| ------------- | ----------------------------------------------------------------------------------------- |
| `api_key`     | Engage API key, sent as `Authorization: Bearer <api_key>`. Required.                      |
| `org_id`      | Sent as the `X-Org-Id` header. Required.                                                  |
| `device_id`   | Default `device_id` for events that don't pass one. Defaults to a uuid4 per client.       |
| `timeout`     | Per-request timeout in seconds (default `30`). `None` disables it.                        |
| `http_client` | Your own `httpx.Client` / `httpx.AsyncClient` (proxies, retries, test transports). It is not closed by the SDK. |

Events are always sent to `https://api.lowco.ai/v1/engage/track`.

## Surface

| Method | Event name | Notes |
| ------ | ---------- | ----- |
| `track(event_name, properties=None, *, ...)` | `event_name` | Custom event. |
| `page(properties=None, *, ...)` | `page_view` | Page view; put `path`, `url`, `title`, `referrer`, `search` in `properties` like the browser SDK does. |
| `identify_user(user_id, properties=None, *, ...)` | `_lowco_identify` | Links `user_id` to the device id. Not remembered. |

Every method takes the keyword-only arguments `user_id` (except `identify_user`, where it is positional), `device_id`, `session_id`, `device_info`, `location` and `event_time`. `event_time` defaults to now; a naive `datetime` is treated as UTC. `datetime` / `date` values inside `properties` are serialised as ISO strings.

`client.device_id` returns the default device id.

## Data shapes

The request body is the same JSON the browser SDK sends (snake_case keys); keys whose value is `None` are left out:

```json
{
  "id": "",
  "event_name": "signup_completed",
  "event_data": {"plan": "pro"},
  "user_id": "user_123",
  "device_id": "5f0c…",
  "session_id": "…",
  "device_info": {"browser": {"name": "Chrome"}, "os": {"name": "macOS"}, "ua": "…"},
  "location": {"latitude": 12.97, "longitude": 77.59},
  "event_time": "2026-09-30T12:34:56.789Z"
}
```

`event_time` is an ISO-8601 UTC string with milliseconds and a `Z` suffix (JavaScript `toISOString`). The types are `TypedDict`s: `Event`, `DeviceInfo` (`browser`, `os`, `device`, `cpu`, `engine`, `ua`), `LocationInfo` and `Metadata` (`dict[str, Any]`). `LocationInfo` also has `ip_address`, which the service reads and which a server usually knows.

## Attribution

```python
from lowcoai.engage import attribution_from_url

attribution = attribution_from_url(request.url)  # full URL, "/path?query", "?query" or "a=b&c=d"
engage.track("signup_completed", {**attribution, "plan": "pro"}, user_id=user.id)
```

Returns the same keys the browser SDK captures: `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content`, `utm_id`, `gclid`, `fbclid`, `msclkid` (empty values and anything after `#` are ignored). First-touch attribution needs per-visitor storage, so it is left to your app.

## Errors

A non-2xx response raises `EngageError` with `status_code`, `message`, `code` and the raw `body`:

```python
from lowcoai.engage import EngageError

try:
    engage.track("signup_completed", user_id="user_123")
except EngageError as err:
    print(err.status_code, err.message, err.code)
```

When the service answers with an opaque platform code (`"AAS-00105"`) as the message, `message` carries the human-readable `error.details` instead; the code is still in `body`. Network failures and timeouts surface as `httpx` exceptions. `ValueError` is raised for a blank `api_key`, `org_id`, `event_name` or `identify_user` `user_id`.

Unlike the browser SDK (which fires and forgets), calls wait for the service's answer. To keep tracking off the request path, call it from a background task or worker.
