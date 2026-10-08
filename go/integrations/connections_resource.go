package integrations

import "context"

type ConnectionsResource struct {
	http *httpClient
}

func (r *ConnectionsResource) List(ctx context.Context, query *PaginationQuery) ([]Connection, error) {
	var result []Connection
	err := r.http.Request(ctx, "GET", "/v1/integrations/connections", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *ConnectionsResource) GetByID(ctx context.Context, id string) (ConnectionResponse, error) {
	var result ConnectionResponse
	err := r.http.Request(ctx, "GET", "/v1/integrations/connections/"+id, nil, nil, &result)
	return result, err
}

func (r *ConnectionsResource) Create(ctx context.Context, payload Connection) (Connection, error) {
	var result Connection
	err := r.http.Request(ctx, "POST", "/v1/integrations/connections", payload, nil, &result)
	return result, err
}

func (r *ConnectionsResource) Update(ctx context.Context, id string, payload Connection) (Connection, error) {
	var result Connection
	err := r.http.Request(ctx, "PUT", "/v1/integrations/connections/"+id, payload, nil, &result)
	return result, err
}

func (r *ConnectionsResource) Delete(ctx context.Context, id string) error {
	return r.http.Request(ctx, "DELETE", "/v1/integrations/connections/"+id, nil, nil, nil)
}

func (r *ConnectionsResource) ListByApplication(ctx context.Context, applicationID string) ([]Connection, error) {
	var result []Connection
	err := r.http.Request(ctx, "GET", "/v1/integrations/applications/"+applicationID+"/connections", nil, nil, &result)
	return result, err
}

// SetAsDefault marks one connection as the default for its application,
// unsetting any other default on the same application.
func (r *ConnectionsResource) SetAsDefault(ctx context.Context, id string, applicationID string) (Connection, error) {
	var result Connection
	err := r.http.Request(ctx, "PATCH", "/v1/integrations/connections/"+id+"/setDefault", SetAsDefaultRequest{ApplicationID: applicationID}, nil, &result)
	return result, err
}
