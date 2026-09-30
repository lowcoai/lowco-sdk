from __future__ import annotations

import inspect
import json
from datetime import datetime, timezone
from typing import Any

import httpx
import pytest

from lowcoai.engage import AsyncEngageClient, EngageClient, EngageError


def make_client(handler: Any, **kwargs: Any) -> AsyncEngageClient:
    return AsyncEngageClient(
        "key_123",
        "org_1",
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        **kwargs,
    )


async def test_async_track_page_identify() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"status": 1, "data": None})

    when = datetime(2026, 9, 30, 1, 2, 3, 4000, tzinfo=timezone.utc)
    async with make_client(handler, device_id="dev_1") as client:
        await client.track("signup", {"plan": "pro"}, user_id="u1", event_time=when)
        await client.page({"path": "/"})
        await client.identify_user("u1", {"email": "a@b.c"}, device_id="dev_2")

    assert [r.method for r in seen] == ["POST"] * 3
    assert all(str(r.url) == "https://api.lowco.ai/v1/engage/track" for r in seen)
    assert seen[0].headers["Authorization"] == "Bearer key_123"
    assert seen[0].headers["X-Org-Id"] == "org_1"
    assert seen[0].headers["Content-Type"] == "application/json"
    bodies = [json.loads(r.content) for r in seen]
    assert bodies[0] == {
        "id": "",
        "event_name": "signup",
        "event_data": {"plan": "pro"},
        "user_id": "u1",
        "device_id": "dev_1",
        "event_time": "2026-09-30T01:02:03.004Z",
    }
    assert bodies[1]["event_name"] == "page_view"
    assert "user_id" not in bodies[1]
    assert bodies[2]["event_name"] == "_lowco_identify"
    assert bodies[2]["user_id"] == "u1"
    assert bodies[2]["device_id"] == "dev_2"


async def test_async_error_mapping() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            500, json={"error": {"code": 500, "message": "AAS-00105", "details": "nats down"}}
        )

    client = make_client(handler)
    with pytest.raises(EngageError) as info:
        await client.track("x")
    assert info.value.status_code == 500
    assert info.value.message == "nats down"
    with pytest.raises(ValueError):
        await client.identify_user(" ")
    await client.aclose()


async def test_async_injected_client_is_not_closed() -> None:
    http = httpx.AsyncClient(transport=httpx.MockTransport(lambda _r: httpx.Response(200)))
    async with AsyncEngageClient("k", "o", http_client=http) as client:
        await client.track("x")
    assert not http.is_closed
    await http.aclose()


def _public_methods(cls: type) -> dict[str, inspect.Signature]:
    return {
        name: inspect.signature(fn)
        for name, fn in inspect.getmembers(cls, inspect.isfunction)
        if not name.startswith("_")
    }


def test_sync_and_async_clients_expose_the_same_api() -> None:
    sync = _public_methods(EngageClient)
    async_ = _public_methods(AsyncEngageClient)
    sync.pop("close")
    async_.pop("aclose")
    assert sync.keys() == async_.keys() == {"track", "page", "identify_user"}
    for name, sig in sync.items():
        assert str(sig) == str(async_[name]), name
        assert inspect.iscoroutinefunction(getattr(AsyncEngageClient, name)), name
    assert inspect.signature(EngageClient.__init__).parameters.keys() == (
        inspect.signature(AsyncEngageClient.__init__).parameters.keys()
    )
    assert isinstance(EngageClient.device_id, property)
    assert isinstance(AsyncEngageClient.device_id, property)
