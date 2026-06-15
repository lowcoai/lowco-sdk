# Quickstart

## 1) Create client

```ts
import { WorkflowClient } from "@lowcoai/workflow";

const client = new WorkflowClient({
  token: process.env.WORKFLOW_TOKEN!, // required: user token or API key
  orgId: "1"
});
```

## 2) Create environment

```ts
const env = await client.environments.create({
  name: "default",
  description: "Default runtime environment",
  variables: [{ name: "API_URL", value: "https://api.example.com" }]
});
```

## 3) Create workflow

```ts
const workflow = await client.workflows.create({
  name: "Order Approval",
  description: "Approve high-value orders",
  ui: { nodes: [], edges: [] },
  inputData: { orderId: "" },
  tags: ["orders", "approval"],
  comment: "Initial version"
});
```

## 4) Trigger workflow

```ts
const execution = await client.workflows.run({
  workflowId: workflow.id!,
  environmentId: env.id,
  inputData: { orderId: "ORD-1001", total: 5000 }
});
```

## 5) Continue from human task

```ts
const tasks = await client.humanTasks.list({ page: 1, limit: 20 });
const task = tasks.find((t) => t.executionId === (execution as any).id);
if (task?.id) {
  await client.humanTasks.complete(task.id, "approve");
}
```

## 6) Inspect execution and activity logs

```ts
const executions = await client.executions.list({ page: 1, limit: 10, full: true });
const activities = await client.activities.list({ page: 1, limit: 50 });
const logs = await client.executions.logs(executions[0].id!);
console.log({ activities: activities.length, logLines: logs.length });
```
