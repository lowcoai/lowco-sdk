package flux

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math"
	"net/url"
	"strconv"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	defaultHeartbeatInterval = 5 * time.Second
	defaultReconnectInterval = 1 * time.Second
	maxReconnectInterval     = 30 * time.Second
)

// Option configures a Client at construction time.
type Option func(*Client)

// WithUserID sets the userId query parameter sent with every connection.
func WithUserID(userID string) Option {
	return func(c *Client) { c.userID = userID }
}

// WithClientID overrides the generated client id.
func WithClientID(clientID string) Option {
	return func(c *Client) {
		if clientID != "" {
			c.clientID = clientID
		}
	}
}

// WithHeartbeatInterval overrides the default ping cadence (5s).
func WithHeartbeatInterval(d time.Duration) Option {
	return func(c *Client) {
		if d > 0 {
			c.heartbeatInterval = d
		}
	}
}

// WithReconnectInterval overrides the initial reconnect backoff (1s); the
// effective backoff doubles on each failure and is capped at 30s.
func WithReconnectInterval(d time.Duration) Option {
	return func(c *Client) {
		if d > 0 {
			c.reconnectInterval = d
		}
	}
}

// WithQueryParam appends an extra query parameter to the connection URL.
func WithQueryParam(key, value string) Option {
	return func(c *Client) {
		if key != "" {
			c.queryParams[key] = value
		}
	}
}

// WithDialer overrides the gorilla websocket dialer (default
// websocket.DefaultDialer).
func WithDialer(d *websocket.Dialer) Option {
	return func(c *Client) {
		if d != nil {
			c.dialer = d
		}
	}
}

// Client is a thread-safe flux WebSocket client.
type Client struct {
	baseURL  string
	token    string
	orgID    string
	userID   string
	clientID string

	heartbeatInterval time.Duration
	reconnectInterval time.Duration
	queryParams       map[string]string
	dialer            *websocket.Dialer

	mu          sync.Mutex
	conn        *websocket.Conn
	connected   bool
	closed      bool
	pingSeq     int
	lastSentSeq int
	hasLastSeq  bool
	subscribed  map[string]struct{}
	channels    map[string]*Channel

	writeMu sync.Mutex

	handlersMu       sync.RWMutex
	messageHandlers  map[uint64]MessageHandler
	errorHandlers    map[uint64]ErrorHandler
	stateHandlers    map[uint64]StateHandler
	channelHandlers  map[string]map[string]map[uint64]ChannelEventHandler
	nextHandlerID    uint64

	closeCh chan struct{}
}

// NewClient creates a Client targeting baseURL (e.g. "wss://flux.example.com/v1/ws").
// http:// and https:// schemes are auto-upgraded to ws:// / wss://.
func NewClient(baseURL, token, orgID string, opts ...Option) (*Client, error) {
	if baseURL == "" {
		return nil, fmt.Errorf("flux: baseURL is required")
	}
	if token == "" {
		return nil, fmt.Errorf("flux: token is required")
	}
	if orgID == "" {
		return nil, fmt.Errorf("flux: orgID is required")
	}

	c := &Client{
		baseURL:           baseURL,
		token:             token,
		orgID:             orgID,
		clientID:          randomClientID(),
		heartbeatInterval: defaultHeartbeatInterval,
		reconnectInterval: defaultReconnectInterval,
		queryParams:       make(map[string]string),
		dialer:            websocket.DefaultDialer,
		subscribed:        make(map[string]struct{}),
		channels:          make(map[string]*Channel),
		messageHandlers:   make(map[uint64]MessageHandler),
		errorHandlers:     make(map[uint64]ErrorHandler),
		stateHandlers:     make(map[uint64]StateHandler),
		channelHandlers:   make(map[string]map[string]map[uint64]ChannelEventHandler),
		closeCh:           make(chan struct{}),
	}
	for _, opt := range opts {
		opt(c)
	}
	return c, nil
}

