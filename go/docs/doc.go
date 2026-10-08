// Package docs is the Go client for the lowco document service (files,
// folders, sharing, triggers, webhooks), the routes under /v1/documents.
//
// A single Client exposes one sub-client per resource group – Buckets,
// Folders, Files, Nodes, Library, Sharing, Automation, AppFiles, Triggers and
// Webhooks – plus Health and Search. They share one HTTP transport and send
// every request to the fixed host DefaultBaseURL ("https://api.lowco.ai").
//
// Construction requires a token (a user token or an API key), sent as
// "Authorization: Bearer <token>", and an org id, sent as the X-Org-Id header
// the service requires on every request:
//
//	client, err := docs.NewClient(docs.Config{
//		Token: "<token-or-api-key>",
//		OrgID: "org_123",
//	})
//	if err != nil {
//		log.Fatal(err)
//	}
//
//	bucket, err := client.Buckets.Get(ctx) // the org's bucket
//	if err != nil {
//		log.Fatal(err)
//	}
//	items, err := client.Folders.List(ctx, bucket.Name, &docs.FolderListParams{Prefix: "projects/"})
//
// Responses arrive in the envelope {"status": 1, "data": ...}; methods return
// the typed data. Non-2xx responses surface as *Error, carrying the HTTP
// status, the best message from either error body shape and the decoded
// payload.
//
// Files.DownloadURL, Files.PreviewURL and Sharing.ResolveLink do not follow
// the service's 307 redirect: they return the Location URL. Folders.DownloadZip
// returns a Binary. Nodes.Resolve and Nodes.Content return a NodeFileResult
// that holds a URL, the file's bytes, or the restore state of a file in cold
// storage (202).
package docs
