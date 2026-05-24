package workflow

import "context"

type WorkflowsResource struct {
	http *httpClient
}

type WorkflowPublishRequest struct {
	Category        string `json:"category"`
	LongDescription string `json:"longDescription"`
}

type SearchPublishedTemplatesParams struct {
	Q        string `json:"q,omitempty"`
	Category string `json:"category,omitempty"`
	Limit    *int   `json:"limit,omitempty"`
}

func (r *WorkflowsResource) List(ctx context.Context, query *PaginationQuery) ([]Workflow, error) {
	var result []Workflow
	err := r.http.Request(ctx, "GET", "/v1/wf/workflows", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *WorkflowsResource) Count(ctx context.Context, query *PaginationQuery) (any, error) {
	var result any
	err := r.http.Request(ctx, "GET", "/v1/wf/workflows/count", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *WorkflowsResource) GetByID(ctx context.Context, id string) (Workflow, error) {
	var result Workflow
	err := r.http.Request(ctx, "GET", "/v1/wf/workflows/"+id, nil, nil, &result)
	return result, err
}

func (r *WorkflowsResource) Create(ctx context.Context, payload WorkflowUpdateRequest) (Workflow, error) {
	var result Workflow
	err := r.http.Request(ctx, "POST", "/v1/wf/workflows", payload, nil, &result)
	return result, err
}

func (r *WorkflowsResource) Update(ctx context.Context, id string, payload WorkflowUpdateRequest) (Workflow, error) {
	var result Workflow
	err := r.http.Request(ctx, "PUT", "/v1/wf/workflows/"+id, payload, nil, &result)
	return result, err
}

func (r *WorkflowsResource) Delete(ctx context.Context, id string) error {
	return r.http.Request(ctx, "DELETE", "/v1/wf/workflows/"+id, nil, nil, nil)
}

func (r *WorkflowsResource) Run(ctx context.Context, payload RunWorkflowRequest) (map[string]any, error) {
	result := make(map[string]any)
	err := r.http.Request(ctx, "POST", "/v1/wf/workflows/run", payload, nil, &result)
	return result, err
}

func (r *WorkflowsResource) Versions(ctx context.Context, id string, query *PaginationQuery) ([]Workflow, error) {
	var result []Workflow
	err := r.http.Request(ctx, "GET", "/v1/wf/workflows/"+id+"/versions", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *WorkflowsResource) Publish(ctx context.Context, id string, payload WorkflowPublishRequest) (WorkflowPublish, error) {
	var result WorkflowPublish
	err := r.http.Request(ctx, "POST", "/v1/wf/workflows/"+id+"/publish", payload, nil, &result)
	return result, err
}

func (r *WorkflowsResource) Published(ctx context.Context, query *PaginationQuery) ([]WorkflowPublish, error) {
	var result []WorkflowPublish
	err := r.http.Request(ctx, "GET", "/v1/wf/workflows/published", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *WorkflowsResource) PublishedCount(ctx context.Context, query *PaginationQuery) (any, error) {
	var result any
	err := r.http.Request(ctx, "GET", "/v1/wf/workflows/published/count", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *WorkflowsResource) GetPublishedByID(ctx context.Context, id string) (WorkflowPublish, error) {
	var result WorkflowPublish
	err := r.http.Request(ctx, "GET", "/v1/wf/workflows/published/"+id, nil, nil, &result)
	return result, err
}

func (r *WorkflowsResource) UpdatePublished(ctx context.Context, id string, payload WorkflowPublishRequest) (WorkflowPublish, error) {
	var result WorkflowPublish
	err := r.http.Request(ctx, "PUT", "/v1/wf/workflows/published/"+id, payload, nil, &result)
	return result, err
}

func (r *WorkflowsResource) DeletePublished(ctx context.Context, id string) error {
	return r.http.Request(ctx, "DELETE", "/v1/wf/workflows/published/"+id, nil, nil, nil)
}

func (r *WorkflowsResource) WebPublished(ctx context.Context, query *PaginationQuery) ([]WorkflowPublish, error) {
	var result []WorkflowPublish
	err := r.http.Request(ctx, "GET", "/v1/wf/workflows/published/web", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *WorkflowsResource) WebPublishedByID(ctx context.Context, id string) (WorkflowPublish, error) {
	var result WorkflowPublish
	err := r.http.Request(ctx, "GET", "/v1/wf/workflows/published/web/"+id, nil, nil, &result)
	return result, err
}

func (r *WorkflowsResource) SearchPublishedTemplates(ctx context.Context, params SearchPublishedTemplatesParams) ([]WorkflowPublish, error) {
	var result []WorkflowPublish
	err := r.http.Request(
		ctx,
		"GET",
		"/v1/wf/workflows/published/web/search",
		nil,
		&RequestOptions{Query: mapFromStruct(params)},
		&result,
	)
	return result, err
}
