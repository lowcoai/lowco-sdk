package docs

import (
	"context"
	"net/http"
)

// WebhooksResource manages webhooks, which call a URL when an object event
// happens under a prefix.
type WebhooksResource struct {
	http *httpClient
}

// WebhookListParams pages Webhooks.List.
type WebhookListParams struct {
	// Page is the page number; 0 leaves the service default.
	Page int
	// Limit is the page size; 0 leaves the service default.
	Limit int
}

// List returns the org's webhooks visible to the caller (rules on another
// member's personal space are hidden).
// GET /v1/documents/webhooks
func (r *WebhooksResource) List(ctx context.Context, params *WebhookListParams) ([]Webhook, error) {
	q := query{}
	if params != nil {
		q.int("page", params.Page)
		q.int("limit", params.Limit)
	}
	return doJSON[[]Webhook](ctx, r.http, http.MethodGet, q, nil, lit("webhooks"))
}

// Create creates a webhook. URL, Method, Prefix and at least one event type
// are required; a prefix in a personal space (.users/{id}/) may only be the
// caller's own.
// POST /v1/documents/webhooks
func (r *WebhooksResource) Create(ctx context.Context, body WebhookRequest) (Webhook, error) {
	return doJSON[Webhook](ctx, r.http, http.MethodPost, nil, body, lit("webhooks"))
}

// Get returns one webhook.
// GET /v1/documents/webhooks/{id}
func (r *WebhooksResource) Get(ctx context.Context, id string) (Webhook, error) {
	return doJSON[Webhook](ctx, r.http, http.MethodGet, nil, nil, lit("webhooks"), param("id", id))
}

// Update replaces every field of a webhook (at least one event type is
// required); it keeps its author.
// PUT /v1/documents/webhooks/{id}
func (r *WebhooksResource) Update(ctx context.Context, id string, body WebhookRequest) (Webhook, error) {
	return doJSON[Webhook](ctx, r.http, http.MethodPut, nil, body, lit("webhooks"), param("id", id))
}

// Delete deletes a webhook.
// DELETE /v1/documents/webhooks/{id}
func (r *WebhooksResource) Delete(ctx context.Context, id string) error {
	_, err := doJSON[any](ctx, r.http, http.MethodDelete, nil, nil, lit("webhooks"), param("id", id))
	return err
}
