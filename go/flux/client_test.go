package flux

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

// fluxStub accepts connections and reports every subscription frame as
// "<sb|usb> <data as JSON>". Each accepted socket is sent on conns so a test
// can drop it, and every upgrade, accepted or rejected, on dials. Pings are
// answered with a pong unless holdPongs says otherwise.
type fluxStub struct {
	frames chan string
	conns  chan *websocket.Conn
	dials  chan stubDial
	dialer *websocket.Dialer
	done   chan struct{}

	mu       sync.Mutex
	reject   func(token string) bool
	mode     rejectMode
	pongGate chan struct{}
}

// stubDial is one upgrade the stub completed.
type stubDial struct {
	token string
	at    time.Time
}

// rejectMode is how the stub turns a token away after the upgrade.
type rejectMode int

const (
	// rejectFrameAndClose is what the server does: an Unauthorized frame on
	// flux:error, then a close with code 1008.
	rejectFrameAndClose rejectMode = iota
	rejectCloseOnly
	// rejectFrameOnly leaves the socket open after the frame.
	rejectFrameOnly
)

func newFluxStub(t *testing.T) *fluxStub {
	t.Helper()
	stub := &fluxStub{
		frames: make(chan string, 64),
		conns:  make(chan *websocket.Conn, 16),
		dials:  make(chan stubDial, 64),
		done:   make(chan struct{}),
	}
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/ws" {
			http.NotFound(w, r)
			return
		}
		if r.URL.Query().Get("replay") != "1" {
			http.Error(w, "client must announce replay=1", http.StatusBadRequest)
			return
		}
		conn, err := (&websocket.Upgrader{}).Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		token := r.URL.Query().Get("token")
		stub.dials <- stubDial{token: token, at: time.Now()}
		// Like the server, check the token only once the socket is upgraded.
		if mode, ok := stub.rejects(token); ok {
			turnAway(conn, mode)
			return
		}
		stub.conns <- conn
		for {
			var msg struct {
				Channel string          `json:"channel"`
				Event   string          `json:"event"`
				Data    json.RawMessage `json:"data"`
			}
			if err := conn.ReadJSON(&msg); err != nil {
				return
			}
			switch {
			case msg.Channel == ChannelSubscription:
				stub.frames <- msg.Event + " " + string(msg.Data)
			case msg.Event == EventPing:
				if !stub.awaitPong() {
					return
				}
				_ = conn.WriteJSON(SocketMessage{Type: MessageTypeSystem, Channel: ChannelHealthCheck, Event: EventPongReply, Data: msg.Data})
			}
		}
	}))
	t.Cleanup(srv.Close)
	t.Cleanup(func() { close(stub.done) })
	// The client always dials DefaultWSURL; send it to the stub instead.
	stub.dialer = &websocket.Dialer{
		NetDialContext: func(ctx context.Context, network, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, network, srv.Listener.Addr().String())
		},
		TLSClientConfig:  &tls.Config{InsecureSkipVerify: true},
		HandshakeTimeout: 5 * time.Second,
	}
	return stub
}

// rejectWhen makes the stub turn away, after the upgrade, every socket whose
// token match accepts.
func (s *fluxStub) rejectWhen(mode rejectMode, match func(token string) bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.mode = mode
	s.reject = match
}

func (s *fluxStub) rejects(token string) (rejectMode, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.reject == nil || !s.reject(token) {
		return 0, false
	}
	return s.mode, true
}

// holdPongs withholds every pong until release is called.
func (s *fluxStub) holdPongs() (release func()) {
	gate := make(chan struct{})
	s.mu.Lock()
	s.pongGate = gate
	s.mu.Unlock()
	var once sync.Once
	return func() { once.Do(func() { close(gate) }) }
}

func (s *fluxStub) awaitPong() bool {
	s.mu.Lock()
	gate := s.pongGate
	s.mu.Unlock()
	if gate == nil {
		return true
	}
	select {
	case <-gate:
		return true
	case <-s.done:
		return false
	}
}

