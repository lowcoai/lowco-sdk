## 0.1.1

- Fix: connect to `wss://api.lowco.ai/v1/ws` (`wsUrl`). The previous endpoint, `wss://ws.lowco.ai/`, does not resolve, so no 0.1.0 client could connect.
- Fix: a token the server rejects after the upgrade (a `flux:error` / `Unauthorized` frame, or close code 1008) no longer makes the client reconnect every `reconnectInterval` forever. The backoff is now reset only when the server answers a heartbeat ping, not when a socket opens; after a rejection the client reconnects only with a different token, and otherwise stops until `setToken`, `connect()` or `disconnect()`.
- Add `FluxUnauthorizedException` (a `FluxException`), reported through `onError` / `errors` when the token is rejected.
- Add the `tokenProvider` option (constructor and `getInstance`), asked for the token of every connection attempt, and `setToken` to replace the stored token and resume a client stopped by a rejection.

## 0.1.0

- Initial release: flux realtime WebSocket client (subscriptions with event filters, channel handles and `bind`, message/error/state handlers and streams, heartbeat with pong sequence check, auto-reconnect with exponential backoff and full subscription replay, `getInstance` singleton).
