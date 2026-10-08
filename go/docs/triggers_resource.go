package docs

import (
	"context"
	"net/http"
)

// TriggersResource manages triggers, which run a workflow when an object
// event happens under a prefix.
type TriggersResource struct {
	http *httpClient
}

// List returns the org's triggers visible to the caller (rules on another
// member's personal space are hidden).
// GET /v1/documents/triggers
func (r *TriggersResource) List(ctx context.Context) ([]Trigger, error) {
	return doJSON[[]Trigger](ctx, r.http, http.MethodGet, nil, nil, lit("triggers"))
}

// Create creates a trigger. Prefix and WorkflowID are required; a prefix in a
// personal space (.users/{id}/) may only be the caller's own.
// POST /v1/documents/triggers
func (r *TriggersResource) Create(ctx context.Context, body TriggerRequest) (Trigger, error) {
	return doJSON[Trigger](ctx, r.http, http.MethodPost, nil, body, lit("triggers"))
}

// Get returns one trigger.
// GET /v1/documents/triggers/{id}
func (r *TriggersResource) Get(ctx context.Context, id string) (Trigger, error) {
	return doJSON[Trigger](ctx, r.http, http.MethodGet, nil, nil, lit("triggers"), param("id", id))
}

// Update replaces every field of a trigger; it keeps its author.
// PUT /v1/documents/triggers/{id}
func (r *TriggersResource) Update(ctx context.Context, id string, body TriggerRequest) (Trigger, error) {
	return doJSON[Trigger](ctx, r.http, http.MethodPut, nil, body, lit("triggers"), param("id", id))
}

// Delete deletes a trigger.
// DELETE /v1/documents/triggers/{id}
func (r *TriggersResource) Delete(ctx context.Context, id string) error {
	_, err := doJSON[any](ctx, r.http, http.MethodDelete, nil, nil, lit("triggers"), param("id", id))
	return err
}
