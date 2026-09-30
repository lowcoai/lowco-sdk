# @lowcoai/workflow

Official Node/TypeScript client for the **workflow-orchestrator** product (routes under `/v1/wf/*`).

```bash
npm install @lowcoai/workflow
```

## Quick start

```ts
import { WorkflowClient } from "@lowcoai/workflow";

const client = new WorkflowClient({
  token: process.env.WORKFLOW_TOKEN!, // required: user token or API key
  orgId: "1",
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

## Trigger a workflow by webhook

```ts
// The payload becomes the workflow's input.
await client.webhooks.trigger("wf_123", { orderId: "o_1" }, { async: true });
```

`trigger` is the only webhook method that calls the API. `listByWorkflow`, `create`,
`update` and `delete` are deprecated: the workflow API does not serve those routes,
and webhook registration is handled by the integrations service. They reject with a
`WorkflowError` (`status` `0`) without sending a request. `create` used to POST to the
trigger route, so it ran the workflow with the webhook config as input.

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

- Host: all requests go to `https://api.lowco.ai`.
- Tenancy: `X-Org-Id` header (set via `orgId`).
- Auth: `Authorization: Bearer <token>` — `token` (user token or API key) is required.
- Response envelope: `{ success, data, error, message }` — the SDK unwraps `data` for you.

## Docs

- `docs/overview.md` — capabilities and architecture
- `docs/quickstart.md` — onboarding and recipes
- `docs/api-reference.md` — full endpoint and SDK method map
- `llms.txt` / `llms-full.txt` — LLM-friendly compact index
