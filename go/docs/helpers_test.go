package docs

import (
	"bytes"
	"io"
	"net/http"
	"testing"
)

// recordedRequest is one request the client sent through mockTransport.
type recordedRequest struct {
	Method string
	URL    string
	// Path is the escaped path exactly as sent on the wire.
	Path     string
	RawQuery string
	Header   http.Header
	Body     []byte
}

// mockTransport records every request and answers it with respond (a
// {"status":1,"data":null} envelope when respond is nil), so tests never
// touch the network.
type mockTransport struct {
	requests []recordedRequest
	respond  func(req *http.Request) (*http.Response, error)
}

func (m *mockTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	var body []byte
	if req.Body != nil {
		raw, err := io.ReadAll(req.Body)
		if err != nil {
			return nil, err
		}
		_ = req.Body.Close()
		body = raw
	}
	m.requests = append(m.requests, recordedRequest{
		Method:   req.Method,
		URL:      req.URL.String(),
		Path:     req.URL.EscapedPath(),
		RawQuery: req.URL.RawQuery,
		Header:   req.Header.Clone(),
		Body:     body,
	})
	if m.respond == nil {
		return jsonResponse(req, http.StatusOK, `{"status":1,"data":null}`), nil
	}
	return m.respond(req)
}

func (m *mockTransport) last(t *testing.T) recordedRequest {
	t.Helper()
	if len(m.requests) == 0 {
		t.Fatal("no request was sent")
	}
	return m.requests[len(m.requests)-1]
}

// newResponse builds a response; headers are key/value pairs.
func newResponse(req *http.Request, status int, body string, headers ...string) *http.Response {
	h := http.Header{}
	for i := 0; i+1 < len(headers); i += 2 {
		h.Add(headers[i], headers[i+1])
	}
	return &http.Response{
		StatusCode: status,
		Status:     http.StatusText(status),
		Header:     h,
		Body:       io.NopCloser(bytes.NewReader([]byte(body))),
		Request:    req,
	}
}

func jsonResponse(req *http.Request, status int, body string) *http.Response {
	return newResponse(req, status, body, "Content-Type", "application/json")
}

// respondWith answers every request with the same status, body and headers.
func respondWith(status int, body string, headers ...string) func(*http.Request) (*http.Response, error) {
	return func(req *http.Request) (*http.Response, error) {
		return newResponse(req, status, body, headers...), nil
	}
}

// newTestClient returns a client whose HTTP client sends through a
// mockTransport, plus that transport and HTTP client.
func newTestClient(t *testing.T, respond func(*http.Request) (*http.Response, error)) (*Client, *mockTransport, *http.Client) {
	t.Helper()
	mt := &mockTransport{respond: respond}
	httpClient := &http.Client{Transport: mt}
	client, err := NewClient(Config{
		Token:      "test-token",
		OrgID:      "org-1",
		Headers:    map[string]string{"X-Trace": "trace-1"},
		HTTPClient: httpClient,
	})
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	return client, mt, httpClient
}
