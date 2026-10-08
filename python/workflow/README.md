# lowcoai-workflow

Python client for the **workflow-orchestrator** product (routes under `/v1/wf/*`). Sync and asyncio clients with the same surface, built on [httpx](https://www.python-httpx.org/). Python 3.10+.

```bash
pip install lowcoai-workflow
```

## Quick start

```python
from lowcoai.workflow import WorkflowClient

with WorkflowClient("<token-or-api-key>", org_id="org_123") as client:
    workflows = client.workflows.list({"page": 1, "limit": 20})

    # Start from the beginning
    run = client.workflows.run(
        {
            "workflowId": "wf_123",
            "inputData": {"orderId": "o_1"},
            "environmentId": "env_default",
        }
    )

    # Resume from an intermediate activity
    client.workflows.run(
        {
            "workflowId": "wf_123",
            "activityId": "human_review_1",
            "executionId": "exe_123",
            "environmentId": "env_default",
        }
    )
```

### asyncio

```python
from lowcoai.workflow import AsyncWorkflowClient

async with AsyncWorkflowClient("<token-or-api-key>", org_id="org_123") as client:
    tasks = await client.human_tasks.list({"page": 1, "limit": 10})
    if tasks:
        await client.human_tasks.complete(tasks[0]["id"], "approve")
```

`AsyncWorkflowClient` has the same resources and methods as `WorkflowClient`; each endpoint method is a coroutine. Close it with `await client.aclose()` if you don't use `async with`.

## Options

| Argument      | Description                                                                          |
| ------------- | ------------------------------------------------------------------------------------ |
| `token`       | User token or API key, sent as `Authorization: Bearer <token>`. Required.            |
| `org_id`      | Sent as the `X-Org-Id` header.                                                       |
| `timeout`     | Per-request timeout in seconds (default `30`). `None` disables it.                   |
| `headers`     | Extra headers added to every request. An `Authorization` or `X-Org-Id` entry here wins over `token` / `org_id`. |
| `http_client` | Your own `httpx.Client` / `httpx.AsyncClient` (proxies, retries, test transports). It is not closed by the SDK. |

All requests go to `https://api.lowco.ai`.

## Data shapes

Request and response bodies are plain dicts typed as `TypedDict`s (`Workflow`, `Environment`, `FunctionEntity`, `Execution`, `HumanTask`, …) whose keys match the JSON on the wire (camelCase). A value returned by one call can be sent back as the body of another. The service's `{ success, data, error, message }` envelope is unwrapped for you.

List and count methods take an optional `query` mapping — `PaginationQuery` (`page`, `limit`, `sortBy`, `sortOrder`, `where`) or any other keys the endpoint understands. Values are encoded like the TypeScript SDK: `None` is skipped, booleans become `"true"` / `"false"`, numbers and strings are sent as-is and anything else as JSON. Count endpoints return `int | dict[str, Any]`, depending on what the service sends.

## Surface

| Resource              | Methods |
| --------------------- | ------- |
| `client.workflows`    | `list`, `count`, `get_by_id`, `create`, `update`, `delete`, `run`, `versions`, `publish`, `published`, `published_count`, `get_published_by_id`, `update_published`, `delete_published`, `web_published`, `web_published_by_id`, `search_published_templates(q=, category=, limit=)` |
| `client.environments` | `list`, `get_by_id`, `create`, `update`, `delete`, `set_default` |
| `client.functions`    | `list`, `get_by_id`, `create`, `update`, `delete`, `versions`, `execute(id, params={})` |
| `client.executions`   | `list` (`query` also takes `full`), `count`, `get_by_id`, `logs` |
| `client.activities`   | `list`, `count`, `get_by_id`, `logs` |
| `client.human_tasks`  | `list`, `get_by_id`, `complete(id, action)` |
| `client.analytics`    | `default`, `get_by_id` |
| `client.dry_run`      | `execute` |
| `client.webhooks`     | `trigger(workflow_id, payload={}, env=, triggered_by=, async_=)` — the only webhook route the orchestrator serves; register webhooks through the integrations service |

`delete` methods of workflows, published workflows, environments and functions return `None`.

### Webhook triggers

```python
client.webhooks.trigger("wf_123", {"orderId": "o_1"}, env="prod", async_=True)
# POST /v1/wf/webhook/wf_123?env=prod&async=true
```

### Endpoints the SDK does not wrap

`HttpClient` / `AsyncHttpClient` are the transports behind the resources and apply the same headers, envelope unwrapping and error mapping:

```python
from lowcoai.workflow import HttpClient

with HttpClient("<token>", org_id="org_123") as http:
    data = http.request("GET", "/v1/wf/workflows", query={"page": 1}, headers={"X-Trace": "t1"})
```

## Errors

Every non-2xx response raises `WorkflowError` with the same fields as the TypeScript class:

```python
from lowcoai.workflow import WorkflowError

try:
    client.workflows.get_by_id("wf_unknown")
except WorkflowError as err:
    print(err.status, err.message, err.payload)
```

- `message` — `"Request failed with status <n>"`.
- `status` — the HTTP status; `0` when no response arrived (connection error, timeout — the `httpx` exception is chained as `__cause__`).
- `payload` — the parsed JSON error body; the raw text when the body is not JSON; `None` when empty.

A 2xx response whose body is not JSON raises `WorkflowError` with that 2xx `status` and the raw text as `payload` (`delete` methods ignore the body).