// Connect opens the WebSocket connection (no-op if already open) and starts
// the read pump, heartbeat, and auto-reconnect loop.
func (c *Client) Connect() {
	c.mu.Lock()
	if c.conn != nil {
		c.mu.Unlock()
		return
	}
	c.closed = false
	c.mu.Unlock()
	go c.run()
}

// IsConnected returns whether the underlying socket is currently open.
func (c *Client) IsConnected() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.connected
}

// Disconnect closes the connection and stops the auto-reconnect loop.
func (c *Client) Disconnect() {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return
	}
	c.closed = true
	conn := c.conn
	c.conn = nil
	c.connected = false
	c.mu.Unlock()
	close(c.closeCh)
	if conn != nil {
		_ = conn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
		_ = conn.Close()
	}
}

// Subscribe registers a single channel on the server and returns a handle
// for binding event handlers.
func (c *Client) Subscribe(channel string) (*Channel, error) {
	topics := normalizeTopics([]string{channel})
	if len(topics) == 0 {
		return nil, ErrEmptyTopic
	}
	if err := c.send(ChannelSubscription, EventSubscribe, topics, MessageTypeAction); err != nil {
		return nil, err
	}
	return c.getOrCreateChannel(topics[0]), nil
}

// SubscribeMany subscribes to a batch of topics in a single request.
func (c *Client) SubscribeMany(topics []string) error {
	normalized := normalizeTopics(topics)
	if len(normalized) == 0 {
		return ErrEmptyTopic
	}
	return c.send(ChannelSubscription, EventSubscribe, normalized, MessageTypeAction)
}

// Unsubscribe unsubscribes from a single channel and removes its handlers.
func (c *Client) Unsubscribe(channel string) error {
	topics := normalizeTopics([]string{channel})
	if len(topics) == 0 {
		return ErrEmptyTopic
	}
	if err := c.send(ChannelSubscription, EventUnsubscribe, topics, MessageTypeAction); err != nil {
		return err
	}
	c.clearChannel(topics[0])
	return nil
}

// UnsubscribeMany unsubscribes from a batch of topics. Bound handlers for
// those topics are NOT removed (use Unsubscribe(name) when you also want to
// drop handlers).
func (c *Client) UnsubscribeMany(topics []string) error {
	normalized := normalizeTopics(topics)
	if len(normalized) == 0 {
		return ErrEmptyTopic
	}
	return c.send(ChannelSubscription, EventUnsubscribe, normalized, MessageTypeAction)
}

// Send writes an action message on the given channel.
func (c *Client) Send(channel, event string, data any) error {
	return c.send(channel, event, data, MessageTypeAction)
}

// SubscribedTopics returns the topics the server has currently acknowledged.
func (c *Client) SubscribedTopics() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make([]string, 0, len(c.subscribed))
	for t := range c.subscribed {
		out = append(out, t)
	}
	return out
}

// OnMessage registers a handler invoked for every received message.
// Returns a cancel func that removes the handler.
func (c *Client) OnMessage(h MessageHandler) func() {
	id := c.allocID()
	c.handlersMu.Lock()
	c.messageHandlers[id] = h
	c.handlersMu.Unlock()
	return func() {
		c.handlersMu.Lock()
		delete(c.messageHandlers, id)
		c.handlersMu.Unlock()
	}
}

// OnError registers a handler invoked for transient socket errors.
func (c *Client) OnError(h ErrorHandler) func() {
	id := c.allocID()
	c.handlersMu.Lock()
	c.errorHandlers[id] = h
	c.handlersMu.Unlock()
	return func() {
		c.handlersMu.Lock()
		delete(c.errorHandlers, id)
		c.handlersMu.Unlock()
	}
}

// OnState registers a connection-state handler.
func (c *Client) OnState(h StateHandler) func() {
	id := c.allocID()
	c.handlersMu.Lock()
	c.stateHandlers[id] = h
	c.handlersMu.Unlock()
	return func() {
		c.handlersMu.Lock()
		delete(c.stateHandlers, id)
		c.handlersMu.Unlock()
	}
}

