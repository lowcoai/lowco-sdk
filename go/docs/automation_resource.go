package docs

import (
	"context"
	"net/http"
)

// AutomationResource manages folder automation rules (folder configs), which
// run a pipeline when files are created or updated under a folder, and their
// run history.
type AutomationResource struct {
	http *httpClient
}

// AutomationListParams filters Automation.List.
type AutomationListParams struct {
	// Prefix returns only the rules on this folder.
	Prefix string
}

// JobListParams filters Automation.Jobs.
type JobListParams struct {
	// ConfigID returns only the runs of this rule.
	ConfigID string
	// Limit is the maximum number of runs (1-200); 0 leaves the service
	// default (50).
	Limit int
}

// List returns the bucket's rules visible to the caller.
// GET /v1/documents/{bucketName}/folder-configs
func (r *AutomationResource) List(ctx context.Context, bucketName string, params *AutomationListParams) ([]FolderConfig, error) {
	q := query{}
	if params != nil {
		q.str("prefix", params.Prefix)
	}
	return doJSON[[]FolderConfig](ctx, r.http, http.MethodGet, q, nil, param("bucketName", bucketName), lit("folder-configs"))
}

// Create creates a rule that runs a pipeline when files are created (or
// updated, per EventTypes) under Prefix.
// POST /v1/documents/{bucketName}/folder-configs
func (r *AutomationResource) Create(ctx context.Context, bucketName string, body FolderConfigRequest) (FolderConfig, error) {
	return doJSON[FolderConfig](ctx, r.http, http.MethodPost, nil, body, param("bucketName", bucketName), lit("folder-configs"))
}

// Get returns one rule.
// GET /v1/documents/{bucketName}/folder-configs/{id}
func (r *AutomationResource) Get(ctx context.Context, bucketName, id string) (FolderConfig, error) {
	return doJSON[FolderConfig](ctx, r.http, http.MethodGet, nil, nil,
		param("bucketName", bucketName), lit("folder-configs"), param("id", id))
}

// Update replaces a rule.
// PUT /v1/documents/{bucketName}/folder-configs/{id}
func (r *AutomationResource) Update(ctx context.Context, bucketName, id string, body FolderConfigRequest) (FolderConfig, error) {
	return doJSON[FolderConfig](ctx, r.http, http.MethodPut, nil, body,
		param("bucketName", bucketName), lit("folder-configs"), param("id", id))
}

// Delete deletes a rule and returns the service's confirmation message.
// DELETE /v1/documents/{bucketName}/folder-configs/{id}
func (r *AutomationResource) Delete(ctx context.Context, bucketName, id string) (string, error) {
	return doJSON[string](ctx, r.http, http.MethodDelete, nil, nil,
		param("bucketName", bucketName), lit("folder-configs"), param("id", id))
}

// Jobs returns the run history of folder automation pipelines, newest first.
// GET /v1/documents/{bucketName}/processing-jobs
func (r *AutomationResource) Jobs(ctx context.Context, bucketName string, params *JobListParams) ([]ProcessingJob, error) {
	q := query{}
	if params != nil {
		q.str("configId", params.ConfigID)
		q.int("limit", params.Limit)
	}
	return doJSON[[]ProcessingJob](ctx, r.http, http.MethodGet, q, nil, param("bucketName", bucketName), lit("processing-jobs"))
}
