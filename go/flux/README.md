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

    // Wait for the socket to open (or use OnState).
    for !client.IsConnected() {
        time.Sleep(50 * time.Millisecond)
    }

    // Subscribe and bind to a channel.
    ch, err := client.Subscribe("tables:leads")
    if err != nil {
        log.Fatal(err)
    }
    _, _ = ch.Bind("row.created", func(data any, msg flux.SocketMessage) {
        log.Printf("new row %+v", data)
    })

    // Batch subscribe.
    _ = client.SubscribeMany([]string{"tables:leads", "tables:orders"})

    // Send a message.
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

The client transparently reconnects with exponential backoff and re-subscribes to the same topics after each reconnect.

## Errors

- `ErrNotConnected` — returned by `Send`, `Subscribe`, etc., when the socket is not open.
- `ErrEmptyTopic` — returned for empty channel / topic input.

Transient errors (decode failures, pong mismatch, server-side errors) are delivered via handlers registered through `OnError`.

## Lifecycle

```go
client.Connect()              // (re)open the socket
client.IsConnected()          // bool
client.Disconnect()           // close and stop reconnects
client.SubscribedTopics()     // server-acknowledged topics
```
