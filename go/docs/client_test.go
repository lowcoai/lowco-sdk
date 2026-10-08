package docs

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestNewClientValidatesConfig(t *testing.T) {
	cases := []struct {
		name   string
		config Config
		want   error
	}{
		{"missing token", Config{OrgID: "org-1"}, ErrMissingToken},
		{"blank token", Config{Token: "   ", OrgID: "org-1"}, ErrMissingToken},
		{"missing orgId", Config{Token: "tok"}, ErrMissingOrgID},
		{"blank orgId", Config{Token: "tok", OrgID: " \t"}, ErrMissingOrgID},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client, err := NewClient(tc.config)
			if !errors.Is(err, tc.want) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
			if client != nil {
				t.Fatalf("client = %v, want nil", client)
			}
		})
	}
}

func TestNewClientDefaults(t *testing.T) {
	client, err := NewClient(Config{Token: "tok", OrgID: "org-1", TimeoutMS: 5000})
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	if client.http.baseURL != "https://api.lowco.ai" {
		t.Errorf("baseURL = %q, want https://api.lowco.ai", client.http.baseURL)
	}
	if client.http.client.Timeout != 5*time.Second {
		t.Errorf("default client timeout = %v, want 5s", client.http.client.Timeout)
	}
	resources := []any{client.Buckets, client.Folders, client.Files, client.Nodes, client.Library,
		client.Sharing, client.Automation, client.AppFiles, client.Triggers, client.Webhooks}
	for i, r := range resources {
		if reflect.ValueOf(r).IsNil() {
			t.Errorf("resource %d is nil", i)
		}
	}
}

func TestRequestHeaders(t *testing.T) {
	client, mt, _ := newTestClient(t, nil)

	if _, err := client.Triggers.Create(context.Background(), TriggerRequest{Prefix: "in/", WorkflowID: "wf1"}); err != nil {
		t.Fatalf("Triggers.Create: %v", err)
	}
	req := mt.last(t)
	u, _ := url.Parse(req.URL)
	if u.Scheme != "https" || u.Host != "api.lowco.ai" {
		t.Errorf("URL = %s, want https://api.lowco.ai/...", req.URL)
	}
	checks := map[string]string{
		"Authorization": "Bearer test-token",
		"X-Org-Id":      "org-1",
		"X-Trace":       "trace-1",
		"Accept":        "application/json",
		"Content-Type":  "application/json",
	}
	for key, want := range checks {
		if got := req.Header.Get(key); got != want {
			t.Errorf("header %s = %q, want %q", key, got, want)
		}
	}

	if _, err := client.Triggers.List(context.Background()); err != nil {
		t.Fatalf("Triggers.List: %v", err)
	}
	if got := mt.last(t).Header.Get("Content-Type"); got != "" {
		t.Errorf("GET without body sent Content-Type %q", got)
	}
}

