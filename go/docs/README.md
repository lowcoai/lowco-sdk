# docs (Go)

Official Go client for the lowco **document** service (files, folders, sharing, triggers, webhooks), the routes under `/v1/documents`.

```bash
go get github.com/lowcoai/lowco-sdk/go/docs
```

## Quick start

```go
package main

import (
	"context"
	"log"

	"github.com/lowcoai/lowco-sdk/go/docs"
)

func main() {
	ctx := context.Background()

	client, err := docs.NewClient(docs.Config{
		Token: "your-token-or-api-key", // required
		OrgID: "org_123",               // required
	})
	if err != nil {
		log.Fatal(err)
	}

	// The org's bucket; its Name is the bucketName every bucket route takes.
	bucket, err := client.Buckets.Get(ctx)
	if err != nil {
		log.Fatal(err)
	}

	items, err := client.Folders.List(ctx, bucket.Name, &docs.FolderListParams{Prefix: "projects/"})
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("found %d items", len(items))
}
```

## Configuration

| Field | Required | Description |
|---|---|---|
| `Token` | yes | User token or API key, sent as `Authorization: Bearer <Token>`. |
| `OrgID` | yes | Sent as `X-Org-Id`; the service rejects every request without it. |
| `TimeoutMS` | no | Timeout of the default HTTP client (30s when zero). |
| `Headers` | no | Extra headers sent on every request. |
| `HTTPClient` | no | Custom `*http.Client` (transport, proxy, timeout). `TimeoutMS` is not applied to it. |

`NewClient` returns `docs.ErrMissingToken` or `docs.ErrMissingOrgID` when either required field is empty. The SDK does not send `X-User-Id`: the gateway derives the user from the token. Add it through `Headers` if you call the service directly.

## Examples

Every method takes a `context.Context` first. `b` below is the bucket name.

### Folders

```go
created, err := client.Folders.Create(ctx, b, docs.CreateFolderRequest{ParentName: "projects", FolderName: "2026/q4"})
rows, err := client.Folders.ListAt(ctx, b, "projects/2026", &docs.ListAtParams{Sizes: docs.Bool(false)})

result, err := client.Folders.Upload(ctx, b, []docs.UploadFile{
	{FileName: "a.jpg", Data: aBytes, ContentType: "image/jpeg"},
	{FileName: "b.jpg", Data: bBytes},
}, &docs.FolderUploadOptions{RelativePaths: []string{"photos/a.jpg", "photos/2026/b.jpg"}, ParentID: "albums"})

zip, err := client.Folders.DownloadZip(ctx, b, "projects/2026") // zip.Data, zip.FileName == "2026.zip"
msg, err := client.Folders.DeleteByPath(ctx, b, "projects/2026/")
```

### Files

```go
doc, err := client.Files.Upload(ctx, b,
	docs.UploadFile{FileName: "q3.pdf", Data: pdf, ContentType: "application/pdf"},
	&docs.FileUploadOptions{ParentID: "reports", OnConflict: docs.OnConflictRename})

// Conditional save: read the etag, send it back as IfMatch.
file, err := client.Files.Read(ctx, b, "notes/todo.md", nil)
_, err = client.Files.Update(ctx, b, docs.UpdateFileRequest{
	ParentName: "notes", FileName: "todo.md", Content: "# Todo", IfMatch: file.ETag,
})
var sdkErr *docs.Error
if errors.As(err, &sdkErr) {
	if state, ok := sdkErr.PreconditionState(); ok {
		log.Printf("changed by %s; current etag %s", state.UpdatedBy, state.CurrentETag)
	}
}

url, err := client.Files.DownloadURL(ctx, b, "reports/q3.pdf") // short-lived URL, not followed
```

### Nodes (permalinks)

```go
res, err := client.Nodes.Resolve(ctx, nodeID, &docs.NodeResolveParams{Download: true})
switch {
case res.URL != "":
	// redirect target (307)
case res.Content != nil:
	// bytes served directly (file restored from cold storage)
case res.Restoring != nil:
	// cold-storage restore running (202); retry after res.RetryAfter seconds
}
```

### Library

```go
_, err := client.Library.Star(ctx, b, nodeID)
_, err = client.Library.StarPath(ctx, b, "projects/", &docs.StarPathParams{Type: docs.NodeTypeFolder})
recent, err := client.Library.Recent(ctx, b, &docs.RecentParams{Limit: 20})
restored, err := client.Library.Restore(ctx, b, trashedNodeID)
```

### Sharing

```go
share, err := client.Sharing.Create(ctx, b, docs.CreateShareRequest{
	Path: ".users/u-123/reports/q3.pdf", SubjectType: docs.ShareSubjectUser,
	SubjectID: "u-456", Role: docs.ShareRoleViewer,
})
grants, err := client.Sharing.List(ctx, b, ".users/u-123/reports/q3.pdf", nil)
link, err := client.Sharing.CreateLink(ctx, b, docs.CreateShareLinkRequest{Path: ".users/u-123/reports/q3.pdf"})
fileURL, err := client.Sharing.ResolveLink(ctx, link.Token) // short-lived URL, not followed
```