// turnAway rejects an upgraded socket the way the server rejects a bad
// token, then reads until the client hangs up so no frame is lost to a reset.
func turnAway(conn *websocket.Conn, mode rejectMode) {
	if mode != rejectCloseOnly {
		_ = conn.WriteJSON(SocketMessage{
			Type:      MessageTypeError,
			Channel:   ChannelError,
			Event:     EventUnauthorized,
			Data:      map[string]string{"message": "Unauthorized"},
			Timestamp: time.Now().UnixMilli(),
		})
	}
	if mode != rejectFrameOnly {
		_ = conn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.ClosePolicyViolation, "unauthorized"))
	}
	_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	for {
		if _, _, err := conn.ReadMessage(); err != nil {
			return
		}
	}
}

func (s *fluxStub) nextDial(t *testing.T) stubDial {
	t.Helper()
	select {
	case d := <-s.dials:
		return d
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for the client to connect")
		return stubDial{}
	}
}

// quiet fails the test if the client connects within window.
func (s *fluxStub) quiet(t *testing.T, window time.Duration) {
	t.Helper()
	select {
	case d := <-s.dials:
		t.Fatalf("client reconnected with token %q, want it to stay down", d.token)
	case <-time.After(window):
	}
}

func (s *fluxStub) next(t *testing.T) string {
	t.Helper()
	select {
	case f := <-s.frames:
		return f
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for a subscription frame")
		return ""
	}
}

func (s *fluxStub) expect(t *testing.T, want ...string) {
	t.Helper()
	for _, w := range want {
		if got := s.next(t); got != w {
			t.Fatalf("frame = %s\nwant    %s", got, w)
		}
	}
}

func TestBuildURL(t *testing.T) {
	client, err := NewClient("t k&1", "org_1", WithClientID("cli-1"), WithQueryParam("app", "crm"), WithQueryParam("replay", "0"))
	if err != nil {
		t.Fatal(err)
	}
	got, err := client.buildURL("t k&1")
	if err != nil {
		t.Fatal(err)
	}
	want := "wss://api.lowco.ai/v1/ws?app=crm&cli=cli-1&orgId=org_1&replay=1&token=t+k%261"
	if got != want {
		t.Fatalf("buildURL = %s\nwant       %s", got, want)
	}
}

func TestSubscriptionFiltersAndReplay(t *testing.T) {
	stub := newFluxStub(t)
	client, err := NewClient("token", "org-1", WithDialer(stub.dialer), WithReconnectInterval(10*time.Millisecond))
	if err != nil {
		t.Fatal(err)
	}
	defer client.Disconnect()

	// Before the socket exists: kept, not an error, sent on connect.
	if err := client.SubscribeWith(
		Subscription{Topic: "agent:1"},
		Subscription{Topic: "channel:s", Events: []string{"messages.*"}},
	); err != nil {
		t.Fatalf("SubscribeWith while down = %v, want nil", err)
	}
	client.Connect()
	first := <-stub.conns
	stub.expect(t, `sb ["agent:1",{"topic":"channel:s","events":["messages.*"]}]`)

	// Only the pattern the topic does not hold yet goes out.
	if _, err := client.Subscribe("channel:s", "messages.*", "tasks.*"); err != nil {
		t.Fatal(err)
	}
	stub.expect(t, `sb [{"topic":"channel:s","events":["tasks.*"]}]`)

	if err := client.UnsubscribeWith(Subscription{Topic: "channel:s", Events: []string{"messages.*"}}); err != nil {
		t.Fatal(err)
	}
	if err := client.UnsubscribeMany([]string{"agent:1"}); err != nil {
		t.Fatal(err)
	}
	stub.expect(t,
		`usb [{"topic":"channel:s","events":["messages.*"]}]`,
		`usb ["agent:1"]`,
	)

	// A dropped socket: the new one gets everything still held, filters and all.
	_ = first.Close()
	<-stub.conns
	stub.expect(t, `sb [{"topic":"channel:s","events":["tasks.*"]}]`)

	// Releasing the last pattern drops the topic whole.
	if err := client.UnsubscribeWith(Subscription{Topic: "channel:s", Events: []string{"tasks.*"}}); err != nil {
		t.Fatal(err)
	}
	stub.expect(t, `usb ["channel:s"]`)
	if got := client.Subscriptions(); len(got) != 0 {
		t.Fatalf("Subscriptions() = %+v, want none", got)
	}
}

