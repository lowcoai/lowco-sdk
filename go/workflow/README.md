# workflow (Go)

Official Go client for the **workflow-orchestrator** product (routes under `/v1/wf/*`).

```bash
go get github.com/backend-platform/lowco-sdk/go/workflow
```

## Quick start

```go
package main

import (
	"context"
	"log"

	"github.com/backend-platform/lowco-sdk/go/workflow"
)

func main() {
	ctx := context.Background()

	client, err := workflow.NewClient(workflow.Config{
		BaseURL: "http://localhost:8080",
		Token:   "your-token",
		OrgID:   "1",
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

- Tenancy: `X-Org-Id` and `X-User-Id` headers (set via `Config.OrgID` / `Config.UserID`).
- Auth: `Authorization: Bearer <Token>`.
- Response envelope: `{ success, data, error, message }` — the SDK unwraps `data` for you.
