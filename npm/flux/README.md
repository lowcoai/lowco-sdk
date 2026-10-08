# @lowcoai/flux

TypeScript / Node client for the **lowco flux** realtime WebSocket service. Works in browsers, modern Node (with a built-in `WebSocket`), Bun, and Deno. For older Node runtimes pass a `ws`-style implementation via `webSocketImpl`.

```bash
npm install @lowcoai/flux
```

## Quick start

```ts
import { FluxClient } from "@lowcoai/flux";

const flux = new FluxClient({
  token: "<token-or-api-key>",
  orgId: "org_123",
});

flux.onState((state) => console.log("flux:", state));
flux.connect();

// Subscribe and bind to one channel
const channel = flux.subscribe("tables:leads");
channel.bind("row.created", (data) => console.log("new row", data));

// Or subscribe to a batch of topics
flux.subscribe(["tables:leads", "tables:orders"]);

// Only some events of a topic — the server sends nothing else
flux.subscribe("channel:<schema>", { events: ["messages.*", "notifications.*"] });

// Send a message
flux.sendMessage("tables:leads", "ping", { hello: "world" });
```

## Options

The client always connects to `wss://api.lowco.ai/v1/ws`.

| Option                 | Description                                                          |
| ---------------------- | -------------------------------------------------------------------- |
| `token`                | Auth token (user token or API key) sent as the `token` query parameter. Required. |
| `getToken`             | Optional `() => string \| null \| Promise<…>` called before every (re)connect, so a refreshed token is used. Empty or a throw falls back to the last token. |
| `orgId`                | Organization id sent as `orgId`. Required.                           |
| `clientId`             | Stable client id; defaults to a generated value.                     |
| `heartbeatIntervalMs`  | Ping interval (default `5000`).                                      |
| `reconnectIntervalMs`  | Initial reconnect backoff (default `1000`, capped at 30 s).          |
| `queryParams`          | Extra query parameters appended to the URL.                          |
| `webSocketImpl`        | Custom WebSocket constructor (e.g. the `ws` package on older Node).  |

## Singleton

Prefer one connection per process? Use `FluxClient.getInstance(options)` on first call and `FluxClient.getInstance()` thereafter; `FluxClient.destroyInstance()` tears it down.

## Channels

`subscribe(name)` returns a `FluxChannel` handle for that topic:

```ts
const channel = flux.subscribe("runs:42");
const unbind = channel.bind("status", (data, msg) => { /* ... */ });
unbind();           // remove this handler
channel.destroy();  // unbind all + unsubscribe
```

`subscribe(topics)` performs a batch subscribe without returning a handle. Each entry is a bare topic string or `{ topic, events }`.

## Event filters

A subscription can be narrowed to the events you want, and the server then delivers only those — useful on a busy channel such as a lowcodb schema channel, where every realtime table arrives as `<table>.<insert|update|delete>`:

```ts
flux.subscribe([
  "agent:42",                                            // every event
  { topic: "channel:<schema>", events: ["messages.*"] }, // one table
]);
flux.subscribe("channel:<schema>", { events: ["notifications.insert"] }); // adds to the filter

flux.unsubscribe([{ topic: "channel:<schema>", events: ["messages.*"] }]); // drops one pattern
flux.unsubscribe(["channel:<schema>"]);                                  // drops the topic
```

Patterns are dot-separated: `*` alone matches every event, and elsewhere `*` matches exactly one token (`messages.*`, `*.delete`). Subscribing adds patterns to what the topic already has, and only the difference is sent. A topic is dropped when its last pattern is. Filters are not access control — channel authorization still applies per topic.

Subscriptions (with their filters) are kept by the client: a subscribe made while the socket is down is sent when it opens, and every reconnect replays them all.

## Errors

`FluxError` is thrown for invalid input or for `sendMessage` while disconnected (subscribes are kept and sent on the next open instead). Transient socket errors (parse failures, server-side errors, pong mismatch) are surfaced through `onError`:

```ts
flux.onError((err) => console.error("flux error", err));
```

### Rejected tokens

When the server rejects the token (an `Unauthorized` error frame, then close code `1008`), the client emits a `FluxUnauthorizedError` through `onError`. It reconnects only if a different token is available, either from `getToken` or from `setToken`. If the token is unchanged, it stops reconnecting instead of retrying in a loop:

```ts
flux.onError((err) => {
  if (err instanceof FluxUnauthorizedError) {
    refreshSession().then((token) => flux.setToken(token)); // reconnects at once
  }
});
```

The reconnect backoff (1 s doubling to 30 s) resets only after the server answers the first heartbeat, not when the socket opens. This is because the server accepts the upgrade before it checks the token.

## Lifecycle

```ts
flux.connect();             // (re)open the socket
flux.isConnected();         // true once `connected` state fires
flux.disconnect();          // close and stop auto-reconnect
flux.setToken(token);       // use a new token; resumes a client stopped by a rejected one
flux.getSubscribedTopics(); // topics this client holds (replayed on reconnect)
flux.getSubscriptions();    // the same, with each topic's event patterns
```
