package docs

import (
	"context"
	"net/http"
)

// AppFilesResource is the upload contract for suite apps: it stores and
// manages files under .apps/{appKey}/ in the bucket of the configured org
// (never caller-supplied).
type AppFilesResource struct {
	http *httpClient
}

// AppFileUploadOptions places an app file upload.
type AppFileUploadOptions struct {
	// Path is the folder inside the app area, e.g. "2026/invoices".
	Path string
	// OnConflict is what to do when the name is taken (service default:
	// OnConflictReplace).
	OnConflict OnConflict
}

// AppFileListParams filters AppFiles.List.
type AppFileListParams struct {
	// Prefix is the folder inside the app area.
	Prefix string
}

// Upload stores file (multipart field "file") at
// .apps/{appKey}/{opts.Path}/{name} and returns a stable node id and
// permalink to store instead of a storage URL.
// POST /v1/documents/app-files/{appKey}
func (r *AppFilesResource) Upload(ctx context.Context, appKey string, file UploadFile, opts *AppFileUploadOptions) (AppFileUpload, error) {
	if opts == nil {
		opts = &AppFileUploadOptions{}
	}
	form := newMultipartForm()
	form.file("file", file)
	form.field("path", opts.Path)
	form.field("onConflict", string(opts.OnConflict))
	return doMultipart[AppFileUpload](ctx, r.http, form, lit("app-files"), param("appKey", appKey))
}

// List lists the direct children of .apps/{appKey}/{Prefix}.
// GET /v1/documents/app-files/{appKey}/objects
func (r *AppFilesResource) List(ctx context.Context, appKey string, params *AppFileListParams) ([]Document, error) {
	q := query{}
	if params != nil {
		q.str("prefix", params.Prefix)
	}
	return doJSON[[]Document](ctx, r.http, http.MethodGet, q, nil, lit("app-files"), param("appKey", appKey), lit("objects"))
}

// Delete permanently deletes .apps/{appKey}/{path} (app data does not go to
// the trash) and returns the service's confirmation message.
// DELETE /v1/documents/app-files/{appKey}/{path}
func (r *AppFilesResource) Delete(ctx context.Context, appKey, path string) (string, error) {
	return doJSON[string](ctx, r.http, http.MethodDelete, nil, nil,
		lit("app-files"), param("appKey", appKey), wildcard("path", path))
}

// Sweep moves the app's files under body.Prefix older than
// body.OlderThanDays to the cold archive tier. Files stay reachable by
// permalink and are restored on demand; nothing is deleted.
// POST /v1/documents/app-files/{appKey}/sweep
func (r *AppFilesResource) Sweep(ctx context.Context, appKey string, body SweepRequest) (AppFilesSweep, error) {
	return doJSON[AppFilesSweep](ctx, r.http, http.MethodPost, nil, body, lit("app-files"), param("appKey", appKey), lit("sweep"))
}