// A bare topic in a usb frame drops the topic whole, so dropping just "*"
// while other patterns are held must name it.
func TestUnsubscribeAllEventsPatternKeepsOthers(t *testing.T) {
	stub := newFluxStub(t)
	client, err := NewClient("token", "org-1", WithDialer(stub.dialer), WithReconnectInterval(10*time.Millisecond))
	if err != nil {
		t.Fatal(err)
	}
	defer client.Disconnect()

	if err := client.SubscribeWith(Subscription{Topic: "channel:s", Events: []string{"*", "messages.*"}}); err != nil {
		t.Fatal(err)
	}
	client.Connect()
	first := <-stub.conns
	stub.expect(t, `sb [{"topic":"channel:s","events":["*","messages.*"]}]`)

	if err := client.UnsubscribeWith(Subscription{Topic: "channel:s", Events: []string{"*"}}); err != nil {
		t.Fatal(err)
	}
	stub.expect(t, `usb [{"topic":"channel:s","events":["*"]}]`)
	if got := client.Subscriptions(); len(got) != 1 || len(got[0].Events) != 1 || got[0].Events[0] != "messages.*" {
		t.Fatalf("Subscriptions() = %+v, want channel:s [messages.*]", got)
	}

	// The replay agrees with what the server was left holding.
	_ = first.Close()
	<-stub.conns
	stub.expect(t, `sb [{"topic":"channel:s","events":["messages.*"]}]`)

	// Releasing the last pattern still drops the topic whole.
	if err := client.UnsubscribeWith(Subscription{Topic: "channel:s", Events: []string{"messages.*"}}); err != nil {
		t.Fatal(err)
	}
	stub.expect(t, `usb ["channel:s"]`)
	if got := client.Subscriptions(); len(got) != 0 {
		t.Fatalf("Subscriptions() = %+v, want none", got)
	}
}

func TestSubscribeWithoutEventsIsBare(t *testing.T) {
	stub := newFluxStub(t)
	client, err := NewClient("token", "org-1", WithDialer(stub.dialer))
	if err != nil {
		t.Fatal(err)
	}
	defer client.Disconnect()
	client.Connect()
	<-stub.conns

	for !client.IsConnected() {
		time.Sleep(5 * time.Millisecond)
	}
	if _, err := client.Subscribe("run:9"); err != nil {
		t.Fatal(err)
	}
	stub.expect(t, `sb ["run:9"]`)
	if got := client.SubscribedTopics(); len(got) != 1 || got[0] != "run:9" {
		t.Fatalf("SubscribedTopics() = %v", got)
	}
}

// collectErrors records what client reports to OnError.
func collectErrors(client *Client) <-chan error {
	errs := make(chan error, 64)
	client.OnError(func(err error) {
		select {
		case errs <- err:
		default:
		}
	})
	return errs
}

// awaitUnauthorized returns the next ErrUnauthorized reported on errs.
func awaitUnauthorized(t *testing.T, errs <-chan error) error {
	t.Helper()
	deadline := time.After(5 * time.Second)
	for {
		select {
		case err := <-errs:
			if errors.Is(err, ErrUnauthorized) {
				return err
			}
		case <-deadline:
			t.Fatal("timed out waiting for ErrUnauthorized")
			return nil
		}
	}
}

func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func backoffAttempt(c *Client) int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.attempt
}

// countingTokens is a provider yielding a new token on every call, so no
// rejection is ever of the token the client would try next.
func countingTokens() func(context.Context) (string, error) {
	var n atomic.Int64
	return func(context.Context) (string, error) {
		return fmt.Sprintf("token-%d", n.Add(1)), nil
	}
}

