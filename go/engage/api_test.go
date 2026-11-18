package engage

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"sync"
	"testing"
)

// served is one request an httptest server received.
type served struct {
	method  string
	path    string
	rawPath string
	headers http.Header
	body    []byte
}

// apiServer is an httptest server that answers every request with
// status/body and records it.
type apiServer struct {
	*httptest.Server
	mu       sync.Mutex
	requests []served
	status   int
	body     string
}

func newAPIServer(t *testing.T, status int, body string) *apiServer {
	t.Helper()
	s := &apiServer{status: status, body: body}
	s.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		s.mu.Lock()
		s.requests = append(s.requests, served{r.Method, r.URL.Path, r.URL.EscapedPath(), r.Header.Clone(), raw})
		s.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(s.status)
		_, _ = io.WriteString(w, s.body)
	}))
	t.Cleanup(s.Close)
	return s
}

func (s *apiServer) last(t *testing.T) served {
	t.Helper()
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.requests) == 0 {
		t.Fatal("no request received")
	}
	return s.requests[len(s.requests)-1]
}

func (s *apiServer) count() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.requests)
}

func (s *apiServer) lastJSON(t *testing.T) map[string]any {
	t.Helper()
	var out map[string]any
	if err := json.Unmarshal(s.last(t).body, &out); err != nil {
		t.Fatalf("body is not JSON: %v (%s)", err, s.last(t).body)
	}
	return out
}

