"""Sync and async HTTP transports (``HttpClient`` in the TS SDK's ``client.ts``)."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

import httpx
from typing_extensions import Self

from ._base import (
    DEFAULT_TIMEOUT,
    BaseHttpClient,
    check_response,
    decode_response,
    encode_body,
    encode_query,
    transport_error,
)
from .types import HttpMethod

__all__ = ["AsyncHttpClient", "HttpClient"]


class HttpClient(BaseHttpClient):
    """Low-level transport used by every resource of :class:`WorkflowClient`.

    Exposed (like the TS ``HttpClient``) for endpoints the SDK does not wrap:
    ``http.request("GET", "/v1/wf/...")`` applies the same headers, envelope
    unwrapping and error mapping as the resource methods.
    """

    def __init__(
        self,
        token: str,
        *,
        org_id: str | None = None,
        timeout: float | None = DEFAULT_TIMEOUT,
        headers: Mapping[str, str] | None = None,
        http_client: httpx.Client | None = None,
    ) -> None:
        super().__init__(token, org_id=org_id, timeout=timeout, headers=headers)
        self._owns_http = http_client is None
        self._http = http_client if http_client is not None else httpx.Client()

    def close(self) -> None:
        """Closes the internally created ``httpx.Client`` (an injected one is left open)."""
        if self._owns_http:
            self._http.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()

    def request(
        self,
        method: HttpMethod,
        path: str,
        body: Any = None,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> Any:
        """Sends a request and returns the decoded payload (``data`` unwrapped).

        ``body=None`` sends no body. Raises :class:`WorkflowError` on a non-2xx
        status (``status`` = HTTP status) or a transport failure (``status`` = 0).
        """
        resp = self._send(method, path, body, query, headers)
        return decode_response(resp.status_code, resp.text)

    def request_void(
        self,
        method: HttpMethod,
        path: str,
        body: Any = None,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> None:
        """Like :meth:`request` but ignores the 2xx response body (JSON or not)."""
        resp = self._send(method, path, body, query, headers)
        check_response(resp.status_code, resp.text)

    def _send(
        self,
        method: str,
        path: str,
        body: Any,
        query: Mapping[str, Any] | None,
        headers: Mapping[str, str] | None,
    ) -> httpx.Response:
        content = encode_body(body)
        try:
            return self._http.request(
                method,
                self._url(path),
                params=encode_query(query),
                content=content,
                headers=self._headers(content is not None, headers),
                timeout=self._timeout,
            )
        except httpx.HTTPError as exc:
            raise transport_error(exc) from exc


class AsyncHttpClient(BaseHttpClient):
    """Asyncio transport used by every resource of :class:`AsyncWorkflowClient`.

    Same surface as :class:`HttpClient`; ``request`` / ``request_void`` are
    coroutines and ``close`` is ``aclose``.
    """

    def __init__(
        self,
        token: str,
        *,
        org_id: str | None = None,
        timeout: float | None = DEFAULT_TIMEOUT,
        headers: Mapping[str, str] | None = None,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        super().__init__(token, org_id=org_id, timeout=timeout, headers=headers)
        self._owns_http = http_client is None
        self._http = http_client if http_client is not None else httpx.AsyncClient()

    async def aclose(self) -> None:
        """Closes the internally created ``httpx.AsyncClient`` (an injected one is left open)."""
        if self._owns_http:
            await self._http.aclose()

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        await self.aclose()

    async def request(
        self,
        method: HttpMethod,
        path: str,
        body: Any = None,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> Any:
        """Sends a request and returns the decoded payload (``data`` unwrapped).

        ``body=None`` sends no body. Raises :class:`WorkflowError` on a non-2xx
        status (``status`` = HTTP status) or a transport failure (``status`` = 0).
        """
        resp = await self._send(method, path, body, query, headers)
        return decode_response(resp.status_code, resp.text)

    async def request_void(
        self,
        method: HttpMethod,
        path: str,
        body: Any = None,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> None:
        """Like :meth:`request` but ignores the 2xx response body (JSON or not)."""
        resp = await self._send(method, path, body, query, headers)
        check_response(resp.status_code, resp.text)

    async def _send(
        self,
        method: str,
        path: str,
        body: Any,
        query: Mapping[str, Any] | None,
        headers: Mapping[str, str] | None,
    ) -> httpx.Response:
        content = encode_body(body)
        try:
            return await self._http.request(
                method,
                self._url(path),
                params=encode_query(query),
                content=content,
                headers=self._headers(content is not None, headers),
                timeout=self._timeout,
            )
        except httpx.HTTPError as exc:
            raise transport_error(exc) from exc
