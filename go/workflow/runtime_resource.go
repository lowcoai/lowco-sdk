package workflow

import "context"

type ListExecutionsQuery struct {
	PaginationQuery
	Full *bool `json:"full,omitempty"`
}

type ExecutionsResource struct {
	http *httpClient
}

func (r *ExecutionsResource) List(ctx context.Context, query *ListExecutionsQuery) ([]Execution, error) {
	var result []Execution
	err := r.http.Request(ctx, "GET", "/v1/wf/executions", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *ExecutionsResource) Count(ctx context.Context, query *PaginationQuery) (any, error) {
	var result any
	err := r.http.Request(ctx, "GET", "/v1/wf/executions/count", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *ExecutionsResource) GetByID(ctx context.Context, id string) (Execution, error) {
	var result Execution
	err := r.http.Request(ctx, "GET", "/v1/wf/executions/"+id, nil, nil, &result)
	return result, err
}

func (r *ExecutionsResource) Logs(ctx context.Context, id string) ([]any, error) {
	var result []any
	err := r.http.Request(ctx, "GET", "/v1/wf/executions/"+id+"/logs", nil, nil, &result)
	return result, err
}

type ActivitiesResource struct {
	http *httpClient
}

func (r *ActivitiesResource) List(ctx context.Context, query *PaginationQuery) ([]ActivityHistoryResponse, error) {
	var result []ActivityHistoryResponse
	err := r.http.Request(ctx, "GET", "/v1/wf/activities", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *ActivitiesResource) Count(ctx context.Context, query *PaginationQuery) (any, error) {
	var result any
	err := r.http.Request(ctx, "GET", "/v1/wf/activities/count", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *ActivitiesResource) GetByID(ctx context.Context, id string) (ActivityHistoryResponse, error) {
	var result ActivityHistoryResponse
	err := r.http.Request(ctx, "GET", "/v1/wf/activities/"+id, nil, nil, &result)
	return result, err
}

func (r *ActivitiesResource) Logs(ctx context.Context, id string) ([]any, error) {
	var result []any
	err := r.http.Request(ctx, "GET", "/v1/wf/activities/"+id+"/logs", nil, nil, &result)
	return result, err
}

type AnalyticsResource struct {
	http *httpClient
}

func (r *AnalyticsResource) Default(ctx context.Context) (map[string]any, error) {
	result := make(map[string]any)
	err := r.http.Request(ctx, "GET", "/v1/wf/analytics", nil, nil, &result)
	return result, err
}

func (r *AnalyticsResource) GetByID(ctx context.Context, id string) (map[string]any, error) {
	result := make(map[string]any)
	err := r.http.Request(ctx, "GET", "/v1/wf/analytics/"+id, nil, nil, &result)
	return result, err
}

type DryRunResource struct {
	http *httpClient
}

func (r *DryRunResource) Execute(ctx context.Context, payload DryRunRequest) (any, error) {
	var result any
	err := r.http.Request(ctx, "POST", "/v1/wf/dryrun", payload, nil, &result)
	return result, err
}

type WebhookTriggerQuery struct {
	Env         string `json:"env,omitempty"`
	TriggeredBy string `json:"triggeredBy,omitempty"`
	Async       *bool  `json:"async,omitempty"`
}

type WebhooksResource struct {
	http *httpClient
}

// Trigger runs the workflow with payload as its input
// (POST /v1/wf/webhook/{id}).
func (r *WebhooksResource) Trigger(ctx context.Context, workflowID string, payload map[string]any, query *WebhookTriggerQuery) (map[string]any, error) {
	if payload == nil {
		payload = map[string]any{}
	}
	result := make(map[string]any)
	err := r.http.Request(ctx, "POST", "/v1/wf/webhook/"+workflowID, payload, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

// unsupportedWebhookError is returned by the deprecated webhook methods. The
// workflow API serves only POST /v1/wf/webhook/{id}, which triggers the
// workflow. Listing, registering, updating and deleting webhooks are not
// routed; registration is handled by the integrations service when a workflow
// is saved with an application trigger. The deprecated methods fail locally so
// they never reach the trigger route.
func unsupportedWebhookError(operation, detail string) *Error {
	return &Error{
		Status: 0,
		Message: "Webhooks." + operation + " is not supported and no request was sent: " + detail +
			" Webhook registration is handled by the integrations service." +
			" Use Webhooks.Trigger to run a workflow.",
		Payload: map[string]any{"code": "unsupported_operation", "operation": "Webhooks." + operation},
	}
}

// ListByWorkflow always returns a *Error without sending a request.
//
// Deprecated: the workflow API does not serve GET /v1/wf/webhook/{id}, and
// webhook registration is handled by the integrations service. Will be removed
// in a future major version.
func (r *WebhooksResource) ListByWorkflow(ctx context.Context, workflowID string) ([]map[string]any, error) {
	return nil, unsupportedWebhookError("ListByWorkflow", "the workflow API does not serve GET /v1/wf/webhook/{id}.")
}

// Create always returns a *Error without sending a request.
//
// Deprecated: POST /v1/wf/webhook/{id} triggers the workflow, so this call used
// to run the workflow with the webhook config as its input. Webhook
// registration is handled by the integrations service; use Trigger to run a
// workflow. Will be removed in a future major version.
func (r *WebhooksResource) Create(ctx context.Context, workflowID string, payload WebhookCreateRequest) (map[string]any, error) {
	return nil, unsupportedWebhookError("Create", "POST /v1/wf/webhook/{id} triggers the workflow, so the webhook config would have run as workflow input.")
}

// Update always returns a *Error without sending a request.
//
// Deprecated: the workflow API does not serve PUT /v1/wf/webhook/{id}, and
// webhook registration is handled by the integrations service. Will be removed
// in a future major version.
func (r *WebhooksResource) Update(ctx context.Context, webhookID string, payload WebhookCreateRequest) (map[string]any, error) {
	return nil, unsupportedWebhookError("Update", "the workflow API does not serve PUT /v1/wf/webhook/{id}.")
}

// Delete always returns a *Error without sending a request.
//
// Deprecated: the workflow API does not serve DELETE /v1/wf/webhook/{id}, and
// webhook registration is handled by the integrations service. Will be removed
// in a future major version.
func (r *WebhooksResource) Delete(ctx context.Context, workflowID string) (map[string]any, error) {
	return nil, unsupportedWebhookError("Delete", "the workflow API does not serve DELETE /v1/wf/webhook/{id}.")
}
