package flux

import "errors"

// ErrNotConnected is returned by Client.Send when the underlying WebSocket
// is not in an OPEN state.
var ErrNotConnected = errors.New("flux: websocket is not connected")

// ErrEmptyTopic is returned by Subscribe / Unsubscribe / Bind when given an
// empty channel or topic.
var ErrEmptyTopic = errors.New("flux: at least one non-empty topic is required")

// ErrUnauthorized is reported to OnError handlers when the server rejects the
// connection's token: an Unauthorized frame on ChannelError, or a close with
// code 1008. The server upgrades the socket before it checks the token, so
// this arrives on an open connection. Match it with errors.Is.
//
// The client then reconnects, with backoff, only if the next token — from
// the WithTokenProvider provider, else the stored token — differs from the
// rejected one. Otherwise it stops until SetToken supplies a different
// token, Connect is called, or Disconnect.
var ErrUnauthorized = errors.New("flux: token rejected by server")
