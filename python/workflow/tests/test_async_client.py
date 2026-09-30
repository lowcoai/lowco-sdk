from __future__ import annotations

import inspect
import json
from typing import Any

import httpx
import pytest

from lowcoai.workflow import (
    AsyncHttpClient,
    AsyncWorkflowClient,
    HttpClient,
    WorkflowClient,
    WorkflowError,
    resources,
)


def make_client(handler: Any, **kwargs: Any) -> AsyncWorkflowClient:
    return AsyncWorkflowClient(
        "tok_123",
        org_id="org_1",
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        **kwargs,
    )


async def test_async_request_roundtrip() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"success": True, "data": {"executionId": "exe_1"}})

    async with make_client(handler, headers={"X-Trace": "t"}) as client:
        result = await client.workflows.run({"workflowId": "wf_1", "inputData": {"a": 1}})
    assert result == {"executionId": "exe_1"}
    req = seen[0]
    assert req.method == "POST"
    assert str(req.url) == "https://api.lowco.ai/v1/wf/workflows/run"
    assert req.headers["Authorization"] == "Bearer tok_123"
    assert req.headers["X-Org-Id"] == "org_1"
    assert req.headers["X-Trace"] == "t"
    assert req.headers["Content-Type"] == "application/json"
    assert json.loads(req.content) == {"workflowId": "wf_1", "inputData": {"a": 1}}


async def test_async_header_precedence() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(204)

    client = make_client(handler, headers={"authorization": "Bearer other", "X-Org-Id": "org_h"})
    assert await client.analytics.default() is None
    assert seen[0].headers.get_list("Authorization") == ["Bearer other"]
    assert seen[0].headers.get_list("X-Org-Id") == ["org_h"]
    await client.aclose()


async def test_async_error_mapping() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/logs"):
            return httpx.Response(503, text="upstream down")
        return httpx.Response(404, json={"success": False, "message": "nope"})

    client = make_client(handler)
    with pytest.raises(WorkflowError) as info:
        await client.executions.get_by_id("exe_1")
    assert (info.value.status, info.value.payload) == (404, {"success": False, "message": "nope"})
    assert info.value.message == "Request failed with status 404"
    with pytest.raises(WorkflowError) as info:
        await client.executions.logs("exe_1")
    assert (info.value.status, info.value.payload) == (503, "upstream down")
    await client.aclose()


async def test_async_transport_error_is_wrapped() -> None:
    cause = httpx.ConnectTimeout("connect timed out")

    def handler(_request: httpx.Request) -> httpx.Response:
        raise cause

    client = make_client(handler)
    with pytest.raises(WorkflowError) as info:
        await client.human_tasks.complete("t1", "approve")
    assert info.value.status == 0
    assert info.value.payload is None
    assert info.value.message == "connect timed out"
    assert info.value.__cause__ is cause
    await client.aclose()


async def test_async_void_method_ignores_non_json_body() -> None:
    client = make_client(lambda _r: httpx.Response(200, text="deleted"))
    assert await client.functions.delete("f1") is None  # type: ignore[func-returns-value]
    await client.aclose()


async def test_async_close_semantics() -> None:
    owned = AsyncWorkflowClient("tok")
    async with owned:
        pass
    assert owned._http._http.is_closed

    injected = httpx.AsyncClient(transport=httpx.MockTransport(lambda _r: httpx.Response(204)))
    async with AsyncWorkflowClient("tok", http_client=injected):
        pass
    assert not injected.is_closed
    await injected.aclose()


# --- sync / async parity --------------------------------------------------------


def _public_methods(cls: type) -> dict[str, inspect.Signature]:
    return {
        name: inspect.signature(fn)
        for name, fn in inspect.getmembers(cls, inspect.isfunction)
        if not name.startswith("_")
    }


def _pairs() -> list[tuple[type, type]]:
    pairs: list[tuple[type, type]] = [
        (WorkflowClient, AsyncWorkflowClient),
        (HttpClient, AsyncHttpClient),
    ]
    for name in resources.__all__:
        if not name.startswith("Async"):
            pairs.append((getattr(resources, name), getattr(resources, "Async" + name)))
    return pairs


@pytest.mark.parametrize(("sync_cls", "async_cls"), _pairs(), ids=lambda c: c.__name__)
def test_sync_and_async_classes_expose_the_same_api(sync_cls: type, async_cls: type) -> None:
    sync = _public_methods(sync_cls)
    async_ = _public_methods(async_cls)
    if "close" in sync:
        sync.pop("close")
        async_.pop("aclose")
    assert sync or sync_cls is WorkflowClient
    assert sync.keys() == async_.keys()
    init = str(inspect.signature(sync_cls.__init__))  # type: ignore[misc]
    init = init.replace("httpx.Client", "httpx.AsyncClient").replace(
        "HttpClient", "AsyncHttpClient"
    )
    assert init == str(inspect.signature(async_cls.__init__))  # type: ignore[misc]
    for name, sig in sync.items():
        assert str(sig) == str(async_[name]), name
        assert inspect.iscoroutinefunction(getattr(async_cls, name)), name
        assert not inspect.iscoroutinefunction(getattr(sync_cls, name)), name


def test_resource_classes_are_all_paired() -> None:
    names = set(resources.__all__)
    sync_names = {n for n in names if not n.startswith("Async")}
    assert len(sync_names) == 9
    assert {"Async" + n for n in sync_names} == names - sync_names


def test_clients_expose_the_same_resources() -> None:
    sync = {k: type(v).__name__ for k, v in vars(WorkflowClient("t")).items() if k[0] != "_"}
    async_ = {k: type(v).__name__ for k, v in vars(AsyncWorkflowClient("t")).items() if k[0] != "_"}
    assert list(sync) == [
        "workflows",
        "environments",
        "functions",
        "executions",
        "activities",
        "human_tasks",
        "analytics",
        "dry_run",
        "webhooks",
    ]
    assert async_ == {k: "Async" + v for k, v in sync.items()}
