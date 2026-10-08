package docs

import (
	"context"
	"net/http"
)

// LibraryResource manages the caller's personal library: stars, recent items
// and trash.
type LibraryResource struct {
	http *httpClient
}

// StarPathParams tunes Library.StarPath.
type StarPathParams struct {
	// Type is the item type; set NodeTypeFolder for folders (service
	// default: NodeTypeFile).
	Type NodeType
}

// RecentParams tunes Library.Recent.
type RecentParams struct {
	// Limit is the maximum number of items (1-200); 0 leaves the service
	// default (50).
	Limit int
}

// Star stars a node and returns the service's confirmation message.
// POST /v1/documents/{bucketName}/nodes/{nodeId}/star
func (r *LibraryResource) Star(ctx context.Context, bucketName, nodeID string) (string, error) {
	return doJSON[string](ctx, r.http, http.MethodPost, nil, nil,
		param("bucketName", bucketName), lit("nodes"), param("nodeId", nodeID), lit("star"))
}

// Unstar removes the caller's star from a node and returns the service's
// confirmation message.
// DELETE /v1/documents/{bucketName}/nodes/{nodeId}/star
func (r *LibraryResource) Unstar(ctx context.Context, bucketName, nodeID string) (string, error) {
	return doJSON[string](ctx, r.http, http.MethodDelete, nil, nil,
		param("bucketName", bucketName), lit("nodes"), param("nodeId", nodeID), lit("star"))
}

// StarPath stars the item at path, creating its node row when needed, and
// returns it. The body is StarByPathRequest{Path, Type}.
// POST /v1/documents/{bucketName}/star
func (r *LibraryResource) StarPath(ctx context.Context, bucketName, path string, params *StarPathParams) (Document, error) {
	if err := requireValue("path", path); err != nil {
		return Document{}, err
	}
	body := StarByPathRequest{Path: path}
	if params != nil {
		body.Type = params.Type
	}
	return doJSON[Document](ctx, r.http, http.MethodPost, nil, body, param("bucketName", bucketName), lit("star"))
}

// UnstarPath removes the caller's star from the item at path and returns the
// service's confirmation message.
// DELETE /v1/documents/{bucketName}/star?path=
func (r *LibraryResource) UnstarPath(ctx context.Context, bucketName, path string) (string, error) {
	if err := requireValue("path", path); err != nil {
		return "", err
	}
	q := query{}
	q.str("path", path)
	return doJSON[string](ctx, r.http, http.MethodDelete, q, nil, param("bucketName", bucketName), lit("star"))
}

// Starred lists the caller's starred items that still exist, are not trashed
// and are still readable.
// GET /v1/documents/{bucketName}/starred
func (r *LibraryResource) Starred(ctx context.Context, bucketName string) ([]Document, error) {
	return doJSON[[]Document](ctx, r.http, http.MethodGet, nil, nil, param("bucketName", bucketName), lit("starred"))
}

// Recent lists items the caller recently uploaded, edited or viewed, newest
// first.
// GET /v1/documents/{bucketName}/recent
func (r *LibraryResource) Recent(ctx context.Context, bucketName string, params *RecentParams) ([]Document, error) {
	q := query{}
	if params != nil {
		q.int("limit", params.Limit)
	}
	return doJSON[[]Document](ctx, r.http, http.MethodGet, q, nil, param("bucketName", bucketName), lit("recent"))
}

// Trash lists trashed items the caller may manage. Paths show the original
// location; Metadata carries trashedAt and trashedBy.
// GET /v1/documents/{bucketName}/trash
func (r *LibraryResource) Trash(ctx context.Context, bucketName string) ([]Document, error) {
	return doJSON[[]Document](ctx, r.http, http.MethodGet, nil, nil, param("bucketName", bucketName), lit("trash"))
}

// Restore puts a trashed file or folder back at its original location.
// POST /v1/documents/{bucketName}/trash/{nodeId}/restore
func (r *LibraryResource) Restore(ctx context.Context, bucketName, nodeID string) (Document, error) {
	return doJSON[Document](ctx, r.http, http.MethodPost, nil, nil,
		param("bucketName", bucketName), lit("trash"), param("nodeId", nodeID), lit("restore"))
}

// Purge permanently deletes a trashed item and returns the service's
// confirmation message.
// DELETE /v1/documents/{bucketName}/trash/{nodeId}
func (r *LibraryResource) Purge(ctx context.Context, bucketName, nodeID string) (string, error) {
	return doJSON[string](ctx, r.http, http.MethodDelete, nil, nil,
		param("bucketName", bucketName), lit("trash"), param("nodeId", nodeID))
}
