package docs

import (
	"context"
	"net/http"
)

// BucketsResource reads the org's bucket. Every bucket route takes the
// bucket name, which is the Name of the Document Get returns.
type BucketsResource struct {
	http *httpClient
}

// Get returns the single bucket that belongs to the configured org, creating
// it on first use, as a folder Document whose Name is the bucket name and
// whose Size is the bucket's total size. Metadata["privateNotes"]
// ("true"/"false") says whether new notes default to the private area.
// GET /v1/documents
func (r *BucketsResource) Get(ctx context.Context) (Document, error) {
	return doJSON[Document](ctx, r.http, http.MethodGet, nil, nil)
}

// Stats returns the bucket's storage usage, split between visible content
// and hidden system content.
// GET /v1/documents/{bucketName}/stats
func (r *BucketsResource) Stats(ctx context.Context, bucketName string) (BucketStats, error) {
	return doJSON[BucketStats](ctx, r.http, http.MethodGet, nil, nil, param("bucketName", bucketName), lit("stats"))
}
