package lowcodb

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// newGatewayServer serves the manager's discovery route and a gateway at
// /gateway/<hash>, recording every path it sees.
func newGatewayServer(t *testing.T, hash string) (*httptest.Server, *[]string, *int32) {
	t.Helper()
	var paths []string
	var discoveries int32
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/lowcodb/bases/gateway-by-schema/", func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&discoveries, 1)
		schema := strings.TrimPrefix(r.URL.Path, "/v1/lowcodb/bases/gateway-by-schema/")
		if schema == "unknown" {
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":{"message":"AAS-00102","code":404,"details":"no base with schema"}}`))
			return
		}
		base := "http://" + r.Host
		_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]any{
			"gatewayId":   "gw-1",
			"hash":        hash,
			"contextPath": "/gateway/" + hash,
			"url":         base + "/gateway/" + hash,
			"internalUrl": "http://gateway-svc-gw-1.prod.svc:80/gateway/" + hash,
			"gatewayType": "dedicated",
		}})
	})
	mux.HandleFunc("/gateway/", func(w http.ResponseWriter, r *http.Request) {
		paths = append(paths, r.Method+" "+r.URL.RequestURI()+" key="+r.Header.Get("X-Api-Key")+" auth="+r.Header.Get("Authorization"))
		switch {
		case strings.Contains(r.URL.Path, "/gateway/stale/"):
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":"route not found"}`))
		case strings.HasSuffix(r.URL.Path, "/v1/over"):
			w.WriteHeader(http.StatusPaymentRequired)
			_, _ = w.Write([]byte(`{"code":"QUOTA_EXCEEDED","message":"plan cap reached","meter":"sch_over_create","consumed":100,"included":100,"hard_cap":100,"period_end":"2026-11-01T00:00:00Z","app_key":"hrms","upgrade":{"app_key":"hrms","plans":["pro"]}}`))
		case strings.HasSuffix(r.URL.Path, "/count"):
			_, _ = w.Write([]byte(`{"data":{"count":3}}`))
		case strings.Contains(r.URL.Path, "/v1/fn/"):
			_, _ = w.Write([]byte(`{"data":{"ok":true}}`))
		case strings.HasSuffix(r.URL.Path, "/v1/transactions"):
			_, _ = w.Write([]byte(`{"data":{"results":[{"id":"r1"}]}}`))
		case r.Method == http.MethodGet && !strings.HasSuffix(r.URL.Path, "/r1"):
			// A collection read answers a list.
			_, _ = w.Write([]byte(`{"data":[{"id":"r1","name":"Ada"}]}`))
		default:
			_, _ = w.Write([]byte(`{"data":{"id":"r1","name":"Ada"}}`))
		}
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv, &paths, &discoveries
}

func newTestClient(t *testing.T, srv *httptest.Server, token string, opts ...Option) *Client {
	t.Helper()
	u, _ := parseBase(srv.URL)
	c, err := NewClient(token, append([]Option{withBaseURL(u)}, opts...)...)
	if err != nil {
		t.Fatal(err)
	}
	return c
}

// Record methods keep (schema, table) but go through the schema's gateway, resolved
// once and cached; the API key travels as X-Api-Key.
func TestDataCallsGoThroughTheResolvedGateway(t *testing.T) {
	srv, paths, discoveries := newGatewayServer(t, "h1")
	c := newTestClient(t, srv, "lc_secret")
	ctx := context.Background()

	if _, err := c.CreateRecord(ctx, "sch", "leads", Record{"name": "Ada"}); err != nil {
		t.Fatal(err)
	}
	if _, err := c.ListRecords(ctx, "sch", "leads", &ListParams{PageNo: 2, Size: 10, Filter: "a=1"}); err != nil {
		t.Fatal(err)
	}
	if _, err := c.CountViewRecords(ctx, "sch", "hot leads", nil); err != nil {
		t.Fatal(err)
	}
	var fnOut map[string]any
	if err := c.InvokeFunction(ctx, "sch", "score-lead", map[string]any{"id": 1}, &fnOut); err != nil {
		t.Fatal(err)
	}
	if _, err := c.ExecuteTransaction(ctx, "sch", []TransactionOperation{{Type: "create", Table: "leads", Record: Record{"a": 1}}}); err != nil {
		t.Fatal(err)
	}

	want := []string{
		"POST /gateway/h1/v1/leads",
		"GET /gateway/h1/v1/leads?filter=a%3D1&pageNo=2&size=10",
		"GET /gateway/h1/v1/views/hot%20leads/count",
		"POST /gateway/h1/v1/fn/score-lead",
		"POST /gateway/h1/v1/transactions",
	}
	if len(*paths) != len(want) {
		t.Fatalf("paths: %v", *paths)
	}
	for i, w := range want {
		if !strings.HasPrefix((*paths)[i], w+" ") {
			t.Fatalf("call %d: want %s, got %s", i, w, (*paths)[i])
		}
		if !strings.Contains((*paths)[i], "key=lc_secret auth=") || strings.Contains((*paths)[i], "Bearer") {
			t.Fatalf("api key must travel as X-Api-Key only: %s", (*paths)[i])
		}
	}
	if atomic.LoadInt32(discoveries) != 1 {
		t.Fatalf("the gateway must be looked up once for five calls, got %d", *discoveries)
	}
}

// A pinned gateway is never looked up; a full URL is used as given.
func TestPinnedGatewaySkipsDiscovery(t *testing.T) {
	srv, paths, discoveries := newGatewayServer(t, "h1")
	c := newTestClient(t, srv, "user-token", WithGateway("sch", "/gateway/pinned"), WithGateway("other", srv.URL+"/gateway/full"))
	ctx := context.Background()
	if _, err := c.GetRecord(ctx, "sch", "leads", "r1"); err != nil {
		t.Fatal(err)
	}
	if _, err := c.GetRecord(ctx, "other", "leads", "r1"); err != nil {
		t.Fatal(err)
	}
	if atomic.LoadInt32(discoveries) != 0 {
		t.Fatalf("pinned gateways must not be looked up")
	}
	if !strings.HasPrefix((*paths)[0], "GET /gateway/pinned/v1/leads/r1 ") || !strings.HasPrefix((*paths)[1], "GET /gateway/full/v1/leads/r1 ") {
		t.Fatalf("paths: %v", *paths)
	}
	if !strings.Contains((*paths)[0], "auth=Bearer user-token") || !strings.Contains((*paths)[0], "key= ") {
		t.Fatalf("a user token travels as Bearer: %s", (*paths)[0])
	}
}

// The internal origin picks the gateway's in-cluster address.
func TestInternalOriginUsesInternalURL(t *testing.T) {
	srv, _, _ := newGatewayServer(t, "h1")
	c := newTestClient(t, srv, "lc_k", WithGatewayOrigin(GatewayOriginInternal))
	base, pinned, err := c.gatewayBase(context.Background(), "sch")
	if err != nil || pinned || base != "http://gateway-svc-gw-1.prod.svc:80/gateway/h1" {
		t.Fatalf("base=%q pinned=%v err=%v", base, pinned, err)
	}
}

// A 404 from a looked-up gateway triggers one fresh lookup (the hash may have been
// regenerated); a pinned gateway's 404 is returned as is.
func TestStaleGatewayIsReResolvedOnce(t *testing.T) {
	srv, paths, discoveries := newGatewayServer(t, "h1")
	c := newTestClient(t, srv, "lc_k")
	c.gatewayCache = map[string]cachedGateway{"sch": {base: srv.URL + "/gateway/stale", expires: time.Now().Add(time.Hour)}}
	if _, err := c.GetRecord(context.Background(), "sch", "leads", "r1"); err != nil {
		t.Fatalf("expected success after re-resolve, got %v", err)
	}
	if len(*paths) != 2 || !strings.HasPrefix((*paths)[0], "GET /gateway/stale/") || !strings.HasPrefix((*paths)[1], "GET /gateway/h1/") {
		t.Fatalf("paths: %v", *paths)
	}
	if atomic.LoadInt32(discoveries) != 1 {
		t.Fatalf("exactly one re-resolve, got %d", *discoveries)
	}
}

func TestUnknownSchemaSurfacesTheManagerError(t *testing.T) {
	srv, _, _ := newGatewayServer(t, "h1")
	c := newTestClient(t, srv, "lc_k")
	_, err := c.ListRecords(context.Background(), "unknown", "t", nil)
	var reqErr *RequestError
	if !errors.As(err, &reqErr) || reqErr.StatusCode != http.StatusNotFound {
		t.Fatalf("expected the discovery 404, got %v", err)
	}
}

// A 402 QUOTA_EXCEEDED from the gateway is a typed error carrying the plane's body.
func TestQuotaExceededIsTyped(t *testing.T) {
	srv, _, _ := newGatewayServer(t, "h1")
	c := newTestClient(t, srv, "lc_k")
	_, err := c.CreateRecord(context.Background(), "sch", "over", Record{})
	var q *QuotaExceededError
	if !errors.As(err, &q) || !IsQuotaExceeded(err) {
		t.Fatalf("expected QuotaExceededError, got %T %v", err, err)
	}
	if q.StatusCode != 402 || q.Meter != "sch_over_create" || q.Consumed != 100 || q.Included != 100 || q.HardCap == nil || *q.HardCap != 100 {
		t.Fatalf("fields: %+v", q)
	}
	if q.AppKey != "hrms" || q.UpgradeAppKey != "hrms" || len(q.UpgradePlans) != 1 || q.PeriodEnd != "2026-11-01T00:00:00Z" {
		t.Fatalf("upgrade fields: %+v", q)
	}
	var reqErr *RequestError
	if !errors.As(err, &reqErr) {
		t.Fatalf("must still unwrap to RequestError")
	}
}

// GatewayClient addresses a gateway without a schema.
func TestGatewayClient(t *testing.T) {
	srv, paths, discoveries := newGatewayServer(t, "h1")
	c := newTestClient(t, srv, "lc_k")
	g := c.Gateway("/gateway/direct")
	if g.URL() != srv.URL+"/gateway/direct" {
		t.Fatalf("url: %s", g.URL())
	}
	if _, err := g.ListViewRecords(context.Background(), "v", nil); err != nil {
		t.Fatal(err)
	}
	if _, err := g.ExecuteTransaction(context.Background(), nil); err != nil {
		t.Fatal(err)
	}
	if atomic.LoadInt32(discoveries) != 0 || !strings.HasPrefix((*paths)[0], "GET /gateway/direct/v1/views/v ") || !strings.HasPrefix((*paths)[1], "POST /gateway/direct/v1/transactions ") {
		t.Fatalf("paths=%v discoveries=%d", *paths, *discoveries)
	}
}

func TestRoutesEscapeSegments(t *testing.T) {
	if got := tableRoute("a/b", "id?1"); got != "/v1/a%2Fb/id%3F1" {
		t.Fatalf("got %s", got)
	}
	if got := viewRoute("my view"); got != "/v1/views/my%20view" {
		t.Fatalf("got %s", got)
	}
}
