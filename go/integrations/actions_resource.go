package integrations

import "context"

type ActionsResource struct {
	http *httpClient
}

func (r *ActionsResource) List(ctx context.Context, query *PaginationQuery) ([]ApplicationAction, error) {
	var result []ApplicationAction
	err := r.http.Request(ctx, "GET", "/v1/integrations/actions", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *ActionsResource) GetByID(ctx context.Context, id string) (ApplicationAction, error) {
	var result ApplicationAction
	err := r.http.Request(ctx, "GET", "/v1/integrations/actions/"+id, nil, nil, &result)
	return result, err
}

// Create attaches a new action to an application.
func (r *ActionsResource) Create(ctx context.Context, applicationID string, payload ApplicationAction) (ApplicationAction, error) {
	var result ApplicationAction
	err := r.http.Request(ctx, "POST", "/v1/integrations/applications/"+applicationID+"/action", payload, nil, &result)
	return result, err
}

func (r *ActionsResource) Update(ctx context.Context, id string, payload ApplicationAction) (ApplicationAction, error) {
	var result ApplicationAction
	err := r.http.Request(ctx, "PUT", "/v1/integrations/actions/"+id, payload, nil, &result)
	return result, err
}

func (r *ActionsResource) Delete(ctx context.Context, id string) error {
	return r.http.Request(ctx, "DELETE", "/v1/integrations/actions/"+id, nil, nil, nil)
}

// ListByApplication returns the actions registered under one application.
func (r *ActionsResource) ListByApplication(ctx context.Context, applicationID string) ([]ApplicationAction, error) {
	var result []ApplicationAction
	err := r.http.Request(ctx, "GET", "/v1/integrations/applications/"+applicationID+"/actions", nil, nil, &result)
	return result, err
}

// Run executes an action. CredentialID is required for actions whose
// application uses a connection-based auth scheme.
func (r *ActionsResource) Run(ctx context.Context, id string, payload RunActionRequest) (any, error) {
	var result any
	err := r.http.Request(ctx, "POST", "/v1/integrations/actions/"+id+"/run", payload, nil, &result)
	return result, err
}

// ResolveCredentials batches action IDs and returns their owning applications
// with the connections available to run them.
func (r *ActionsResource) ResolveCredentials(ctx context.Context, actionIDs []string) ([]ApplicationWithConnection, error) {
	var result []ApplicationWithConnection
	err := r.http.Request(ctx, "POST", "/v1/integrations/actions/allCredential", actionIDs, nil, &result)
	return result, err
}