### Automation (folder configs)

```go
rule, err := client.Automation.Create(ctx, b, docs.FolderConfigRequest{
	Prefix: "invoices/", PipelineType: docs.PipelineCustomWorkflow, WorkflowID: "wf_123",
	FileSuffixes: []string{".pdf"}, EventTypes: []docs.EventType{docs.EventTypeCreate},
})
jobs, err := client.Automation.Jobs(ctx, b, &docs.JobListParams{ConfigID: rule.ID, Limit: 50})
```

### App files

```go
up, err := client.AppFiles.Upload(ctx, "invoicing",
	docs.UploadFile{FileName: "INV-0042.pdf", Data: pdf},
	&docs.AppFileUploadOptions{Path: "2026/invoices"})
// Store up.Permalink (/v1/documents/d/{nodeId}) instead of a storage URL.
sweep, err := client.AppFiles.Sweep(ctx, "invoicing", docs.SweepRequest{Prefix: "2026", OlderThanDays: 90})
```

### Triggers and webhooks

```go
trigger, err := client.Triggers.Create(ctx, docs.TriggerRequest{
	EventType: docs.EventTypeCreate, Active: true, WorkflowID: "wf_123", Prefix: "invoices/", Suffix: ".pdf",
})
hook, err := client.Webhooks.Create(ctx, docs.WebhookRequest{
	URL: "https://hooks.example.com/documents", Method: "POST", Active: true,
	EventTypes: []docs.EventType{docs.EventTypeCreate, docs.EventTypeUpdate}, Prefix: "uploads/",
})
hooks, err := client.Webhooks.List(ctx, &docs.WebhookListParams{Page: 1, Limit: 20})
```

`Update` replaces every field of a trigger or webhook, and `Active` is stored exactly as sent.

### Search and health

```go
hits, err := client.Search(ctx, b, "invoice")
status, err := client.Health(ctx) // "Working!"
```

## Resources

`client.Buckets`, `client.Folders`, `client.Files`, `client.Nodes`, `client.Library`,
`client.Sharing`, `client.Automation`, `client.AppFiles`, `client.Triggers`,
`client.Webhooks`, plus `client.Health` and `client.Search`. Each method's doc comment
names the endpoint it calls.

## Error handling

Non-2xx responses, network and timeout failures (`Status` `0`) and invalid arguments
(`Status` `0`, no request sent) return `*docs.Error`:

```go
if err != nil {
	var sdkErr *docs.Error
	if errors.As(err, &sdkErr) {
		log.Printf("status=%d code=%s message=%s payload=%v",
			sdkErr.Status, sdkErr.Code, sdkErr.Message, sdkErr.Payload)
	}
}
```

The service answers errors as `{"status":0,"error":{"message","code","details"}}` or
`{"message":"..."}`. For the first shape, when `error.message` is a platform code such as
`AAS-00106`, `Message` holds `details` and `Code` holds the code. `Payload` is the decoded
body. `errors.Is(err, context.DeadlineExceeded)` works for transport failures.

Empty required arguments and path segments that are exactly `.` or `..` are rejected
before sending, since URL normalisation would route them elsewhere.

## Redirects and binary results

- `Files.DownloadURL`, `Files.PreviewURL` and `Sharing.ResolveLink` do not follow the
  service's 307: they return the `Location` URL (a signed URL is returned verbatim). They
  send through a shallow copy of your `*http.Client` with redirects disabled, so your
  client is never mutated.
- `Folders.DownloadZip` returns a `docs.Binary` (`Data`, `ContentType`, `FileName`).
  `FileName` comes from `X-File-Name`, else from `Content-Disposition`.
- `Nodes.Resolve` and `Nodes.Content` return a `docs.NodeFileResult` with exactly one of
  `URL` (307), `Content` (200) or `Restoring` (202, cold storage) set; `RetryAfter` holds
  the `Retry-After` seconds.
- Binary bodies are read fully into memory. For very large zips, pass an `HTTPClient`
  with a suitable timeout.

## Conventions

- Host: all requests go to `https://api.lowco.ai` (`docs.DefaultBaseURL`), under `/v1/documents` (`/health` excepted).
- Auth: `Authorization: Bearer <Token>` on every request.
- Tenancy: `X-Org-Id` header (from `Config.OrgID`).
- Response envelope: `{ "status": 1, "data": ... }`. The SDK unwraps `data` for you.
- Path parameters: single-segment values are fully percent-encoded; file and folder paths
  keep their `/` separators, with each segment encoded and a leading `/` stripped.
- Query parameters are omitted when unset (zero values of optional fields).