func TestEnvelopeUnwrapping(t *testing.T) {
	ctx := context.Background()

	t.Run("object", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusOK,
			`{"status":1,"data":{"id":"n1","name":"plan.md","path":"/projects/plan.md","type":"file","size":2048,`+
				`"metadata":{"role":"owner","etag":"e1"},"createdAt":"2026-10-01T09:30:00Z","etag":"e1"}}`))
		doc, err := client.Files.Get(ctx, "b1", "projects/plan.md")
		if err != nil {
			t.Fatalf("Files.Get: %v", err)
		}
		if doc.ID != "n1" || doc.Name != "plan.md" || doc.Type != NodeTypeFile || doc.Size != 2048 ||
			doc.Metadata["role"] != "owner" || doc.CreatedAt != "2026-10-01T09:30:00Z" || doc.ETag != "e1" {
			t.Fatalf("doc = %+v, want the unwrapped data", doc)
		}
	})

	t.Run("list", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusOK,
			`{"status":1,"data":[{"id":"a","name":"a"},{"id":"b","name":"b","type":"folder"}]}`))
		docs, err := client.Folders.List(ctx, "b1", nil)
		if err != nil {
			t.Fatalf("Folders.List: %v", err)
		}
		if len(docs) != 2 || docs[1].Type != NodeTypeFolder {
			t.Fatalf("docs = %+v, want 2 unwrapped rows", docs)
		}
	})

	t.Run("message", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusOK, `{"status":1,"data":"file deleted"}`))
		msg, err := client.Files.Delete(ctx, "b1", "a.txt")
		if err != nil || msg != "file deleted" {
			t.Fatalf("Files.Delete = %q, %v; want the data message", msg, err)
		}
	})

	t.Run("int64 precision", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusOK,
			`{"status":1,"data":{"totalSize":9007199254740993,"folderCount":3}}`))
		stats, err := client.Buckets.Stats(ctx, "b1")
		if err != nil {
			t.Fatalf("Buckets.Stats: %v", err)
		}
		if stats.TotalSize != 9007199254740993 || stats.FolderCount != 3 {
			t.Fatalf("stats = %+v, want exact int64 values", stats)
		}
	})

	t.Run("not an envelope", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusOK, `[{"id":"t1","eventType":"create"}]`))
		triggers, err := client.Triggers.List(ctx)
		if err != nil || len(triggers) != 1 || triggers[0].EventType != EventTypeCreate {
			t.Fatalf("Triggers.List = %+v, %v; want the bare body decoded", triggers, err)
		}
	})

	t.Run("no content", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusNoContent, ``))
		if err := client.Webhooks.Delete(ctx, "w1"); err != nil {
			t.Fatalf("Webhooks.Delete: %v", err)
		}
	})

	t.Run("undecodable", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusOK, `{"status":1,"data":"not a document"}`))
		_, err := client.Files.Get(ctx, "b1", "a.txt")
		var sdkErr *Error
		if !errors.As(err, &sdkErr) || !strings.Contains(sdkErr.Message, "could not decode response") {
			t.Fatalf("err = %v, want a decode *Error", err)
		}
	})
}

func TestErrorBodyShapes(t *testing.T) {
	cases := []struct {
		name        string
		status      int
		body        string
		wantMessage string
		wantCode    string
	}{
		{
			name:        "envelope with code and details",
			status:      http.StatusBadRequest,
			body:        `{"status":0,"error":{"message":"AAS-00106","code":400,"details":"bucket name is required"}}`,
			wantMessage: "bucket name is required",
			wantCode:    "AAS-00106",
		},
		{
			name:        "envelope with code only",
			status:      http.StatusInternalServerError,
			body:        `{"status":0,"error":{"message":"AAS-00105","code":500}}`,
			wantMessage: "AAS-00105",
			wantCode:    "AAS-00105",
		},
		{
			name:        "envelope with a human message",
			status:      http.StatusNotFound,
			body:        `{"status":0,"error":{"message":"webhook not found","code":404}}`,
			wantMessage: "webhook not found",
		},
		{
			name:        "echo message",
			status:      http.StatusForbidden,
			body:        `{"message":"you don't have access to this item"}`,
			wantMessage: "you don't have access to this item",
		},
		{
			name:        "plain text",
			status:      http.StatusBadGateway,
			body:        "upstream unavailable\n",
			wantMessage: "upstream unavailable",
		},
		{
			name:        "empty body",
			status:      http.StatusInternalServerError,
			body:        "",
			wantMessage: "request failed with status 500",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client, _, _ := newTestClient(t, respondWith(tc.status, tc.body))
			_, err := client.Buckets.Stats(context.Background(), "b1")
			var sdkErr *Error
			if !errors.As(err, &sdkErr) {
				t.Fatalf("err = %v (%T), want *docs.Error", err, err)
			}
			if sdkErr.Status != tc.status {
				t.Errorf("Status = %d, want %d", sdkErr.Status, tc.status)
			}
			if sdkErr.Message != tc.wantMessage || sdkErr.Error() != tc.wantMessage {
				t.Errorf("Message = %q, want %q", sdkErr.Message, tc.wantMessage)
			}
			if sdkErr.Code != tc.wantCode {
				t.Errorf("Code = %q, want %q", sdkErr.Code, tc.wantCode)
			}
			if tc.body != "" && sdkErr.Payload == nil {
				t.Errorf("Payload is nil, want the body")
			}
		})
	}

	t.Run("payload is decoded JSON", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusBadRequest,
			`{"status":0,"error":{"message":"AAS-00106","code":400,"details":"bad"}}`))
		_, err := client.Buckets.Stats(context.Background(), "b1")
		var sdkErr *Error
		errors.As(err, &sdkErr)
		payload, _ := sdkErr.Payload.(map[string]any)
		inner, _ := payload["error"].(map[string]any)
		if inner["message"] != "AAS-00106" || inner["code"] != float64(400) {
			t.Fatalf("Payload = %v, want the decoded error envelope", sdkErr.Payload)
		}
	})
}

