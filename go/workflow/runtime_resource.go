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

func (r *WebhooksResource) Trigger(ctx context.Context, workflowID string, payload map[string]any, query *WebhookTriggerQuery) (map[string]any, error) {
	if payload == nil {
		payload = map[string]any{}
	}
	result := make(map[string]any)
	err := r.http.Request(ctx, "POST", "/v1/wf/webhook/"+workflowID, payload, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *WebhooksResource) ListByWorkflow(ctx context.Context, workflowID string) ([]map[string]any, error) {
	var result []map[string]any
	err := r.http.Request(ctx, "GET", "/v1/wf/webhook/"+workflowID, nil, nil, &result)
	return result, err
}

func (r *WebhooksResource) Create(ctx context.Context, workflowID string, payload WebhookCreateRequest) (map[string]any, error) {
	result := make(map[string]any)
	err := r.http.Request(ctx, "POST", "/v1/wf/webhook/"+workflowID, payload, nil, &result)
	return result, err
}

func (r *WebhooksResource) Update(ctx context.Context, webhookID string, payload WebhookCreateRequest) (map[string]any, error) {
	result := make(map[string]any)
	err := r.http.Request(ctx, "PUT", "/v1/wf/webhook/"+webhookID, payload, nil, &result)
	return result, err
}

func (r *WebhooksResource) Delete(ctx context.Context, workflowID string) (map[string]any, error) {
	result := make(map[string]any)
	err := r.http.Request(ctx, "DELETE", "/v1/wf/webhook/"+workflowID, nil, nil, &result)
	return result, err
}
