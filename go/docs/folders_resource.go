package docs

import (
	"context"
	"net/http"
)

// FoldersResource lists, creates, uploads, zips, renames and deletes folders.
type FoldersResource struct {
	http *httpClient
}

// FolderListParams filters a folder listing.
type FolderListParams struct {
	// Prefix is the folder to list ("" = the root of the listed area).
	Prefix string
	// Sizes set to false skips recursive folder sizes (folders then report
	// size 0); nil leaves the service default (sizes computed).
	Sizes *bool
}

// ListAtParams tunes Folders.ListAt.
type ListAtParams struct {
	// Sizes set to false skips recursive folder sizes; nil leaves the
	// service default.
	Sizes *bool
}

// FolderUploadOptions places a folder upload.
type FolderUploadOptions struct {
	// RelativePaths holds the relative path of each file, in the same order
	// as the files (e.g. "photos/2026/a.jpg"). A missing or empty entry is
	// filled with that file's FileName, so nested names survive the
	// service's base-name handling of part file names.
	RelativePaths []string
	// ParentID is the destination folder (sent as form field "parentID";
	// empty or the bucket name = root).
	ParentID string
	// Prefix is the destination folder used when ParentID is empty.
	Prefix string
}

func folderListQuery(params *FolderListParams) query {
	q := query{}
	if params != nil {
		q.str("prefix", params.Prefix)
		q.optBool("sizes", params.Sizes)
	}
	return q
}

// List lists the direct children of a library folder. Rows carry the stable
// node id, URLs and, in Metadata, the caller's role, the file etag and a
// sharing badge.
// GET /v1/documents/{bucketName}/objects
func (r *FoldersResource) List(ctx context.Context, bucketName string, params *FolderListParams) ([]Document, error) {
	return doJSON[[]Document](ctx, r.http, http.MethodGet, folderListQuery(params), nil,
		param("bucketName", bucketName), lit("objects"))
}

// ListAt is List with the folder path in the URL; path may contain "/".
// GET /v1/documents/{bucketName}/objects/{path}
func (r *FoldersResource) ListAt(ctx context.Context, bucketName, path string, params *ListAtParams) ([]Document, error) {
	q := query{}
	if params != nil {
		q.optBool("sizes", params.Sizes)
	}
	return doJSON[[]Document](ctx, r.http, http.MethodGet, q, nil,
		param("bucketName", bucketName), lit("objects"), wildcard("path", path))
}

// ListPublic lists an org-library folder, addressed by Prefix only.
// GET /v1/documents/{bucketName}/public/objects
func (r *FoldersResource) ListPublic(ctx context.Context, bucketName string, params *FolderListParams) ([]Document, error) {
	return doJSON[[]Document](ctx, r.http, http.MethodGet, folderListQuery(params), nil,
		param("bucketName", bucketName), lit("public"), lit("objects"))
}

// ListUser lists the personal drive .users/{userID}/{Prefix}. Only the
// owner, or a member the owner shared with, may list it.
// GET /v1/documents/{bucketName}/users/{userId}/objects
func (r *FoldersResource) ListUser(ctx context.Context, bucketName, userID string, params *FolderListParams) ([]Document, error) {
	return doJSON[[]Document](ctx, r.http, http.MethodGet, folderListQuery(params), nil,
		param("bucketName", bucketName), lit("users"), param("userId", userID), lit("objects"))
}

// ListApp lists an app's data folder .apps/{appID}/{Prefix}.
// GET /v1/documents/{bucketName}/apps/{appId}/objects
func (r *FoldersResource) ListApp(ctx context.Context, bucketName, appID string, params *FolderListParams) ([]Document, error) {
	return doJSON[[]Document](ctx, r.http, http.MethodGet, folderListQuery(params), nil,
		param("bucketName", bucketName), lit("apps"), param("appId", appID), lit("objects"))
}

// Get returns the raw listing of the folder named by one path segment: names
// are full keys and no role, sharing or size enrichment is applied.
// GET /v1/documents/{bucketName}/folder/{key}
func (r *FoldersResource) Get(ctx context.Context, bucketName, key string) ([]Document, error) {
	return doJSON[[]Document](ctx, r.http, http.MethodGet, nil, nil,
		param("bucketName", bucketName), lit("folder"), param("key", key))
}

