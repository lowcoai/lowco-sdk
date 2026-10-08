// Package flux is the Go client for the lowco flux realtime WebSocket service.
//
// A Client owns a single connection, transparently reconnects with
// exponential backoff, and re-subscribes to the same set of topics — each with
// its event filter, see Subscription — after each reconnect. Messages are exchanged as JSON envelopes (SocketMessage); the
// client handles ping/pong heartbeats automatically.
//
// Every client connects to the fixed endpoint DefaultWSURL
// ("wss://api.lowco.ai/v1/ws"). Authentication is supplied via NewClient's required
// token (a user token or an API key) and orgID; both are sent as query
// parameters, and user identity is derived from the token server-side.
//
// The server checks the token only after the upgrade, so the reconnect
// backoff starts over only once a socket answers its first ping. A rejected
// token is reported as ErrUnauthorized, and the client stops reconnecting
// rather than retry the same token. WithTokenProvider and SetToken supply a
// fresh one, and SetToken also resumes a client stopped this way.
package flux
