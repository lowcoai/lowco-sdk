package docs

import (
	"bytes"
	"context"
	"errors"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"reflect"
	"testing"
	"time"
)

// formPart is one part of a recorded multipart body, in wire order.
type formPart struct {
	Name        string
	FileName    string
	ContentType string
	Value       string
}

func readMultipart(t *testing.T, req recordedRequest) []formPart {
	t.Helper()
	mediaType, params, err := mime.ParseMediaType(req.Header.Get("Content-Type"))
	if err != nil || mediaType != "multipart/form-data" {
		t.Fatalf("Content-Type = %q, want multipart/form-data", req.Header.Get("Content-Type"))
	}
	reader := multipart.NewReader(bytes.NewReader(req.Body), params["boundary"])
	var parts []formPart
	for {
		part, err := reader.NextPart()
		if errors.Is(err, io.EOF) {
			return parts
		}
		if err != nil {
			t.Fatalf("NextPart: %v", err)
		}
		data, err := io.ReadAll(part)
		if err != nil {
			t.Fatalf("read part: %v", err)
		}
		fp := formPart{Name: part.FormName(), Value: string(data)}
		if _, dispParams, err := mime.ParseMediaType(part.Header.Get("Content-Disposition")); err == nil {
			fp.FileName = dispParams["filename"]
		}
		if fp.FileName != "" {
			fp.ContentType = part.Header.Get("Content-Type")
		}
		parts = append(parts, fp)
	}
}

func TestFilesUploadMultipart(t *testing.T) {
	client, mt, _ := newTestClient(t, respondWith(http.StatusOK,
		`{"status":1,"data":{"id":"n9","name":"q3.pdf","path":"/reports/q3.pdf","type":"file"}}`))

	doc, err := client.Files.Upload(context.Background(), "b1",
		UploadFile{FileName: "q3.pdf", Data: []byte("%PDF-1.7"), ContentType: "application/pdf"},
		&FileUploadOptions{ParentID: "reports", OnConflict: OnConflictRename})
	if err != nil {
		t.Fatalf("Files.Upload: %v", err)
	}
	if doc.ID != "n9" {
		t.Errorf("doc = %+v, want the unwrapped document", doc)
	}

	req := mt.last(t)
	if req.Method != http.MethodPost || req.Path != "/v1/documents/b1/upload-file" {
		t.Fatalf("request = %s %s", req.Method, req.Path)
	}
	want := []formPart{
		{Name: "file", FileName: "q3.pdf", ContentType: "application/pdf", Value: "%PDF-1.7"},
		{Name: "ParentID", Value: "reports"},
		{Name: "onConflict", Value: "rename"},
	}
	if got := readMultipart(t, req); !reflect.DeepEqual(got, want) {
		t.Fatalf("parts = %+v\nwant    %+v", got, want)
	}

	// Empty options are omitted; the content type defaults to octet-stream.
	if _, err := client.Files.Upload(context.Background(), "b1", UploadFile{FileName: "a.bin", Data: []byte{1, 2}}, nil); err != nil {
		t.Fatalf("Files.Upload: %v", err)
	}
	want = []formPart{{Name: "file", FileName: "a.bin", ContentType: "application/octet-stream", Value: "\x01\x02"}}
	if got := readMultipart(t, mt.last(t)); !reflect.DeepEqual(got, want) {
		t.Fatalf("parts = %+v\nwant    %+v", got, want)
	}
}

func TestFoldersUploadMultipart(t *testing.T) {
	client, mt, _ := newTestClient(t, respondWith(http.StatusOK,
		`{"status":1,"data":{"folder":{"name":"photos","type":"folder"},"files":[{"name":"a.jpg"},{"name":"b.jpg"}]}}`))

	result, err := client.Folders.Upload(context.Background(), "b1", []UploadFile{
		{FileName: "a.jpg", Data: []byte("A"), ContentType: "image/jpeg"},
		{FileName: "photos/2026/b.jpg", Data: []byte("B")},
	}, &FolderUploadOptions{RelativePaths: []string{"photos/a.jpg"}, ParentID: "albums", Prefix: "ignored/"})
	if err != nil {
		t.Fatalf("Folders.Upload: %v", err)
	}
	if result.Folder.Name != "photos" || len(result.Files) != 2 {
		t.Errorf("result = %+v, want the unwrapped upload result", result)
	}

	req := mt.last(t)
	if req.Method != http.MethodPost || req.Path != "/v1/documents/b1/upload-folder" {
		t.Fatalf("request = %s %s", req.Method, req.Path)
	}
	want := []formPart{
		{Name: "files", FileName: "a.jpg", ContentType: "image/jpeg", Value: "A"},
		{Name: "files", FileName: "photos/2026/b.jpg", ContentType: "application/octet-stream", Value: "B"},
		{Name: "relativePaths", Value: "photos/a.jpg"},
		// The missing entry is filled with the file's own name.
		{Name: "relativePaths", Value: "photos/2026/b.jpg"},
		{Name: "parentID", Value: "albums"},
		{Name: "prefix", Value: "ignored/"},
	}
	if got := readMultipart(t, req); !reflect.DeepEqual(got, want) {
		t.Fatalf("parts = %+v\nwant    %+v", got, want)
	}
}