// The server upgrades before it checks the token, so a socket it then
// rejects must not reset the backoff: the gaps between attempts keep
// doubling rather than staying at the initial interval.
func TestRejectedUpgradeKeepsBackingOff(t *testing.T) {
	stub := newFluxStub(t)
	stub.rejectWhen(rejectFrameAndClose, func(string) bool { return true })
	const interval = 20 * time.Millisecond
	client, err := NewClient("token", "org-1", WithDialer(stub.dialer),
		WithReconnectInterval(interval), WithTokenProvider(countingTokens()))
	if err != nil {
		t.Fatal(err)
	}
	defer client.Disconnect()
	client.Connect()

	prev := stub.nextDial(t)
	for i := 0; i < 4; i++ {
		next := stub.nextDial(t)
		if gap, want := next.at.Sub(prev.at), interval<<i; gap < want {
			t.Fatalf("gap before attempt %d = %v, want >= %v: the upgrade reset the backoff", i+2, gap, want)
		}
		prev = next
	}
}

// Retrying a token the server rejected would only be rejected again, so the
// client stops, however the server says no.
func TestAuthRejectionStopsReconnecting(t *testing.T) {
	for _, tc := range []struct {
		name string
		mode rejectMode
	}{
		{"error frame then close 1008", rejectFrameAndClose},
		{"close 1008", rejectCloseOnly},
		{"error frame", rejectFrameOnly},
	} {
		t.Run(tc.name, func(t *testing.T) {
			stub := newFluxStub(t)
			stub.rejectWhen(tc.mode, func(token string) bool { return token == "stale" })
			const interval = 10 * time.Millisecond
			client, err := NewClient("stale", "org-1", WithDialer(stub.dialer), WithReconnectInterval(interval))
			if err != nil {
				t.Fatal(err)
			}
			errs := collectErrors(client)
			defer client.Disconnect()
			client.Connect()

			if d := stub.nextDial(t); d.token != "stale" {
				t.Fatalf("dialed with %q, want stale", d.token)
			}
			err = awaitUnauthorized(t, errs)
			var closeErr *websocket.CloseError
			if tc.mode == rejectCloseOnly && (!errors.As(err, &closeErr) || closeErr.Code != websocket.ClosePolicyViolation) {
				t.Fatalf("err = %v, want it to wrap the 1008 close", err)
			}
			// Still backing off, the client would dial at 10, 30, 70, 150
			// and 310ms.
			stub.quiet(t, 30*interval)
			if client.IsConnected() {
				t.Fatal("IsConnected() = true after the rejection")
			}
		})
	}
}

func TestTokenProviderReplacesRejectedToken(t *testing.T) {
	stub := newFluxStub(t)
	stub.rejectWhen(rejectFrameAndClose, func(token string) bool { return token == "stale" })
	var calls atomic.Int64
	provider := func(context.Context) (string, error) {
		if calls.Add(1) == 1 {
			return "stale", nil
		}
		return "fresh", nil
	}
	client, err := NewClient("initial", "org-1", WithDialer(stub.dialer),
		WithReconnectInterval(10*time.Millisecond), WithTokenProvider(provider))
	if err != nil {
		t.Fatal(err)
	}
	errs := collectErrors(client)
	defer client.Disconnect()
	client.Connect()

	if d := stub.nextDial(t); d.token != "stale" {
		t.Fatalf("first dial used %q, want the provider's stale", d.token)
	}
	awaitUnauthorized(t, errs)
	if d := stub.nextDial(t); d.token != "fresh" {
		t.Fatalf("after the rejection dialed with %q, want fresh", d.token)
	}
	<-stub.conns
	waitFor(t, "the fresh token's connection", client.IsConnected)
}

