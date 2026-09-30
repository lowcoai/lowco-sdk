# lowcoai-flux

Python client for the **lowco flux** realtime WebSocket service, built on [websockets](https://websockets.readthedocs.io/). asyncio only. Python 3.10+.

```bash
pip install lowcoai-flux
```

## Quick start

```python
import asyncio

from lowcoai.flux import FluxClient


async def main() -> None:
    async with FluxClient("<token-or-api-key>", "org_123") as flux:
        flux.on_state(lambda state: print("flux:", state))

        # Subscribe and bind to one channel
        channel = await flux.subscribe("tables:leads")
        channel.bind("row.created", lambda data, msg: print("new row", data))

        # Or subscribe to a batch of topics
        await flux.subscribe_many(["tables:leads", "tables:orders"])

        # Only some events of a topic: the server sends nothing else
        await flux.subscribe("channel:<schema>", events=["messages.*", "notifications.*"])

        # Send a message (needs an open socket)
        await flux.wait_until_connected(timeout=10)
        await flux.send_message("tables:leads", "ping", {"hello": "world"})

        await asyncio.Event().wait()  # keep listening


asyncio.run(main())
```

`connect()` returns immediately: a background task dials, reads, sends heartbeats and reconnects until `disconnect()`. `async with` calls `connect()` on entry and `disconnect()` on exit. Subscribing does not need an open socket (see [Event filters](#event-filters)); sending does, so await `wait_until_connected()` first.

**asyncio only.** A flux connection is long-lived and push-driven, so there is no sync client. From synchronous code, run the client on an event loop in a thread of its own.

**No singleton.** The TypeScript SDK's `FluxClient.getInstance()` / `destroyInstance()` are not ported. Create one `FluxClient` and share it (a module-level variable or your dependency container) if you want one connection per process.

## Options

The client always connects to `wss://ws.lowco.ai/?token=…&orgId=…&cli=…&replay=1`. `replay=1` tells the server the client re-sends every subscription on connect.

| Argument             | Description                                                                          |
| -------------------- | ------------------------------------------------------------------------------------ |
| `token`              | User token or API key, sent as the `token` query parameter. Required (`FluxError` if blank). |
| `org_id`             | Organization id, sent as `orgId`. Required (`FluxError` if blank).                   |
| `client_id`          | Stable client id sent as `cli`. Defaults to a random UUID4 (`generate_client_id()`). |
| `heartbeat_interval` | Seconds between pings (default `5`).                                                 |
| `reconnect_interval` | Initial reconnect backoff in seconds (default `1`), doubled per attempt, capped at 30 s. |
| `query_params`       | Extra query parameters added to the URL.                                             |
| `connect`            | Transport factory `async (url) -> connection`. Defaults to `websockets.asyncio.client.connect(url, max_size=None)`. |

Pass `connect` to tune the transport (timeouts, headers, TLS, proxies) or to point the client at a test server. The connection it returns needs `send(str)`, `close()` and async iteration over incoming frames (the `FluxConnection` protocol); a websockets `ClientConnection` has all three.

```python
from websockets.asyncio.client import connect


async def dial(url: str):
    return await connect(url, open_timeout=5, max_size=None)


flux = FluxClient("<token>", "org_123", connect=dial)
```

## Channels

`subscribe(name)` returns a `FluxChannel` handle for that topic:

```python
channel = await flux.subscribe("runs:42")
unbind = channel.bind("status", lambda data, msg: ...)
unbind()  # remove this handler
await channel.destroy()  # unbind all + unsubscribe
```

Handlers are called with `(data, message)` for frames whose channel and event match exactly (both trimmed). `subscribe_many(topics)` subscribes to a batch without returning handles; each entry is a bare topic string or `{"topic": ..., "events": [...]}`.

## Event filters

A subscription can be narrowed to the events you want, and the server then delivers only those. This helps on a busy channel such as a lowcodb schema channel, where every realtime table arrives as `<table>.<insert|update|delete>`:

```python
await flux.subscribe_many(
    [
        "agent:42",  # every event
        {"topic": "channel:<schema>", "events": ["messages.*"]},  # one table
    ]
)
await flux.subscribe("channel:<schema>", events=["notifications.insert"])  # adds to the filter

# Drop one pattern, then the whole topic
await flux.unsubscribe_many([{"topic": "channel:<schema>", "events": ["messages.*"]}])
await flux.unsubscribe_many(["channel:<schema>"])
```

Patterns are dot-separated: `*` alone (`ALL_EVENTS`) matches every event, and elsewhere `*` matches exactly one token (`messages.*`, `*.delete`). Subscribing adds patterns to what the topic already has, and only the difference is sent. A topic is dropped when its last pattern is. Topics and patterns are trimmed, and blanks and duplicates are dropped. Filters are not access control: channel authorization still applies per topic.

The client keeps its own record of subscriptions (with their filters). A subscribe made while the socket is down is sent when it opens, an unsubscribe made while it is down only updates the record, and every reconnect replays everything in one frame. `unsubscribe(topic)` also removes the channel's bound handlers; `unsubscribe_many` does not.

## Handlers

`on_message`, `on_error` and `on_state` register a handler and return a function that removes it. `bind(channel, event, handler)` does the same for one channel and event, and `unbind(channel, event=None, handler=None)` removes all of a channel's handlers, one event's, or a single handler.

Handlers can be plain functions or `async def` functions. Coroutines are scheduled as tasks, so a slow async handler does not hold up the read loop; keep plain functions quick. If a handler raises, the exception goes to the `on_error` handlers, or to the `lowcoai.flux` logger when there are none (or when an error handler itself raises). Reading continues either way.

`on_state` receives `"connected"` when a socket opens, `"disconnected"` whenever one closes or a dial fails, and `"error"` just before `"disconnected"` for a failed dial or an abnormal closure.

## Data shapes

Frames are plain dicts typed as `SocketMessage` (`TypedDict`) with the keys used on the wire: `channel`, `event`, `type` (`"action" | "event" | "system" | "error" | "ack"`), `data` (any JSON value), `request_id`, `timestamp` (Unix seconds) and `meta` (`{"seq", "run_id"}`). `get_subscriptions()` returns `TopicSubscription` dicts, `{"topic": str, "events": list[str]}`.

## Surface

| Area          | Methods |
| ------------- | ------- |
| Lifecycle     | `connect`, `disconnect`, `is_connected`, `wait_until_connected`, `async with`, `client_id` |
| Subscriptions | `subscribe` (returns `FluxChannel`), `subscribe_many`, `unsubscribe`, `unsubscribe_many`, `get_subscribed_topics`, `get_subscriptions` |
| Messages      | `send_message` |
| Handlers      | `on_message`, `on_error`, `on_state`, `bind`, `unbind` |
| `FluxChannel` | `name`, `bind`, `unbind`, `unsubscribe`, `destroy`, `send_message` |
| Helpers       | `WS_URL`, `build_websocket_url`, `generate_client_id`, `ALL_EVENTS`, `SocketEvent`, `CHANNEL_SUBSCRIPTION`, `CHANNEL_HEALTH_CHECK` |

## Heartbeat and reconnects

Every `heartbeat_interval` seconds the client sends a ping (`pi`) on `flux:health_check` carrying a sequence number. A `pong` whose sequence does not match the last ping is reported as `FluxError("pong out of sync, reconnecting")` and the socket is replaced. After any close the client reconnects after `reconnect_interval * 2**attempt` seconds (at most 30); the counter resets once a socket opens. Calling `connect()` during the backoff dials right away.

## Errors

`FluxError` (with a `message` attribute) is raised for invalid input (blank token, org id, topic, channel or event name) and for `send_message` while the socket is not open. Messages are not queued. `subscribe` and `unsubscribe` never fail for connectivity reasons.

```python
from lowcoai.flux import FluxError

try:
    await flux.send_message("tables:leads", "ping", {})
except FluxError as err:
    print(err.message)  # "websocket is not connected"
```

Transient problems are not raised. They go to `on_error` handlers and the client reconnects on its own: failed dials (`websockets` exceptions such as `InvalidStatus` or `OSError`), abnormal closures (`ConnectionClosedError`), non-JSON frames and pong mismatches. `wait_until_connected(timeout)` raises `TimeoutError` when the socket is not open in time, and `FluxError` if `connect()` was never called or `disconnect()` is called while waiting.
