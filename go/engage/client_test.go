package engage

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"net/http"
	"reflect"
	"regexp"
	"strings"
	"testing"
	"time"
)

var uuidPattern = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)

var fixed = time.Date(2026, 9, 30, 12, 34, 56, 789123000, time.UTC)

type recorded struct {
	method  string
	url     string
	headers http.Header
	body    []byte
}

// recorder answers every request with respond and keeps a copy of it.
type recorder struct {
	requests []recorded
	respond  func(*http.Request) (*http.Response, error)
}

func (r *recorder) RoundTrip(req *http.Request) (*http.Response, error) {
	// Like http.Transport, a done context fails the request.
	if err := req.Context().Err(); err != nil {
		return nil, err
	}
	body, _ := io.ReadAll(req.Body)
	r.requests = append(r.requests, recorded{req.Method, req.URL.String(), req.Header.Clone(), body})
	if r.respond != nil {
		return r.respond(req)
	}
	return reply(200, `{"status":1}`), nil
}

func (r *recorder) last(t *testing.T) recorded {
	t.Helper()
	if len(r.requests) == 0 {
		t.Fatal("no request sent")
	}
	return r.requests[len(r.requests)-1]
}

func (r *recorder) lastJSON(t *testing.T) map[string]any {
	t.Helper()
	var out map[string]any
	if err := json.Unmarshal(r.last(t).body, &out); err != nil {
		t.Fatalf("body is not JSON: %v", err)
	}
	return out
}

func reply(status int, body string) *http.Response {
	return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(body)), Header: make(http.Header)}
}

