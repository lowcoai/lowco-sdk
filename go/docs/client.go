package docs

import (
	"context"
	"net/http"
)

// DefaultBaseURL is the fixed API host every request is sent to.
const DefaultBaseURL = "https://api.lowco.ai"

// Client is the document service client. It exposes one sub-client per
// resource group that all share the same HTTP transport and tenancy headers.
type Client struct {
	// Buckets reads the org's bucket and its storage usage.
	Buckets *BucketsResource
	// Folders lists, creates, uploads, zips, renames and deletes folders.
	Folders *FoldersResource
	// Files reads, saves, uploads, renames, deletes and links files.
	Files *FilesResource
	// Nodes resolves stable node ids (permalinks) to metadata and content.
	Nodes *NodesResource
	// Library manages the caller's stars, recent items and trash.
	Library *LibraryResource
	// Sharing manages grants, share links and items shared with the caller.
	Sharing *SharingResource
	// Automation manages folder automation rules and their run history.
	Automation *AutomationResource
	// AppFiles stores and manages app data under .apps/{appKey}/.
	AppFiles *AppFilesResource
	// Triggers manages workflow triggers on object events.
	Triggers *TriggersResource
	// Webhooks manages webhooks on object events.
	Webhooks *WebhooksResource

	http *httpClient
}

// NewClient constructs a Client targeting DefaultBaseURL. Config.Token and
// Config.OrgID are required: it returns ErrMissingToken or ErrMissingOrgID
// when either is empty.
func NewClient(config Config) (*Client, error) {
	transport, err := newHTTPClient(config)
	if err != nil {
		return nil, err
	}

	return &Client{
		Buckets:    &BucketsResource{http: transport},
		Folders:    &FoldersResource{http: transport},
		Files:      &FilesResource{http: transport},
		Nodes:      &NodesResource{http: transport},
		Library:    &LibraryResource{http: transport},
		Sharing:    &SharingResource{http: transport},
		Automation: &AutomationResource{http: transport},
		AppFiles:   &AppFilesResource{http: transport},
		Triggers:   &TriggersResource{http: transport},
		Webhooks:   &WebhooksResource{http: transport},
		http:       transport,
	}, nil
}

// Health calls the liveness probe (GET /health, outside the /v1/documents
// prefix) and returns its text body ("Working!").
func (c *Client) Health(ctx context.Context) (string, error) {
	return c.http.doText(ctx, "/health")
}

// Search finds files and folders in bucketName whose name matches q, then
// documents whose extracted text matches (marked metadata.matchedBy=content).
// GET /v1/documents/{bucketName}/search?q=
func (c *Client) Search(ctx context.Context, bucketName, q string) ([]Document, error) {
	if err := requireValue("q", q); err != nil {
		return nil, err
	}
	params := query{}
	params.str("q", q)
	return doJSON[[]Document](ctx, c.http, http.MethodGet, params, nil, param("bucketName", bucketName), lit("search"))
}
