"""HTTP transports shared by the three sub-clients of one top-level client."""

from __future__ import annotations

from collections.abc import AsyncIterator, Iterator
from contextlib import asynccontextmanager, contextmanager
from typing import Any

import httpx

from ._base import (
    ACCEPT_JSON,
    BASE_URL,
    check_status,
    decode_response,
    encode_body,
    is_success,
    request_headers,
)
from ._errors import build_http_error


class _TransportConfig:
    def __init__(self, headers: dict[str, str], timeout: float | None) -> None:
        # Mutable header bag: the top-level client owns it and mutates it in place
        # (set_org_id / set_header), so every sub-client sees the change.
        self.headers = headers
        self.timeout = timeout

    @staticmethod
    def url(path: str) -> str:
        return BASE_URL + path

    def stream_timeout(self) -> httpx.Timeout:
        # Connect / write / pool keep the configured timeout; reading a
        # long-lived event stream must not time out between events.
        return httpx.Timeout(self.timeout, read=None)


class SyncTransport(_TransportConfig):
    def __init__(
        self, headers: dict[str, str], timeout: float | None, http_client: httpx.Client | None
    ) -> None:
        super().__init__(headers, timeout)
        self.owns_http = http_client is None
        self.http = http_client if http_client is not None else httpx.Client()

    def close(self) -> None:
        if self.owns_http:
            self.http.close()

    def send(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, str] | None = None,
        body: Any = None,
    ) -> httpx.Response:
        content = encode_body(body)
        return self.http.request(
            method,
            self.url(path),
            params=query or None,
            content=content,
            headers=request_headers(self.headers, ACCEPT_JSON, content is not None),
            timeout=self.timeout,
        )

    def request(
        self,
        method: str,
        path: str,
        *,
        enveloped: bool,
        query: dict[str, str] | None = None,
        body: Any = None,
    ) -> Any:
        resp = self.send(method, path, query=query, body=body)
        return decode_response(resp.status_code, resp.text, enveloped=enveloped)

    def request_void(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, str] | None = None,
        body: Any = None,
    ) -> None:
        resp = self.send(method, path, query=query, body=body)
        check_status(resp.status_code, resp.text)

    @contextmanager
    def stream(self, method: str, path: str, *, body: Any, accept: str) -> Iterator[httpx.Response]:
        content = encode_body(body)
        with self.http.stream(
            method,
            self.url(path),
            content=content,
            headers=request_headers(self.headers, accept, content is not None),
            timeout=self.stream_timeout(),
        ) as resp:
            if not is_success(resp.status_code):
                resp.read()
                raise build_http_error(resp.status_code, resp.text)
            yield resp


class AsyncTransport(_TransportConfig):
    def __init__(
        self,
        headers: dict[str, str],
        timeout: float | None,
        http_client: httpx.AsyncClient | None,
    ) -> None:
        super().__init__(headers, timeout)
        self.owns_http = http_client is None
        self.http = http_client if http_client is not None else httpx.AsyncClient()

    async def aclose(self) -> None:
        if self.owns_http:
            await self.http.aclose()

    async def send(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, str] | None = None,
        body: Any = None,
    ) -> httpx.Response:
        content = encode_body(body)
        return await self.http.request(
            method,
            self.url(path),
            params=query or None,
            content=content,
            headers=request_headers(self.headers, ACCEPT_JSON, content is not None),
            timeout=self.timeout,
        )

    async def request(
        self,
        method: str,
        path: str,
        *,
        enveloped: bool,
        query: dict[str, str] | None = None,
        body: Any = None,
    ) -> Any:
        resp = await self.send(method, path, query=query, body=body)
        return decode_response(resp.status_code, resp.text, enveloped=enveloped)

    async def request_void(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, str] | None = None,
        body: Any = None,
    ) -> None:
        resp = await self.send(method, path, query=query, body=body)
        check_status(resp.status_code, resp.text)

    @asynccontextmanager
    async def stream(
        self, method: str, path: str, *, body: Any, accept: str
    ) -> AsyncIterator[httpx.Response]:
        content = encode_body(body)
        async with self.http.stream(
            method,
            self.url(path),
            content=content,
            headers=request_headers(self.headers, accept, content is not None),
            timeout=self.stream_timeout(),
        ) as resp:
            if not is_success(resp.status_code):
                await resp.aread()
                raise build_http_error(resp.status_code, resp.text)
            yield resp
