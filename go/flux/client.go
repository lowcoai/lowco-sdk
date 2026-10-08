package flux

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/url"
	"sort"
	"strconv"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// DefaultWSURL is the fixed flux WebSocket endpoint every client connects to.
const DefaultWSURL = "wss://api.lowco.ai/v1/ws"

const (
	defaultHeartbeatInterval = 5 * time.Second
	defaultReconnectInterval = 1 * time.Second
	maxReconnectInterval     = 30 * time.Second
)

// Option configures a Client at construction time.
type Option func(*Client)

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
// effective backoff doubles on each failure and is capped at 30s. It starts
// over only once a socket answers its first ping.
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

// WithTokenProvider sets a function asked for the token before every
// connection attempt, so a long-lived client can hand over a fresh token
// before the old one expires. An error or empty token falls back to the
// stored token (NewClient's, or the last SetToken). After the server rejects
// a token the provider is asked once more, and the client stops reconnecting
// if it yields the same token (see ErrUnauthorized). ctx is cancelled by
// Disconnect.
func WithTokenProvider(provider func(ctx context.Context) (string, error)) Option {
	return func(c *Client) {
		if provider != nil {
			c.tokenProvider = provider
		}
	}
}

// Client is a thread-safe flux WebSocket client.
type Client struct {
	orgID    string
	clientID string

	heartbeatInterval time.Duration
	reconnectInterval time.Duration
	queryParams       map[string]string
	dialer            *websocket.Dialer
	tokenProvider     func(ctx context.Context) (string, error)

	mu          sync.Mutex
	conn        *websocket.Conn
	connected   bool
	pingSeq     int
	lastSentSeq int
	hasLastSeq  bool
	channels    map[string]*Channel

	// The reconnect loop's state, also guarded by mu.
	//
	// token is the stored token: NewClient's, then the last SetToken. It is
	// used when there is no provider or the provider yields none. tokenGen
	// counts changes to it, so a loop deciding whether to park can tell that
	// SetToken ran meanwhile.
	token    string
	tokenGen uint64
	// stop ends the running loop; nil while none runs. It is only called
	// with mu held, so a loop whose context is still live is the current one.
	stop context.CancelFunc
	// attempt counts reconnects since a socket last answered a ping; it sets
	// the backoff.
	attempt int
	// parked is non-nil while the loop waits for a token other than
	// rejectedToken, which the server turned away; closing it resumes the
	// loop.
	parked        chan struct{}
	rejectedToken string

	// subMu guards desired and is held across the frame that reports a
	// change to it, so a reconnect's replay cannot interleave with a
	// subscribe or unsubscribe and resurrect a released topic.
	subMu sync.Mutex
	// desired is what this client wants delivered: topic → event patterns
	// (AllEvents = every event). It is the client's own record, not a mirror
	// of the server's acks, so every reconnect replays it in full.
	desired map[string]map[string]struct{}

	writeMu sync.Mutex

	handlersMu      sync.RWMutex
	messageHandlers map[uint64]MessageHandler
	errorHandlers   map[uint64]ErrorHandler
	stateHandlers   map[uint64]StateHandler
	channelHandlers map[string]map[string]map[uint64]ChannelEventHandler
	nextHandlerID   uint64
}

// NewClient creates a Client that connects to the flux service at
// DefaultWSURL. token is required and may hold a user token or an API key;
// it is sent as the `token` query parameter on every connection, unless
// SetToken or a WithTokenProvider provider supplies a newer one.
func NewClient(token, orgID string, opts ...Option) (*Client, error) {
	if token == "" {
		return nil, fmt.Errorf("flux: token is required")
	}
	if orgID == "" {
		return nil, fmt.Errorf("flux: orgID is required")
	}

	c := &Client{
		token:             token,
		orgID:             orgID,
		clientID:          randomClientID(),
		heartbeatInterval: defaultHeartbeatInterval,
		reconnectInterval: defaultReconnectInterval,
		queryParams:       make(map[string]string),
		dialer:            websocket.DefaultDialer,
		desired:           make(map[string]map[string]struct{}),
		channels:          make(map[string]*Channel),
		messageHandlers:   make(map[uint64]MessageHandler),
		errorHandlers:     make(map[uint64]ErrorHandler),
		stateHandlers:     make(map[uint64]StateHandler),
		channelHandlers:   make(map[string]map[string]map[uint64]ChannelEventHandler),
	}
	for _, opt := range opts {
		opt(c)
	}
	return c, nil
}