// Bind registers a handler for a specific channel + event.
func (c *Client) Bind(channel, event string, h ChannelEventHandler) (func(), error) {
	ch := normalizeTopic(channel)
	ev := normalizeTopic(event)
	if ch == "" || ev == "" {
		return nil, ErrEmptyTopic
	}
	id := c.allocID()
	c.handlersMu.Lock()
	events, ok := c.channelHandlers[ch]
	if !ok {
		events = make(map[string]map[uint64]ChannelEventHandler)
		c.channelHandlers[ch] = events
	}
	handlers, ok := events[ev]
	if !ok {
		handlers = make(map[uint64]ChannelEventHandler)
		events[ev] = handlers
	}
	handlers[id] = h
	c.handlersMu.Unlock()

	return func() {
		c.handlersMu.Lock()
		defer c.handlersMu.Unlock()
		if events, ok := c.channelHandlers[ch]; ok {
			if hs, ok := events[ev]; ok {
				delete(hs, id)
				if len(hs) == 0 {
					delete(events, ev)
				}
			}
			if len(events) == 0 {
				delete(c.channelHandlers, ch)
			}
		}
	}, nil
}

// Unbind drops all handlers for a channel. Pass a non-empty event to drop
// only handlers for that event.
func (c *Client) Unbind(channel, event string) {
	ch := normalizeTopic(channel)
	if ch == "" {
		return
	}
	c.handlersMu.Lock()
	defer c.handlersMu.Unlock()
	events, ok := c.channelHandlers[ch]
	if !ok {
		return
	}
	if event == "" {
		delete(c.channelHandlers, ch)
		return
	}
	delete(events, normalizeTopic(event))
	if len(events) == 0 {
		delete(c.channelHandlers, ch)
	}
}

// -- internals -----------------------------------------------------------

func (c *Client) allocID() uint64 {
	c.handlersMu.Lock()
	defer c.handlersMu.Unlock()
	c.nextHandlerID++
	return c.nextHandlerID
}

func (c *Client) run() {
	attempt := 0
	for {
		c.mu.Lock()
		if c.closed {
			c.mu.Unlock()
			return
		}
		c.mu.Unlock()

		dialURL, err := c.buildURL()
		if err != nil {
			c.emitError(err)
			c.emitState(StateError)
			return
		}

		conn, _, err := c.dialer.Dial(dialURL, nil)
		if err != nil {
			c.emitError(err)
			c.emitState(StateError)
			if c.sleepBackoff(&attempt) {
				return
			}
			continue
		}

		c.mu.Lock()
		c.conn = conn
		c.connected = true
		c.pingSeq = 1
		c.hasLastSeq = false
		c.mu.Unlock()

		attempt = 0
		c.emitState(StateConnected)
		c.resubscribe()

		stopHeartbeat := make(chan struct{})
		go c.heartbeat(conn, stopHeartbeat)
		c.readLoop(conn)
		close(stopHeartbeat)

		c.mu.Lock()
		c.connected = false
		c.conn = nil
		closed := c.closed
		c.mu.Unlock()
		c.emitState(StateDisconnected)

		if closed {
			return
		}
		if c.sleepBackoff(&attempt) {
			return
		}
	}
}

func (c *Client) sleepBackoff(attempt *int) (closed bool) {
	delay := time.Duration(float64(c.reconnectInterval) * math.Pow(2, float64(*attempt)))
	if delay > maxReconnectInterval {
		delay = maxReconnectInterval
	}
	*attempt++
	select {
	case <-time.After(delay):
		return false
	case <-c.closeCh:
		return true
	}
}

func (c *Client) heartbeat(conn *websocket.Conn, stop <-chan struct{}) {
	c.mu.Lock()
	c.lastSentSeq = c.pingSeq
	c.hasLastSeq = true
	c.mu.Unlock()
	_ = c.sendOn(conn, ChannelHealthCheck, EventPing, strconv.Itoa(c.pingSeq), MessageTypeAction)

	t := time.NewTicker(c.heartbeatInterval)
	defer t.Stop()
	for {
		select {
		case <-stop:
			return
		case <-t.C:
			c.mu.Lock()
			seq := c.pingSeq
			c.lastSentSeq = seq
			c.hasLastSeq = true
			c.pingSeq++
			c.mu.Unlock()
			if err := c.sendOn(conn, ChannelHealthCheck, EventPing, strconv.Itoa(seq), MessageTypeAction); err != nil {
				c.emitError(err)
				_ = conn.Close()
				return
			}
		}
	}
}

