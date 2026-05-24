package integrations

import "context"

type TriggersResource struct {
	http *httpClient
}

// ListByApplication returns triggers attached to one application. Webhook
// triggers include a populated WebhookURL.
func (r *TriggersResource) ListByApplication(ctx context.Context, applicationID string, query *PaginationQuery) ([]ApplicationTrigger, error) {
	var result []ApplicationTrigger
	err := r.http.Request(ctx, "GET", "/v1/integrations/applications/"+applicationID+"/triggers", nil, &RequestOptions{Query: mapFromStruct(query)}, &result)
	return result, err
}

func (r *TriggersResource) GetByID(ctx context.Context, id string) (ApplicationTrigger, error) {
	var result ApplicationTrigger
	err := r.http.Request(ctx, "GET", "/v1/integrations/triggers/"+id, nil, nil, &result)
	return result, err
}

func (r *TriggersResource) Create(ctx context.Context, payload ApplicationTrigger) (ApplicationTrigger, error) {
	var result ApplicationTrigger
	err := r.http.Request(ctx, "POST", "/v1/integrations/triggers", payload, nil, &result)
	return result, err
}

func (r *TriggersResource) Update(ctx context.Context, id string, payload ApplicationTrigger) (ApplicationTrigger, error) {
	var result ApplicationTrigger
	err := r.http.Request(ctx, "PUT", "/v1/integrations/triggers/"+id, payload, nil, &result)
	return result, err
}

func (r *TriggersResource) Delete(ctx context.Context, id string) error {
	return r.http.Request(ctx, "DELETE", "/v1/integrations/triggers/"+id, nil, nil, nil)
}

// GetState returns runner-owned runtime state (last run, error, cursor,
// lease). Returns a 404-mapped *Error before the first run has happened.
func (r *TriggersResource) GetState(ctx context.Context, id string) (TriggerState, error) {
	var result TriggerState
	err := r.http.Request(ctx, "GET", "/v1/integrations/triggers/"+id+"/state", nil, nil, &result)
	return result, err
}
