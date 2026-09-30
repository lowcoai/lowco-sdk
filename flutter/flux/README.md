# lowcoai_flux

Dart / Flutter client for the **lowco flux** realtime WebSocket service. Pure Dart on top of [`package:web_socket_channel`](https://pub.dev/packages/web_socket_channel), so it runs in Flutter (iOS, Android, web, desktop) and on the Dart VM.

```yaml
dependencies:
  lowcoai_flux: ^0.1.0
```

## Quick start

```dart
import 'package:lowcoai_flux/lowcoai_flux.dart';

final flux = FluxClient(token: '<token-or-api-key>', orgId: 'org_123');

flux.onState((state) => print('flux: ${state.name}'));
flux.connect();

// Subscribe and bind to one channel
final channel = flux.subscribe('tables:leads');
channel.bind('row.created', (data, message) => print('new row $data'));

// Or subscribe to a batch of topics
flux.subscribeMany([const TopicSubscription('tables:leads'), const TopicSubscription('tables:orders')]);

// Only some events of a topic — the server sends nothing else
flux.subscribe('channel:<schema>', events: ['messages.*', 'notifications.*']);

// Send a message (needs an open socket)
flux.sendMessage('tables:leads', 'ping', {'hello': 'world'});
```

## Options

The client always connects to `wss://ws.lowco.ai/` (`wsUrl`).

| Parameter           | Description                                                                          |
| ------------------- | ------------------------------------------------------------------------------------ |
| `token`             | Auth token (user token or API key) sent as the `token` query parameter. Required.    |
| `orgId`             | Organization id sent as `orgId`. Required.                                           |
| `clientId`          | Stable client id sent as `cli`; defaults to a random UUID v4.                        |
| `heartbeatInterval` | Ping interval (default 5 s).                                                         |
| `reconnectInterval` | Initial reconnect backoff (default 1 s, doubled per failed attempt, capped at 30 s). |
| `queryParams`       | Extra query parameters appended to the URL (`replay=1` is always sent).              |
| `channelFactory`    | `WebSocketChannel Function(Uri)` used to dial; defaults to `WebSocketChannel.connect`. Inject one for a custom `HttpClient`, a proxy, or tests. |

A blank `token` / `orgId` (or a non-positive interval) throws `FluxException`. `buildWebSocketUrl(token, orgId, clientId, [queryParams])` and `generateClientId()` are exported too.

## Singleton

Prefer one connection per app? Call `FluxClient.getInstance(token: ..., orgId: ...)` once (it creates and connects the client) and `FluxClient.getInstance()` thereafter; `FluxClient.destroyInstance()` disconnects and clears it.

## Channels

`subscribe(topic)` returns a `FluxChannel` handle for that topic (the same handle every time):

```dart
final channel = flux.subscribe('runs:42');
final unbind = channel.bind('status', (data, message) { /* ... */ });
unbind();          // remove this handler
channel.destroy(); // unbind all + unsubscribe
```

`bind` matches the message's `channel` and `event` exactly (both trimmed), and bound handlers run before the `onMessage` handlers. `channel.unbind()` drops every handler of the channel, `channel.unbind('status')` those of one event, `channel.unbind('status', handler)` just one. `flux.unsubscribe(topic)` also drops the topic's bound handlers and its handle.

`subscribeMany(topics)` performs a batch subscribe without returning handles. Each entry is a `TopicSubscription(topic, events: [...])`; leave `events` out for every event.

## Event filters

A subscription can be narrowed to the events you want, and the server then delivers only those — useful on a busy channel such as a lowcodb schema channel, where every realtime table arrives as `<table>.<insert|update|delete>`:

```dart
flux.subscribeMany([
  const TopicSubscription('agent:42'),                                     // every event
  const TopicSubscription('channel:<schema>', events: ['messages.*']),     // one table
]);
flux.subscribe('channel:<schema>', events: ['notifications.insert']);     // adds to the filter

flux.unsubscribeMany([const TopicSubscription('channel:<schema>', events: ['messages.*'])]); // drops one pattern
flux.unsubscribeMany([const TopicSubscription('channel:<schema>')]);                          // drops the topic
```

Patterns are dot-separated: `*` alone (`allEvents`) matches every event, and elsewhere `*` matches exactly one token (`messages.*`, `*.delete`). Subscribing adds patterns to what the topic already has, and only the difference is sent. A topic is dropped when its last pattern is. Topics and patterns are trimmed and de-duplicated; blank ones are ignored. Filters are not access control — channel authorization still applies per topic.

Subscriptions (with their filters) are kept by the client: a subscribe made while the socket is down is sent when it opens, and every reconnect replays them all in one frame. An unsubscribe while the socket is down just updates that record.

## Handlers and streams

Each registration returns its remover:

```dart
final off = flux.onMessage((SocketMessage m) => print('${m.channel} ${m.event} ${m.data}'));
flux.onError((Object error) => print('flux error $error'));
flux.onState((ConnectionState state) => print(state.name)); // connected / disconnected / error
off();
```

The same events are also available as broadcast streams — `flux.messages`, `flux.errors`, `flux.states` — handy with `StreamBuilder` or `await for`.

In a Flutter file that also imports `package:flutter/widgets.dart` (which has its own `ConnectionState`), use the `FluxConnectionState` alias or `import 'package:flutter/widgets.dart' hide ConnectionState;`.

## Errors

`FluxException` (with a `message`) is thrown for invalid input or for `sendMessage` while disconnected (subscribes are kept and sent on the next open instead). Transient socket errors — non-JSON frames, a pong out of sync (the client then reconnects), a failed dial — are not thrown; they are surfaced through `onError` / `errors`:

```dart
flux.onError((error) => print('flux error $error'));
```

## Lifecycle

```dart
flux.connect();               // (re)open the socket; no-op while open or connecting
flux.isConnected;             // true once `connected` state fires
flux.disconnect();            // close and stop auto-reconnect
flux.getSubscribedTopics();   // topics this client holds (replayed on reconnect)
flux.getSubscriptions();      // the same, as TopicSubscription with each topic's patterns
```

The client pings `flux:health_check` every `heartbeatInterval`. A dropped socket or a failed dial reconnects after `reconnectInterval * 2^attempt` (capped at 30 s; reset once a socket opens) until `disconnect()` is called.