func TestAppFilesUploadMultipart(t *testing.T) {
	client, mt, _ := newTestClient(t, respondWith(http.StatusOK,
		`{"status":1,"data":{"appKey":"invoicing","name":"INV-1.pdf","nodeId":"n1","permalink":"/v1/documents/d/n1","size":3}}`))

	up, err := client.AppFiles.Upload(context.Background(), "invoicing",
		UploadFile{FileName: "INV-1.pdf", Data: []byte("pdf")},
		&AppFileUploadOptions{Path: "2026/invoices", OnConflict: OnConflictReplace})
	if err != nil {
		t.Fatalf("AppFiles.Upload: %v", err)
	}
	if up.Permalink != "/v1/documents/d/n1" || up.Size != 3 {
		t.Errorf("upload = %+v", up)
	}
	req := mt.last(t)
	if req.Method != http.MethodPost || req.Path != "/v1/documents/app-files/invoicing" {
		t.Fatalf("request = %s %s", req.Method, req.Path)
	}
	want := []formPart{
		{Name: "file", FileName: "INV-1.pdf", ContentType: "application/octet-stream", Value: "pdf"},
		{Name: "path", Value: "2026/invoices"},
		{Name: "onConflict", Value: "replace"},
	}
	if got := readMultipart(t, req); !reflect.DeepEqual(got, want) {
		t.Fatalf("parts = %+v\nwant    %+v", got, want)
	}
}

func TestRedirectURLMethods(t *testing.T) {
	ctx := context.Background()
	const location = "https://cdn.example.com/b1/a%20b.pdf?X-Amz-Signature=abc%2Fdef&X-Amz-Expires=300"
	cases := []struct {
		name     string
		call     func(*Client) (string, error)
		wantPath string
	}{
		{"Files.DownloadURL", func(c *Client) (string, error) { return c.Files.DownloadURL(ctx, "b1", "docs/a b.pdf") },
			"/v1/documents/b1/download/docs/a%20b.pdf"},
		{"Files.PreviewURL", func(c *Client) (string, error) { return c.Files.PreviewURL(ctx, "b1", "docs/a.docx") },
			"/v1/documents/b1/preview/docs/a.docx"},
		{"Sharing.ResolveLink", func(c *Client) (string, error) { return c.Sharing.ResolveLink(ctx, "tok1") },
			"/v1/documents/link/tok1"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client, mt, httpClient := newTestClient(t,
				respondWith(http.StatusTemporaryRedirect, "", "Location", location))

			got, err := tc.call(client)
			if err != nil {
				t.Fatalf("call: %v", err)
			}
			if got != location {
				t.Errorf("URL = %q, want the Location header verbatim", got)
			}
			if len(mt.requests) != 1 {
				t.Fatalf("sent %d requests, want 1 (redirect must not be followed)", len(mt.requests))
			}
			if req := mt.last(t); req.Method != http.MethodGet || req.Path != tc.wantPath {
				t.Errorf("request = %s %s, want GET %s", req.Method, req.Path, tc.wantPath)
			}
			if httpClient.CheckRedirect != nil {
				t.Error("the caller's http.Client was mutated (CheckRedirect set)")
			}
		})
	}

	t.Run("relative location is resolved", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusFound, "", "Location", "/files/a.pdf?sig=1"))
		got, err := client.Files.DownloadURL(ctx, "b1", "a.pdf")
		if err != nil || got != "https://api.lowco.ai/files/a.pdf?sig=1" {
			t.Fatalf("DownloadURL = %q, %v", got, err)
		}
	})

	t.Run("JSON methods still follow redirects", func(t *testing.T) {
		calls := 0
		client, mt, _ := newTestClient(t, func(req *http.Request) (*http.Response, error) {
			calls++
			if calls == 1 {
				return newResponse(req, http.StatusTemporaryRedirect, "", "Location", "/v1/documents/b1/stats2"), nil
			}
			return jsonResponse(req, http.StatusOK, `{"status":1,"data":{"folderCount":1}}`), nil
		})
		stats, err := client.Buckets.Stats(ctx, "b1")
		if err != nil || stats.FolderCount != 1 || len(mt.requests) != 2 {
			t.Fatalf("Stats = %+v, %v after %d requests; want the followed response", stats, err, len(mt.requests))
		}
	})
}

