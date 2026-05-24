package integrations

import "context"

type McpResource struct {
	http *httpClient
}

// CallPublished sends a JSON-RPC request to an application's published MCP
// endpoint identified by its mcpKey.
func (r *McpResource) CallPublished(ctx context.Context, key string, payload JSONRPCRequest) (JSONRPCResponse, error) {
	var result JSONRPCResponse
	err := r.http.Request(ctx, "POST", "/v1/integrations/applications/published/"+key, payload, nil, &result)
	return result, err
}

// InfoPublished hits the GET variant of the published MCP endpoint and
// returns the welcome metadata.
func (r *McpResource) InfoPublished(ctx context.Context, key string) (map[string]any, error) {
	result := map[string]any{}
	err := r.http.Request(ctx, "GET", "/v1/integrations/applications/published/"+key, nil, nil, &result)
	return result, err
}