// Create creates FolderName inside ParentName. A nested name ("a/b/c")
// creates each level; the result lists every level created, outermost first.
// POST /v1/documents/{bucketName}/folder
func (r *FoldersResource) Create(ctx context.Context, bucketName string, body CreateFolderRequest) ([]Document, error) {
	return doJSON[[]Document](ctx, r.http, http.MethodPost, nil, body, param("bucketName", bucketName), lit("folder"))
}

// Delete deletes a top-level folder named by one path segment and returns the
// service's confirmation message; use DeleteByPath for nested folders.
// Library and personal folders move to the trash; .apps/ folders are deleted
// permanently.
// DELETE /v1/documents/{bucketName}/folder/{key}
func (r *FoldersResource) Delete(ctx context.Context, bucketName, key string) (string, error) {
	return doJSON[string](ctx, r.http, http.MethodDelete, nil, nil,
		param("bucketName", bucketName), lit("folder"), param("key", key))
}

// DeleteByPath deletes the folder at path, at any depth, and returns the
// service's confirmation message.
// DELETE /v1/documents/{bucketName}/folder?path=
func (r *FoldersResource) DeleteByPath(ctx context.Context, bucketName, path string) (string, error) {
	if err := requireValue("path", path); err != nil {
		return "", err
	}
	q := query{}
	q.str("path", path)
	return doJSON[string](ctx, r.http, http.MethodDelete, q, nil, param("bucketName", bucketName), lit("folder"))
}

// Upload uploads files under a destination folder as one multipart request
// (repeated "files" parts and "relativePaths" values). Every key is checked
// before anything is written; files that fail to upload are missing from
// the result.
// POST /v1/documents/{bucketName}/upload-folder
func (r *FoldersResource) Upload(ctx context.Context, bucketName string, files []UploadFile, opts *FolderUploadOptions) (UploadFolderResult, error) {
	if len(files) == 0 {
		return UploadFolderResult{}, argumentError("files")
	}
	if opts == nil {
		opts = &FolderUploadOptions{}
	}
	form := newMultipartForm()
	for _, f := range files {
		form.file("files", f)
	}
	for i, f := range files {
		relativePath := f.FileName
		if i < len(opts.RelativePaths) && opts.RelativePaths[i] != "" {
			relativePath = opts.RelativePaths[i]
		}
		form.field("relativePaths", relativePath)
	}
	form.field("parentID", opts.ParentID)
	form.field("prefix", opts.Prefix)
	return doMultipart[UploadFolderResult](ctx, r.http, form, param("bucketName", bucketName), lit("upload-folder"))
}

// DownloadZip streams every object under the folder at path as a zip
// archive; FileName is "<folder>.zip".
// GET /v1/documents/{bucketName}/folder-zip/{path}
func (r *FoldersResource) DownloadZip(ctx context.Context, bucketName, path string) (Binary, error) {
	return r.http.doBinary(ctx, param("bucketName", bucketName), lit("folder-zip"), wildcard("path", path))
}

// Duplicate copies a file or folder next to itself as "<name> copy",
// "<name> copy 2", ...
// POST /v1/documents/{bucketName}/duplicate
func (r *FoldersResource) Duplicate(ctx context.Context, bucketName string, body DuplicateRequest) (Document, error) {
	return doJSON[Document](ctx, r.http, http.MethodPost, nil, body, param("bucketName", bucketName), lit("duplicate"))
}

// Rename renames ParentName/OldName to ParentName/NewName (NewName may hold a
// path to move the folder). Node ids survive.
// PUT /v1/documents/{bucketName}/folder/rename
func (r *FoldersResource) Rename(ctx context.Context, bucketName string, body RenameRequest) (Document, error) {
	return doJSON[Document](ctx, r.http, http.MethodPut, nil, body,
		param("bucketName", bucketName), lit("folder"), lit("rename"))
}
