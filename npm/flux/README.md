# @lowcoai/flux

TypeScript / Node client for the **lowco flux** realtime WebSocket service. Works in browsers, modern Node (with a built-in `WebSocket`), Bun, and Deno. For older Node runtimes pass a `ws`-style implementation via `webSocketImpl`.

```bash
npm install @lowcoai/flux
```

## Quick start

```ts
import { FluxClient } from "@lowcoai/flux";

const flux = new FluxClient({
  baseUrl: "wss://flux.example.com/v1/ws",
  token: "<jwt>",
  orgId: "org_123",
  userId: "user_123",
});

flux.onState((state) => console.log("flux:", state));
flux.connect();

// Subscribe and bind to one channel
const channel = flux.subscribe("tables:leads");
channel.bind("row.created", (data) => console.log("new row", data));

// Or subscribe to a batch of topics
flux.subscribe(["tables:leads", "tables:orders"]);

// Send a message
flux.sendMessage("tables:leads", "ping", { hello: "world" });
```

## Options

| Option                 | Description                                                          |
| ---------------------- | -------------------------------------------------------------------- |
| `baseUrl`              | WebSocket URL (`ws://`, `wss://`, `http://`, `https://`). Required.  |
| `token`                | Auth token sent as the `token` query parameter. Required.            |
| `orgId`                | Organization id sent as `orgId`. Required.                           |
| `userId`               | User id sent as `userId` (optional).                                 |
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

`subscribe(topics: string[])` performs a batch subscribe without returning a handle.

## Errors

`FluxError` is thrown for invalid input or sending while disconnected. Transient socket errors (parse failures, server-side errors, pong mismatch) are surfaced through `onError`:

```ts
flux.onError((err) => console.error("flux error", err));
```

## Lifecycle

```ts
flux.connect();             // (re)open the socket
flux.isConnected();         // true once `connected` state fires
flux.disconnect();          // close and stop auto-reconnect
flux.getSubscribedTopics(); // current server-acknowledged topics
```
