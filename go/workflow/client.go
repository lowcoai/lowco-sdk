// Package workflow is the Go client for the workflow-orchestrator product
// (routes under /v1/wf/*). It mirrors the lowco-sdk per-product layout used by
// agentx and lowcodb — a single top-level Client exposes per-resource
// sub-clients that share one HTTP transport and tenancy headers.
package workflow

// DefaultBaseURL is the fixed API host every request is sent to.
const DefaultBaseURL = "https://api.lowco.ai"

// Client is the unified workflow client. It exposes one sub-client per
// resource (Workflows, Environments, Functions, …) that all share the same
// HTTP transport.
type Client struct {
	Workflows    *WorkflowsResource
	Environments *EnvironmentsResource
	Functions    *FunctionsResource
	Executions   *ExecutionsResource
	Activities   *ActivitiesResource
	HumanTasks   *HumanTasksResource
	Analytics    *AnalyticsResource
	DryRun       *DryRunResource
	Webhooks     *WebhooksResource
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
		Workflows:    &WorkflowsResource{http: http},
		Environments: &EnvironmentsResource{http: http},
		Functions:    &FunctionsResource{http: http},
		Executions:   &ExecutionsResource{http: http},
		Activities:   &ActivitiesResource{http: http},
		HumanTasks:   &HumanTasksResource{http: http},
		Analytics:    &AnalyticsResource{http: http},
		DryRun:       &DryRunResource{http: http},
		Webhooks:     &WebhooksResource{http: http},
	}, nil
}
