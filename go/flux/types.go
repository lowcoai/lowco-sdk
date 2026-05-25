package flux

// MessageType is the high-level kind of a SocketMessage.
type MessageType string

const (
	MessageTypeAction MessageType = "action"
	MessageTypeEvent  MessageType = "event"
	MessageTypeSystem MessageType = "system"
	MessageTypeError  MessageType = "error"
	MessageTypeAck    MessageType = "ack"
)

// Reserved wire-level event names used by the flux protocol.
const (
	EventPing        = "pi"
	EventPong        = "po"
	EventPongReply   = "pong"
	EventSubscribe   = "sb"
	EventUnsubscribe = "usb"
)

// Reserved channels.
const (
	ChannelSubscription = "flux:subscription"
	ChannelHealthCheck  = "flux:health_check"
)

// MessageMeta carries optional metadata transmitted alongside a message.
type MessageMeta struct {
	Seq   int64  `json:"seq,omitempty"`
	RunID string `json:"run_id,omitempty"`
}

// SocketMessage is the JSON envelope exchanged with the flux server.
type SocketMessage struct {
	Type      MessageType `json:"type,omitempty"`
	Channel   string      `json:"channel,omitempty"`
	Event     string      `json:"event,omitempty"`
	Data      any         `json:"data,omitempty"`
	RequestID string      `json:"request_id,omitempty"`
	Timestamp int64       `json:"timestamp,omitempty"`
	Meta      *MessageMeta `json:"meta,omitempty"`
}

// ConnectionState is reported via Client.OnState.
type ConnectionState string

const (
	StateConnected    ConnectionState = "connected"
	StateDisconnected ConnectionState = "disconnected"
	StateError        ConnectionState = "error"
)

// Handler signatures.
type (
	MessageHandler      func(msg SocketMessage)
	ErrorHandler        func(err error)
	StateHandler        func(state ConnectionState)
	ChannelEventHandler func(data any, msg SocketMessage)
)
