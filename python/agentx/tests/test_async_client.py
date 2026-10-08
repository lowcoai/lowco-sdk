from __future__ import annotations

import inspect
import json
from typing import Any

import httpx
import pytest

from lowcoai.agentx import (
    HEADER_ORG_ID,
    AgentxClient,
    AgentxError,
    AsyncAgentxClient,
    AsyncExecutorClient,
    AsyncKBClient,
    AsyncManagerClient,
    ExecutorClient,
    KBClient,
    ManagerClient,
    MessageSendParams,
)

PARAMS: MessageSendParams = {
    "message": {
        "role": "user",
        "messageId": "m1",
        "kind": "message",
        "parts": [{"kind": "data", "data": {"x": 1}}],
    },
}


def make_client(handler: Any, **kwargs: Any) -> AsyncAgentxClient:
    return AsyncAgentxClient(
        "tok_123",
        org_id="org_1",
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        **kwargs,
    )


def test_async_token_is_required() -> None:
    with pytest.raises(ValueError, match="token is required"):
        AsyncAgentxClient(" ")


async def test_async_roundtrip_across_sub_clients() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.url.path.endswith("/execute"):
            return httpx.Response(200, json={"jsonrpc": "2.0", "id": "agent_1", "result": {}})
        if request.url.path.endswith("/count"):
            return httpx.Response(200, json=5)
        return httpx.Response(200, json={"success": True, "data": {"id": "x1"}})

    async with make_client(handler, kb_api_base_path="/kb-v2") as client:
        assert await client.manager.create_conversation("agent_1") == {"id": "x1"}
        assert await client.kb.get_knowledge_base_count(size=1) == 5
        resp = await client.executor.send_message("agent_1", PARAMS)
        assert resp == {"jsonrpc": "2.0", "id": "agent_1", "result": {}}

        client.set_org_id("org_2")
        client.set_header("X-Extra", "1")
        await client.manager.health()
        await client.kb.health()
        await client.executor.health()

    assert [r.url.path for r in seen] == [
        "/v1/agentx/manager/conversations",
        "/kb-v2/knowledges/count",
        "/v1/agentx/executors/execute",
        "/health",
        "/health",
        "/health",
    ]
    assert json.loads(seen[0].content) == {"agentId": "agent_1"}
    assert dict(seen[1].url.params) == {"size": "1"}
    assert json.loads(seen[2].content) == {
        "jsonrpc": "2.0",
        "method": "message/send",
        "params": PARAMS,
        "id": "agent_1",
    }
    for req in seen[:3]:
        assert req.headers[HEADER_ORG_ID] == "org_1"
        assert "X-Extra" not in req.headers
    for req in seen[3:]:
        assert req.headers[HEADER_ORG_ID] == "org_2"
        assert req.headers["X-Extra"] == "1"
        assert req.headers["Authorization"] == "Bearer tok_123"


async def test_async_send_message_empty_body() -> None:
    client = make_client(lambda _r: httpx.Response(204))
    assert await client.executor.send_message("a", PARAMS) == {"jsonrpc": "2.0", "id": "a"}
    await client.aclose()


async def test_async_error_mapping() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            403, json={"success": False, "error": {"code": "FORBIDDEN", "message": "no access"}}
        )

    client = make_client(handler)
    with pytest.raises(AgentxError) as info:
        await client.manager.bulk_delete_agents(["a1"])
    assert (info.value.status_code, info.value.code, info.value.message) == (
        403,
        "FORBIDDEN",
        "no access",
    )
    with pytest.raises(AgentxError):
        await client.executor.send_message("a", PARAMS)
    await client.aclose()


async def test_async_owned_http_client_closes_but_injected_does_not() -> None:
    injected = httpx.AsyncClient(transport=httpx.MockTransport(lambda _r: httpx.Response(200)))
    async with AsyncAgentxClient("t", http_client=injected):
        pass
    assert not injected.is_closed
    await injected.aclose()

    owned = AsyncAgentxClient("t")
    await owned.aclose()
    assert owned._transport.http.is_closed


def _public_methods(cls: type) -> dict[str, str]:
    return {
        name: str(inspect.signature(fn))
        # stream_message returns Generator / AsyncGenerator respectively.
        .replace("AsyncGenerator[StreamEvent, None]", "Generator[StreamEvent, None, None]")
        for name, fn in inspect.getmembers(cls, inspect.isfunction)
        if not name.startswith("_")
    }


@pytest.mark.parametrize(
    ("sync_cls", "async_cls"),
    [
        (AgentxClient, AsyncAgentxClient),
        (ManagerClient, AsyncManagerClient),
        (KBClient, AsyncKBClient),
        (ExecutorClient, AsyncExecutorClient),
    ],
)
def test_sync_and_async_clients_expose_the_same_api(sync_cls: type, async_cls: type) -> None:
    sync = _public_methods(sync_cls)
    async_ = _public_methods(async_cls)
    if sync_cls is AgentxClient:
        sync.pop("close")
        async_.pop("aclose")
        assert vars(sync_cls)["__init__"].__doc__ and vars(async_cls)["__init__"].__doc__
        assert sync_cls.__annotations__.keys() == async_cls.__annotations__.keys()
        assert str(inspect.signature(sync_cls)) == str(inspect.signature(async_cls)).replace(
            "httpx.AsyncClient", "httpx.Client"
        )
    assert sync.keys() == async_.keys()
    assert sync  # the comparison is not vacuous
    for name, sig in sync.items():
        assert sig == async_[name], name
        fn = getattr(async_cls, name)
        if name in {"set_org_id", "set_header"}:
            assert not inspect.iscoroutinefunction(fn), name
        elif name == "stream_message":
            assert inspect.isasyncgenfunction(fn)
            assert inspect.isgeneratorfunction(getattr(sync_cls, name))
        else:
            assert inspect.iscoroutinefunction(fn), name
