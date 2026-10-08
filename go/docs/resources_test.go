package docs

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"reflect"
	"strings"
	"testing"
)

// routeResponder answers like the service would per route kind: redirects for
// URL methods and permalinks, bytes for zips and text for /health.
func routeResponder(req *http.Request) (*http.Response, error) {
	p := req.URL.Path
	switch {
	case p == "/health":
		return newResponse(req, http.StatusOK, "Working!", "Content-Type", "text/plain"), nil
	case strings.Contains(p, "/download/"), strings.Contains(p, "/preview/"),
		strings.HasPrefix(p, "/v1/documents/link/"), p == "/v1/documents/d/n1":
		return newResponse(req, http.StatusTemporaryRedirect, "", "Location", "https://cdn.example.com/f"), nil
	case strings.Contains(p, "/folder-zip/"), p == "/v1/documents/d/n1/content":
		return newResponse(req, http.StatusOK, "bytes", "Content-Type", "application/octet-stream"), nil
	}
	return jsonResponse(req, http.StatusOK, `{"status":1,"data":null}`), nil
}

// TestEveryOperationRoute checks the method, escaped path, query and body of
// all 69 operations.
func TestEveryOperationRoute(t *testing.T) {
	ctx := context.Background()
	file := UploadFile{FileName: "a.txt", Data: []byte("a")}
	type op struct {
		name   string
		call   func(*Client) error
		method string
		path   string
		query  url.Values
		// body is the expected JSON body; "" means no body, "multipart" a form.
		body string
	}
	ops := []op{
		// Client
		{"Health", func(c *Client) error { _, err := c.Health(ctx); return err }, "GET", "/health", nil, ""},
		{"Search", func(c *Client) error { _, err := c.Search(ctx, "b1", "plan q3"); return err },
			"GET", "/v1/documents/b1/search", url.Values{"q": {"plan q3"}}, ""},

		// Buckets
		{"Buckets.Get", func(c *Client) error { _, err := c.Buckets.Get(ctx); return err }, "GET", "/v1/documents", nil, ""},
		{"Buckets.Stats", func(c *Client) error { _, err := c.Buckets.Stats(ctx, "b1"); return err },
			"GET", "/v1/documents/b1/stats", nil, ""},

		// Folders
		{"Folders.List", func(c *Client) error {
			_, err := c.Folders.List(ctx, "b1", &FolderListParams{Prefix: "p/", Sizes: Bool(false)})
			return err
		}, "GET", "/v1/documents/b1/objects", url.Values{"prefix": {"p/"}, "sizes": {"false"}}, ""},
		{"Folders.ListAt", func(c *Client) error { _, err := c.Folders.ListAt(ctx, "b1", "p/q", nil); return err },
			"GET", "/v1/documents/b1/objects/p/q", nil, ""},
		{"Folders.ListPublic", func(c *Client) error {
			_, err := c.Folders.ListPublic(ctx, "b1", &FolderListParams{Prefix: "p/"})
			return err
		}, "GET", "/v1/documents/b1/public/objects", url.Values{"prefix": {"p/"}}, ""},
		{"Folders.ListUser", func(c *Client) error { _, err := c.Folders.ListUser(ctx, "b1", "u1", nil); return err },
			"GET", "/v1/documents/b1/users/u1/objects", nil, ""},
		{"Folders.ListApp", func(c *Client) error {
			_, err := c.Folders.ListApp(ctx, "b1", "a1", &FolderListParams{Sizes: Bool(true)})
			return err
		}, "GET", "/v1/documents/b1/apps/a1/objects", url.Values{"sizes": {"true"}}, ""},
		{"Folders.Get", func(c *Client) error { _, err := c.Folders.Get(ctx, "b1", "k1"); return err },
			"GET", "/v1/documents/b1/folder/k1", nil, ""},
		{"Folders.Create", func(c *Client) error {
			_, err := c.Folders.Create(ctx, "b1", CreateFolderRequest{ParentName: "p", FolderName: "a/b"})
			return err
		}, "POST", "/v1/documents/b1/folder", nil, `{"parentName":"p","folderName":"a/b"}`},
		{"Folders.Delete", func(c *Client) error { _, err := c.Folders.Delete(ctx, "b1", "k1"); return err },
			"DELETE", "/v1/documents/b1/folder/k1", nil, ""},
		{"Folders.DeleteByPath", func(c *Client) error { _, err := c.Folders.DeleteByPath(ctx, "b1", "p/q/"); return err },
			"DELETE", "/v1/documents/b1/folder", url.Values{"path": {"p/q/"}}, ""},
		{"Folders.Upload", func(c *Client) error { _, err := c.Folders.Upload(ctx, "b1", []UploadFile{file}, nil); return err },
			"POST", "/v1/documents/b1/upload-folder", nil, "multipart"},
		{"Folders.DownloadZip", func(c *Client) error { _, err := c.Folders.DownloadZip(ctx, "b1", "p/q"); return err },
			"GET", "/v1/documents/b1/folder-zip/p/q", nil, ""},
		{"Folders.Duplicate", func(c *Client) error {
			_, err := c.Folders.Duplicate(ctx, "b1", DuplicateRequest{Path: "p/a.md", Type: NodeTypeFile})
			return err
		}, "POST", "/v1/documents/b1/duplicate", nil, `{"path":"p/a.md","type":"file"}`},
		{"Folders.Rename", func(c *Client) error {
			_, err := c.Folders.Rename(ctx, "b1", RenameRequest{ParentName: "p", OldName: "a", NewName: "b"})
			return err
		}, "PUT", "/v1/documents/b1/folder/rename", nil, `{"parentName":"p","oldName":"a","newName":"b"}`},

		// Files
		{"Files.Get", func(c *Client) error { _, err := c.Files.Get(ctx, "b1", "p/a.md"); return err },
			"GET", "/v1/documents/b1/file/p/a.md", nil, ""},
		{"Files.Read", func(c *Client) error {
			_, err := c.Files.Read(ctx, "b1", "p/a.md", &FileReadParams{Meta: true})
			return err
		}, "GET", "/v1/documents/b1/file", url.Values{"path": {"p/a.md"}, "meta": {"1"}}, ""},
		{"Files.CreateBlank", func(c *Client) error {
			_, err := c.Files.CreateBlank(ctx, "b1", CreateBlankFileRequest{ParentName: "p", FileName: "a.md"})
			return err
		}, "POST", "/v1/documents/b1/file", nil, `{"parentName":"p","fileName":"a.md"}`},
		{"Files.Update", func(c *Client) error {
			_, err := c.Files.Update(ctx, "b1", UpdateFileRequest{ParentName: "p", FileName: "a.md", Content: "# A", IfMatch: "e1"})
			return err
		}, "PUT", "/v1/documents/b1/file", nil, `{"parentName":"p","fileName":"a.md","content":"# A","ifMatch":"e1"}`},
		{"Files.UpdateAt", func(c *Client) error {
			_, err := c.Files.UpdateAt(ctx, "b1", "p/a.md", UpdateFileRequest{FileName: "a.md", Content: "", IfNoneMatch: "*"})
			return err
		}, "PUT", "/v1/documents/b1/file/p/a.md", nil, `{"fileName":"a.md","content":"","ifNoneMatch":"*"}`},
		{"Files.Rename", func(c *Client) error {
			_, err := c.Files.Rename(ctx, "b1", RenameRequest{OldName: "a.md", NewName: "b.md"})
			return err
		}, "PUT", "/v1/documents/b1/file/rename", nil, `{"oldName":"a.md","newName":"b.md"}`},
		{"Files.Delete", func(c *Client) error { _, err := c.Files.Delete(ctx, "b1", "p/a.md"); return err },
			"DELETE", "/v1/documents/b1/file/p/a.md", nil, ""},
		{"Files.DeleteByPath", func(c *Client) error { _, err := c.Files.DeleteByPath(ctx, "b1", "p/a.md"); return err },
			"DELETE", "/v1/documents/b1/file", url.Values{"path": {"p/a.md"}}, ""},
		{"Files.Upload", func(c *Client) error { _, err := c.Files.Upload(ctx, "b1", file, nil); return err },
			"POST", "/v1/documents/b1/upload-file", nil, "multipart"},
		{"Files.DownloadURL", func(c *Client) error { _, err := c.Files.DownloadURL(ctx, "b1", "p/a.md"); return err },
			"GET", "/v1/documents/b1/download/p/a.md", nil, ""},
		{"Files.PreviewURL", func(c *Client) error { _, err := c.Files.PreviewURL(ctx, "b1", "p/a.docx"); return err },
			"GET", "/v1/documents/b1/preview/p/a.docx", nil, ""},
		{"Files.ListArchive", func(c *Client) error { _, err := c.Files.ListArchive(ctx, "b1", "p/a.zip"); return err },
			"GET", "/v1/documents/b1/archive/p/a.zip", nil, ""},

		// Nodes
		{"Nodes.Get", func(c *Client) error { _, err := c.Nodes.Get(ctx, "n1"); return err },
			"GET", "/v1/documents/nodes/n1", nil, ""},
		{"Nodes.Resolve", func(c *Client) error {
			_, err := c.Nodes.Resolve(ctx, "n1", &NodeResolveParams{Download: true})
			return err
		},
			"GET", "/v1/documents/d/n1", url.Values{"download": {"1"}}, ""},
		{"Nodes.Content", func(c *Client) error { _, err := c.Nodes.Content(ctx, "n1"); return err },
			"GET", "/v1/documents/d/n1/content", nil, ""},

		// Library
		{"Library.Star", func(c *Client) error { _, err := c.Library.Star(ctx, "b1", "n1"); return err },
			"POST", "/v1/documents/b1/nodes/n1/star", nil, ""},
		{"Library.Unstar", func(c *Client) error { _, err := c.Library.Unstar(ctx, "b1", "n1"); return err },
			"DELETE", "/v1/documents/b1/nodes/n1/star", nil, ""},
		{"Library.StarPath", func(c *Client) error {
			_, err := c.Library.StarPath(ctx, "b1", "p/", &StarPathParams{Type: NodeTypeFolder})
			return err
		}, "POST", "/v1/documents/b1/star", nil, `{"path":"p/","type":"folder"}`},
		{"Library.UnstarPath", func(c *Client) error { _, err := c.Library.UnstarPath(ctx, "b1", "p/a.md"); return err },
			"DELETE", "/v1/documents/b1/star", url.Values{"path": {"p/a.md"}}, ""},
		{"Library.Starred", func(c *Client) error { _, err := c.Library.Starred(ctx, "b1"); return err },
			"GET", "/v1/documents/b1/starred", nil, ""},
		{"Library.Recent", func(c *Client) error { _, err := c.Library.Recent(ctx, "b1", &RecentParams{Limit: 5}); return err },
			"GET", "/v1/documents/b1/recent", url.Values{"limit": {"5"}}, ""},
		{"Library.Trash", func(c *Client) error { _, err := c.Library.Trash(ctx, "b1"); return err },
			"GET", "/v1/documents/b1/trash", nil, ""},
		{"Library.Restore", func(c *Client) error { _, err := c.Library.Restore(ctx, "b1", "n1"); return err },
			"POST", "/v1/documents/b1/trash/n1/restore", nil, ""},
		{"Library.Purge", func(c *Client) error { _, err := c.Library.Purge(ctx, "b1", "n1"); return err },
			"DELETE", "/v1/documents/b1/trash/n1", nil, ""},

		// Sharing
		{"Sharing.Create", func(c *Client) error {
			_, err := c.Sharing.Create(ctx, "b1", CreateShareRequest{Path: ".users/u1/a.pdf", Type: NodeTypeFile,
				SubjectType: ShareSubjectUser, SubjectID: "u2", Role: ShareRoleViewer, ExpiresAt: "2026-12-31T00:00:00Z"})
			return err
		}, "POST", "/v1/documents/b1/shares", nil,
			`{"path":".users/u1/a.pdf","type":"file","subjectType":"user","subjectId":"u2","role":"viewer","expiresAt":"2026-12-31T00:00:00Z"}`},
		{"Sharing.List", func(c *Client) error {
			_, err := c.Sharing.List(ctx, "b1", ".users/u1/p/", &ShareListParams{Type: NodeTypeFolder})
			return err
		}, "GET", "/v1/documents/b1/shares", url.Values{"path": {".users/u1/p/"}, "type": {"folder"}}, ""},
		{"Sharing.Delete", func(c *Client) error { _, err := c.Sharing.Delete(ctx, "b1", "i1"); return err },
			"DELETE", "/v1/documents/b1/shares/i1", nil, ""},
		{"Sharing.SharedWithMe", func(c *Client) error {
			_, err := c.Sharing.SharedWithMe(ctx, "b1", &SharedWithMeParams{AppKey: "notes"})
			return err
		}, "GET", "/v1/documents/b1/shared-with-me", url.Values{"appKey": {"notes"}}, ""},
		{"Sharing.CreateLink", func(c *Client) error {
			_, err := c.Sharing.CreateLink(ctx, "b1", CreateShareLinkRequest{Path: ".users/u1/a.pdf", Type: NodeTypeFile})
			return err
		}, "POST", "/v1/documents/b1/share-links", nil, `{"path":".users/u1/a.pdf","type":"file"}`},
		{"Sharing.ListLinks", func(c *Client) error {
			_, err := c.Sharing.ListLinks(ctx, "b1", ".users/u1/a.pdf", nil)
			return err
		}, "GET", "/v1/documents/b1/share-links", url.Values{"path": {".users/u1/a.pdf"}}, ""},
		{"Sharing.DeleteLink", func(c *Client) error { _, err := c.Sharing.DeleteLink(ctx, "b1", "i1"); return err },
			"DELETE", "/v1/documents/b1/share-links/i1", nil, ""},
		{"Sharing.ResolveLink", func(c *Client) error { _, err := c.Sharing.ResolveLink(ctx, "t1"); return err },
			"GET", "/v1/documents/link/t1", nil, ""},

		// Automation
		{"Automation.List", func(c *Client) error {
			_, err := c.Automation.List(ctx, "b1", &AutomationListParams{Prefix: "in/"})
			return err
		}, "GET", "/v1/documents/b1/folder-configs", url.Values{"prefix": {"in/"}}, ""},
		{"Automation.Create", func(c *Client) error {
			_, err := c.Automation.Create(ctx, "b1", FolderConfigRequest{Prefix: "in/", PipelineType: PipelineExtractText})
			return err
		}, "POST", "/v1/documents/b1/folder-configs", nil, `{"prefix":"in/","pipelineType":"extract_text"}`},
		{"Automation.Get", func(c *Client) error { _, err := c.Automation.Get(ctx, "b1", "i1"); return err },
			"GET", "/v1/documents/b1/folder-configs/i1", nil, ""},
		{"Automation.Update", func(c *Client) error {
			_, err := c.Automation.Update(ctx, "b1", "i1", FolderConfigRequest{Prefix: "in/", PipelineType: PipelineThumbnail, Active: Bool(true)})
			return err
		}, "PUT", "/v1/documents/b1/folder-configs/i1", nil, `{"prefix":"in/","pipelineType":"thumbnail","active":true}`},
		{"Automation.Delete", func(c *Client) error { _, err := c.Automation.Delete(ctx, "b1", "i1"); return err },
			"DELETE", "/v1/documents/b1/folder-configs/i1", nil, ""},
		{"Automation.Jobs", func(c *Client) error {
			_, err := c.Automation.Jobs(ctx, "b1", &JobListParams{ConfigID: "i1", Limit: 10})
			return err
		}, "GET", "/v1/documents/b1/processing-jobs", url.Values{"configId": {"i1"}, "limit": {"10"}}, ""},

		// AppFiles
		{"AppFiles.Upload", func(c *Client) error { _, err := c.AppFiles.Upload(ctx, "app1", file, nil); return err },
			"POST", "/v1/documents/app-files/app1", nil, "multipart"},
		{"AppFiles.List", func(c *Client) error {
			_, err := c.AppFiles.List(ctx, "app1", &AppFileListParams{Prefix: "2026"})
			return err
		}, "GET", "/v1/documents/app-files/app1/objects", url.Values{"prefix": {"2026"}}, ""},
		{"AppFiles.Delete", func(c *Client) error { _, err := c.AppFiles.Delete(ctx, "app1", "2026/a.pdf"); return err },
			"DELETE", "/v1/documents/app-files/app1/2026/a.pdf", nil, ""},
		{"AppFiles.Sweep", func(c *Client) error {
			_, err := c.AppFiles.Sweep(ctx, "app1", SweepRequest{Prefix: "skills", OlderThanDays: 30, Limit: 100})
			return err
		}, "POST", "/v1/documents/app-files/app1/sweep", nil, `{"prefix":"skills","olderThanDays":30,"limit":100}`},

		// Triggers
		{"Triggers.List", func(c *Client) error { _, err := c.Triggers.List(ctx); return err },
			"GET", "/v1/documents/triggers", nil, ""},
		{"Triggers.Create", func(c *Client) error {
			_, err := c.Triggers.Create(ctx, TriggerRequest{EventType: EventTypeCreate, Active: true, WorkflowID: "wf1", Prefix: "in/", Suffix: ".pdf"})
			return err
		}, "POST", "/v1/documents/triggers", nil, `{"eventType":"create","active":true,"workflowId":"wf1","prefix":"in/","suffix":".pdf"}`},
		{"Triggers.Get", func(c *Client) error { _, err := c.Triggers.Get(ctx, "i1"); return err },
			"GET", "/v1/documents/triggers/i1", nil, ""},
		{"Triggers.Update", func(c *Client) error {
			_, err := c.Triggers.Update(ctx, "i1", TriggerRequest{EventType: EventTypeDelete, WorkflowID: "wf1", WorkflowName: "Intake", Prefix: "in/"})
			return err
		}, "PUT", "/v1/documents/triggers/i1", nil, `{"eventType":"delete","active":false,"workflowId":"wf1","workflowName":"Intake","prefix":"in/"}`},
		{"Triggers.Delete", func(c *Client) error { return c.Triggers.Delete(ctx, "i1") },
			"DELETE", "/v1/documents/triggers/i1", nil, ""},

		// Webhooks
		{"Webhooks.List", func(c *Client) error {
			_, err := c.Webhooks.List(ctx, &WebhookListParams{Page: 1, Limit: 20})
			return err
		},
			"GET", "/v1/documents/webhooks", url.Values{"page": {"1"}, "limit": {"20"}}, ""},
		{"Webhooks.Create", func(c *Client) error {
			_, err := c.Webhooks.Create(ctx, WebhookRequest{URL: "https://hooks.example.com", Headers: map[string]string{"X-Key": "k"},
				EventTypes: []EventType{EventTypeCreate}, Method: "POST", Active: true, Prefix: "up/"})
			return err
		}, "POST", "/v1/documents/webhooks", nil,
			`{"url":"https://hooks.example.com","headers":{"X-Key":"k"},"eventTypes":["create"],"method":"POST","active":true,"prefix":"up/"}`},
		{"Webhooks.Get", func(c *Client) error { _, err := c.Webhooks.Get(ctx, "i1"); return err },
			"GET", "/v1/documents/webhooks/i1", nil, ""},
		{"Webhooks.Update", func(c *Client) error {
			_, err := c.Webhooks.Update(ctx, "i1", WebhookRequest{URL: "https://h", EventTypes: []EventType{EventTypeUpdate}, Method: "PUT", Prefix: "up/", Suffix: ".png"})
			return err
		}, "PUT", "/v1/documents/webhooks/i1", nil,
			`{"url":"https://h","eventTypes":["update"],"method":"PUT","active":false,"prefix":"up/","suffix":".png"}`},
		{"Webhooks.Delete", func(c *Client) error { return c.Webhooks.Delete(ctx, "i1") },
			"DELETE", "/v1/documents/webhooks/i1", nil, ""},
	}

	if len(ops) != 69 {
		t.Fatalf("table covers %d operations, want 69", len(ops))
	}

	for _, tc := range ops {
		t.Run(tc.name, func(t *testing.T) {
			client, mt, _ := newTestClient(t, routeResponder)
			if err := tc.call(client); err != nil {
				t.Fatalf("call: %v", err)
			}
			if len(mt.requests) != 1 {
				t.Fatalf("sent %d requests, want 1", len(mt.requests))
			}
			req := mt.last(t)
			if req.Method != tc.method || req.Path != tc.path {
				t.Fatalf("request = %s %s, want %s %s", req.Method, req.Path, tc.method, tc.path)
			}
			gotQuery, _ := url.ParseQuery(req.RawQuery)
			if len(tc.query) == 0 && req.RawQuery != "" {
				t.Errorf("query = %q, want none", req.RawQuery)
			}
			if len(tc.query) > 0 && !reflect.DeepEqual(gotQuery, tc.query) {
				t.Errorf("query = %v, want %v", gotQuery, tc.query)
			}
			if req.Header.Get("Authorization") != "Bearer test-token" || req.Header.Get("X-Org-Id") != "org-1" {
				t.Errorf("auth headers = %q / %q", req.Header.Get("Authorization"), req.Header.Get("X-Org-Id"))
			}
			switch tc.body {
			case "":
				if len(req.Body) != 0 {
					t.Errorf("body = %s, want none", req.Body)
				}
			case "multipart":
				if !strings.HasPrefix(req.Header.Get("Content-Type"), "multipart/form-data; boundary=") {
					t.Errorf("Content-Type = %q, want multipart/form-data", req.Header.Get("Content-Type"))
				}
			default:
				var got, want any
				if err := json.Unmarshal(req.Body, &got); err != nil {
					t.Fatalf("body %q is not JSON: %v", req.Body, err)
				}
				if err := json.Unmarshal([]byte(tc.body), &want); err != nil {
					t.Fatalf("bad expected body: %v", err)
				}
				if !reflect.DeepEqual(got, want) {
					t.Errorf("body = %s\nwant   %s", req.Body, tc.body)
				}
			}
		})
	}
}