func (c *Client) readLoop(conn *websocket.Conn) {
	for {
		_, payload, err := conn.ReadMessage()
		if err != nil {
			if !websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway) {
				c.emitError(err)
			}
			return
		}
		var msg SocketMessage
		if err := json.Unmarshal(payload, &msg); err != nil {
			c.emitError(fmt.Errorf("flux: received non-JSON message: %w", err))
			continue
		}
		if msg.Event == EventPongReply && !c.isExpectedPong(msg.Data) {
			c.emitError(fmt.Errorf("flux: pong out of sync, reconnecting"))
			_ = conn.Close()
			return
		}
		if msg.Event == EventSubscribe || msg.Event == EventUnsubscribe {
			c.syncSubscribed(msg.Data)
		}
		c.emitChannelEvent(msg)
		c.emitMessage(msg)
	}
}

func (c *Client) send(channel, event string, data any, mt MessageType) error {
	c.mu.Lock()
	conn := c.conn
	connected := c.connected
	c.mu.Unlock()
	if !connected || conn == nil {
		return ErrNotConnected
	}
	return c.sendOn(conn, channel, event, data, mt)
}

func (c *Client) sendOn(conn *websocket.Conn, channel, event string, data any, mt MessageType) error {
	msg := SocketMessage{
		Type:      mt,
		Channel:   channel,
		Event:     event,
		Data:      data,
		Timestamp: time.Now().Unix(),
		RequestID: randomRequestID(),
	}
	buf, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	return conn.WriteMessage(websocket.TextMessage, buf)
}

func (c *Client) buildURL() (string, error) {
	u, err := url.Parse(c.baseURL)
	if err != nil {
		return "", fmt.Errorf("flux: parse baseURL: %w", err)
	}
	switch u.Scheme {
	case "http":
		u.Scheme = "ws"
	case "https":
		u.Scheme = "wss"
	case "ws", "wss":
	default:
		return "", fmt.Errorf("flux: unsupported scheme %q", u.Scheme)
	}
	q := u.Query()
	q.Set("token", c.token)
	q.Set("orgId", c.orgID)
	q.Set("cli", c.clientID)
	if c.userID != "" {
		q.Set("userId", c.userID)
	}
	for k, v := range c.queryParams {
		q.Set(k, v)
	}
	u.RawQuery = q.Encode()
	return u.String(), nil
}

func (c *Client) isExpectedPong(content any) bool {
	c.mu.Lock()
	last := c.lastSentSeq
	has := c.hasLastSeq
	c.mu.Unlock()
	if !has {
		return false
	}
	switch v := content.(type) {
	case string:
		n, err := strconv.Atoi(v)
		return err == nil && n == last
	case float64:
		return !math.IsNaN(v) && !math.IsInf(v, 0) && int(v) == last
	case int:
		return v == last
	}
	return false
}

func (c *Client) syncSubscribed(content any) {
	arr, ok := content.([]any)
	if !ok {
		return
	}
	next := make(map[string]struct{}, len(arr))
	for _, v := range arr {
		if s, ok := v.(string); ok && s != "" {
			next[s] = struct{}{}
		}
	}
	c.mu.Lock()
	c.subscribed = next
	c.mu.Unlock()
}

func (c *Client) resubscribe() {
	c.mu.Lock()
	topics := make([]string, 0, len(c.subscribed))
	for t := range c.subscribed {
		topics = append(topics, t)
	}
	c.mu.Unlock()
	if len(topics) == 0 {
		return
	}
	_ = c.send(ChannelSubscription, EventSubscribe, topics, MessageTypeAction)
}

func (c *Client) getOrCreateChannel(name string) *Channel {
	c.mu.Lock()
	defer c.mu.Unlock()
	if ch, ok := c.channels[name]; ok {
		return ch
	}
	ch := &Channel{client: c, Name: name}
	c.channels[name] = ch
	return ch
}

