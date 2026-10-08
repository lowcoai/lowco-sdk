# workflow (Go)

Official Go client for the **workflow-orchestrator** product (routes under `/v1/wf/*`).

```bash
go get github.com/lowcoai/lowco-sdk/go/workflow
```

## Quick start

```go
package main

import (
	"context"
	"log"

	"github.com/lowcoai/lowco-sdk/go/workflow"
)

func main() {
	ctx := context.Background()

	client, err := workflow.NewClient(workflow.Config{
		Token: "your-token-or-api-key", // required
		OrgID: "1",
	})
	if err != nil {
		log.Fatal(err)
	}

	page, limit := 1, 20
	workflows, err := client.Workflows.List(ctx, &workflow.PaginationQuery{
		Page:  &page,
		Limit: &limit,
	})
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("found %d workflows", len(workflows))
}
```

## Trigger a workflow

```go
// Start from beginning
_, err := client.Workflows.Run(ctx, workflow.RunWorkflowRequest{
	WorkflowID:    "wf_123",
	InputData:     map[string]any{"orderId": "o_1"},
	EnvironmentID: "env_default",
})

// Resume from an intermediate activity
_, err = client.Workflows.Run(ctx, workflow.RunWorkflowRequest{
	WorkflowID:    "wf_123",
	ActivityID:    "human_review_1",
	ExecutionID:   "exe_123",
	EnvironmentID: "env_default",
})
```

## Trigger a workflow by webhook

```go
// The payload becomes the workflow's input.
async := true
_, err = client.Webhooks.Trigger(ctx, "wf_123", map[string]any{"orderId": "o_1"},
	&workflow.WebhookTriggerQuery{Async: &async})
```

`Trigger` is the only webhook method that calls the API. `ListByWorkflow`, `Create`,
`Update` and `Delete` are deprecated: the workflow API does not serve those routes,
and webhook registration is handled by the integrations service. They return a
`*workflow.Error` (`Status` `0`) without sending a request. `Create` used to POST to the
trigger route, so it ran the workflow with the webhook config as input.

## Resources

`client.Workflows`, `client.Environments`, `client.Functions`, `client.Executions`,
`client.Activities`, `client.HumanTasks`, `client.Analytics`, `client.DryRun`,
`client.Webhooks` — see [`../../docs/workflow.md`](../../docs/workflow.md) for the
full method-to-endpoint map.

## Error handling

All non-2xx responses return `*workflow.Error`:

```go
if err != nil {
	var sdkErr *workflow.Error
	if errors.As(err, &sdkErr) {
		log.Printf("status=%d payload=%v", sdkErr.Status, sdkErr.Payload)
	}
}
```

## Conventions

- Host: all requests go to `https://api.lowco.ai` (`workflow.DefaultBaseURL`).
- Auth: `Config.Token` is required (a user token or an API key) and is sent as `Authorization: Bearer <Token>` on every request.
- Tenancy: `X-Org-Id` header (set via `Config.OrgID`).
- Response envelope: `{ success, data, error, message }` — the SDK unwraps `data` for you.