func newTestClient(t *testing.T, rec *recorder, config Config) *Client {
	t.Helper()
	if config.APIKey == "" {
		config.APIKey = "key_123"
	}
	if config.OrgID == "" {
		config.OrgID = "org_1"
	}
	config.HTTPClient = &http.Client{Transport: rec}
	c, err := NewClient(config)
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func TestNewClientRequiresAPIKeyAndOrgID(t *testing.T) {
	cases := []struct {
		config Config
		want   error
	}{
		{Config{APIKey: "", OrgID: "org_1"}, ErrMissingAPIKey},
		{Config{APIKey: "  ", OrgID: "org_1"}, ErrMissingAPIKey},
		{Config{APIKey: "k", OrgID: " "}, ErrMissingOrgID},
	}
	for _, tc := range cases {
		if _, err := NewClient(tc.config); !errors.Is(err, tc.want) {
			t.Errorf("NewClient(%+v) = %v, want %v", tc.config, err, tc.want)
		}
	}
}

func TestTrackSendsOneEventWithHeadersAndURL(t *testing.T) {
	rec := &recorder{}
	c := newTestClient(t, rec, Config{DeviceID: "dev_1"})
	err := c.Track(context.Background(), "signup_completed", Metadata{"plan": "pro", "seats": 3},
		&EventOptions{UserID: "user_1", SessionID: "sess_1", EventTime: fixed})
	if err != nil {
		t.Fatal(err)
	}
	if len(rec.requests) != 1 {
		t.Fatalf("sent %d requests, want 1", len(rec.requests))
	}
	req := rec.last(t)
	if req.method != http.MethodPost || req.url != "https://api.lowco.ai/v1/engage/track" {
		t.Errorf("request = %s %s", req.method, req.url)
	}
	for header, want := range map[string]string{
		"Authorization": "Bearer key_123",
		"X-Org-Id":      "org_1",
		"Content-Type":  "application/json",
	} {
		if got := req.headers.Get(header); got != want {
			t.Errorf("%s = %q, want %q", header, got, want)
		}
	}
	for _, header := range []string{"X-Api-Key", "X-Engage-App-Id"} {
		if _, ok := req.headers[header]; ok {
			t.Errorf("%s sent by default", header)
		}
	}
	want := `{"id":"","event_name":"signup_completed","event_data":{"plan":"pro","seats":3},` +
		`"user_id":"user_1","device_id":"dev_1","session_id":"sess_1","event_time":"2026-09-30T12:34:56.789Z"}`
	if string(req.body) != want {
		t.Errorf("body =\n%s\nwant\n%s", req.body, want)
	}
}

func TestAppIDIsSentAsEngageAppHeader(t *testing.T) {
	rec := &recorder{}
	c := newTestClient(t, rec, Config{AppID: " app_42 "})
	if c.AppID() != "app_42" {
		t.Errorf("AppID() = %q", c.AppID())
	}
	ctx := context.Background()
	if err := c.Track(ctx, "x", nil, nil); err != nil {
		t.Fatal(err)
	}
	if err := c.Page(ctx, nil, nil); err != nil {
		t.Fatal(err)
	}
	if err := c.IdentifyUser(ctx, "u1", nil, nil); err != nil {
		t.Fatal(err)
	}
	for i, r := range rec.requests {
		if got := r.headers.Get("X-Engage-App-Id"); got != "app_42" {
			t.Errorf("request %d: X-Engage-App-Id = %q", i, got)
		}
		if got := r.headers.Get("X-Org-Id"); got != "org_1" {
			t.Errorf("request %d: X-Org-Id = %q", i, got)
		}
	}
}

func TestBlankAppIDMeansDefaultApp(t *testing.T) {
	rec := &recorder{}
	c := newTestClient(t, rec, Config{AppID: "   "})
	if err := c.Track(context.Background(), "x", nil, nil); err != nil {
		t.Fatal(err)
	}
	if c.AppID() != "" {
		t.Errorf("AppID() = %q", c.AppID())
	}
	if _, ok := rec.last(t).headers["X-Engage-App-Id"]; ok {
		t.Error("blank AppID sent")
	}
}

func TestLcAPIKeyIsSentAsXAPIKey(t *testing.T) {
	rec := &recorder{}
	c := newTestClient(t, rec, Config{APIKey: " lc_secret ", AppID: "app_7"})
	if err := c.Track(context.Background(), "x", nil, nil); err != nil {
		t.Fatal(err)
	}
	h := rec.last(t).headers
	if got := h.Get("X-Api-Key"); got != "lc_secret" {
		t.Errorf("X-Api-Key = %q", got)
	}
	if _, ok := h["Authorization"]; ok {
		t.Error("an lc_ key must not also travel as Authorization")
	}
	if h.Get("X-Org-Id") != "org_1" || h.Get("X-Engage-App-Id") != "app_7" {
		t.Errorf("headers = %v", h)
	}
}

func TestIsAPIKey(t *testing.T) {
	for key, want := range map[string]bool{
		"lc_abc":           true,
		"  lc_abc":         true,
		"eyJhbGciOi.token": false,
		"LC_abc":           false,
		"":                 false,
	} {
		if got := IsAPIKey(key); got != want {
			t.Errorf("IsAPIKey(%q) = %v", key, got)
		}
	}
}

func TestEmptyFieldsAreOmittedAndEventDataDefaultsToEmpty(t *testing.T) {
	rec := &recorder{}
	c := newTestClient(t, rec, Config{DeviceID: "dev_1"})
	if err := c.Track(context.Background(), "ping", nil, nil); err != nil {
		t.Fatal(err)
	}
	body := rec.lastJSON(t)
	keys := make([]string, 0, len(body))
	for k := range body {
		keys = append(keys, k)
	}
	for _, k := range []string{"user_id", "session_id", "device_info", "location"} {
		if _, ok := body[k]; ok {
			t.Errorf("%s sent though empty", k)
		}
	}
	if !reflect.DeepEqual(body["event_data"], map[string]any{}) {
		t.Errorf("event_data = %v", body["event_data"])
	}
	if len(body) != 5 {
		t.Errorf("keys = %v", keys)
	}
}

func TestDeviceInfoAndLocationAreSent(t *testing.T) {
	rec := &recorder{}
	c := newTestClient(t, rec, Config{})
	err := c.Track(context.Background(), "checkout", nil, &EventOptions{
		DeviceInfo: &DeviceInfo{
			Browser: &BrowserInfo{Name: "Chrome", Version: "126.0.0.0", Major: "126"},
			OS:      &OSInfo{Name: "Mac OS", Version: "10.15.7"},
			CPU:     &CPUInfo{Architecture: "arm64"},
			UA:      "Mozilla/5.0",
		},
		Location: &LocationInfo{Latitude: Float64(0), Longitude: Float64(77.59), IPAddress: "203.0.113.7"},
	})
	if err != nil {
		t.Fatal(err)
	}
	body := rec.lastJSON(t)
	wantDevice := map[string]any{
		"browser": map[string]any{"name": "Chrome", "version": "126.0.0.0", "major": "126"},
		"os":      map[string]any{"name": "Mac OS", "version": "10.15.7"},
		"cpu":     map[string]any{"architecture": "arm64"},
		"ua":      "Mozilla/5.0",
	}
	if !reflect.DeepEqual(body["device_info"], wantDevice) {
		t.Errorf("device_info = %v", body["device_info"])
	}
	wantLocation := map[string]any{"latitude": 0.0, "longitude": 77.59, "ip_address": "203.0.113.7"}
	if !reflect.DeepEqual(body["location"], wantLocation) {
		t.Errorf("location = %v", body["location"])
	}
}

func TestBodyIsUnescapedUTF8AndBadValuesFailBeforeSending(t *testing.T) {
	rec := &recorder{}
	c := newTestClient(t, rec, Config{DeviceID: "d"})
	if err := c.Track(context.Background(), "café", Metadata{"q": "<a&b>"}, &EventOptions{EventTime: fixed}); err != nil {
		t.Fatal(err)
	}
	want := `{"id":"","event_name":"café","event_data":{"q":"<a&b>"},"device_id":"d","event_time":"2026-09-30T12:34:56.789Z"}`
	if got := string(rec.last(t).body); got != want {
		t.Errorf("body = %s", got)
	}
	if err := c.Track(context.Background(), "x", Metadata{"bad": math.NaN()}, nil); err == nil {
		t.Error("NaN accepted")
	}
	if len(rec.requests) != 1 {
		t.Errorf("sent %d requests", len(rec.requests))
	}
}

func TestEventTime(t *testing.T) {
	ist := time.FixedZone("IST", 5*3600+1800)
	cases := map[string]time.Time{
		"2026-09-30T12:34:56.789Z": fixed,
		"2026-09-30T12:34:56.005Z": time.Date(2026, 9, 30, 18, 4, 56, 5000000, ist),
		"2026-01-02T03:04:05.999Z": time.Date(2026, 1, 2, 3, 4, 5, 999999999, time.UTC),
	}
	for want, at := range cases {
		rec := &recorder{}
		c := newTestClient(t, rec, Config{})
		if err := c.Track(context.Background(), "x", nil, &EventOptions{EventTime: at}); err != nil {
			t.Fatal(err)
		}
		if got := rec.lastJSON(t)["event_time"]; got != want {
			t.Errorf("event_time = %v, want %s", got, want)
		}
	}

	rec := &recorder{}
	c := newTestClient(t, rec, Config{})
	c.now = func() time.Time { return fixed }
	if err := c.Track(context.Background(), "x", nil, nil); err != nil {
		t.Fatal(err)
	}
	if got := rec.lastJSON(t)["event_time"]; got != "2026-09-30T12:34:56.789Z" {
		t.Errorf("default event_time = %v", got)
	}
}

func TestDeviceIDDefaultsToAUUIDPerClient(t *testing.T) {
	rec := &recorder{}
	a := newTestClient(t, rec, Config{})
	b := newTestClient(t, rec, Config{})
	if !uuidPattern.MatchString(a.DeviceID()) || a.DeviceID() == b.DeviceID() {
		t.Errorf("device ids %q %q", a.DeviceID(), b.DeviceID())
	}
	if err := a.Track(context.Background(), "x", nil, &EventOptions{DeviceID: "dev_browser"}); err != nil {
		t.Fatal(err)
	}
	if got := rec.lastJSON(t)["device_id"]; got != "dev_browser" {
		t.Errorf("per-call device_id = %v", got)
	}
	if err := a.Track(context.Background(), "x", nil, nil); err != nil {
		t.Fatal(err)
	}
	if got := rec.lastJSON(t)["device_id"]; got != a.DeviceID() {
		t.Errorf("default device_id = %v", got)
	}
}

func TestPageAndIdentifyUser(t *testing.T) {
	rec := &recorder{}
	c := newTestClient(t, rec, Config{DeviceID: "dev_1"})
	ctx := context.Background()
	if err := c.Page(ctx, Metadata{"path": "/pricing"}, &EventOptions{UserID: "u1"}); err != nil {
		t.Fatal(err)
	}
	body := rec.lastJSON(t)
	if body["event_name"] != "page_view" || body["user_id"] != "u1" {
		t.Errorf("page body = %v", body)
	}
	if err := c.IdentifyUser(ctx, "user_42", Metadata{"email": "ada@example.com"}, &EventOptions{UserID: "ignored", SessionID: "s1"}); err != nil {
		t.Fatal(err)
	}
	body = rec.lastJSON(t)
	if body["event_name"] != "_lowco_identify" || body["user_id"] != "user_42" || body["session_id"] != "s1" {
		t.Errorf("identify body = %v", body)
	}
	if err := c.Track(ctx, "after_identify", nil, nil); err != nil {
		t.Fatal(err)
	}
	if _, ok := rec.lastJSON(t)["user_id"]; ok {
		t.Error("the client remembered the identified user")
	}
}

func TestPropertiesAreCopied(t *testing.T) {
	rec := &recorder{}
	c := newTestClient(t, rec, Config{})
	props := Metadata{"a": 1}
	if err := c.Track(context.Background(), "x", props, nil); err != nil {
		t.Fatal(err)
	}
	if len(props) != 1 {
		t.Errorf("properties mutated: %v", props)
	}
}

func TestArgumentErrorsSendNothing(t *testing.T) {
	rec := &recorder{}
	c := newTestClient(t, rec, Config{})
	if err := c.Track(context.Background(), " ", nil, nil); !errors.Is(err, ErrMissingEventName) {
		t.Errorf("Track(blank) = %v", err)
	}
	if err := c.IdentifyUser(context.Background(), "", nil, nil); !errors.Is(err, ErrMissingUserID) {
		t.Errorf("IdentifyUser(blank) = %v", err)
	}
	if len(rec.requests) != 0 {
		t.Errorf("sent %d requests", len(rec.requests))
	}
}

func TestErrorResponses(t *testing.T) {
	cases := []struct {
		status  int
		body    string
		message string
		code    string
	}{
		{400, `{"status":0,"error":{"message":"AAS-00400","code":400,"details":"bad event_time"}}`, "bad event_time", "AAS-00400"},
		{403, `{"message":"forbidden"}`, "forbidden", ""},
		{502, "Bad Gateway", "Bad Gateway", ""},
		{401, "", "engage: status=401", ""},
	}
	for _, tc := range cases {
		rec := &recorder{respond: func(*http.Request) (*http.Response, error) { return reply(tc.status, tc.body), nil }}
		err := newTestClient(t, rec, Config{}).Track(context.Background(), "x", nil, nil)
		var e *Error
		if !errors.As(err, &e) {
			t.Fatalf("status %d: error %T %v", tc.status, err, err)
		}
		if e.Status != tc.status || e.Message != tc.message || e.Code != tc.code || e.Body != tc.body {
			t.Errorf("status %d: got %+v", tc.status, e)
		}
	}
}

func TestNon2xxOnlyIsAnError(t *testing.T) {
	for _, status := range []int{200, 202, 204} {
		rec := &recorder{respond: func(*http.Request) (*http.Response, error) { return reply(status, "ok"), nil }}
		if err := newTestClient(t, rec, Config{}).Track(context.Background(), "x", nil, nil); err != nil {
			t.Errorf("status %d: %v", status, err)
		}
	}
}

func TestTransportErrorsUnwrap(t *testing.T) {
	boom := errors.New("down")
	rec := &recorder{respond: func(*http.Request) (*http.Response, error) { return nil, boom }}
	err := newTestClient(t, rec, Config{}).Track(context.Background(), "x", nil, nil)
	var e *Error
	if !errors.As(err, &e) || e.Status != 0 || !errors.Is(err, boom) {
		t.Errorf("err = %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	rec = &recorder{}
	err = newTestClient(t, rec, Config{}).Track(ctx, "x", nil, nil)
	if !errors.Is(err, context.Canceled) {
		t.Errorf("canceled: %v", err)
	}
}
