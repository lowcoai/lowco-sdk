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
	// EventUnauthorized is the event of the ChannelError frame the server
	// sends before closing a socket whose token it rejects.
	EventUnauthorized = "Unauthorized"
)

// Reserved channels.
const (
	ChannelSubscription = "flux:subscription"
	ChannelHealthCheck  = "flux:health_check"
	ChannelError        = "flux:error"
)

// MessageMeta carries optional metadata transmitted alongside a message.
type MessageMeta struct {
	Seq   int64  `json:"seq,omitempty"`
	RunID string `json:"run_id,omitempty"`
}

// SocketMessage is the JSON envelope exchanged with the flux server.
type SocketMessage struct {
	Type      MessageType  `json:"type,omitempty"`
	Channel   string       `json:"channel,omitempty"`
	Event     string       `json:"event,omitempty"`
	Data      any          `json:"data,omitempty"`
	RequestID string       `json:"request_id,omitempty"`
	Timestamp int64        `json:"timestamp,omitempty"`
	Meta      *MessageMeta `json:"meta,omitempty"`
}

// AllEvents is the event pattern that matches every event on a topic.
const AllEvents = "*"

// Subscription is a topic narrowed to the events wanted from it. The server
// delivers only events matching one of the patterns: "*" alone is every
// event, otherwise patterns are compared token by token on "." with "*"
// matching exactly one token ("messages.*", "*.delete", "messages.insert").
// No Events means every event (subscribe) or the whole topic (unsubscribe).
type Subscription struct {
	Topic  string   `json:"topic"`
	Events []string `json:"events,omitempty"`
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
