# lowcoai-lowcodb

Python client for the **lowcodb manager** service. Sync and asyncio clients with the same surface, built on [httpx](https://www.python-httpx.org/). Python 3.10+.

```bash
pip install lowcoai-lowcodb
```

## Quick start

```python
from lowcoai.lowcodb import LowcodbClient

with LowcodbClient("<token-or-api-key>", org_id="org_123") as client:
    bases = client.list_bases()
    base = client.create_base({"name": "crm", "baseType": "internal"})

    row = client.create_record(base["schema"], "leads", {"name": "Ada", "status": "open"})
    open_leads = client.list_records(base["schema"], "leads", filter="status='open'", size=50)
```

### asyncio

```python
from lowcoai.lowcodb import AsyncLowcodbClient

async with AsyncLowcodbClient("<token-or-api-key>", org_id="org_123") as client:
    bases = await client.list_bases()
```

`AsyncLowcodbClient` has the same methods as `LowcodbClient`; each one is a coroutine. Close it with `await client.aclose()` if you don't use `async with`.

## Options

| Argument          | Description                                                                          |
| ----------------- | ------------------------------------------------------------------------------------ |
| `token`           | User token or API key, sent as `Authorization: Bearer <token>`. Required.            |
| `org_id`          | Sent as the `X-Org-Id` header.                                                       |
| `base_url`        | Origin of the manager, e.g. `"http://lowcodb-service:8080"` in-cluster. Defaults to `https://api.lowco.ai`. |
| `api_base_path`   | Route prefix, default `/v1/lowcodb`.                                                 |
| `default_headers` | Extra headers added to every request.                                                |
| `timeout`         | Per-request timeout in seconds (default `30`). `None` disables it.                   |
| `http_client`     | Your own `httpx.Client` / `httpx.AsyncClient` (proxies, retries, test transports). It is not closed by the SDK. |

`client.set_org_id(...)` and `client.set_header(key, value)` change headers for later requests; pass `None` to remove.

## Data shapes

Request and response bodies are plain dicts typed as `TypedDict`s (`Base`, `Table`, `Column`, `DBFunction`, …) whose keys match the JSON on the wire (camelCase). A value returned by one call can be sent back as the body of another. Rows are `dict[str, Any]` (`LowcodbRecord`).

List methods take keyword-only `page_no`, `size`, `filter` and `sort`.

## Surface

| Area              | Methods |
| ----------------- | ------- |
| Health            | `health` |
| Bases             | `get_base`, `create_base`, `update_base`, `delete_base`, `list_bases`, `export_base_collection` (bytes), `sync_base_tables` |
| Tables            | `get_table`, `create_table`, `update_table`, `delete_table`, `list_tables` |
| Columns           | `get_column`, `create_column`, `bulk_create_columns`, `update_column`, `bulk_update_columns`, `delete_column`, `list_columns`, `validate_field` |
| Table indexes     | `get_table_index`, `create_table_index`, `update_table_index`, `list_table_indexes`, `delete_table_index` |
| Records           | `create_record`, `get_record`, `update_record`, `delete_record`, `list_records`, `count_records`, `create_bulk_records`, `update_bulk_records`, `delete_bulk_records` |
| View data         | `get_view_record`, `list_view_records`, `count_view_records` |
| Dashboards        | `get_overview_counts`, `get_metrics_dashboard`, `get_dashboard_overview` |
| Triggers          | `get_trigger`, `create_trigger`, `update_trigger`, `delete_trigger`, `list_triggers` |
| Webhooks          | `get_webhook`, `create_webhook`, `update_webhook`, `delete_webhook`, `list_webhooks` |
| Transactions      | `execute_transaction` |
| Events            | `publish_event` |
| DB functions      | `list_functions`, `get_function`, `create_function`, `update_function`, `delete_function`, `list_function_versions`, `execute_function`, `invoke_function` |
| Query             | `execute_query`, `get_query_suggestions` |
| Views (metadata)  | `list_views`, `create_view`, `get_view`, `update_view`, `delete_view`, `refresh_view` |

### Transactions

```python
client.execute_transaction(
    "app_crm",
    [
        {"type": "create", "table": "leads", "record": {"name": "Ada"}},
        {"type": "update", "table": "accounts", "id": "acc_1", "record": {"leadCount": 4}},
    ],
)
```

All operations succeed or none apply (internal bases only).

### DB functions

```python
fn = client.create_function(
    {
        "baseId": base["id"],
        "name": "Score lead",
        "functionKey": "score-lead",
        "body": "return { score: ctx.request.body.value * 2 };",
    }
)

result = client.execute_function(fn["id"], {"value": 21})  # console run: result, logs, error
value = client.invoke_function("app_crm", "score-lead", {"value": 21})  # data-plane call
value = client.invoke_function("app_crm", "score-lead", method="GET")
```

## Errors

Every non-2xx response raises `LowcodbError` with `status_code`, `message`, `code` and the raw `body`:

```python
from lowcoai.lowcodb import LowcodbError

try:
    client.invoke_function("app_crm", "score-lead", {})
except LowcodbError as err:
    print(err.status_code, err.message, err.code)
```

When the manager answers with an opaque platform code (`"AAS-00105"`) as the message, `message` carries the human-readable `error.details` instead; the code is still in `body`. Network failures and timeouts surface as `httpx` exceptions.
