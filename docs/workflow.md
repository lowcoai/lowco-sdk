# workflow — REST surface reference

Service: **workflow-orchestrator**. All routes are mounted under `/v1/wf/*`.

## Conventions

- **Host**: always `https://api.lowco.ai`.
- **Auth**: `Authorization: Bearer <user-token-or-api-key>` — required; identifies the acting user.
- **Tenancy**: pass `X-Org-Id` on every request.
- **Response envelope**: `{ success, data, error, message }`. Clients should read the inner `data`. Every SDK (`@lowcoai/workflow`, `github.com/lowcoai/lowco-sdk/go/workflow`, `lowcoai-workflow` on PyPI, `lowcoai_workflow` on pub.dev) unwraps automatically.

## Endpoints

### Workflows

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET`    | `/workflows` | List workflows (pagination) |
| `GET`    | `/workflows/count` | Count workflows |
| `GET`    | `/workflows/:id` | Get one workflow |
| `POST`   | `/workflows` | Create workflow |
| `PUT`    | `/workflows/:id` | Update workflow (creates a new version) |
| `DELETE` | `/workflows/:id` | Delete workflow |
| `POST`   | `/workflows/run` | Start or resume an execution |
| `GET`    | `/workflows/:id/versions` | List versions for a workflow |
| `POST`   | `/workflows/:id/publish` | Publish workflow as a template |
| `GET`    | `/workflows/published` | List published templates |
| `GET`    | `/workflows/published/count` | Count published templates |
| `GET`    | `/workflows/published/:id` | Get a published template |
| `PUT`    | `/workflows/published/:id` | Update a published template |
| `DELETE` | `/workflows/published/:id` | Delete a published template |
| `GET`    | `/workflows/published/web` | List web-facing published templates |
| `GET`    | `/workflows/published/web/:id` | Get a web-facing published template |
| `GET`    | `/workflows/published/web/search` | Search published templates |

#### Run payload

- **Start**: `{ workflowId, inputData?, environmentId? }`
- **Resume**: `{ workflowId, executionId, activityId, environmentId? }`

### Environments

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET`    | `/environments` | List environments |
| `GET`    | `/environments/:id` | Get one environment |
| `POST`   | `/environments` | Create environment |
| `PUT`    | `/environments/:id` | Update environment |
| `DELETE` | `/environments/:id` | Delete environment |
| `PATCH`  | `/environments/:id/default` | Mark environment as default |

### Functions

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET`    | `/functions` | List functions |
| `GET`    | `/functions/:id` | Get one function |
| `POST`   | `/functions` | Create function |
| `PUT`    | `/functions/:id` | Update function (creates a new version) |
| `DELETE` | `/functions/:id` | Delete function |
| `GET`    | `/functions/:id/versions` | List versions for a function |
| `POST`   | `/functions/:id/execute` | Execute a function with params |

### Executions

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/executions` | List executions (supports `?full=true`) |
| `GET` | `/executions/count` | Count executions |
| `GET` | `/executions/:id` | Get one execution |
| `GET` | `/executions/:id/logs` | Stream/list logs for an execution |

### Activities

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/activities` | List activity-history entries |
| `GET` | `/activities/count` | Count activity-history entries |
| `GET` | `/activities/:id` | Get one activity-history entry |
| `GET` | `/activities/:id/logs` | Logs for a single activity |

### Human tasks

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET`   | `/human-tasks` | List human tasks |
| `GET`   | `/human-tasks/:id` | Get a single human task |
| `PATCH` | `/human-tasks/:id/complete` | Complete a human task with an action |

### Analytics

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/analytics` | Default analytics snapshot |
| `GET` | `/analytics/:id` | Analytics for a specific entity (e.g. workflow) |

### Dry run

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `POST` | `/dryrun` | Evaluate an expression against an execution context |

### Webhooks

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `POST` | `/webhook/:workflowId` | Trigger the workflow. The request body becomes its input. Query: `env`, `triggeredBy`, `async`. |

Only the trigger route is served. The workflow API does not serve webhook listing, registration, update or delete: `GET`, `PUT` and `DELETE /webhook/:id` fail with 404 or 405. Registration is handled by the integrations service. Saving a workflow whose start node uses an application trigger registers the workflow's webhook URL with the provider. No public route exposes this.

In `@lowcoai/workflow` and the Go SDK, the webhook `listByWorkflow`, `create`, `update` and `delete` methods are deprecated. They return an SDK error (status `0`) without sending a request. `create` used to `POST` to the trigger route, so it ran the workflow with the webhook config as input.

## See also

- Go client: [`../go/workflow/README.md`](../go/workflow/README.md)
- npm client: [`../npm/workflow/README.md`](../npm/workflow/README.md)
