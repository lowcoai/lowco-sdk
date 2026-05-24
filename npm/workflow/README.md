# @lowcoai/workflow

Official Node/TypeScript client for the **workflow-orchestrator** product (routes under `/v1/wf/*`).

```bash
npm install @lowcoai/workflow
```

## Quick start

```ts
import { WorkflowClient } from "@lowcoai/workflow";

const client = new WorkflowClient({
  baseUrl: "http://localhost:8080",
  token: process.env.WORKFLOW_TOKEN,
  orgId: "1",
  userId: "user_123",
});

const workflows = await client.workflows.list({ page: 1, limit: 20 });
console.log(workflows.length);
```

## Trigger a workflow

```ts
// Start from beginning
await client.workflows.run({
  workflowId: "wf_123",
  inputData: { orderId: "o_1" },
  environmentId: "env_default",
});

// Resume from an intermediate activity
await client.workflows.run({
  workflowId: "wf_123",
  activityId: "human_review_1",
  executionId: "exe_123",
  environmentId: "env_default",
});
```

## Complete a human task

```ts
const tasks = await client.humanTasks.list({ page: 1, limit: 10 });
if (tasks[0]) {
  await client.humanTasks.complete(tasks[0].id!, "approve");
}
```

## Resources

`client.workflows`, `client.environments`, `client.functions`, `client.executions`,
`client.activities`, `client.humanTasks`, `client.analytics`, `client.dryRun`,
`client.webhooks` — see [`../../docs/workflow.md`](../../docs/workflow.md) for the
full method-to-endpoint map.

## Error handling

All non-2xx responses throw `WorkflowError`:

```ts
import { WorkflowError } from "@lowcoai/workflow";

try {
  await client.workflows.getById("wf_unknown");
} catch (err) {
  if (err instanceof WorkflowError) {
    console.error(err.status, err.payload);
  }
}
```

## Conventions

- Tenancy: `X-Org-Id` and `X-User-Id` headers (set via `orgId` / `userId`).
- Auth: `Authorization: Bearer <token>`.
- Response envelope: `{ success, data, error, message }` — the SDK unwraps `data` for you.

## Docs

- `docs/overview.md` — capabilities and architecture
- `docs/quickstart.md` — onboarding and recipes
- `docs/api-reference.md` — full endpoint and SDK method map
- `llms.txt` / `llms-full.txt` — LLM-friendly compact index