// Connect opens the WebSocket connection and starts the read pump,
// heartbeat, and auto-reconnect loop. It is a no-op while that loop runs,
// except that a client stopped by an auth rejection retries at once.
func (c *Client) Connect() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.stop != nil {
		c.resumeLocked()
		return
	}
	ctx, stop := context.WithCancel(context.Background())
	c.stop = stop
	c.attempt = 0
	go c.run(ctx)
}

// SetToken replaces the stored token, which later connection attempts use
// when there is no provider or the provider yields none; an empty token is
// ignored, and the open socket keeps the token it connected with. A client
// stopped by an auth rejection resumes connecting at once when given a token
// other than the rejected one — unless Disconnect stopped it.
func (c *Client) SetToken(token string) {
	if token == "" {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if token != c.token {
		c.token = token
		c.tokenGen++
	}
	if token != c.rejectedToken {
		c.resumeLocked()
	}
}

// IsConnected returns whether the underlying socket is currently open.
func (c *Client) IsConnected() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.connected
}

// Disconnect closes the connection and stops the auto-reconnect loop, also
// one stopped by an auth rejection.
func (c *Client) Disconnect() {
	c.mu.Lock()
	if c.stop != nil {
		c.stop()
		c.stop = nil
	}
	c.parked = nil
	conn := c.conn
	c.conn = nil
	c.connected = false
	c.mu.Unlock()
	if conn != nil {
		// The heartbeat may be mid-write on this socket; gorilla allows one
		// writer at a time.
		c.writeMu.Lock()
		_ = conn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
		c.writeMu.Unlock()
		_ = conn.Close()
	}
}

// Subscribe asks the server for a channel's events and returns a handle for
// binding handlers. Pass event patterns to receive only the matching ones —
// Subscribe("channel:<schema>", "messages.*") — or none for every event.
//
// Subscribes add to what the client already holds on a topic, and only the
// difference is sent. While the socket is down the subscription is kept and
// sent on the next connect, so this returns nil rather than ErrNotConnected.
func (c *Client) Subscribe(channel string, events ...string) (*Channel, error) {
	subs := parseSubscriptions([]Subscription{{Topic: channel, Events: events}})
	if len(subs) == 0 {
		return nil, ErrEmptyTopic
	}
	if err := c.addSubscriptions(subs); err != nil {
		return nil, err
	}
	return c.getOrCreateChannel(subs[0].topic), nil
}

// SubscribeMany subscribes to every event of a batch of topics in one frame.
func (c *Client) SubscribeMany(topics []string) error {
	return c.SubscribeWith(bareSubscriptions(topics)...)
}

// SubscribeWith subscribes to a batch of topics, each with its own event
// filter, in one frame.
func (c *Client) SubscribeWith(subs ...Subscription) error {
	parsed := parseSubscriptions(subs)
	if len(parsed) == 0 {
		return ErrEmptyTopic
	}
	return c.addSubscriptions(parsed)
}

// Unsubscribe leaves a channel entirely and removes its handlers.
func (c *Client) Unsubscribe(channel string) error {
	subs := parseSubscriptions([]Subscription{{Topic: channel}})
	if len(subs) == 0 {
		return ErrEmptyTopic
	}
	if err := c.removeSubscriptions(subs); err != nil {
		return err
	}
	c.clearChannel(subs[0].topic)
	return nil
}

// UnsubscribeMany leaves a batch of topics entirely. Bound handlers for
// those topics are NOT removed (use Unsubscribe(name) when you also want to
// drop handlers).
func (c *Client) UnsubscribeMany(topics []string) error {
	return c.UnsubscribeWith(bareSubscriptions(topics)...)
}

// UnsubscribeWith drops event patterns: an entry with Events drops only
// those, and its topic once none is left; an entry without drops the topic
// whole. Bound handlers are not removed.
func (c *Client) UnsubscribeWith(subs ...Subscription) error {
	parsed := parseSubscriptions(subs)
	if len(parsed) == 0 {
		return ErrEmptyTopic
	}
	return c.removeSubscriptions(parsed)
}

