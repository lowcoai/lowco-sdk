package workflow

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"
)

// recordingTransport captures every request the client sends and answers each
// with a fixed success envelope, so tests never touch the network.
type recordingTransport struct {
	requests []*http.Request
	bodies   []string
}

func (t *recordingTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	body := ""
	if req.Body != nil {
		raw, err := io.ReadAll(req.Body)
		if err != nil {
			return nil, err
		}
		body = string(raw)
	}
	t.requests = append(t.requests, req)
	t.bodies = append(t.bodies, body)
	return &http.Response{
		StatusCode: http.StatusOK,
		Header:     http.Header{"Content-Type": []string{"application/json"}},
		Body:       io.NopCloser(strings.NewReader(`{"success":true,"data":{"ok":true}}`)),
		Request:    req,
	}, nil
}

func newRecordingClient(t *testing.T) (*Client, *recordingTransport) {
	t.Helper()
	rt := &recordingTransport{}
	client, err := NewClient(Config{Token: "test-token", HTTPClient: &http.Client{Transport: rt}})
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	return client, rt
}

func TestWebhooksTriggerPostsToTriggerRoute(t *testing.T) {
	client, rt := newRecordingClient(t)
	async := true

	out, err := client.Webhooks.Trigger(context.Background(), "wf1", map[string]any{"a": 1}, &WebhookTriggerQuery{Env: "env1", Async: &async})
	if err != nil {
		t.Fatalf("Trigger: %v", err)
	}
	if out["ok"] != true {
		t.Fatalf("Trigger result = %v, want unwrapped data", out)
	}
	if len(rt.requests) != 1 {
		t.Fatalf("sent %d requests, want 1", len(rt.requests))
	}
	req := rt.requests[0]
	if req.Method != http.MethodPost || req.URL.Path != "/v1/wf/webhook/wf1" {
		t.Fatalf("request = %s %s, want POST /v1/wf/webhook/wf1", req.Method, req.URL.Path)
	}
	if got := req.URL.Query(); got.Get("env") != "env1" || got.Get("async") != "true" {
		t.Fatalf("query = %v, want env=env1 async=true", got)
	}
	var body map[string]any
	if err := json.Unmarshal([]byte(rt.bodies[0]), &body); err != nil || body["a"] != float64(1) {
		t.Fatalf("body = %q, want the trigger payload", rt.bodies[0])
	}
}

func TestDeprecatedWebhookMethodsFailWithoutSending(t *testing.T) {
	ctx := context.Background()
	cfg := WebhookCreateRequest{URL: "https://example.com/hook", AuthDetails: map[string]any{"secret": "s"}}
	cases := []struct {
		operation string
		call      func(*Client) (any, error)
	}{
		{"ListByWorkflow", func(c *Client) (any, error) { return c.Webhooks.ListByWorkflow(ctx, "wf1") }},
		{"Create", func(c *Client) (any, error) { return c.Webhooks.Create(ctx, "wf1", cfg) }},
		{"Update", func(c *Client) (any, error) { return c.Webhooks.Update(ctx, "wh1", cfg) }},
		{"Delete", func(c *Client) (any, error) { return c.Webhooks.Delete(ctx, "wf1") }},
	}

	for _, tc := range cases {
		t.Run(tc.operation, func(t *testing.T) {
			client, rt := newRecordingClient(t)

			_, err := tc.call(client)

			if len(rt.requests) != 0 {
				t.Fatalf("sent %d requests (%s %s), want none", len(rt.requests), rt.requests[0].Method, rt.requests[0].URL.Path)
			}
			var sdkErr *Error
			if !errors.As(err, &sdkErr) {
				t.Fatalf("err = %v (%T), want *workflow.Error", err, err)
			}
			if sdkErr.Status != 0 {
				t.Errorf("Status = %d, want 0 (no response)", sdkErr.Status)
			}
			if !strings.Contains(sdkErr.Message, "Webhooks."+tc.operation+" is not supported") ||
				!strings.Contains(sdkErr.Message, "integrations service") {
				t.Errorf("Message = %q, want it to name the operation and the integrations service", sdkErr.Message)
			}
			payload, _ := sdkErr.Payload.(map[string]any)
			if payload["code"] != "unsupported_operation" || payload["operation"] != "Webhooks."+tc.operation {
				t.Errorf("Payload = %v, want code=unsupported_operation operation=Webhooks.%s", sdkErr.Payload, tc.operation)
			}
		})
	}
}