func (c *Client) clearChannel(name string) {
	c.handlersMu.Lock()
	delete(c.channelHandlers, name)
	c.handlersMu.Unlock()
	c.mu.Lock()
	delete(c.channels, name)
	c.mu.Unlock()
}

func (c *Client) emitMessage(msg SocketMessage) {
	c.handlersMu.RLock()
	handlers := make([]MessageHandler, 0, len(c.messageHandlers))
	for _, h := range c.messageHandlers {
		handlers = append(handlers, h)
	}
	c.handlersMu.RUnlock()
	for _, h := range handlers {
		h(msg)
	}
}

func (c *Client) emitError(err error) {
	c.handlersMu.RLock()
	handlers := make([]ErrorHandler, 0, len(c.errorHandlers))
	for _, h := range c.errorHandlers {
		handlers = append(handlers, h)
	}
	c.handlersMu.RUnlock()
	for _, h := range handlers {
		h(err)
	}
}

func (c *Client) emitState(state ConnectionState) {
	c.handlersMu.RLock()
	handlers := make([]StateHandler, 0, len(c.stateHandlers))
	for _, h := range c.stateHandlers {
		handlers = append(handlers, h)
	}
	c.handlersMu.RUnlock()
	for _, h := range handlers {
		h(state)
	}
}

func (c *Client) emitChannelEvent(msg SocketMessage) {
	ch := normalizeTopic(msg.Channel)
	ev := normalizeTopic(msg.Event)
	if ch == "" || ev == "" {
		return
	}
	c.handlersMu.RLock()
	events, ok := c.channelHandlers[ch]
	if !ok {
		c.handlersMu.RUnlock()
		return
	}
	handlersMap, ok := events[ev]
	if !ok {
		c.handlersMu.RUnlock()
		return
	}
	handlers := make([]ChannelEventHandler, 0, len(handlersMap))
	for _, h := range handlersMap {
		handlers = append(handlers, h)
	}
	c.handlersMu.RUnlock()
	for _, h := range handlers {
		h(msg.Data, msg)
	}
}

// Channel is a convenience handle returned by Subscribe; it binds /
// unsubscribes by name against its parent client.
type Channel struct {
	client *Client
	Name   string
}

// Bind registers an event handler for this channel.
func (ch *Channel) Bind(event string, h ChannelEventHandler) (func(), error) {
	return ch.client.Bind(ch.Name, event, h)
}

// Unbind drops handlers on this channel (all events if event == "").
func (ch *Channel) Unbind(event string) {
	ch.client.Unbind(ch.Name, event)
}

// Unsubscribe leaves the channel on the server and drops handlers.
func (ch *Channel) Unsubscribe() error {
	return ch.client.Unsubscribe(ch.Name)
}

// Send writes an action message on this channel.
func (ch *Channel) Send(event string, data any) error {
	return ch.client.Send(ch.Name, event, data)
}

// -- helpers -------------------------------------------------------------

func normalizeTopic(s string) string {
	out := []rune(s)
	start := 0
	end := len(out)
	for start < end && isSpace(out[start]) {
		start++
	}
	for end > start && isSpace(out[end-1]) {
		end--
	}
	return string(out[start:end])
}

func normalizeTopics(in []string) []string {
	seen := make(map[string]struct{}, len(in))
	out := make([]string, 0, len(in))
	for _, t := range in {
		n := normalizeTopic(t)
		if n == "" {
			continue
		}
		if _, ok := seen[n]; ok {
			continue
		}
		seen[n] = struct{}{}
		out = append(out, n)
	}
	return out
}

func isSpace(r rune) bool {
	return r == ' ' || r == '\t' || r == '\n' || r == '\r'
}

func randomClientID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 36)
	}
	return hex.EncodeToString(b[:])
}

func randomRequestID() string {
	var b [10]byte
	if _, err := rand.Read(b[:]); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 36)
	}
	return hex.EncodeToString(b[:])
}