// Send writes an action message on the given channel.
func (c *Client) Send(channel, event string, data any) error {
	return c.send(channel, event, data, MessageTypeAction)
}

// SubscribedTopics returns the topics this client holds (and replays on
// every reconnect).
func (c *Client) SubscribedTopics() []string {
	subs := c.Subscriptions()
	out := make([]string, len(subs))
	for i, sub := range subs {
		out[i] = sub.Topic
	}
	return out
}

// Subscriptions returns every held topic with the event patterns asked of
// it, sorted by topic.
func (c *Client) Subscriptions() []Subscription {
	c.subMu.Lock()
	defer c.subMu.Unlock()
	return c.subscriptionsLocked()
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

// OnError registers a handler invoked for transient socket errors, and with
// ErrUnauthorized when the server rejects the token.
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

func (c *Client) run(ctx context.Context) {
	for {
		token := c.resolveToken(ctx)
		dialURL, err := c.buildURL(token)
		if err != nil {
			c.emitError(err)
			c.emitState(StateError)
			c.mu.Lock()
			if ctx.Err() == nil {
				// Let a later Connect start over.
				c.stop()
				c.stop = nil
			}
			c.mu.Unlock()
			return
		}

		conn, _, err := c.dialer.DialContext(ctx, dialURL, nil)
		if err != nil {
			if ctx.Err() != nil {
				return // Disconnect abandoned the dial.
			}
			c.emitError(err)
			c.emitState(StateError)
			if c.sleepBackoff(ctx) {
				return
			}
			continue
		}

		c.mu.Lock()
		if ctx.Err() != nil {
			// Disconnect ran while the upgrade was finishing.
			c.mu.Unlock()
			_ = conn.Close()
			return
		}
		c.conn = conn
		c.connected = true
		c.pingSeq = 1
		c.hasLastSeq = false
		c.mu.Unlock()

		// The backoff is not reset here: the server completes the upgrade
		// before it checks the token, so a rejected token would reconnect at
		// the initial interval forever. The first pong resets it (readLoop).
		c.emitState(StateConnected)
		c.resubscribe()

		stopHeartbeat := make(chan struct{})
		go c.heartbeat(conn, stopHeartbeat)
		rejected := c.readLoop(conn)
		close(stopHeartbeat)
		_ = conn.Close()

		c.mu.Lock()
		if c.conn == conn {
			c.connected = false
			c.conn = nil
		}
		c.mu.Unlock()
		c.emitState(StateDisconnected)

		if ctx.Err() != nil {
			return
		}
		if rejected {
			if c.awaitNewToken(ctx, token) {
				return
			}
			continue
		}
		if c.sleepBackoff(ctx) {
			return
		}
	}
}

// resolveToken returns the token for the next connection attempt: the
// provider's when it yields one, else the stored token.
func (c *Client) resolveToken(ctx context.Context) string {
	if c.tokenProvider != nil {
		token, err := c.tokenProvider(ctx)
		if err == nil && token != "" {
			return token
		}
		if err != nil && ctx.Err() == nil {
			c.emitError(fmt.Errorf("flux: token provider: %w", err))
		}
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.token
}

// awaitNewToken follows a socket the server rejected for carrying token. A
// different token (from the provider, or stored by SetToken) is tried after
// the usual backoff. The same one would only be rejected again, so the loop
// parks, with no timer, until SetToken stores another token, Connect is
// called, or Disconnect ends the loop.
func (c *Client) awaitNewToken(ctx context.Context, token string) (closed bool) {
	for {
		c.mu.Lock()
		gen := c.tokenGen
		c.mu.Unlock()
		if c.resolveToken(ctx) != token {
			return c.sleepBackoff(ctx)
		}

		c.mu.Lock()
		if ctx.Err() != nil {
			c.mu.Unlock()
			return true
		}
		if c.tokenGen != gen {
			// SetToken ran while the provider was asked; decide again.
			c.mu.Unlock()
			continue
		}
		parked := make(chan struct{})
		c.parked = parked
		c.rejectedToken = token
		c.mu.Unlock()

		select {
		case <-parked:
			return false
		case <-ctx.Done():
			return true
		}
	}
}

// resumeLocked wakes a reconnect loop parked on a rejected token. The caller
// holds mu.
func (c *Client) resumeLocked() {
	if c.parked != nil {
		close(c.parked)
		c.parked = nil
	}
}

// sleepBackoff waits out the reconnect delay: the initial interval doubled
// per attempt since a socket last answered a ping, capped at 30s.
func (c *Client) sleepBackoff(ctx context.Context) (closed bool) {
	c.mu.Lock()
	if ctx.Err() != nil {
		c.mu.Unlock()
		return true
	}
	// Doubled as a float: after enough failures the product overflows
	// time.Duration.
	delay := maxReconnectInterval
	if d := float64(c.reconnectInterval) * math.Pow(2, float64(c.attempt)); d < float64(maxReconnectInterval) {
		delay = time.Duration(d)
	}
	c.attempt++
	c.mu.Unlock()

	t := time.NewTimer(delay)
	defer t.Stop()
	select {
	case <-t.C:
		return false
	case <-ctx.Done():
		return true
	}
}

// resetBackoff starts the reconnect backoff over once conn, still the
// current socket, answers a ping: only then has the server accepted it.
func (c *Client) resetBackoff(conn *websocket.Conn) {
	c.mu.Lock()
	if c.conn == conn {
		c.attempt = 0
	}
	c.mu.Unlock()
}

func (c *Client) heartbeat(conn *websocket.Conn, stop <-chan struct{}) {
	c.mu.Lock()
	first := c.pingSeq
	c.lastSentSeq = first
	c.hasLastSeq = true
	c.mu.Unlock()
	_ = c.sendOn(conn, ChannelHealthCheck, EventPing, strconv.Itoa(first), MessageTypeAction)

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

// readLoop pumps conn until it fails, and reports whether the server
// rejected the socket's token: an Unauthorized frame on flux:error, or a
// close with code 1008. Either is reported to OnError as ErrUnauthorized.
func (c *Client) readLoop(conn *websocket.Conn) (rejected bool) {
	for {
		_, payload, err := conn.ReadMessage()
		if err != nil {
			var closeErr *websocket.CloseError
			if errors.As(err, &closeErr) && closeErr.Code == websocket.ClosePolicyViolation {
				c.emitError(fmt.Errorf("%w: %w", ErrUnauthorized, err))
				return true
			}
			if !websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway) {
				c.emitError(err)
			}
			return false
		}
		var msg SocketMessage
		if err := json.Unmarshal(payload, &msg); err != nil {
			c.emitError(fmt.Errorf("flux: received non-JSON message: %w", err))
			continue
		}
		if msg.Event == EventPongReply {
			if !c.isExpectedPong(msg.Data) {
				c.emitError(fmt.Errorf("flux: pong out of sync, reconnecting"))
				_ = conn.Close()
				return false
			}
			c.resetBackoff(conn)
		}
		c.emitChannelEvent(msg)
		c.emitMessage(msg)
		if msg.Channel == ChannelError && msg.Event == EventUnauthorized {
			// The server closes the socket next; don't wait for it.
			c.emitError(unauthorizedError(msg))
			return true
		}
	}
}

// unauthorizedError wraps ErrUnauthorized with the message the server's
// error frame carries, if any.
func unauthorizedError(msg SocketMessage) error {
	if data, ok := msg.Data.(map[string]any); ok {
		if text, _ := data["message"].(string); text != "" {
			return fmt.Errorf("%w: %s", ErrUnauthorized, text)
		}
	}
	return ErrUnauthorized
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

func (c *Client) buildURL(token string) (string, error) {
	u, err := url.Parse(DefaultWSURL)
	if err != nil {
		return "", fmt.Errorf("flux: parse endpoint URL: %w", err)
	}
	q := u.Query()
	q.Set("token", token)
	q.Set("orgId", c.orgID)
	q.Set("cli", c.clientID)
	for k, v := range c.queryParams {
		q.Set(k, v)
	}
	// Tells the server this client re-sends every subscription on connect,
	// so it starts the socket clean.
	q.Set("replay", "1")
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

type parsedSubscription struct {
	topic string
	// events is nil for a bare topic: every event on subscribe, the whole
	// topic on unsubscribe.
	events []string
}

func parseSubscriptions(subs []Subscription) []parsedSubscription {
	out := make([]parsedSubscription, 0, len(subs))
	for _, sub := range subs {
		topic := normalizeTopic(sub.Topic)
		if topic == "" {
			continue
		}
		events := normalizeTopics(sub.Events)
		if len(events) == 0 {
			events = nil
		}
		out = append(out, parsedSubscription{topic: topic, events: events})
	}
	return out
}

func bareSubscriptions(topics []string) []Subscription {
	subs := make([]Subscription, len(topics))
	for i, topic := range topics {
		subs[i] = Subscription{Topic: topic}
	}
	return subs
}

// wireSubscription is one entry of an sb frame: a bare topic string when it
// stands for every event (the frame older servers read), otherwise
// {topic, events}. Not for usb, where a bare topic drops the whole topic.
func wireSubscription(topic string, events []string) any {
	if len(events) == 0 || (len(events) == 1 && events[0] == AllEvents) {
		return topic
	}
	return Subscription{Topic: topic, Events: events}
}

func (c *Client) addSubscriptions(subs []parsedSubscription) error {
	c.subMu.Lock()
	defer c.subMu.Unlock()
	var added []any
	for _, sub := range subs {
		held, ok := c.desired[sub.topic]
		if !ok {
			held = make(map[string]struct{})
			c.desired[sub.topic] = held
		}
		events := sub.events
		if events == nil {
			events = []string{AllEvents}
		}
		var fresh []string
		for _, e := range events {
			if _, dup := held[e]; dup {
				continue
			}
			held[e] = struct{}{}
			fresh = append(fresh, e)
		}
		if len(fresh) > 0 {
			added = append(added, wireSubscription(sub.topic, fresh))
		}
	}
	return c.sendSubscriptionsLocked(EventSubscribe, added)
}

func (c *Client) removeSubscriptions(subs []parsedSubscription) error {
	c.subMu.Lock()
	defer c.subMu.Unlock()
	var removed []any
	for _, sub := range subs {
		if sub.events == nil {
			delete(c.desired, sub.topic)
			removed = append(removed, sub.topic)
			continue
		}
		held, ok := c.desired[sub.topic]
		if !ok {
			continue
		}
		var dropped []string
		for _, e := range sub.events {
			if _, has := held[e]; has {
				delete(held, e)
				dropped = append(dropped, e)
			}
		}
		if len(held) == 0 {
			// Released whole, so the server drops the topic whatever it holds.
			delete(c.desired, sub.topic)
			removed = append(removed, sub.topic)
		} else if len(dropped) > 0 {
			// Always {topic, events}: a bare topic here, even for just "*",
			// would drop the patterns the topic still holds.
			removed = append(removed, Subscription{Topic: sub.topic, Events: dropped})
		}
	}
	return c.sendSubscriptionsLocked(EventUnsubscribe, removed)
}

// sendSubscriptionsLocked writes an sb/usb frame. A closed socket is not an
// error: the server keeps nothing for it, and the next connect replays
// desired. The caller holds subMu.
func (c *Client) sendSubscriptionsLocked(event string, entries []any) error {
	if len(entries) == 0 {
		return nil
	}
	err := c.send(ChannelSubscription, event, entries, MessageTypeAction)
	if errors.Is(err, ErrNotConnected) {
		return nil
	}
	return err
}

func (c *Client) subscriptionsLocked() []Subscription {
	out := make([]Subscription, 0, len(c.desired))
	for topic, held := range c.desired {
		events := make([]string, 0, len(held))
		for e := range held {
			events = append(events, e)
		}
		sort.Strings(events)
		out = append(out, Subscription{Topic: topic, Events: events})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Topic < out[j].Topic })
	return out
}

// resubscribe replays every subscription on a fresh socket, which the server
// knows nothing about.
func (c *Client) resubscribe() {
	c.subMu.Lock()
	defer c.subMu.Unlock()
	subs := c.subscriptionsLocked()
	entries := make([]any, len(subs))
	for i, sub := range subs {
		entries[i] = wireSubscription(sub.Topic, sub.Events)
	}
	_ = c.sendSubscriptionsLocked(EventSubscribe, entries)
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
