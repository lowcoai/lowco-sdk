# lowcoai-integrations

Python client for the **integrations-manager** product (routes under `/v1/integrations/*`). Sync and asyncio clients with the same surface, built on [httpx](https://www.python-httpx.org/). Python 3.10+.

```bash
pip install lowcoai-integrations
```

## Quick start

```python
from lowcoai.integrations import IntegrationsClient

with IntegrationsClient("<token-or-api-key>", org_id="org_123") as client:
    apps = client.applications.list({"page": 1, "limit": 20, "tags": "crm,sales"})

    result = client.actions.run(
        "action_123",
        {
            "credentialId": "conn_456",
            "inputBody": {"to": "alice@example.com", "subject": "Hello"},
        },
    )
```

### asyncio

```python
from lowcoai.integrations import AsyncIntegrationsClient

async with AsyncIntegrationsClient("<token-or-api-key>", org_id="org_123") as client:
    connections = await client.connections.list_by_application("app_slack")
```

`AsyncIntegrationsClient` has the same resources and methods as `IntegrationsClient`; each endpoint method is a coroutine. Close it with `await client.aclose()` if you don't use `async with`.

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

Request and response bodies are plain dicts typed as `TypedDict`s (`Application`, `ApplicationAction`, `Connection`, `ApplicationTrigger`, `AuthToken`, `JsonRpcRequest`, …) whose keys match the JSON on the wire (camelCase). A value returned by one call can be sent back as the body of another. The service's `{ success, data, error, message }` envelope is unwrapped for you.

Open-ended string unions of the TypeScript SDK (`ApplicationType`, `ApplicationSubType`, `ConnectionType`, `ConnectionStatus`) are plain `str` aliases; their docstrings list the known values.

List methods take an optional `query` mapping — `PaginationQuery` (`page`, `limit`, `sortBy`, `sortOrder`, `filter`, `tags` as a comma-separated string) or any other keys the endpoint understands. Values are encoded like the TypeScript SDK: `None` is skipped, booleans become `"true"` / `"false"`, numbers and strings are sent as-is and anything else as JSON.

## Surface

| Resource                | Methods |
| ----------------------- | ------- |
| `client.applications`   | `list`, `get_by_id`, `create`, `update`, `delete`, `patch_tags(id, tags)`, `run`, `load_actions(id, postman_folder)`, `versions`, `regenerate_mcp_key`, `get_mcp_tools`, `get_sub_applications`, `get_applications_with_triggers` |
| `client.actions`        | `list`, `get_by_id`, `create(application_id, action)`, `update`, `delete`, `list_by_application`, `run`, `resolve_credentials(action_ids)` |
| `client.connections`    | `list`, `get_by_id`, `create`, `update`, `delete`, `list_by_application`, `set_as_default(id, application_id)` |
| `client.triggers`       | `list_by_application(application_id, query=None)`, `get_by_id`, `create`, `update`, `delete`, `get_state` |
| `client.oauth`          | `login(application_id, request)`, `callback`, `get_token_by_credential_id`, `refresh_token_by_credential_id`, `refresh_expiring_tokens` |
| `client.configurations` | `get` |
| `client.mcp`            | `call_published(key, json_rpc_request)`, `info_published(key)` |

`delete` methods return `None`.

### OAuth flow

```python
login = client.oauth.login("app_slack", {"applicationId": "app_slack", "name": "Slack — Sales"})
# redirect the user to login["url"] ...

# On the redirect_uri callback:
client.oauth.callback({"state": state, "code": code})
```

### Published MCP endpoint

```python
tools = client.mcp.call_published(mcp_key, {"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
```

### Endpoints the SDK does not wrap

`HttpClient` / `AsyncHttpClient` are the transports behind the resources and apply the same headers, envelope unwrapping and error mapping:

```python
from lowcoai.integrations import HttpClient

with HttpClient("<token>", org_id="org_123") as http:
    data = http.request("GET", "/v1/integrations/applications", query={"page": 1})
```

## Errors

Every non-2xx response raises `IntegrationsError` with the same fields as the TypeScript class:

```python
from lowcoai.integrations import IntegrationsError

try:
    client.actions.run("action_123", {"inputBody": {}})
except IntegrationsError as err:
    print(err.status, err.message, err.payload)
```

- `message` — `"Request failed with status <n>"`.
- `status` — the HTTP status; `0` when no response arrived (connection error, timeout — the `httpx` exception is chained as `__cause__`).
- `payload` — the parsed JSON error body; the raw text when the body is not JSON; `None` when empty.

A 2xx response whose body is not JSON raises `IntegrationsError` with that 2xx `status` and the raw text as `payload` (`delete` methods ignore the body).
