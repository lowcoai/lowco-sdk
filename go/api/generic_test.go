package api_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"testing"

	api "github.com/lowcoai/lowco-sdk/go/api"
)

func TestOperationByPath(t *testing.T) {
	m := newMock(t)
	c, _ := api.NewClient(api.Config{APIKey: "lc_test_sdk", BaseURL: m.srv.URL})
	ctx := context.Background()

	// files[] as multipart, options as the options part.
	ans, err := c.Operation(ctx, "/v1/pdf/merge", api.OperationInput{
		Files:  []api.FileInput{api.FileBytes([]byte("%PDF-a"), api.WithFilename("a.pdf")), api.FileBytes([]byte("%PDF-b"), api.WithFilename("b.pdf"))},
		Params: map[string]any{"bookmarks": true},
	})
	if err != nil {
		t.Fatal(err)
	}
	var merged struct {
		Pages int `json:"pages"`
	}
	if ans.Data == nil || json.Unmarshal(*ans.Data, &merged) != nil || merged.Pages != 2 {
		t.Fatalf("merge data = %v", ans.Data)
	}
	last := m.seen[len(m.seen)-1]
	if !strings.HasPrefix(last.header.Get("Content-Type"), "multipart/form-data") || !strings.Contains(string(last.body), `{"bookmarks":true}`) ||
		strings.Count(string(last.body), `name="files[]"`) != 2 {
		t.Fatalf("merge request = %s", last.body)
	}

	// A remote file by reference, async, then Result waits for the job.
	ans, err = c.Operation(ctx, "/v1/docai/invoice", api.OperationInput{File: api.FileID("file_1")}, api.WithMode("async"))
	if err != nil || ans.Job == nil || ans.Job.JobID != "job_inv" {
		t.Fatalf("async = %+v, %v", ans, err)
	}
	if body := string(m.seen[len(m.seen)-1].body); body != `{"file_id":"file_1"}` {
		t.Fatalf("reference body = %s", body)
	}
	res, err := ans.Result(ctx)
	if err != nil || !strings.Contains(string(*res), `"INV-1"`) {
		t.Fatalf("result = %s, %v", *res, err)
	}

	// No file input: options only; errors are the typed *Error.
	if _, err := c.Operation(ctx, "/v1/qr/generate", api.OperationInput{Params: map[string]any{"content": "hi"}}); err != nil {
		t.Fatal(err)
	}
	_, err = c.Operation(ctx, "/v1/pdf/rotate", api.OperationInput{File: api.FileID("file_1"), Params: map[string]any{"angle": 45}})
	var ae *api.Error
	if !errors.As(err, &ae) || ae.Reason != api.ReasonInvalidParam || ae.Param != "angle" {
		t.Fatalf("rotate err = %v", err)
	}
	if _, err := c.Operation(ctx, "/v1/pdf/merge", api.OperationInput{File: api.FileID("a"), Files: []api.FileInput{api.FileID("b")}}); err == nil {
		t.Fatal("File and Files together were accepted")
	}
}

func TestRequestByPath(t *testing.T) {
	m := newMock(t)
	c, _ := api.NewClient(api.Config{APIKey: "lc_test_sdk", BaseURL: m.srv.URL})
	ctx := context.Background()

	raw, err := c.Request(ctx, http.MethodGet, "/v1/jobs", url.Values{"status": {"failed"}}, nil)
	if err != nil || !strings.Contains(string(raw), `"next_cursor":"c2"`) {
		t.Fatalf("list = %s, %v", raw, err)
	}
	if q := m.seen[len(m.seen)-1].query; q["status"] != "failed" {
		t.Fatalf("query = %v", q)
	}
	// GETs are retried on 429 like the typed resources.
	raw, err = c.Request(ctx, http.MethodGet, "/v1/settings", nil, nil)
	if err != nil || !strings.Contains(string(raw), `"test"`) {
		t.Fatalf("settings = %s, %v", raw, err)
	}
	body, ctype, err := c.RequestRaw(ctx, http.MethodGet, "/v1/usage", url.Values{"format": {"csv"}}, "text/csv")
	if err != nil || ctype != "text/csv" || !strings.HasPrefix(string(body), "day,credits") {
		t.Fatalf("csv = %q %q %v", body, ctype, err)
	}
	if a := m.seen[len(m.seen)-1].header.Get("Accept"); a != "text/csv" {
		t.Fatalf("accept = %q", a)
	}
	_, err = c.Request(ctx, http.MethodGet, "/v1/nope", nil, nil)
	var ae *api.Error
	if !errors.As(err, &ae) || ae.Status != 404 {
		t.Fatalf("404 = %v", err)
	}
}
