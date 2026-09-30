from __future__ import annotations

import inspect
import json
from typing import Any

import httpx
import pytest

from lowcoai.lowcodb import AsyncLowcodbClient, LowcodbClient, LowcodbError


def make_client(handler: Any) -> AsyncLowcodbClient:
    return AsyncLowcodbClient(
        "tok_123",
        org_id="org_1",
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )


async def test_async_request_roundtrip() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"data": {"id": "r1", "name": "Ada"}})

    async with make_client(handler) as client:
        row = await client.create_record("app_crm", "leads", {"name": "Ada"})
    assert row == {"id": "r1", "name": "Ada"}
    req = seen[0]
    assert req.method == "POST"
    assert req.url.path == "/v1/lowcodb/data/app_crm/tables/leads/records"
    assert req.headers["Authorization"] == "Bearer tok_123"
    assert req.headers["X-Org-Id"] == "org_1"
    assert json.loads(req.content) == {"name": "Ada"}


async def test_async_list_query_and_error() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/functions"):
            return httpx.Response(200, json={"data": [{"id": "f1"}]})
        return httpx.Response(
            500, json={"error": {"code": 500, "message": "AAS-00105", "details": "boom"}}
        )

    client = make_client(handler)
    assert await client.list_functions(size=10) == [{"id": "f1"}]
    with pytest.raises(LowcodbError) as info:
        await client.execute_function("f1", {"x": 1})
    assert info.value.message == "boom"
    await client.aclose()


def _public_methods(cls: type) -> dict[str, inspect.Signature]:
    return {
        name: inspect.signature(fn)
        for name, fn in inspect.getmembers(cls, inspect.isfunction)
        if not name.startswith("_")
    }


def test_sync_and_async_clients_expose_the_same_api() -> None:
    sync = _public_methods(LowcodbClient)
    async_ = _public_methods(AsyncLowcodbClient)
    sync.pop("close")
    async_.pop("aclose")
    assert sync.keys() == async_.keys()
    for name, sig in sync.items():
        assert str(sig) == str(async_[name]), name
        assert inspect.iscoroutinefunction(getattr(AsyncLowcodbClient, name)) or name in {
            "set_org_id",
            "set_header",
        }, name
