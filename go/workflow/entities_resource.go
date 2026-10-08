package workflow

import "context"

type EnvironmentsResource struct {
	http *httpClient
}

func (r *EnvironmentsResource) List(ctx context.Context, query *PaginationQuery) ([]Environment, error) {
	var result []Environment
	err := r.http.Request(ctx, "GET", "/v1/wf/environments", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *EnvironmentsResource) GetByID(ctx context.Context, id string) (Environment, error) {
	var result Environment
	err := r.http.Request(ctx, "GET", "/v1/wf/environments/"+id, nil, nil, &result)
	return result, err
}

func (r *EnvironmentsResource) Create(ctx context.Context, payload Environment) (Environment, error) {
	var result Environment
	err := r.http.Request(ctx, "POST", "/v1/wf/environments", payload, nil, &result)
	return result, err
}

func (r *EnvironmentsResource) Update(ctx context.Context, id string, payload Environment) (Environment, error) {
	var result Environment
	err := r.http.Request(ctx, "PUT", "/v1/wf/environments/"+id, payload, nil, &result)
	return result, err
}

func (r *EnvironmentsResource) Delete(ctx context.Context, id string) error {
	return r.http.Request(ctx, "DELETE", "/v1/wf/environments/"+id, nil, nil, nil)
}

func (r *EnvironmentsResource) SetDefault(ctx context.Context, id string) (Environment, error) {
	var result Environment
	err := r.http.Request(ctx, "PATCH", "/v1/wf/environments/"+id+"/default", nil, nil, &result)
	return result, err
}

type FunctionsResource struct {
	http *httpClient
}

func (r *FunctionsResource) List(ctx context.Context, query *PaginationQuery) ([]FunctionEntity, error) {
	var result []FunctionEntity
	err := r.http.Request(ctx, "GET", "/v1/wf/functions", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *FunctionsResource) GetByID(ctx context.Context, id string) (FunctionEntity, error) {
	var result FunctionEntity
	err := r.http.Request(ctx, "GET", "/v1/wf/functions/"+id, nil, nil, &result)
	return result, err
}

func (r *FunctionsResource) Create(ctx context.Context, payload FunctionEntity) (FunctionEntity, error) {
	var result FunctionEntity
	err := r.http.Request(ctx, "POST", "/v1/wf/functions", payload, nil, &result)
	return result, err
}

func (r *FunctionsResource) Update(ctx context.Context, id string, payload FunctionVersionRequest) (FunctionEntity, error) {
	var result FunctionEntity
	err := r.http.Request(ctx, "PUT", "/v1/wf/functions/"+id, payload, nil, &result)
	return result, err
}

func (r *FunctionsResource) Delete(ctx context.Context, id string) error {
	return r.http.Request(ctx, "DELETE", "/v1/wf/functions/"+id, nil, nil, nil)
}

func (r *FunctionsResource) Versions(ctx context.Context, id string, query *PaginationQuery) ([]FunctionEntity, error) {
	var result []FunctionEntity
	err := r.http.Request(ctx, "GET", "/v1/wf/functions/"+id+"/versions", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *FunctionsResource) Execute(ctx context.Context, id string, params map[string]any) (map[string]any, error) {
	if params == nil {
		params = map[string]any{}
	}
	result := make(map[string]any)
	err := r.http.Request(ctx, "POST", "/v1/wf/functions/"+id+"/execute", params, nil, &result)
	return result, err
}

type HumanTasksResource struct {
	http *httpClient
}

func (r *HumanTasksResource) List(ctx context.Context, query *PaginationQuery) ([]HumanTask, error) {
	var result []HumanTask
	err := r.http.Request(ctx, "GET", "/v1/wf/human-tasks", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *HumanTasksResource) GetByID(ctx context.Context, id string) (HumanTask, error) {
	var result HumanTask
	err := r.http.Request(ctx, "GET", "/v1/wf/human-tasks/"+id, nil, nil, &result)
	return result, err
}

func (r *HumanTasksResource) Complete(ctx context.Context, id string, action string) (HumanTask, error) {
	var result HumanTask
	err := r.http.Request(ctx, "PATCH", "/v1/wf/human-tasks/"+id+"/complete", map[string]string{"action": action}, nil, &result)
	return result, err
}
