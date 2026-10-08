from __future__ import annotations

import inspect
import json
from typing import Any

import httpx
import pytest

from lowcoai.docs import (
    AsyncDocsClient,
    AsyncHttpClient,
    Binary,
    DocsClient,
    DocsError,
    HttpClient,
    NodeFileResult,
    UploadFile,
    resources,
)

from .test_resources import parse_multipart


def make_client(handler: Any, **kwargs: Any) -> AsyncDocsClient:
    return AsyncDocsClient(
        "tok_123",
        org_id="org_1",
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        **kwargs,
    )


async def test_async_request_roundtrip() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"status": 1, "data": [{"id": "f1"}]})

    async with make_client(handler, headers={"X-Trace": "t"}) as client:
        result = await client.folders.create("b", {"parentName": "", "folderName": "a/b"})
    assert result == [{"id": "f1"}]
    req = seen[0]
    assert req.method == "POST"
    assert str(req.url) == "https://api.lowco.ai/v1/documents/b/folder"
    assert req.headers["Authorization"] == "Bearer tok_123"
    assert req.headers["X-Org-Id"] == "org_1"
    assert req.headers["X-Trace"] == "t"
    assert req.headers["Content-Type"] == "application/json"
    assert json.loads(req.content) == {"parentName": "", "folderName": "a/b"}


async def test_async_header_precedence() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(204)

    client = make_client(handler, headers={"authorization": "Bearer other", "X-Org-Id": "org_h"})
    assert await client.triggers.delete("t1") is None  # type: ignore[func-returns-value]
    assert seen[0].headers.get_list("Authorization") == ["Bearer other"]
    assert seen[0].headers.get_list("X-Org-Id") == ["org_h"]
    await client.aclose()


async def test_async_error_mapping() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/stats"):
            return httpx.Response(503, text="upstream down")
        body = {"status": 0, "error": {"message": "AAS-00102", "code": 404, "details": "nope"}}
        return httpx.Response(404, json=body)

    client = make_client(handler)
    with pytest.raises(DocsError) as info:
        await client.nodes.get("n1")
    assert (info.value.status, info.value.message, info.value.code) == (404, "nope", "AAS-00102")
    with pytest.raises(DocsError) as info:
        await client.buckets.stats("b")
    assert (info.value.status, info.value.payload) == (503, "upstream down")
    assert info.value.message == "Request failed with status 503"
    await client.aclose()


async def test_async_transport_error_is_wrapped() -> None:
    cause = httpx.ConnectTimeout("connect timed out")

    def handler(_request: httpx.Request) -> httpx.Response:
        raise cause

    client = make_client(handler)
    with pytest.raises(DocsError) as info:
        await client.files.upload("b", ("a.txt", b"a"))
    assert info.value.status == 0
    assert info.value.payload is None
    assert info.value.message == "connect timed out"
    assert info.value.__cause__ is cause
    await client.aclose()


async def test_async_multipart_upload() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"status": 1, "data": {"nodeId": "n1"}})

    async with make_client(handler) as client:
        result = await client.app_files.upload(
            "invoicing", UploadFile("INV.pdf", b"%PDF"), path="2026", on_conflict="rename"
        )
    assert result == {"nodeId": "n1"}
    assert parse_multipart(seen[0]) == [
        ("path", None, None, b"2026"),
        ("onConflict", None, None, b"rename"),
        ("file", "INV.pdf", "application/pdf", b"%PDF"),
    ]


async def test_async_redirect_binary_and_restoring() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if path.startswith("/v1/documents/b/download/"):
            return httpx.Response(307, headers={"Location": "https://cdn/x"})
        if path.startswith("/v1/documents/b/folder-zip/"):
            return httpx.Response(
                200,
                content=b"PK",
                headers={"Content-Type": "application/zip", "X-File-Name": "a.zip"},
            )
        return httpx.Response(
            202,
            json={"status": 1, "data": {"status": "restoring", "nodeId": "n1"}},
            headers={"Retry-After": "300"},
        )

    async with make_client(handler) as client:
        assert await client.files.download_url("b", "a b.txt") == "https://cdn/x"
        assert await client.folders.download_zip("b", "a") == Binary(
            b"PK", "application/zip", "a.zip"
        )
        assert await client.nodes.content("n1") == NodeFileResult(
            restoring={"status": "restoring", "nodeId": "n1"}, retry_after=300
        )


async def test_async_dot_segments_are_rejected() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(204)

    async with make_client(handler) as client:
        with pytest.raises(DocsError, match="path segment"):
            await client.files.delete("b", "a/../b")
    assert seen == []


async def test_async_close_semantics() -> None:
    owned = AsyncDocsClient("tok", org_id="org")
    async with owned:
        pass
    assert owned._http._http.is_closed

    injected = httpx.AsyncClient(transport=httpx.MockTransport(lambda _r: httpx.Response(204)))
    async with AsyncDocsClient("tok", org_id="org", http_client=injected):
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
        (DocsClient, AsyncDocsClient),
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
    assert sync
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
    assert len(sync_names) == 10
    assert {"Async" + n for n in sync_names} == names - sync_names


def test_clients_expose_the_same_resources() -> None:
    sync = {
        k: type(v).__name__ for k, v in vars(DocsClient("t", org_id="o")).items() if k[0] != "_"
    }
    async_ = {
        k: type(v).__name__
        for k, v in vars(AsyncDocsClient("t", org_id="o")).items()
        if k[0] != "_"
    }
    assert list(sync) == [
        "buckets",
        "folders",
        "files",
        "nodes",
        "library",
        "sharing",
        "automation",
        "app_files",
        "triggers",
        "webhooks",
    ]
    assert async_ == {k: "Async" + v for k, v in sync.items()}
