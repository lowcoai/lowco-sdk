# lowcoai-agentx

Python client for the **agentx** backend: the **agent-manager**, **agent-kb** (knowledge-base) and **agent-executor** services in one package. Sync and asyncio clients with the same surface, built on [httpx](https://www.python-httpx.org/). Python 3.10+.

```bash
pip install lowcoai-agentx
```

## Quick start

```python
from lowcoai.agentx import AgentxClient, MessageSendParams

params: MessageSendParams = {
    "message": {
        "role": "user",
        "messageId": "msg_001",
        "kind": "message",
        "parts": [{"kind": "text", "text": "Hello!"}],
    },
    "chatType": "chat",
}

with AgentxClient("<token-or-api-key>", org_id="org_123") as client:
    agents = client.manager.list_agents(page_no=1, size=25)
    kbs = client.kb.list_knowledge_bases()

    resp = client.executor.send_message("agent_abc", params)
    if "error" in resp:
        print("rpc error", resp["error"])
    else:
        print("result", resp.get("result"))
```

The three sub-clients (`client.manager`, `client.kb`, `client.executor`) share one connection pool and one set of default headers.

### asyncio

```python
from lowcoai.agentx import AsyncAgentxClient

async with AsyncAgentxClient("<token-or-api-key>", org_id="org_123") as client:
    agents = await client.manager.list_agents()
```

`AsyncAgentxClient` has the same sub-clients and methods as `AgentxClient`; each endpoint method is a coroutine (`stream_message` is an async generator). Close it with `await client.aclose()` if you don't use `async with`.

## Streaming the executor

```python
from lowcoai.agentx import try_parse_message

for ev in client.executor.stream_message("agent_abc", params):
    msg = try_parse_message(ev)
    if msg:
        print("delta:", msg)
    else:
        print("raw:", ev.data)
```

Each `StreamEvent` carries the raw `data` of one server-sent event (multi-line `data:` fields joined with `"\n"`); `try_parse_message(ev)` decodes it as JSON and returns `None` when it is not a JSON object. The request is sent when iteration starts, a non-2xx answer raises `AgentxError`, and the read timeout does not apply to the stream. Breaking out of the loop closes the connection; with asyncio, wrap the generator in `contextlib.aclosing` to close it deterministically:

```python
from contextlib import aclosing

async with aclosing(client.executor.stream_message("agent_abc", params)) as events:
    async for ev in events:
        if ev.data == "[DONE]":
            break
```

## Options

All requests go to `https://api.lowco.ai`.

| Argument                 | Description                                                                          |
| ------------------------ | ------------------------------------------------------------------------------------ |
| `token`                  | User token or API key, sent as `Authorization: Bearer <token>`. Required.            |
| `org_id`                 | Sent as the `X-Org-Id` header.                                                       |
| `manager_api_base_path` / `kb_api_base_path` / `executor_api_base_path` | Route prefix per service (defaults `/v1/agentx/manager`, `/v1/agentx/kb`, `/v1/agentx/executors`). |
| `default_headers`        | Extra headers added to every request.                                                |
| `timeout`                | Per-request timeout in seconds (default `30`). `None` disables it. `stream_message` keeps it for connecting but not for reading the stream. |
| `http_client`            | Your own `httpx.Client` / `httpx.AsyncClient` (proxies, retries, test transports). It is not closed by the SDK. |

`client.set_org_id(...)` and `client.set_header(key, value)` change headers for later requests of all three sub-clients; pass `None` to remove.

## Data shapes

Request and response bodies are plain dicts typed as `TypedDict`s (`Agent`, `LlmModel`, `Conversation`, `KnowledgeBase`, `Dataset`, `A2AMessage`, `MessageSendParams`, `JSONRPCResponse`, …) whose keys match the JSON on the wire (camelCase). A value returned by one call can be sent back as the body of another. Message parts are the `TextPart` / `FilePart` / `DataPart` union (`Part`), discriminated by `kind`.

List methods take keyword-only `page_no`, `size`, `filter` and `sort`. The `get_*_count` methods return a plain `int`.

Constants: `HEADER_ORG_ID`, `DEFAULT_MANAGER_API_BASE_PATH`, `DEFAULT_KB_API_BASE_PATH`, `DEFAULT_EXECUTOR_API_BASE_PATH`, `METHOD_MESSAGE_SEND`, `JSONRPC_ERROR_CODES`, `A2A_ERROR_CODES`.

## Surface

| Sub-client        | Area              | Methods |
| ----------------- | ----------------- | ------- |
| `client.manager`  | Health            | `health` |
|                   | Agents            | `list_agents`, `get_agent`, `create_agent`, `update_agent`, `patch_agent`, `get_agent_count`, `delete_agent`, `bulk_delete_agents`, `get_agent_versions` |
|                   | Published agents  | `publish_agent`, `get_published_agent`, `update_published_agent`, `delete_published_agent`, `list_published_agents` |
|                   | LLM models        | `create_model`, `get_model`, `update_model`, `list_models`, `delete_model`, `enable_model`, `disable_model` |
|                   | Conversations     | `list_conversations_by_agent`, `create_conversation`, `delete_conversation`, `get_conversation_messages` |
| `client.kb`       | Health            | `health` |
|                   | Knowledge bases   | `list_knowledge_bases`, `create_knowledge_base`, `get_knowledge_base`, `update_knowledge_base`, `get_knowledge_base_count` |
|                   | Datasets          | `list_datasets`, `create_dataset`, `get_dataset`, `update_dataset`, `delete_dataset`, `get_dataset_count` |
|                   | Embeddings        | `store_embeddings` (returns the service's message) |
| `client.executor` | A2A JSON-RPC      | `send_message`, `stream_message`, `health` |

`health` calls `GET /health` at the host root.

## Errors

Every HTTP-level non-2xx response raises `AgentxError` with `status_code`, `message`, `code` and the raw `body`. JSON-RPC level errors from the executor are not raised: they come back in the `error` field of the `JSONRPCResponse`.

```python
from lowcoai.agentx import AgentxError

try:
    client.manager.get_agent("missing")
except AgentxError as err:
    print(err.status_code, err.code, err.message, err.body)
```

`message` and `code` come from the service's `error` envelope when present, otherwise from a top-level `message`, otherwise `message` is the raw response text. Network failures and timeouts surface as `httpx` exceptions.
