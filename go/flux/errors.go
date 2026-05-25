package flux

import "errors"

// ErrNotConnected is returned by Client.Send when the underlying WebSocket
// is not in an OPEN state.
var ErrNotConnected = errors.New("flux: websocket is not connected")

// ErrEmptyTopic is returned by Subscribe / Unsubscribe / Bind when given an
// empty channel or topic.
var ErrEmptyTopic = errors.New("flux: at least one non-empty topic is required")