func newServerClient(t *testing.T, s *apiServer, config Config) *Client {
	t.Helper()
	if config.APIKey == "" {
		config.APIKey = "lc_admin"
	}
	if config.OrgID == "" {
		config.OrgID = "org_1"
	}
	config.BaseURL = s.URL + "/"
	c, err := NewClient(config)
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func TestBaseURLDefaultsAndTrailingSlash(t *testing.T) {
	c, err := NewClient(Config{APIKey: "k", OrgID: "o"})
	if err != nil {
		t.Fatal(err)
	}
	if c.baseURL != DefaultBaseURL || c.trackURL != DefaultBaseURL+TrackPath {
		t.Errorf("default urls = %q %q", c.baseURL, c.trackURL)
	}
	c, err = NewClient(Config{APIKey: "k", OrgID: "o", BaseURL: " https://staging.example/// "})
	if err != nil {
		t.Fatal(err)
	}
	if c.trackURL != "https://staging.example/v1/engage/track" {
		t.Errorf("trackURL = %q", c.trackURL)
	}
}

func TestTrackUsesBaseURL(t *testing.T) {
	s := newAPIServer(t, 200, `{"status":1}`)
	c := newServerClient(t, s, Config{DeviceID: "dev_1"})
	if err := c.Track(context.Background(), "signup", Metadata{"plan": "pro"}, &EventOptions{EventTime: fixed}); err != nil {
		t.Fatal(err)
	}
	req := s.last(t)
	if req.method != http.MethodPost || req.path != TrackPath {
		t.Errorf("request = %s %s", req.method, req.path)
	}
	want := `{"id":"","event_name":"signup","event_data":{"plan":"pro"},"device_id":"dev_1","event_time":"2026-09-30T12:34:56.789Z"}`
	if string(req.body) != want {
		t.Errorf("body = %s", req.body)
	}
}

func TestNewEventMatchesTrack(t *testing.T) {
	rec := &recorder{}
	c := newTestClient(t, rec, Config{DeviceID: "dev_1"})
	opts := &EventOptions{UserID: "u1", SessionID: "s1", EventTime: fixed}
	ev := c.NewEvent("checkout", Metadata{"total": 12.5}, opts)
	if err := c.Track(context.Background(), "checkout", Metadata{"total": 12.5}, opts); err != nil {
		t.Fatal(err)
	}
	body, err := encodeEvent(ev)
	if err != nil {
		t.Fatal(err)
	}
	if string(body) != string(rec.last(t).body) {
		t.Errorf("NewEvent = %s\nTrack sent %s", body, rec.last(t).body)
	}
}

const batchAnswer = `{"status":1,"data":{"accepted":2,"rejected":1,"results":[` +
	`{"index":0,"eventName":"a","ok":true},` +
	`{"index":1,"eventName":"","ok":false,"error":"event_name is required"},` +
	`{"index":2,"eventName":"order","ok":false,"error":"breaks its strict event definition",` +
	`"issues":[{"property":"total","kind":"type","expected":"number","got":"string"}]}]}}`

func TestTrackBatchPostsEventsAndDecodesRows(t *testing.T) {
	s := newAPIServer(t, 200, batchAnswer)
	c := newServerClient(t, s, Config{DeviceID: "dev_1", AppID: "app_9"})
	events := []Event{
		c.NewEvent("a", Metadata{"q": "<b>"}, &EventOptions{EventTime: fixed}),
		c.NewEvent("", nil, &EventOptions{EventTime: fixed}),
		c.NewEvent("order", Metadata{"total": "12"}, &EventOptions{UserID: "u1", EventTime: fixed}),
	}
	res, err := c.TrackBatch(context.Background(), events)
	if err != nil {
		t.Fatal(err)
	}
	req := s.last(t)
	if req.method != http.MethodPost || req.path != "/v1/engage/track/batch" {
		t.Errorf("request = %s %s", req.method, req.path)
	}
	for header, want := range map[string]string{
		"X-Api-Key":       "lc_admin",
		"X-Org-Id":        "org_1",
		"X-Engage-App-Id": "app_9",
		"Content-Type":    "application/json",
	} {
		if got := req.headers.Get(header); got != want {
			t.Errorf("%s = %q, want %q", header, got, want)
		}
	}
	if _, ok := req.headers["Authorization"]; ok {
		t.Error("lc_ key also sent as Authorization")
	}
	want := `{"events":[` +
		`{"id":"","event_name":"a","event_data":{"q":"<b>"},"device_id":"dev_1","event_time":"2026-09-30T12:34:56.789Z"},` +
		`{"id":"","event_name":"","event_data":{},"device_id":"dev_1","event_time":"2026-09-30T12:34:56.789Z"},` +
		`{"id":"","event_name":"order","event_data":{"total":"12"},"user_id":"u1","device_id":"dev_1","event_time":"2026-09-30T12:34:56.789Z"}]}`
	if string(req.body) != want {
		t.Errorf("body =\n%s\nwant\n%s", req.body, want)
	}
	if res.Accepted != 2 || res.Rejected != 1 || len(res.Results) != 3 {
		t.Fatalf("result = %+v", res)
	}
	if !res.Results[0].OK || res.Results[1].Error != "event_name is required" {
		t.Errorf("rows = %+v", res.Results)
	}
	wantIssues := []BatchIssue{{Property: "total", Kind: "type", Expected: "number", Got: "string"}}
	if !reflect.DeepEqual(res.Results[2].Issues, wantIssues) {
		t.Errorf("issues = %+v", res.Results[2].Issues)
	}
	rejected := res.RejectedRows()
	if len(rejected) != 2 || rejected[0].Index != 1 || rejected[1].Index != 2 {
		t.Errorf("RejectedRows = %+v", rejected)
	}
}

func TestTrackBatchLimitsSendNothing(t *testing.T) {
	s := newAPIServer(t, 200, batchAnswer)
	c := newServerClient(t, s, Config{})
	if _, err := c.TrackBatch(context.Background(), nil); !errors.Is(err, ErrEmptyBatch) {
		t.Errorf("empty batch = %v", err)
	}
	big := make([]Event, MaxBatch+1)
	for i := range big {
		big[i] = c.NewEvent("x", nil, nil)
	}
	if _, err := c.TrackBatch(context.Background(), big); !errors.Is(err, ErrBatchTooLarge) {
		t.Errorf("1001 events = %v", err)
	}
	bad := []Event{c.NewEvent("x", Metadata{"n": math.Inf(1)}, nil)}
	if _, err := c.TrackBatch(context.Background(), bad); err == nil {
		t.Error("Inf accepted")
	}
	if s.count() != 0 {
		t.Errorf("sent %d requests", s.count())
	}
	s.body = `{"status":1,"data":{"accepted":1000,"rejected":0,"results":[]}}`
	if _, err := c.TrackBatch(context.Background(), big[:MaxBatch]); err != nil {
		t.Errorf("1000 events = %v", err)
	}
}

func TestTrackBatchWholeBatchRefused(t *testing.T) {
	s := newAPIServer(t, 413, `{"status":0,"error":{"message":"AAS-00413","code":413,"details":"at most 1000 events a batch"}}`)
	c := newServerClient(t, s, Config{})
	_, err := c.TrackBatch(context.Background(), []Event{c.NewEvent("x", nil, nil)})
	var e *Error
	if !errors.As(err, &e) || e.Status != 413 || e.Message != "at most 1000 events a batch" || e.Code != "AAS-00413" {
		t.Errorf("err = %#v", err)
	}
}

func TestAlias(t *testing.T) {
	s := newAPIServer(t, 200, `{"status":1,"data":{"claimed":true}}`)
	c := newServerClient(t, s, Config{APIKey: "eyJ.token"})
	res, err := c.Alias(context.Background(), "u_1", AliasEmail, "ana@example.in")
	if err != nil {
		t.Fatal(err)
	}
	req := s.last(t)
	if req.method != http.MethodPost || req.path != "/v1/engage/users/alias" {
		t.Errorf("request = %s %s", req.method, req.path)
	}
	if req.headers.Get("Authorization") != "Bearer eyJ.token" || req.headers.Get("X-Org-Id") != "org_1" {
		t.Errorf("headers = %v", req.headers)
	}
	if _, ok := req.headers["X-Engage-App-Id"]; ok {
		t.Error("X-Engage-App-Id sent without an app")
	}
	if string(req.body) != `{"aliasType":"email","aliasValue":"ana@example.in","userId":"u_1"}` {
		t.Errorf("body = %s", req.body)
	}
	if !res.Claimed || res.HeldBy != "" {
		t.Errorf("result = %+v", res)
	}

	s.body = `{"status":1,"data":{"claimed":false,"heldBy":"u_2"}}`
	res, err = c.Alias(context.Background(), "u_1", AliasAnonymous, "dev_9")
	if err != nil || res.Claimed || res.HeldBy != "u_2" {
		t.Errorf("held alias = %+v, %v", res, err)
	}
}

func TestMergeAcceptsOKAndAccepted(t *testing.T) {
	profile := `{"id":"p1","orgId":"org_1","appId":"app_1","userId":"u_keep","userMetadata":{"email":"ana@example.in"},` +
		`"createdAt":"2026-09-30T12:00:00Z","createdBy":"x","prn":"prn:1"}`
	for _, status := range []int{200, 202} {
		s := newAPIServer(t, status, `{"status":1,"data":`+profile+`}`)
		c := newServerClient(t, s, Config{AppID: "app_1"})
		got, err := c.Merge(context.Background(), "u_keep", "ana@example.in")
		if err != nil {
			t.Fatalf("status %d: %v", status, err)
		}
		req := s.last(t)
		if req.method != http.MethodPost || req.path != "/v1/engage/users/merge" || req.headers.Get("X-Engage-App-Id") != "app_1" {
			t.Errorf("request = %s %s %v", req.method, req.path, req.headers)
		}
		if string(req.body) != `{"keepUserId":"u_keep","mergeUserId":"ana@example.in"}` {
			t.Errorf("body = %s", req.body)
		}
		if got.ID != "p1" || got.UserID != "u_keep" || got.AppID != "app_1" || got.UserMetadata["email"] != "ana@example.in" {
			t.Errorf("profile = %+v", got)
		}
		if got.CreatedAt.IsZero() || !strings.Contains(string(got.Raw), `"prn":"prn:1"`) {
			t.Errorf("createdAt/raw = %v %s", got.CreatedAt, got.Raw)
		}
	}
}

func TestMergeMissingProfileIs404(t *testing.T) {
	s := newAPIServer(t, 404, `{"status":0,"error":{"message":"profile not found","code":404}}`)
	c := newServerClient(t, s, Config{})
	_, err := c.Merge(context.Background(), "a", "b")
	var e *Error
	if !errors.As(err, &e) || e.Status != http.StatusNotFound || e.Message != "profile not found" {
		t.Errorf("err = %#v", err)
	}
}

func TestSetConsent(t *testing.T) {
	s := newAPIServer(t, 200, `{"status":1,"data":{"channel":"whatsapp","status":"opted_in","previous":"pending","confirmation":"sent"}}`)
	c := newServerClient(t, s, Config{})
	res, err := c.SetConsent(context.Background(), "u/1 ana", ConsentRequest{
		Channel: ConsentWhatsApp, Status: ConsentOptedIn, Source: "form", Evidence: Metadata{"formId": "f1"},
	})
	if err != nil {
		t.Fatal(err)
	}
	req := s.last(t)
	if req.method != http.MethodPut || req.rawPath != "/v1/engage/users/userId/u%2F1%20ana/consents" {
		t.Errorf("request = %s %s", req.method, req.rawPath)
	}
	if string(req.body) != `{"channel":"whatsapp","status":"opted_in","source":"form","evidence":{"formId":"f1"}}` {
		t.Errorf("body = %s", req.body)
	}
	want := ConsentResult{Channel: "whatsapp", Status: "opted_in", Previous: "pending", Confirmation: "sent"}
	if *res != want {
		t.Errorf("result = %+v", res)
	}

	if _, err := c.SetConsent(context.Background(), "u1", ConsentRequest{Channel: "email", Status: ConsentOptedOut}); err != nil {
		t.Fatal(err)
	}
	if got := string(s.last(t).body); got != `{"channel":"email","status":"opted_out"}` {
		t.Errorf("minimal body = %s", got)
	}
}

func TestEnterJourney(t *testing.T) {
	s := newAPIServer(t, 201, `{"status":1,"data":{"id":"jp1","appId":"app_1","journeyId":"j 1","version":3,"userId":"u1",`+
		`"status":"active","enteredAt":"2026-09-30T12:00:00Z"}}`)
	c := newServerClient(t, s, Config{})
	p, err := c.EnterJourney(context.Background(), "j 1", "u1")
	if err != nil {
		t.Fatal(err)
	}
	req := s.last(t)
	if req.method != http.MethodPost || req.rawPath != "/v1/engage/configurations/journeys/j%201/enter" {
		t.Errorf("request = %s %s", req.method, req.rawPath)
	}
	if string(req.body) != `{"userId":"u1"}` {
		t.Errorf("body = %s", req.body)
	}
	if p.ID != "jp1" || p.JourneyID != "j 1" || p.Version != 3 || p.Status != "active" || p.EnteredAt.IsZero() {
		t.Errorf("participant = %+v", p)
	}
}

func TestEnterJourneyConflictIs409(t *testing.T) {
	s := newAPIServer(t, 409, `{"status":0,"error":{"message":"AAS-00409","code":409,"details":"already in the journey"}}`)
	c := newServerClient(t, s, Config{})
	_, err := c.EnterJourney(context.Background(), "j1", "u1")
	var e *Error
	if !errors.As(err, &e) || e.Status != http.StatusConflict || e.Message != "already in the journey" {
		t.Errorf("err = %#v", err)
	}
}

func TestProfileCallArgumentErrorsSendNothing(t *testing.T) {
	s := newAPIServer(t, 200, `{"status":1,"data":{}}`)
	c := newServerClient(t, s, Config{})
	ctx := context.Background()
	first := func(_ any, err error) error { return err }
	cases := []struct {
		name string
		err  error
		want error
	}{
		{"alias user", first(c.Alias(ctx, " ", AliasEmail, "a@b.c")), ErrMissingUserID},
		{"alias type", first(c.Alias(ctx, "u1", "", "a@b.c")), ErrMissingAlias},
		{"alias value", first(c.Alias(ctx, "u1", AliasEmail, " ")), ErrMissingAlias},
		{"merge", first(c.Merge(ctx, "u1", "")), ErrMissingUserID},
		{"consent user", first(c.SetConsent(ctx, "", ConsentRequest{Channel: "email", Status: ConsentOptedIn})), ErrMissingUserID},
		{"consent status", first(c.SetConsent(ctx, "u1", ConsentRequest{Channel: "email"})), ErrMissingConsent},
		{"journey id", first(c.EnterJourney(ctx, "", "u1")), ErrMissingJourneyID},
		{"journey user", first(c.EnterJourney(ctx, "j1", " ")), ErrMissingUserID},
	}
	for _, tc := range cases {
		if !errors.Is(tc.err, tc.want) {
			t.Errorf("%s: %v, want %v", tc.name, tc.err, tc.want)
		}
	}
	if s.count() != 0 {
		t.Errorf("sent %d requests", s.count())
	}
}

func TestAPICallTransportErrorAndBadJSON(t *testing.T) {
	s := newAPIServer(t, 200, `not json`)
	c := newServerClient(t, s, Config{})
	if _, err := c.Alias(context.Background(), "u1", AliasEmail, "a@b.c"); err == nil || !strings.Contains(err.Error(), "decode response") {
		t.Errorf("bad JSON = %v", err)
	}
	s.Close()
	_, err := c.EnterJourney(context.Background(), "j1", "u1")
	var e *Error
	if !errors.As(err, &e) || e.Status != 0 {
		t.Errorf("closed server = %#v", err)
	}
}
