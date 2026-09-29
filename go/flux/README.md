# flux — Go SDK

Go client for the **lowco flux** realtime WebSocket service. Built on `github.com/gorilla/websocket`.

Every client connects to the fixed endpoint `wss://ws.lowco.ai/` (`flux.DefaultWSURL`). Authentication uses a required token (a user token or an API key); user identity is derived from the token server-side.

```
go get github.com/backend-platform/lowco-sdk/go/flux
```

## Quick start

```go
package main

import (
    "log"
    "time"

    flux "github.com/backend-platform/lowco-sdk/go/flux"
)

func main() {
    client, err := flux.NewClient("<token-or-api-key>", "org_123")
    if err != nil {
        log.Fatal(err)
    }

    client.OnState(func(s flux.ConnectionState) { log.Println("state:", s) })
    client.OnError(func(e error) { log.Println("error:", e) })

    client.Connect()
    defer client.Disconnect()

    // Subscribe and bind to a channel. A subscribe made before the socket
    // opens is kept and sent once it does.
    ch, err := client.Subscribe("tables:leads")
    if err != nil {
        log.Fatal(err)
    }
    _, _ = ch.Bind("row.created", func(data any, msg flux.SocketMessage) {
        log.Printf("new row %+v", data)
    })

    // Batch subscribe.
    _ = client.SubscribeMany([]string{"tables:leads", "tables:orders"})

    // Only some events of a topic — the server sends nothing else.
    _, _ = client.Subscribe("channel:<schema>", "messages.*", "notifications.*")

    // Send a message (needs an open socket).
    for !client.IsConnected() {
        time.Sleep(50 * time.Millisecond)
    }
    _ = ch.Send("ping", map[string]string{"hello": "world"})

    select {}
}
```

## Options

| Option                    | Description                                                  |
| ------------------------- | ------------------------------------------------------------ |
| `WithClientID(id)`        | Overrides the generated client id.                           |
| `WithHeartbeatInterval`   | Ping cadence (default `5s`).                                 |
| `WithReconnectInterval`   | Initial reconnect backoff (default `1s`, capped at `30s`).   |
| `WithQueryParam(k, v)`    | Extra query parameter appended to the connection URL.        |
| `WithDialer(d)`           | Custom `*websocket.Dialer`.                                  |

The client transparently reconnects with exponential backoff and re-subscribes to the same topics, with their event filters, after each reconnect.

## Event filters

A subscription can be narrowed to the events you want, and the server then delivers only those — useful on a busy channel such as a lowcodb schema channel, where every realtime table arrives as `<table>.<insert|update|delete>`:

```go
_ = client.SubscribeWith(
    flux.Subscription{Topic: "agent:42"},                                      // every event
    flux.Subscription{Topic: "channel:<schema>", Events: []string{"messages.*"}}, // one table
)
_, _ = client.Subscribe("channel:<schema>", "notifications.insert") // adds to the filter

_ = client.UnsubscribeWith(flux.Subscription{Topic: "channel:<schema>", Events: []string{"messages.*"}}) // one pattern
_ = client.UnsubscribeMany([]string{"channel:<schema>"})                                               // the topic
```

Patterns are dot-separated: `*` alone matches every event, and elsewhere `*` matches exactly one token (`messages.*`, `*.delete`). Subscribing adds patterns to what the topic already has, and only the difference is sent. A topic is dropped when its last pattern is. Filters are not access control — channel authorization still applies per topic.

## Errors

- `ErrNotConnected` — returned by `Send` when the socket is not open. Subscribes are kept and sent on the next connect instead.
- `ErrEmptyTopic` — returned for empty channel / topic input.

Transient errors (decode failures, pong mismatch, server-side errors) are delivered via handlers registered through `OnError`.

## Lifecycle

```go
client.Connect()              // (re)open the socket
client.IsConnected()          // bool
client.Disconnect()           // close and stop reconnects
client.SubscribedTopics()     // topics this client holds (replayed on reconnect)
client.Subscriptions()        // the same, with each topic's event patterns
```
