// Package integrations is the Go client for the integrations-manager product
// (routes under /v1/integrations/*). It mirrors the lowco-sdk per-product
// layout used by workflow and agentx — a single top-level Client exposes
// per-resource sub-clients that share one HTTP transport and tenancy headers.
package integrations

// DefaultBaseURL is the fixed API host every request is sent to.
const DefaultBaseURL = "https://api.lowco.ai"

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

// NewClient constructs a Client targeting DefaultBaseURL. Config.Token is
// required (a user token or an API key) and is sent as a Bearer token on
// every request; OrgID sets the X-Org-Id header.
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
