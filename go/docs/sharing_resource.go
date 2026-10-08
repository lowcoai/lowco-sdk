package docs

import (
	"context"
	"net/http"
)

// SharingResource manages grants and share links on My Drive items, and
// lists items shared with the caller.
type SharingResource struct {
	http *httpClient
}

// ShareListParams tunes Sharing.List and Sharing.ListLinks.
type ShareListParams struct {
	// Type is the item type (service default: NodeTypeFile).
	Type NodeType
}

// SharedWithMeParams filters Sharing.SharedWithMe.
type SharedWithMeParams struct {
	// AppKey returns only that app's items (e.g. "notes"). Without it, app
	// data (.users/*/.apps/...) is left out.
	AppKey string
}

func shareListQuery(path string, params *ShareListParams) (query, error) {
	if err := requireValue("path", path); err != nil {
		return nil, err
	}
	q := query{}
	q.str("path", path)
	if params != nil {
		q.str("type", string(params.Type))
	}
	return q, nil
}

// Create grants one org member (SubjectType user) or the whole org
// (SubjectType org) viewer or editor access to a My Drive item the caller
// owns. A folder grant covers everything under it.
// POST /v1/documents/{bucketName}/shares
func (r *SharingResource) Create(ctx context.Context, bucketName string, body CreateShareRequest) (Share, error) {
	return doJSON[Share](ctx, r.http, http.MethodPost, nil, body, param("bucketName", bucketName), lit("shares"))
}

// List returns who has access to the My Drive item at path (owner only).
// GET /v1/documents/{bucketName}/shares?path=&type=
func (r *SharingResource) List(ctx context.Context, bucketName, path string, params *ShareListParams) ([]Share, error) {
	q, err := shareListQuery(path, params)
	if err != nil {
		return nil, err
	}
	return doJSON[[]Share](ctx, r.http, http.MethodGet, q, nil, param("bucketName", bucketName), lit("shares"))
}

// Delete revokes a grant (owner only) and returns the service's confirmation
// message.
// DELETE /v1/documents/{bucketName}/shares/{id}
func (r *SharingResource) Delete(ctx context.Context, bucketName, id string) (string, error) {
	return doJSON[string](ctx, r.http, http.MethodDelete, nil, nil,
		param("bucketName", bucketName), lit("shares"), param("id", id))
}

// SharedWithMe lists items other members shared with the caller, directly
// or org-wide. Metadata carries role, sharedRole, via, ownerId, sharedBy and
// expiresAt.
// GET /v1/documents/{bucketName}/shared-with-me
func (r *SharingResource) SharedWithMe(ctx context.Context, bucketName string, params *SharedWithMeParams) ([]Document, error) {
	q := query{}
	if params != nil {
		q.str("appKey", params.AppKey)
	}
	return doJSON[[]Document](ctx, r.http, http.MethodGet, q, nil, param("bucketName", bucketName), lit("shared-with-me"))
}

// CreateLink mints an org-scope viewer link for a My Drive file the caller
// owns: any signed-in member of the org can follow it.
// POST /v1/documents/{bucketName}/share-links
func (r *SharingResource) CreateLink(ctx context.Context, bucketName string, body CreateShareLinkRequest) (ShareLinkCreated, error) {
	return doJSON[ShareLinkCreated](ctx, r.http, http.MethodPost, nil, body, param("bucketName", bucketName), lit("share-links"))
}

// ListLinks lists the share links of the file at path (owner only).
// GET /v1/documents/{bucketName}/share-links?path=&type=
func (r *SharingResource) ListLinks(ctx context.Context, bucketName, path string, params *ShareListParams) ([]ShareLink, error) {
	q, err := shareListQuery(path, params)
	if err != nil {
		return nil, err
	}
	return doJSON[[]ShareLink](ctx, r.http, http.MethodGet, q, nil, param("bucketName", bucketName), lit("share-links"))
}

// DeleteLink revokes a share link and returns the service's confirmation
// message.
// DELETE /v1/documents/{bucketName}/share-links/{id}
func (r *SharingResource) DeleteLink(ctx context.Context, bucketName, id string) (string, error) {
	return doJSON[string](ctx, r.http, http.MethodDelete, nil, nil,
		param("bucketName", bucketName), lit("share-links"), param("id", id))
}

// ResolveLink follows a share link token without following its redirect and
// returns the fresh short-lived file URL.
// GET /v1/documents/link/{token}
func (r *SharingResource) ResolveLink(ctx context.Context, token string) (string, error) {
	return r.http.doRedirect(ctx, nil, lit("link"), param("token", token))
}
