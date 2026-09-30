package flux

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

// fluxStub accepts connections and reports every subscription frame as
// "<sb|usb> <data as JSON>". Each accepted socket is sent on conns so a test
// can drop it.
type fluxStub struct {
	frames chan string
	conns  chan *websocket.Conn
	dialer *websocket.Dialer
}

func newFluxStub(t *testing.T) *fluxStub {
	t.Helper()
	stub := &fluxStub{frames: make(chan string, 64), conns: make(chan *websocket.Conn, 4)}
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("replay") != "1" {
			http.Error(w, "client must announce replay=1", http.StatusBadRequest)
			return
		}
		conn, err := (&websocket.Upgrader{}).Upgrade(w, r, nil)
		if err != nil {
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
			if msg.Channel == ChannelSubscription {
				stub.frames <- msg.Event + " " + string(msg.Data)
			}
		}
	}))
	t.Cleanup(srv.Close)
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