func TestPreconditionFailed(t *testing.T) {
	client, _, _ := newTestClient(t, respondWith(http.StatusPreconditionFailed,
		`{"status":0,"data":{"currentEtag":"e2","updatedAt":"2026-10-01T09:30:00Z","updatedBy":"u-456"},`+
			`"error":{"message":"the file was changed by someone else","code":412}}`))

	_, err := client.Files.Update(context.Background(), "b1", UpdateFileRequest{FileName: "a.md", Content: "x", IfMatch: "e1"})

	var sdkErr *Error
	if !errors.As(err, &sdkErr) || sdkErr.Status != http.StatusPreconditionFailed {
		t.Fatalf("err = %v, want a 412 *docs.Error", err)
	}
	if sdkErr.Message != "the file was changed by someone else" || sdkErr.Code != "" {
		t.Errorf("Message = %q, Code = %q", sdkErr.Message, sdkErr.Code)
	}
	state, ok := sdkErr.PreconditionState()
	if !ok || state.CurrentETag != "e2" || state.UpdatedBy != "u-456" {
		t.Fatalf("PreconditionState = %+v, %v; want the current state", state, ok)
	}

	other := &Error{Status: http.StatusBadRequest}
	if _, ok := other.PreconditionState(); ok {
		t.Error("PreconditionState on a 400 reported ok")
	}
}

func TestTransportErrorWrapsCause(t *testing.T) {
	boom := errors.New("connection refused")
	client, _, _ := newTestClient(t, func(*http.Request) (*http.Response, error) { return nil, boom })

	_, err := client.Buckets.Get(context.Background())

	var sdkErr *Error
	if !errors.As(err, &sdkErr) || sdkErr.Status != 0 {
		t.Fatalf("err = %v, want a Status 0 *docs.Error", err)
	}
	if !errors.Is(err, boom) {
		t.Errorf("errors.Is(err, cause) = false; err = %v", err)
	}
}

func TestPathEncoding(t *testing.T) {
	ctx := context.Background()
	cases := []struct {
		name     string
		call     func(*Client) error
		wantPath string
	}{
		{
			name: "single-segment params are fully encoded",
			call: func(c *Client) error {
				_, err := c.Folders.Get(ctx, "my bucket", "a/b c?d#e&f+g=h@i:j;k,l$m%n")
				return err
			},
			wantPath: "/v1/documents/my%20bucket/folder/a%2Fb%20c%3Fd%23e%26f%2Bg%3Dh%40i%3Aj%3Bk%2Cl%24m%25n",
		},
		{
			name: "encodeURIComponent keeps !'()*-._~",
			call: func(c *Client) error {
				_, err := c.Nodes.Get(ctx, "a!'()*-._~z")
				return err
			},
			wantPath: "/v1/documents/nodes/a!'()*-._~z",
		},
		{
			name: "share link token",
			call: func(c *Client) error {
				_, err := c.Sharing.ResolveLink(ctx, "tok/en")
				return err
			},
			wantPath: "/v1/documents/link/tok%2Fen",
		},
		{
			name: "wildcard keeps separators",
			call: func(c *Client) error {
				_, err := c.Files.Get(ctx, "b1", "a b/c.txt")
				return err
			},
			wantPath: "/v1/documents/b1/file/a%20b/c.txt",
		},
		{
			name: "wildcard strips leading slash",
			call: func(c *Client) error {
				_, err := c.Files.ListArchive(ctx, "b1", "/exports/q3 report.zip")
				return err
			},
			wantPath: "/v1/documents/b1/archive/exports/q3%20report.zip",
		},
		{
			name: "wildcard encodes each segment",
			call: func(c *Client) error {
				_, err := c.AppFiles.Delete(ctx, "app 1", "2026/100% done?.txt")
				return err
			},
			wantPath: "/v1/documents/app-files/app%201/2026/100%25%20done%3F.txt",
		},
		{
			name: "wildcard keeps trailing slash and unicode",
			call: func(c *Client) error {
				_, err := c.Folders.ListAt(ctx, "b1", "नोट्स/Résumé/", nil)
				return err
			},
			wantPath: "/v1/documents/b1/objects/" + encodeComponent("नोट्स") + "/R%C3%A9sum%C3%A9/",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client, mt, _ := newTestClient(t, func(req *http.Request) (*http.Response, error) {
				if strings.Contains(req.URL.Path, "/link/") {
					return newResponse(req, http.StatusTemporaryRedirect, "", "Location", "https://cdn.example.com/x"), nil
				}
				return jsonResponse(req, http.StatusOK, `{"status":1,"data":null}`), nil
			})
			if err := tc.call(client); err != nil {
				t.Fatalf("call: %v", err)
			}
			if got := mt.last(t).Path; got != tc.wantPath {
				t.Fatalf("path = %s\n          want %s", got, tc.wantPath)
			}
		})
	}
}

