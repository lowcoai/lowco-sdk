// Package flux is the Go client for the lowco flux realtime WebSocket service.
//
// A Client owns a single connection, transparently reconnects with
// exponential backoff, and re-subscribes to the same set of topics after each
// reconnect. Messages are exchanged as JSON envelopes (SocketMessage); the
// client handles ping/pong heartbeats automatically.
//
// Authentication is supplied via NewClient's required token and orgID; an
// optional userID is sent as a query parameter so the server can route
// per-user events.
package flux
