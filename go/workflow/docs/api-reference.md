# API Reference

This page maps SDK methods to `workflow-orchestrator` routes.

## Initialization

- `NewClient(config)` creates the workflow client; resources are exposed as `client.Workflows`, `client.Environments`, `client.Functions`, `client.Executions`, `client.Activities`, `client.HumanTasks`, `client.Analytics`, `client.DryRun`, `client.Webhooks`.

## Workflows

- `List` -> `GET /v1/wf/workflows`
- `Count` -> `GET /v1/wf/workflows/count`
- `GetByID` -> `GET /v1/wf/workflows/:id`
- `Create` -> `POST /v1/wf/workflows`
- `Update` -> `PUT /v1/wf/workflows/:id`
- `Delete` -> `DELETE /v1/wf/workflows/:id`
- `Run` -> `POST /v1/wf/workflows/run`
- `Versions` -> `GET /v1/wf/workflows/:id/versions`
- `Publish` -> `POST /v1/wf/workflows/:id/publish`
- `Published` -> `GET /v1/wf/workflows/published`
- `PublishedCount` -> `GET /v1/wf/workflows/published/count`
- `GetPublishedByID` -> `GET /v1/wf/workflows/published/:id`
- `UpdatePublished` -> `PUT /v1/wf/workflows/published/:id`
- `DeletePublished` -> `DELETE /v1/wf/workflows/published/:id`
- `WebPublished` -> `GET /v1/wf/workflows/published/web`
- `WebPublishedByID` -> `GET /v1/wf/workflows/published/web/:id`
- `SearchPublishedTemplates` -> `GET /v1/wf/workflows/published/web/search`

## Environments

- `List` -> `GET /v1/wf/environments`
- `GetByID` -> `GET /v1/wf/environments/:id`
- `Create` -> `POST /v1/wf/environments`
- `Update` -> `PUT /v1/wf/environments/:id`
- `Delete` -> `DELETE /v1/wf/environments/:id`
- `SetDefault` -> `PATCH /v1/wf/environments/:id/default`

## Functions

- `List` -> `GET /v1/wf/functions`
- `GetByID` -> `GET /v1/wf/functions/:id`
- `Create` -> `POST /v1/wf/functions`
- `Update` -> `PUT /v1/wf/functions/:id`
- `Delete` -> `DELETE /v1/wf/functions/:id`
- `Versions` -> `GET /v1/wf/functions/:id/versions`
- `Execute` -> `POST /v1/wf/functions/:id/execute`

## Human tasks

- `List` -> `GET /v1/wf/human-tasks`
- `GetByID` -> `GET /v1/wf/human-tasks/:id`
- `Complete` -> `PATCH /v1/wf/human-tasks/:id/complete`

## Executions

- `List` -> `GET /v1/wf/executions`
- `Count` -> `GET /v1/wf/executions/count`
- `GetByID` -> `GET /v1/wf/executions/:id`
- `Logs` -> `GET /v1/wf/executions/:id/logs`

## Activities

- `List` -> `GET /v1/wf/activities`
- `Count` -> `GET /v1/wf/activities/count`
- `GetByID` -> `GET /v1/wf/activities/:id`
- `Logs` -> `GET /v1/wf/activities/:id/logs`

## Analytics

- `Default` -> `GET /v1/wf/analytics`
- `GetByID` -> `GET /v1/wf/analytics/:id`

## Dry run

- `Execute` -> `POST /v1/wf/dryrun`

## Webhooks

- `Trigger` -> `POST /v1/wf/webhook/:workflowId`
- `ListByWorkflow` -> `GET /v1/wf/webhook/:workflowId`
- `Create` -> `POST /v1/wf/webhook/:workflowId`
- `Update` -> `PUT /v1/wf/webhook/:webhookId`
- `Delete` -> `DELETE /v1/wf/webhook/:workflowId`
