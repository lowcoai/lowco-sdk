package docs

import (
	"context"
	"net/http"
)

// FilesResource reads, saves, uploads, renames, deletes and links files.
type FilesResource struct {
	http *httpClient
}

// FileReadParams tunes Files.Read.
type FileReadParams struct {
	// Meta skips the body and returns metadata only (sent as meta=1).
	Meta bool
}

// FileUploadOptions places a file upload.
type FileUploadOptions struct {
	// ParentID is the destination folder path (sent as form field
	// "ParentID"; empty = library root).
	ParentID string
	// OnConflict is what to do when the name is taken (service default:
	// OnConflictReplace).
	OnConflict OnConflict
}

// Get returns the file's metadata, URLs and body (as text) and records a
// view. For conditional saves use Read, which also returns the etag and the
// caller's role.
// GET /v1/documents/{bucketName}/file/{path}
func (r *FilesResource) Get(ctx context.Context, bucketName, path string) (Document, error) {
	return doJSON[Document](ctx, r.http, http.MethodGet, nil, nil,
		param("bucketName", bucketName), lit("file"), wildcard("path", path))
}

// Read returns the body of the file at path with the etag of exactly that
// version (send it back as UpdateFileRequest.IfMatch), the caller's role,
// the space owner and the real node id.
// GET /v1/documents/{bucketName}/file?path=&meta=
func (r *FilesResource) Read(ctx context.Context, bucketName, path string, params *FileReadParams) (FileContent, error) {
	if err := requireValue("path", path); err != nil {
		return FileContent{}, err
	}
	q := query{}
	q.str("path", path)
	if params != nil {
		q.flag("meta", params.Meta)
	}
	return doJSON[FileContent](ctx, r.http, http.MethodGet, q, nil, param("bucketName", bucketName), lit("file"))
}

// CreateBlank creates a zero-byte file at ParentName/FileName and returns it
// with its node id.
// POST /v1/documents/{bucketName}/file
func (r *FilesResource) CreateBlank(ctx context.Context, bucketName string, body CreateBlankFileRequest) (Document, error) {
	return doJSON[Document](ctx, r.http, http.MethodPost, nil, body, param("bucketName", bucketName), lit("file"))
}

// Update writes the whole body of ParentName/FileName, creating it when
// missing. IfMatch/IfNoneMatch make the save conditional: a stale etag fails
// with a 412 *Error whose PreconditionState holds the file's current state.
// PUT /v1/documents/{bucketName}/file
func (r *FilesResource) Update(ctx context.Context, bucketName string, body UpdateFileRequest) (Document, error) {
	return doJSON[Document](ctx, r.http, http.MethodPut, nil, body, param("bucketName", bucketName), lit("file"))
}

// UpdateAt is Update with a path in the URL. The service takes the target
// from the body's ParentName/FileName and ignores the URL path.
// PUT /v1/documents/{bucketName}/file/{path}
func (r *FilesResource) UpdateAt(ctx context.Context, bucketName, path string, body UpdateFileRequest) (Document, error) {
	return doJSON[Document](ctx, r.http, http.MethodPut, nil, body,
		param("bucketName", bucketName), lit("file"), wildcard("path", path))
}

// Rename renames ParentName/OldName to ParentName/NewName (NewName may hold a
// path to move the file). The node keeps its id, so shares, stars and
// permalinks survive.
// PUT /v1/documents/{bucketName}/file/rename
func (r *FilesResource) Rename(ctx context.Context, bucketName string, body RenameRequest) (Document, error) {
	return doJSON[Document](ctx, r.http, http.MethodPut, nil, body,
		param("bucketName", bucketName), lit("file"), lit("rename"))
}

// Delete deletes the file at path and returns the service's confirmation
// message. Library and personal files move to the trash; .apps/ and system
// files are deleted permanently.
// DELETE /v1/documents/{bucketName}/file/{path}
func (r *FilesResource) Delete(ctx context.Context, bucketName, path string) (string, error) {
	return doJSON[string](ctx, r.http, http.MethodDelete, nil, nil,
		param("bucketName", bucketName), lit("file"), wildcard("path", path))
}

// DeleteByPath is Delete with the key in the query string.
// DELETE /v1/documents/{bucketName}/file?path=
func (r *FilesResource) DeleteByPath(ctx context.Context, bucketName, path string) (string, error) {
	if err := requireValue("path", path); err != nil {
		return "", err
	}
	q := query{}
	q.str("path", path)
	return doJSON[string](ctx, r.http, http.MethodDelete, q, nil, param("bucketName", bucketName), lit("file"))
}

// Upload uploads one file (multipart field "file") into the folder named by
// opts.ParentID.
// POST /v1/documents/{bucketName}/upload-file
func (r *FilesResource) Upload(ctx context.Context, bucketName string, file UploadFile, opts *FileUploadOptions) (Document, error) {
	if opts == nil {
		opts = &FileUploadOptions{}
	}
	form := newMultipartForm()
	form.file("file", file)
	form.field("ParentID", opts.ParentID)
	form.field("onConflict", string(opts.OnConflict))
	return doMultipart[Document](ctx, r.http, form, param("bucketName", bucketName), lit("upload-file"))
}

// DownloadURL returns the short-lived URL that downloads the file under its
// real name. The redirect is not followed; the Location URL is returned.
// GET /v1/documents/{bucketName}/download/{path}
func (r *FilesResource) DownloadURL(ctx context.Context, bucketName, path string) (string, error) {
	return r.http.doRedirect(ctx, nil, param("bucketName", bucketName), lit("download"), wildcard("path", path))
}

// PreviewURL returns the URL of the file's PDF rendition (PDFs point at
// themselves; office documents are converted once and cached). The redirect
// is not followed; the Location URL is returned.
// GET /v1/documents/{bucketName}/preview/{path}
func (r *FilesResource) PreviewURL(ctx context.Context, bucketName, path string) (string, error) {
	return r.http.doRedirect(ctx, nil, param("bucketName", bucketName), lit("preview"), wildcard("path", path))
}

// ListArchive lists the entries of a stored .zip (up to 100 MiB) without
// extracting it.
// GET /v1/documents/{bucketName}/archive/{path}
func (r *FilesResource) ListArchive(ctx context.Context, bucketName, path string) (ArchiveListing, error) {
	return doJSON[ArchiveListing](ctx, r.http, http.MethodGet, nil, nil,
		param("bucketName", bucketName), lit("archive"), wildcard("path", path))
}
