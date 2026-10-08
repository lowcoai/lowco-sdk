package docs

import (
	"context"
	"net/http"
)

// NodesResource resolves stable node ids. Apps store the permalink
// /v1/documents/d/{nodeId} instead of storage URLs; it survives renames.
type NodesResource struct {
	http *httpClient
}

// NodeResolveParams tunes Nodes.Resolve.
type NodeResolveParams struct {
	// Download makes the URL force a download under the file's name (sent
	// as download=1).
	Download bool
}

// Get returns a live node the caller can read, with the caller's role.
// GET /v1/documents/nodes/{nodeId}
func (r *NodesResource) Get(ctx context.Context, nodeID string) (NodeView, error) {
	return doJSON[NodeView](ctx, r.http, http.MethodGet, nil, nil, lit("nodes"), param("nodeId", nodeID))
}

// Resolve resolves a permalink without following its redirect. The result
// holds the fresh short-lived URL (307), the bytes of a file served from
// cold storage (200), or the restore state while a cold-storage restore runs
// (202; retry after RetryAfter seconds).
// GET /v1/documents/d/{nodeId}
func (r *NodesResource) Resolve(ctx context.Context, nodeID string, params *NodeResolveParams) (NodeFileResult, error) {
	q := query{}
	if params != nil {
		q.flag("download", params.Download)
	}
	return r.http.doNodeFile(ctx, q, lit("d"), param("nodeId", nodeID))
}

// Content returns the file's bytes with its stored content type and name
// (200), or the restore state while a cold-storage restore runs (202).
// GET /v1/documents/d/{nodeId}/content
func (r *NodesResource) Content(ctx context.Context, nodeID string) (NodeFileResult, error) {
	return r.http.doNodeFile(ctx, nil, lit("d"), param("nodeId", nodeID), lit("content"))
}