func TestRedirectURLMethodErrors(t *testing.T) {
	ctx := context.Background()
	cases := []struct {
		name        string
		status      int
		body        string
		headers     []string
		wantStatus  int
		wantMessage string
	}{
		{"error body", http.StatusForbidden, `{"message":"no read access"}`, nil, http.StatusForbidden, "no read access"},
		{"missing location", http.StatusTemporaryRedirect, "", nil, http.StatusTemporaryRedirect,
			"redirect response (status 307) has no Location header"},
		{"not a redirect", http.StatusOK, `{"status":1,"data":"x"}`, nil, http.StatusOK, "expected a redirect, got status 200"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client, _, _ := newTestClient(t, respondWith(tc.status, tc.body, tc.headers...))
			_, err := client.Files.PreviewURL(ctx, "b1", "a.docx")
			var sdkErr *Error
			if !errors.As(err, &sdkErr) || sdkErr.Status != tc.wantStatus || sdkErr.Message != tc.wantMessage {
				t.Fatalf("err = %#v, want status %d message %q", err, tc.wantStatus, tc.wantMessage)
			}
		})
	}
}

func TestDownloadZipBinary(t *testing.T) {
	ctx := context.Background()

	t.Run("X-File-Name wins", func(t *testing.T) {
		client, mt, _ := newTestClient(t, respondWith(http.StatusOK, "PK\x03\x04zip",
			"Content-Type", "application/zip",
			"X-File-Name", "Q3 reports.zip",
			"Content-Disposition", `attachment; filename="other.zip"`))
		bin, err := client.Folders.DownloadZip(ctx, "b1", "projects/Q3 reports/")
		if err != nil {
			t.Fatalf("DownloadZip: %v", err)
		}
		if string(bin.Data) != "PK\x03\x04zip" || bin.ContentType != "application/zip" || bin.FileName != "Q3 reports.zip" {
			t.Fatalf("binary = %+v", bin)
		}
		req := mt.last(t)
		if req.Path != "/v1/documents/b1/folder-zip/projects/Q3%20reports/" || req.Header.Get("Accept") != "*/*" {
			t.Errorf("request = %s Accept %q", req.Path, req.Header.Get("Accept"))
		}
	})

	t.Run("Content-Disposition fallback", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusOK, "zip",
			"Content-Type", "application/zip",
			"Content-Disposition", `attachment; filename="projects.zip"`))
		bin, err := client.Folders.DownloadZip(ctx, "b1", "projects")
		if err != nil || bin.FileName != "projects.zip" {
			t.Fatalf("binary = %+v, %v; want FileName from Content-Disposition", bin, err)
		}
	})

	t.Run("error body", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusNotFound,
			`{"status":0,"error":{"message":"AAS-00102","code":404,"details":"folder not found"}}`))
		_, err := client.Folders.DownloadZip(ctx, "b1", "nope")
		var sdkErr *Error
		if !errors.As(err, &sdkErr) || sdkErr.Status != http.StatusNotFound || sdkErr.Message != "folder not found" {
			t.Fatalf("err = %v, want a 404 *docs.Error", err)
		}
	})
}

