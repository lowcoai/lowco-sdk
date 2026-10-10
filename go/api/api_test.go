package api_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	api "github.com/lowcoai/lowco-sdk/go/api"
)

var png = []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR")

type seen struct {
	method, path string
	query        map[string]string
	header       http.Header
	body         []byte
}

type mock struct {
	mu       sync.Mutex
	seen     []seen
	polls    int
	settings int
	srv      *httptest.Server
}

func env(data any) []byte { b, _ := json.Marshal(map[string]any{"status": 1, "data": data}); return b }

func job(id, status string, extra map[string]any) map[string]any {
	j := map[string]any{"job_id": id, "service": "docai", "operation": "invoice", "status": status, "progress": nil, "input": map[string]any{},
		"result": nil, "error": nil, "usage": nil, "attempts": 1, "created_at": "2026-10-09T09:30:00Z", "started_at": nil, "finished_at": nil,
		"expires_at": "2026-10-16T09:30:00Z", "links": map[string]any{"self": "/v1/jobs/" + id, "cancel": "/v1/jobs/" + id + "/cancel"}}
	for k, v := range extra {
		j[k] = v
	}
	return j
}

func newMock(t *testing.T) *mock {
	m := &mock{}
	m.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		q := map[string]string{}
		for k, v := range r.URL.Query() {
			q[k] = v[0]
		}
		m.mu.Lock()
		m.seen = append(m.seen, seen{r.Method, r.URL.Path, q, r.Header.Clone(), body})
		m.mu.Unlock()
		send := func(status int, b []byte, hdr ...string) {
			w.Header().Set("Content-Type", "application/json")
			w.Header().Set("X-Request-Id", "req_test")
			for i := 0; i+1 < len(hdr); i += 2 {
				w.Header().Set(hdr[i], hdr[i+1])
			}
			w.WriteHeader(status)
			_, _ = w.Write(b)
		}
		apiErr := func(status int, reason, msg, param string) []byte {
			b, _ := json.Marshal(map[string]any{"status": 0, "error": map[string]any{"code": status, "reason": reason, "message": msg, "param": param, "request_id": "req_err", "doc_url": "https://docs.lowco.ai/api/errors#" + reason}})
			return b
		}
		if r.Header.Get("Authorization") != "Bearer lc_test_sdk" && !strings.HasPrefix(r.URL.Path, "/v1/downloads/") {
			send(401, apiErr(401, "missing_key", "No key", ""))
			return
		}
		switch r.Method + " " + r.URL.Path {
		case "POST /v1/qr/generate":
			if r.Header.Get("Accept") == "image/png" {
				w.Header().Set("Content-Type", "image/png")
				_, _ = w.Write(png)
				return
			}
			send(200, env(map[string]any{"format": "png", "width": 512}), "X-Lowco-Credits-Used", "0.0500")
		case "POST /v1/docai/invoice":
			if q["mode"] == "async" {
				send(202, env(job("job_inv", "queued", nil)), "Retry-After", "0")
				return
			}
			send(200, env(map[string]any{}))
		case "GET /v1/jobs/job_inv":
			m.mu.Lock()
			m.polls++
			n := m.polls
			m.mu.Unlock()
			if n < 3 {
				send(200, env(job("job_inv", "processing", nil)), "Retry-After", "0")
				return
			}
			send(200, env(job("job_inv", "succeeded", map[string]any{"result": map[string]any{"invoice_number": map[string]any{"value": "INV-1", "confidence": 0.98, "source": map[string]any{"page": 1}}}})))
		case "GET /v1/jobs/job_bad":
			send(200, env(job("job_bad", "failed", map[string]any{"error": map[string]any{"code": 422, "reason": "file_corrupt", "message": "The file is not a readable PDF.", "doc_url": "x"}})))
		case "GET /v1/jobs/job_slow":
			send(200, env(job("job_slow", "processing", nil)), "Retry-After", "0")
		case "GET /v1/jobs":
			if q["cursor"] == "" {
				send(200, env(map[string]any{"items": []any{job("j1", "succeeded", nil), job("j2", "succeeded", nil)}, "next_cursor": "c2"}))
				return
			}
			send(200, env(map[string]any{"items": []any{job("j3", "failed", nil)}, "next_cursor": nil}))
		case "POST /v1/files":
			send(201, env(map[string]any{"file_id": "file_uploaded", "filename": "file", "bytes": 3, "mime_type": "application/pdf", "sha256": "x", "source": "upload", "expires_at": nil, "created_at": "2026-10-09T09:30:00Z"}))
		case "POST /v1/pdf/merge":
			send(200, env(map[string]any{"pages": 2, "files_merged": 2, "file": map[string]any{"file_id": "file_m", "url": nil}}))
		case "POST /v1/pdf/rotate":
			send(400, apiErr(400, "invalid_param", "angle must be 90, 180 or 270.", "angle"))
		case "POST /v1/ocr/text":
			send(202, env(job("job_ocr", "queued", nil)), "Idempotent-Replayed", "true")
		case "GET /v1/settings":
			m.mu.Lock()
			m.settings++
			n := m.settings
			m.mu.Unlock()
			if n == 1 {
				send(429, apiErr(429, "rate_limited", "Slow down", ""), "Retry-After", "0")
				return
			}
			send(200, env(map[string]any{"environment": "test"}))
		case "GET /v1/files/file_x/content":
			w.Header().Set("Location", m.srv.URL+"/v1/downloads/tok_x")
			w.WriteHeader(307)
		case "GET /v1/usage":
			if q["format"] == "csv" {
				w.Header().Set("Content-Type", "text/csv")
				_, _ = w.Write([]byte("day,credits\n2026-10-09,1.50\n"))
				return
			}
			send(200, env(map[string]any{"rows": []any{}}))
		case "GET /v1/downloads/tok_x":
			w.Header().Set("Content-Type", "application/pdf")
			_, _ = w.Write([]byte("%PDF-1.7"))
		default:
			send(404, apiErr(404, "route_not_found", "no route", ""))
		}
	}))
	t.Cleanup(m.srv.Close)
	return m
}

