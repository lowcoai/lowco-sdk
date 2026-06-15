// Package flux is the Go client for the lowco flux realtime WebSocket service.
//
// A Client owns a single connection, transparently reconnects with
// exponential backoff, and re-subscribes to the same set of topics after each
// reconnect. Messages are exchanged as JSON envelopes (SocketMessage); the
// client handles ping/pong heartbeats automatically.
//
// Every client connects to the fixed endpoint DefaultWSURL
// ("wss://ws.lowco.ai/"). Authentication is supplied via NewClient's required
// token (a user token or an API key) and orgID; both are sent as query
// parameters, and user identity is derived from the token server-side.
package flux