func TestNodesResolve(t *testing.T) {
	ctx := context.Background()

	t.Run("redirect", func(t *testing.T) {
		client, mt, _ := newTestClient(t, respondWith(http.StatusTemporaryRedirect, "", "Location", "https://cdn.example.com/a.pdf?sig=1"))
		res, err := client.Nodes.Resolve(ctx, "n1", &NodeResolveParams{Download: true})
		if err != nil {
			t.Fatalf("Resolve: %v", err)
		}
		if res.URL != "https://cdn.example.com/a.pdf?sig=1" || res.Content != nil || res.Restoring != nil {
			t.Fatalf("result = %+v, want only URL", res)
		}
		req := mt.last(t)
		if len(mt.requests) != 1 || req.Path != "/v1/documents/d/n1" || req.RawQuery != "download=1" {
			t.Errorf("request = %s?%s (%d sent)", req.Path, req.RawQuery, len(mt.requests))
		}
	})

	t.Run("no download flag", func(t *testing.T) {
		client, mt, _ := newTestClient(t, respondWith(http.StatusTemporaryRedirect, "", "Location", "https://cdn.example.com/a"))
		if _, err := client.Nodes.Resolve(ctx, "n1", &NodeResolveParams{}); err != nil {
			t.Fatalf("Resolve: %v", err)
		}
		if q := mt.last(t).RawQuery; q != "" {
			t.Errorf("RawQuery = %q, want none", q)
		}
	})

	t.Run("content from cold storage", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusOK, "bytes", "Content-Type", "application/pdf"))
		res, err := client.Nodes.Resolve(ctx, "n1", nil)
		if err != nil || res.Content == nil || string(res.Content.Data) != "bytes" ||
			res.Content.ContentType != "application/pdf" || res.URL != "" || res.Restoring != nil {
			t.Fatalf("result = %+v, %v; want only Content", res, err)
		}
	})

	t.Run("restoring", func(t *testing.T) {
		client, _, _ := newTestClient(t, func(req *http.Request) (*http.Response, error) {
			resp := jsonResponse(req, http.StatusAccepted, `{"status":1,"data":{"status":"restoring","nodeId":"n1",`+
				`"name":"q3.pdf","retryAfterSeconds":300,"message":"try again in a few minutes"}}`)
			resp.Header.Set("Retry-After", "120")
			return resp, nil
		})
		res, err := client.Nodes.Resolve(ctx, "n1", nil)
		if err != nil {
			t.Fatalf("Resolve: %v", err)
		}
		if res.Restoring == nil || res.Restoring.Status != "restoring" || res.Restoring.NodeID != "n1" ||
			res.Restoring.RetryAfterSeconds != 300 || res.URL != "" || res.Content != nil {
			t.Fatalf("result = %+v, want only Restoring", res)
		}
		if res.RetryAfter != 120 {
			t.Errorf("RetryAfter = %d, want 120 from the header", res.RetryAfter)
		}
	})

	t.Run("error", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusGone, `{"message":"archive tier not available"}`))
		_, err := client.Nodes.Resolve(ctx, "n1", nil)
		var sdkErr *Error
		if !errors.As(err, &sdkErr) || sdkErr.Status != http.StatusGone {
			t.Fatalf("err = %v, want a 410 *docs.Error", err)
		}
	})
}

func TestNodesContent(t *testing.T) {
	ctx := context.Background()

	t.Run("bytes", func(t *testing.T) {
		client, mt, _ := newTestClient(t, respondWith(http.StatusOK, "hello",
			"Content-Type", "text/plain; charset=utf-8",
			"X-File-Name", "skill.py",
			"Content-Disposition", `inline; filename="skill.py"`))
		res, err := client.Nodes.Content(ctx, "n1")
		if err != nil {
			t.Fatalf("Content: %v", err)
		}
		if res.Content == nil || string(res.Content.Data) != "hello" || res.Content.FileName != "skill.py" ||
			res.Content.ContentType != "text/plain; charset=utf-8" {
			t.Fatalf("result = %+v", res)
		}
		if req := mt.last(t); req.Path != "/v1/documents/d/n1/content" {
			t.Errorf("path = %s", req.Path)
		}
	})

	t.Run("restoring without Retry-After", func(t *testing.T) {
		client, _, _ := newTestClient(t, respondWith(http.StatusAccepted,
			`{"status":1,"data":{"status":"restoring","nodeId":"n1","retryAfterSeconds":300}}`))
		res, err := client.Nodes.Content(ctx, "n1")
		if err != nil || res.Restoring == nil || res.RetryAfter != 300 {
			t.Fatalf("result = %+v, %v; want RetryAfter from the body", res, err)
		}
	})
}

func TestHealth(t *testing.T) {
	client, mt, _ := newTestClient(t, respondWith(http.StatusOK, "Working!", "Content-Type", "text/plain"))
	got, err := client.Health(context.Background())
	if err != nil || got != "Working!" {
		t.Fatalf("Health = %q, %v", got, err)
	}
	if req := mt.last(t); req.Path != "/health" || req.Header.Get("Accept") != "text/plain" {
		t.Errorf("request = %s Accept %q, want /health outside the prefix", req.Path, req.Header.Get("Accept"))
	}
}

func TestParseRetryAfter(t *testing.T) {
	if got := parseRetryAfter("300"); got != 300 {
		t.Errorf("seconds = %d", got)
	}
	for _, v := range []string{"", "-5", "soon"} {
		if got := parseRetryAfter(v); got != 0 {
			t.Errorf("parseRetryAfter(%q) = %d, want 0", v, got)
		}
	}
	date := time.Now().Add(90 * time.Second).UTC().Format(http.TimeFormat)
	if got := parseRetryAfter(date); got < 85 || got > 91 {
		t.Errorf("HTTP date = %d, want about 90", got)
	}
}