func TestEncodeComponentMatchesEncodeURIComponent(t *testing.T) {
	// Expected values are what JavaScript's encodeURIComponent returns.
	cases := map[string]string{
		"abcXYZ019":   "abcXYZ019",
		"-_.!~*'()":   "-_.!~*'()",
		" ":           "%20",
		"/?#[]@":      "%2F%3F%23%5B%5D%40",
		"$&+,;=:":     "%24%26%2B%2C%3B%3D%3A",
		"%":           "%25",
		"\"<>\\^`{|}": "%22%3C%3E%5C%5E%60%7B%7C%7D",
		"é":           "%C3%A9",
		"€":           "%E2%82%AC",
	}
	for in, want := range cases {
		if got := encodeComponent(in); got != want {
			t.Errorf("encodeComponent(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestQueryParams(t *testing.T) {
	ctx := context.Background()
	cases := []struct {
		name string
		call func(*Client) error
		want url.Values
	}{
		{"folders nil params", func(c *Client) error { _, err := c.Folders.List(ctx, "b1", nil); return err }, url.Values{}},
		{"folders zero params", func(c *Client) error {
			_, err := c.Folders.List(ctx, "b1", &FolderListParams{})
			return err
		}, url.Values{}},
		{"folders sizes=false is sent", func(c *Client) error {
			_, err := c.Folders.List(ctx, "b1", &FolderListParams{Prefix: "a b/", Sizes: Bool(false)})
			return err
		}, url.Values{"prefix": {"a b/"}, "sizes": {"false"}}},
		{"listAt sizes", func(c *Client) error {
			_, err := c.Folders.ListAt(ctx, "b1", "x", &ListAtParams{Sizes: Bool(true)})
			return err
		}, url.Values{"sizes": {"true"}}},
		{"read without meta", func(c *Client) error {
			_, err := c.Files.Read(ctx, "b1", "notes/a.md", &FileReadParams{})
			return err
		}, url.Values{"path": {"notes/a.md"}}},
		{"read with meta", func(c *Client) error {
			_, err := c.Files.Read(ctx, "b1", "notes/a.md", &FileReadParams{Meta: true})
			return err
		}, url.Values{"path": {"notes/a.md"}, "meta": {"1"}}},
		{"recent zero limit", func(c *Client) error {
			_, err := c.Library.Recent(ctx, "b1", &RecentParams{})
			return err
		}, url.Values{}},
		{"recent limit", func(c *Client) error {
			_, err := c.Library.Recent(ctx, "b1", &RecentParams{Limit: 20})
			return err
		}, url.Values{"limit": {"20"}}},
		{"jobs", func(c *Client) error {
			_, err := c.Automation.Jobs(ctx, "b1", &JobListParams{ConfigID: "fc1"})
			return err
		}, url.Values{"configId": {"fc1"}}},
		{"shares without type", func(c *Client) error {
			_, err := c.Sharing.List(ctx, "b1", ".users/u1/a.pdf", &ShareListParams{})
			return err
		}, url.Values{"path": {".users/u1/a.pdf"}}},
		{"shared-with-me nil", func(c *Client) error { _, err := c.Sharing.SharedWithMe(ctx, "b1", nil); return err }, url.Values{}},
		{"webhooks nil", func(c *Client) error { _, err := c.Webhooks.List(ctx, nil); return err }, url.Values{}},
		{"webhooks page", func(c *Client) error {
			_, err := c.Webhooks.List(ctx, &WebhookListParams{Page: 2, Limit: 10})
			return err
		}, url.Values{"page": {"2"}, "limit": {"10"}}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client, mt, _ := newTestClient(t, nil)
			if err := tc.call(client); err != nil {
				t.Fatalf("call: %v", err)
			}
			req := mt.last(t)
			got, _ := url.ParseQuery(req.RawQuery)
			if len(tc.want) == 0 {
				if req.RawQuery != "" {
					t.Fatalf("RawQuery = %q, want no query string", req.RawQuery)
				}
				return
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("query = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestMissingRequiredArgumentsSendNothing(t *testing.T) {
	ctx := context.Background()
	cases := []struct {
		name string
		arg  string
		call func(*Client) error
	}{
		{"bucket", "bucketName", func(c *Client) error { _, err := c.Buckets.Stats(ctx, ""); return err }},
		{"folder key", "key", func(c *Client) error { _, err := c.Folders.Delete(ctx, "b1", " "); return err }},
		{"wildcard path", "path", func(c *Client) error { _, err := c.Files.Get(ctx, "b1", "/"); return err }},
		{"query path", "path", func(c *Client) error { _, err := c.Files.DeleteByPath(ctx, "b1", ""); return err }},
		{"search q", "q", func(c *Client) error { _, err := c.Search(ctx, "b1", ""); return err }},
		{"node id", "nodeId", func(c *Client) error { _, err := c.Nodes.Resolve(ctx, "", nil); return err }},
		{"share list path", "path", func(c *Client) error { _, err := c.Sharing.List(ctx, "b1", "", nil); return err }},
		{"share links path", "path", func(c *Client) error { _, err := c.Sharing.ListLinks(ctx, "b1", " ", nil); return err }},
		{"star path", "path", func(c *Client) error { _, err := c.Library.StarPath(ctx, "b1", "", nil); return err }},
		{"trigger id", "id", func(c *Client) error { return c.Triggers.Delete(ctx, "") }},
		{"upload files", "files", func(c *Client) error { _, err := c.Folders.Upload(ctx, "b1", nil, nil); return err }},
		{"upload file name", "file name", func(c *Client) error {
			_, err := c.Files.Upload(ctx, "b1", UploadFile{Data: []byte("x")}, nil)
			return err
		}},
		{"redirect token", "token", func(c *Client) error { _, err := c.Sharing.ResolveLink(ctx, ""); return err }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client, mt, _ := newTestClient(t, nil)
			err := tc.call(client)
			var sdkErr *Error
			if !errors.As(err, &sdkErr) || sdkErr.Status != 0 || sdkErr.Message != tc.arg+" is required" {
				t.Fatalf("err = %v, want *docs.Error %q", err, tc.arg+" is required")
			}
			if len(mt.requests) != 0 {
				t.Fatalf("sent %d requests, want none", len(mt.requests))
			}
		})
	}
}

func TestRequestBodiesUseSpecFieldNames(t *testing.T) {
	client, mt, _ := newTestClient(t, nil)
	_, err := client.Automation.Create(context.Background(), "b1", FolderConfigRequest{
		Prefix:       "invoices/",
		PipelineType: PipelineCustomWorkflow,
		WorkflowID:   "wf1",
		FileSuffixes: []string{".pdf"},
		EventTypes:   []EventType{EventTypeCreate, EventTypeUpdate},
		Active:       Bool(false),
		Config:       map[string]any{"lang": "en"},
	})
	if err != nil {
		t.Fatalf("Automation.Create: %v", err)
	}
	var body map[string]any
	if err := json.Unmarshal(mt.last(t).Body, &body); err != nil {
		t.Fatalf("body is not JSON: %v", err)
	}
	want := map[string]any{
		"prefix":       "invoices/",
		"pipelineType": "custom_workflow",
		"workflowId":   "wf1",
		"fileSuffixes": []any{".pdf"},
		"eventTypes":   []any{"create", "update"},
		"active":       false,
		"config":       map[string]any{"lang": "en"},
	}
	if !reflect.DeepEqual(body, want) {
		t.Fatalf("body = %v\nwant   %v", body, want)
	}

	// StarPath without params sends only the path; the service defaults the type.
	if _, err := client.Library.StarPath(context.Background(), "b1", "p/a.md", nil); err != nil {
		t.Fatalf("Library.StarPath: %v", err)
	}
	if got := string(mt.last(t).Body); got != `{"path":"p/a.md"}` {
		t.Errorf("star body = %s, want only the path", got)
	}

	// Trigger and webhook Active is always sent: the service stores it as is.
	if _, err := client.Triggers.Update(context.Background(), "t1", TriggerRequest{Prefix: "a/", WorkflowID: "wf1"}); err != nil {
		t.Fatalf("Triggers.Update: %v", err)
	}
	if !strings.Contains(string(mt.last(t).Body), `"active":false`) {
		t.Errorf("trigger body %s does not carry active", mt.last(t).Body)
	}
}

func TestDotSegmentsAreRejected(t *testing.T) {
	ctx := context.Background()
	cases := []struct {
		name string
		arg  string
		call func(*Client) error
	}{
		{"param dot", "bucketName", func(c *Client) error { _, err := c.Buckets.Stats(ctx, "."); return err }},
		{"param dot-dot", "key", func(c *Client) error { _, err := c.Folders.Get(ctx, "b1", ".."); return err }},
		{"node id", "nodeId", func(c *Client) error { _, err := c.Nodes.Get(ctx, ".."); return err }},
		{"wildcard leading", "path", func(c *Client) error { _, err := c.Files.Get(ctx, "b1", "../etc/passwd"); return err }},
		{"wildcard middle", "path", func(c *Client) error { _, err := c.Files.Delete(ctx, "b1", "a/./b.txt"); return err }},
		{"wildcard trailing", "path", func(c *Client) error { _, err := c.Folders.DownloadZip(ctx, "b1", "a/.."); return err }},
		{"redirect method", "path", func(c *Client) error { _, err := c.Files.DownloadURL(ctx, "b1", "a/../b"); return err }},
		{"app file", "path", func(c *Client) error { _, err := c.AppFiles.Delete(ctx, "app1", "../x"); return err }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client, mt, _ := newTestClient(t, nil)
			err := tc.call(client)
			var sdkErr *Error
			want := tc.arg + ` must not contain "." or ".." segments`
			if !errors.As(err, &sdkErr) || sdkErr.Status != 0 || sdkErr.Message != want {
				t.Fatalf("err = %v, want *docs.Error %q", err, want)
			}
			if len(mt.requests) != 0 {
				t.Fatalf("sent %d requests, want none", len(mt.requests))
			}
		})
	}

	// Dots inside a segment are ordinary characters.
	client, mt, _ := newTestClient(t, nil)
	if _, err := client.Files.Get(ctx, "b1", ".users/u1/a..b/.hidden/x...md"); err != nil {
		t.Fatalf("Files.Get: %v", err)
	}
	if got := mt.last(t).Path; got != "/v1/documents/b1/file/.users/u1/a..b/.hidden/x...md" {
		t.Fatalf("path = %s", got)
	}
}

func TestNoUserIDHeader(t *testing.T) {
	client, mt, _ := newTestClient(t, nil)
	if _, err := client.Library.Starred(context.Background(), "b1"); err != nil {
		t.Fatalf("Library.Starred: %v", err)
	}
	if got := mt.last(t).Header.Get("X-User-Id"); got != "" {
		t.Fatalf("X-User-Id = %q, want it unset (identity comes from the token)", got)
	}
}
