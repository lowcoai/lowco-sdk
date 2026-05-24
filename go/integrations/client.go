// Package integrations is the Go client for the integrations-manager product
// (routes under /v1/integrations/*). It mirrors the lowco-sdk per-product
// layout used by workflow and agentx — a single top-level Client exposes
// per-resource sub-clients that share one HTTP transport and tenancy headers.
package integrations

// Client is the unified integrations client. Each sub-client groups the
// endpoints for one resource and shares the same underlying HTTP transport.
type Client struct {
	Applications   *ApplicationsResource
	Actions        *ActionsResource
	Connections    *ConnectionsResource
	Triggers       *TriggersResource
	OAuth          *OAuthResource
	Configurations *ConfigurationsResource
	MCP            *McpResource
}

// NewClient constructs a Client. BaseURL is required; OrgID / UserID set the
// X-Org-Id and X-User-Id headers on every request.
func NewClient(config Config) (*Client, error) {
	http, err := newHTTPClient(config)
	if err != nil {
		return nil, err
	}

	return &Client{
		Applications:   &ApplicationsResource{http: http},
		Actions:        &ActionsResource{http: http},
		Connections:    &ConnectionsResource{http: http},
		Triggers:       &TriggersResource{http: http},
		OAuth:          &OAuthResource{http: http},
		Configurations: &ConfigurationsResource{http: http},
		MCP:            &McpResource{http: http},
	}, nil
}
