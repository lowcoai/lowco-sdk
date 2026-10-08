package integrations

import "context"

type ConfigurationsResource struct {
	http *httpClient
}

// Get returns the catalog of supported application types mapped to their
// subtypes (e.g. database → [postgres, mysql, …]).
func (r *ConfigurationsResource) Get(ctx context.Context) (map[ApplicationType][]ApplicationSubType, error) {
	result := map[ApplicationType][]ApplicationSubType{}
	err := r.http.Request(ctx, "GET", "/v1/integrations/configurations", nil, nil, &result)
	return result, err
}
