package integrations

import "context"

type ApplicationsResource struct {
	http *httpClient
}

// List returns applications visible to the caller's org plus any global
// applications. Use query.Tags ("a,b") to filter by tag membership.
func (r *ApplicationsResource) List(ctx context.Context, query *PaginationQuery) ([]ApplicationWithCount, error) {
	var result []ApplicationWithCount
	err := r.http.Request(ctx, "GET", "/v1/integrations/applications", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *ApplicationsResource) GetByID(ctx context.Context, id string) (Application, error) {
	var result Application
	err := r.http.Request(ctx, "GET", "/v1/integrations/applications/"+id, nil, nil, &result)
	return result, err
}

func (r *ApplicationsResource) Create(ctx context.Context, payload Application) (Application, error) {
	var result Application
	err := r.http.Request(ctx, "POST", "/v1/integrations/applications", payload, nil, &result)
	return result, err
}

func (r *ApplicationsResource) Update(ctx context.Context, id string, payload Application) (Application, error) {
	var result Application
	err := r.http.Request(ctx, "PUT", "/v1/integrations/applications/"+id, payload, nil, &result)
	return result, err
}

func (r *ApplicationsResource) Delete(ctx context.Context, id string) error {
	return r.http.Request(ctx, "DELETE", "/v1/integrations/applications/"+id, nil, nil, nil)
}

func (r *ApplicationsResource) PatchTags(ctx context.Context, id string, tags []string) (Application, error) {
	var result Application
	err := r.http.Request(ctx, "PATCH", "/v1/integrations/applications/"+id+"/tags", PatchTagsRequest{Tags: tags}, nil, &result)
	return result, err
}

// Run executes an application directly (DB query for database apps, message
// publish for queue apps). For action invocations use Actions.Run instead.
func (r *ApplicationsResource) Run(ctx context.Context, id string, payload RunApplicationRequest) (any, error) {
	var result any
	err := r.http.Request(ctx, "POST", "/v1/integrations/applications/"+id+"/run", payload, nil, &result)
	return result, err
}

// LoadActions bulk-replaces an application's actions from a Postman folder.
func (r *ApplicationsResource) LoadActions(ctx context.Context, id string, folder PostmanFolder) ([]ApplicationAction, error) {
	var result []ApplicationAction
	err := r.http.Request(ctx, "POST", "/v1/integrations/applications/"+id+"/load-actions", folder, nil, &result)
	return result, err
}

func (r *ApplicationsResource) Versions(ctx context.Context, id string, query *PaginationQuery) ([]ApplicationHistory, error) {
	var result []ApplicationHistory
	err := r.http.Request(ctx, "GET", "/v1/integrations/applications/"+id+"/versions", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *ApplicationsResource) RegenerateMcpKey(ctx context.Context, id string) (Application, error) {
	var result Application
	err := r.http.Request(ctx, "GET", "/v1/integrations/applications/"+id+"/regenerate-mcp-key", nil, nil, &result)
	return result, err
}

func (r *ApplicationsResource) GetMcpTools(ctx context.Context, id string) (McpToolsResponse, error) {
	var result McpToolsResponse
	err := r.http.Request(ctx, "GET", "/v1/integrations/applications/"+id+"/mcp/tools", nil, nil, &result)
	return result, err
}

func (r *ApplicationsResource) GetSubApplications(ctx context.Context) (SubApplicationConfig, error) {
	result := SubApplicationConfig{}
	err := r.http.Request(ctx, "GET", "/v1/integrations/applications/types", nil, nil, &result)
	return result, err
}

// GetApplicationsWithTriggers lists applications that have at least one trigger.
func (r *ApplicationsResource) GetApplicationsWithTriggers(ctx context.Context) ([]Application, error) {
	var result []Application
	err := r.http.Request(ctx, "GET", "/v1/integrations/applications/by-trigger", nil, nil, &result)
	return result, err
}
