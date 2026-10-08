# Quickstart

## 1) Initialize client

```go
ctx := context.Background()

client, err := workflow.NewClient(workflow.Config{
	Token:     os.Getenv("WORKFLOW_TOKEN"), // required: user token or API key
	OrgID:     "1",
	TimeoutMS: 30_000,
	Headers: map[string]string{
		"X-Request-Source": "payments-service",
	},
})
if err != nil {
	log.Fatal(err)
}
```

## 2) List workflows

```go
page := 1
limit := 10
items, err := client.Workflows.List(ctx, &workflow.PaginationQuery{
	Page:  &page,
	Limit: &limit,
})
if err != nil {
	log.Fatal(err)
}
```

## 3) Run workflow

```go
resp, err := client.Workflows.Run(ctx, workflow.RunWorkflowRequest{
	WorkflowID:    "wf_123",
	EnvironmentID: "env_default",
	InputData: map[string]any{
		"orderId": "ord_123",
		"amount":  4499,
	},
})
if err != nil {
	log.Fatal(err)
}
_ = resp
```

## 4) Complete human task

```go
tasks, err := client.HumanTasks.List(ctx, &workflow.PaginationQuery{})
if err != nil {
	log.Fatal(err)
}
if len(tasks) > 0 {
	_, err = client.HumanTasks.Complete(ctx, tasks[0].ID, "approve")
	if err != nil {
		log.Fatal(err)
	}
}
```

## 5) Handle API failures

```go
if err != nil {
	var apiErr *workflow.Error
	if errors.As(err, &apiErr) {
		log.Printf("status=%d body=%v", apiErr.Status, apiErr.Payload)
	}
}
```