func (m *mock) last(path string) seen {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i := len(m.seen) - 1; i >= 0; i-- {
		if m.seen[i].path == path {
			return m.seen[i]
		}
	}
	return seen{}
}

func client(t *testing.T, m *mock) *api.Client {
	c, err := api.NewClient(api.Config{APIKey: "lc_test_sdk", BaseURL: m.srv.URL})
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func TestInlineAnswerAndBytes(t *testing.T) {
	m := newMock(t)
	ctx := context.Background()
	a, err := client(t, m).QR.Generate(ctx, api.QrGenerateParams{Type: api.String("upi"), Pa: api.String("acme@okhdfcbank"), Pn: api.String("Acme"), Am: api.String("1499.00")})
	if err != nil {
		t.Fatal(err)
	}
	if a.Status != 200 || a.Data.Width == nil || *a.Data.Width != 512 || a.RequestID != "req_test" || a.CreditsUsed != "0.0500" {
		t.Fatalf("answer %+v", a)
	}
	var sent map[string]any
	_ = json.Unmarshal(m.last("/v1/qr/generate").body, &sent)
	if len(sent) != 4 || sent["pa"] != "acme@okhdfcbank" {
		t.Fatalf("body %v", sent)
	}
	if !strings.HasPrefix(m.last("/v1/qr/generate").header.Get("X-Client-User-Agent"), "lowcoai-api-go/") {
		t.Fatal("user agent")
	}
	raw, err := client(t, m).QR.Generate(ctx, api.QrGenerateParams{Content: api.String("x")}, api.WithAccept("image/png"))
	if err != nil || string(raw.Bytes) != string(png) || raw.ContentType != "image/png" {
		t.Fatalf("bytes %v %v", raw, err)
	}
}

func TestMultipartThenResult(t *testing.T) {
	m := newMock(t)
	dir := t.TempDir()
	path := filepath.Join(dir, "invoice.pdf")
	_ = os.WriteFile(path, []byte("%PDF-1.7 test"), 0o644)
	ctx := context.Background()
	a, err := client(t, m).DocAI.Invoice(ctx, api.DocaiInvoiceParams{File: api.FilePath(path), Languages: []string{"eng", "hin"}}, api.WithMode("async"))
	if err != nil {
		t.Fatal(err)
	}
	if a.Status != 202 || a.Job.JobID != "job_inv" {
		t.Fatalf("answer %+v", a)
	}
	sent := m.last("/v1/docai/invoice")
	if !strings.HasPrefix(sent.header.Get("Content-Type"), "multipart/form-data") || sent.query["mode"] != "async" {
		t.Fatalf("sent %v %v", sent.header, sent.query)
	}
	text := string(sent.body)
	for _, want := range []string{`name="file"; filename="invoice.pdf"`, "%PDF-1.7 test", "name=\"options\"\r\n\r\n{\"languages\":[\"eng\",\"hin\"]}"} {
		if !strings.Contains(text, want) {
			t.Fatalf("multipart lacks %q:\n%s", want, text)
		}
	}
	inv, err := a.Result(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if inv.InvoiceNumber.Value != "INV-1" || m.polls != 3 {
		t.Fatalf("result %+v after %d polls", inv.InvoiceNumber, m.polls)
	}
}

func TestReferencesAndMixedInputs(t *testing.T) {
	m := newMock(t)
	ctx := context.Background()
	c := client(t, m)
	if _, err := c.PDF.Merge(ctx, api.PdfMergeParams{Files: []api.FileInput{api.FileID("file_a"), api.FileURL("https://example.com/b.pdf")}, Bookmarks: api.Bool(true)}); err != nil {
		t.Fatal(err)
	}
	if got := string(m.last("/v1/pdf/merge").body); got != `{"bookmarks":true,"files":[{"file_id":"file_a"},{"file_url":"https://example.com/b.pdf"}]}` {
		t.Fatalf("json %s", got)
	}
	if _, err := c.PDF.Merge(ctx, api.PdfMergeParams{Files: []api.FileInput{api.FileID("file_a"), api.FileBytes([]byte("%PD"))}}); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(m.last("/v1/files").header.Get("Content-Type"), "multipart/form-data") {
		t.Fatal("no upload")
	}
	if got := string(m.last("/v1/pdf/merge").body); got != `{"files":[{"file_id":"file_a"},{"file_id":"file_uploaded"}]}` {
		t.Fatalf("mixed json %s", got)
	}
}

func TestTypedErrors(t *testing.T) {
	m := newMock(t)
	_, err := client(t, m).PDF.Rotate(context.Background(), api.PdfRotateParams{File: api.FileID("file_a"), Angle: 45})
	var e *api.Error
	if !errors.As(err, &e) || e.Status != 400 || e.Reason != api.ReasonInvalidParam || e.Param != "angle" || e.RequestID != "req_err" || e.DocURL != "https://docs.lowco.ai/api/errors#invalid_param" {
		t.Fatalf("error %#v", err)
	}
	if api.ErrorReasons[api.ReasonInvalidParam].Status != 400 || len(api.ErrorReasons) != 56 {
		t.Fatal("reasons")
	}
}

func TestIdempotencyRetryAndPaging(t *testing.T) {
	m := newMock(t)
	ctx := context.Background()
	c := client(t, m)
	key := api.NewIdempotencyKey()
	a, err := c.OCR.Text(ctx, api.OcrTextParams{File: api.FileID("file_a")}, api.WithIdempotencyKey(key), api.WithMode("async"))
	if err != nil || !a.Replayed || m.last("/v1/ocr/text").header.Get("Idempotency-Key") != key {
		t.Fatalf("idempotency %v %v", a, err)
	}
	s, err := c.Settings.Get(ctx)
	if err != nil || s.Environment != "test" || m.settings != 2 {
		t.Fatalf("retry %v %v %d", s, err, m.settings)
	}
	jobs, err := c.Jobs.ListAll(ctx, &api.JobsListQuery{Status: api.String("succeeded")}).All(ctx)
	if err != nil || len(jobs) != 3 || jobs[2].JobID != "j3" || m.last("/v1/jobs").query["cursor"] != "c2" {
		t.Fatalf("paging %v %v", jobs, err)
	}
}

func TestJobFailuresAndTimeouts(t *testing.T) {
	m := newMock(t)
	ctx := context.Background()
	c := client(t, m)
	_, err := c.Jobs.Wait(ctx, "job_bad")
	var je *api.JobFailedError
	var e *api.Error
	if !errors.As(err, &je) || je.Job.Status != "failed" || !errors.As(err, &e) || e.Reason != api.ReasonFileCorrupt {
		t.Fatalf("failed job %v", err)
	}
	_, err = c.Jobs.Wait(ctx, "job_slow", api.WithWaitTimeout(50*time.Millisecond))
	var te *api.TimeoutError
	if !errors.As(err, &te) || te.JobID != "job_slow" {
		t.Fatalf("timeout %v", err)
	}
}

func TestContentURLAndDownload(t *testing.T) {
	m := newMock(t)
	ctx := context.Background()
	c := client(t, m)
	link, err := c.Files.ContentURL(ctx, "file_x")
	if err != nil || link != m.srv.URL+"/v1/downloads/tok_x" {
		t.Fatalf("link %q %v", link, err)
	}
	b, err := c.Files.Download(ctx, link)
	if err != nil || string(b) != "%PDF-1.7" || m.last("/v1/downloads/tok_x").header.Get("Authorization") != "" {
		t.Fatalf("download %q %v", b, err)
	}
}

func TestMissingKey(t *testing.T) {
	t.Setenv("LOWCO_API_KEY", "")
	if _, err := api.NewClient(api.Config{}); !errors.Is(err, api.ErrMissingAPIKey) {
		t.Fatalf("missing key: %v", err)
	}
}

func TestWebhookVectorsFromLowcoAPI(t *testing.T) {
	b, err := os.ReadFile("../../specs/webhook-signature-vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	var f struct {
		Vectors []struct {
			Name, Header, Body, Secret string
			Now                        int64
			Valid                      bool
		}
	}
	if err := json.Unmarshal(b, &f); err != nil || len(f.Vectors) != 8 {
		t.Fatalf("vectors %v", err)
	}
	for _, v := range f.Vectors {
		if got := api.VerifySignature(v.Header, []byte(v.Body), v.Secret, api.WithNow(time.Unix(v.Now, 0))); got != v.Valid {
			t.Errorf("%s: %v", v.Name, got)
		}
	}
	ok := f.Vectors[0]
	ev, err := api.ConstructEvent([]byte(ok.Body), ok.Header, ok.Secret, api.WithNow(time.Unix(ok.Now, 0)))
	if err != nil || ev.Type != "job.succeeded" {
		t.Fatalf("event %v %v", ev, err)
	}
}
