# API Reference (SDK map)

Base path: `/v1/wf`

## Access pattern

- Construct the client: `const client = new WorkflowClient(config)`
- Resources are exposed directly on the client: `client.workflows`, `client.environments`, etc.

## Workflows

- `client.workflows.list(query)` -> `GET /workflows`
- `client.workflows.count(query)` -> `GET /workflows/count`
- `client.workflows.getById(id)` -> `GET /workflows/:id`
- `client.workflows.create(payload)` -> `POST /workflows`
- `client.workflows.update(id, payload)` -> `PUT /workflows/:id`
- `client.workflows.delete(id)` -> `DELETE /workflows/:id`
- `client.workflows.run(payload)` -> `POST /workflows/run`
- `client.workflows.versions(id, query)` -> `GET /workflows/:id/versions`
- `client.workflows.publish(id, payload)` -> `POST /workflows/:id/publish`
- `client.workflows.published(query)` -> `GET /workflows/published`
- `client.workflows.publishedCount(query)` -> `GET /workflows/published/count`
- `client.workflows.getPublishedById(id)` -> `GET /workflows/published/:id`
- `client.workflows.updatePublished(id, payload)` -> `PUT /workflows/published/:id`
- `client.workflows.deletePublished(id)` -> `DELETE /workflows/published/:id`
- `client.workflows.webPublished(query)` -> `GET /workflows/published/web`
- `client.workflows.webPublishedById(id)` -> `GET /workflows/published/web/:id`
- `client.workflows.searchPublishedTemplates(params)` -> `GET /workflows/published/web/search`

### Run payload notes

- Start: provide `workflowId` (+ optional `inputData`, `environmentId`)
- Resume: provide `workflowId` + `executionId` + `activityId`

## Environments

- `client.environments.list(query)` -> `GET /environments`
- `client.environments.getById(id)` -> `GET /environments/:id`
- `client.environments.create(payload)` -> `POST /environments`
- `client.environments.update(id, payload)` -> `PUT /environments/:id`
- `client.environments.delete(id)` -> `DELETE /environments/:id`
- `client.environments.setDefault(id)` -> `PATCH /environments/:id/default`

## Functions

- `client.functions.list(query)` -> `GET /functions`
- `client.functions.getById(id)` -> `GET /functions/:id`
- `client.functions.create(payload)` -> `POST /functions`
- `client.functions.update(id, payload)` -> `PUT /functions/:id`
- `client.functions.delete(id)` -> `DELETE /functions/:id`
- `client.functions.versions(id, query)` -> `GET /functions/:id/versions`
- `client.functions.execute(id, params)` -> `POST /functions/:id/execute`

## Executions

- `client.executions.list(query)` -> `GET /executions`
- `client.executions.count(query)` -> `GET /executions/count`
- `client.executions.getById(id)` -> `GET /executions/:id`
- `client.executions.logs(id)` -> `GET /executions/:id/logs`

## Activities

- `client.activities.list(query)` -> `GET /activities`
- `client.activities.count(query)` -> `GET /activities/count`
- `client.activities.getById(id)` -> `GET /activities/:id`
- `client.activities.logs(id)` -> `GET /activities/:id/logs`

## Human tasks

- `client.humanTasks.list(query)` -> `GET /human-tasks`
- `client.humanTasks.getById(id)` -> `GET /human-tasks/:id`
- `client.humanTasks.complete(id, action)` -> `PATCH /human-tasks/:id/complete`

## Analytics

- `client.analytics.default()` -> `GET /analytics`
- `client.analytics.getById(id)` -> `GET /analytics/:id`

## Dry run

- `client.dryRun.execute(payload)` -> `POST /dryrun`

## Webhooks

- `client.webhooks.trigger(workflowId, payload, query)` -> `POST /webhook/:id` (runs the workflow with `payload` as input)

Deprecated. The workflow API does not serve these routes, and webhook registration is handled by the integrations service. Each rejects with a `WorkflowError` (`status` `0`, `payload.code` `"unsupported_operation"`) without sending a request:

- `client.webhooks.listByWorkflow(workflowId)`
- `client.webhooks.create(workflowId, payload)`. It used to POST to the trigger route, so it ran the workflow with the webhook config as input.
- `client.webhooks.update(webhookId, payload)`
- `client.webhooks.delete(workflowId)`