func TestTokenProviderErrorFallsBackToStoredToken(t *testing.T) {
	stub := newFluxStub(t)
	failure := errors.New("refresh failed")
	provider := func(context.Context) (string, error) { return "", failure }
	client, err := NewClient("initial", "org-1", WithDialer(stub.dialer), WithTokenProvider(provider))
	if err != nil {
		t.Fatal(err)
	}
	errs := collectErrors(client)
	defer client.Disconnect()
	client.SetToken("stored")
	client.Connect()

	if d := stub.nextDial(t); d.token != "stored" {
		t.Fatalf("dialed with %q, want the stored token", d.token)
	}
	select {
	case err := <-errs:
		if !errors.Is(err, failure) {
			t.Fatalf("err = %v, want the provider's error", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the provider's error was not reported")
	}
}

func TestSetTokenResumesParkedClient(t *testing.T) {
	stub := newFluxStub(t)
	stub.rejectWhen(rejectFrameAndClose, func(token string) bool { return token == "stale" })
	client, err := NewClient("stale", "org-1", WithDialer(stub.dialer), WithReconnectInterval(10*time.Millisecond))
	if err != nil {
		t.Fatal(err)
	}
	errs := collectErrors(client)
	defer client.Disconnect()
	client.Connect()

	stub.nextDial(t)
	awaitUnauthorized(t, errs)
	stub.quiet(t, 200*time.Millisecond)

	// Neither an empty token nor the rejected one is worth a dial.
	client.SetToken("")
	client.SetToken("stale")
	stub.quiet(t, 200*time.Millisecond)

	client.SetToken("fresh")
	if d := stub.nextDial(t); d.token != "fresh" {
		t.Fatalf("resumed with %q, want fresh", d.token)
	}
	<-stub.conns
	waitFor(t, "the fresh token's connection", client.IsConnected)
}

// Only a pong shows the server accepted the socket, so that, and not the
// upgrade, starts the backoff over.
func TestBackoffResetsOnFirstPong(t *testing.T) {
	stub := newFluxStub(t)
	rejected := 0 // only touched by the match func, under stub.mu
	stub.rejectWhen(rejectFrameAndClose, func(string) bool {
		rejected++
		return rejected <= 3
	})
	release := stub.holdPongs()
	defer release()
	client, err := NewClient("token", "org-1", WithDialer(stub.dialer),
		WithReconnectInterval(10*time.Millisecond), WithTokenProvider(countingTokens()))
	if err != nil {
		t.Fatal(err)
	}
	defer client.Disconnect()
	client.Connect()

	for i := 0; i < 4; i++ {
		stub.nextDial(t)
	}
	<-stub.conns
	waitFor(t, "the accepted connection", client.IsConnected)
	if got := backoffAttempt(client); got != 3 {
		t.Fatalf("attempt on an upgraded socket = %d, want 3 until it answers a ping", got)
	}

	release()
	waitFor(t, "the pong to reset the backoff", func() bool { return backoffAttempt(client) == 0 })
}

// A parked client retries on Connect, stops cleanly on Disconnect — after
// which SetToken does not bring it back — and starts over on a later Connect.
func TestParkedClientLifecycle(t *testing.T) {
	stub := newFluxStub(t)
	stub.rejectWhen(rejectFrameAndClose, func(token string) bool { return token == "stale" })
	client, err := NewClient("stale", "org-1", WithDialer(stub.dialer), WithReconnectInterval(10*time.Millisecond))
	if err != nil {
		t.Fatal(err)
	}
	errs := collectErrors(client)
	defer client.Disconnect()
	client.Connect()

	stub.nextDial(t)
	awaitUnauthorized(t, errs)
	stub.quiet(t, 100*time.Millisecond)

	// Connect retries the same token once, then parks again.
	client.Connect()
	if d := stub.nextDial(t); d.token != "stale" {
		t.Fatalf("Connect retried with %q, want stale", d.token)
	}
	awaitUnauthorized(t, errs)
	stub.quiet(t, 100*time.Millisecond)

	disconnected := make(chan struct{})
	go func() {
		client.Disconnect()
		close(disconnected)
	}()
	select {
	case <-disconnected:
	case <-time.After(5 * time.Second):
		t.Fatal("Disconnect hung on a parked client")
	}

	client.SetToken("fresh")
	stub.quiet(t, 100*time.Millisecond)

	client.Connect()
	if d := stub.nextDial(t); d.token != "fresh" {
		t.Fatalf("Connect after Disconnect dialed with %q, want fresh", d.token)
	}
	<-stub.conns
	waitFor(t, "the fresh token's connection", client.IsConnected)
	client.Disconnect()
	client.Disconnect()
	if client.IsConnected() {
		t.Fatal("IsConnected() = true after Disconnect")
	}
}
