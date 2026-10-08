"""Sync and async HTTP transports behind :class:`DocsClient` / :class:`AsyncDocsClient`."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any

import httpx
from typing_extensions import Self

from ._base import (
    ACCEPT_ANY,
    ACCEPT_JSON,
    DEFAULT_TIMEOUT,
    BaseHttpClient,
    BodyKind,
    MultipartFields,
    check_response,
    decode_binary,
    decode_node_file,
    decode_redirect,
    decode_response,
    decode_text,
    encode_body,
    encode_multipart,
    encode_query,
    transport_error,
)
from .types import Binary, FileInput, HttpMethod, NodeFileResult

__all__ = ["AsyncHttpClient", "HttpClient"]


class HttpClient(BaseHttpClient):
    """Low-level transport used by every resource of :class:`DocsClient`.

    Exposed for endpoints the SDK does not wrap: ``http.request("GET",
    "/v1/documents/...")`` applies the same headers, envelope unwrapping and
    error mapping as the resource methods. Redirects are never followed.
    """

    def __init__(
        self,
        token: str,
        *,
        org_id: str,
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
        """Sends a JSON request and returns the decoded payload (``data`` unwrapped).

        ``body=None`` sends no body. Raises :class:`DocsError` on a non-2xx
        status (``status`` = HTTP status) or a transport failure (``status`` = 0).
        """
        resp = self._send(method, path, query, headers, body=body)
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
        resp = self._send(method, path, query, headers, body=body)
        check_response(resp.status_code, resp.text)

    def request_text(
        self,
        method: HttpMethod,
        path: str,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> str:
        """Sends a request and returns the 2xx body as text."""
        resp = self._send(method, path, query, headers, accept=ACCEPT_ANY)
        return decode_text(resp.status_code, resp.text)

    def request_binary(
        self,
        method: HttpMethod,
        path: str,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> Binary:
        """Sends a request and returns the 2xx body as :class:`Binary`."""
        return decode_binary(self._send(method, path, query, headers, accept=ACCEPT_ANY))

    def request_redirect(
        self,
        method: HttpMethod,
        path: str,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> str:
        """Sends a request without following the redirect and returns its ``Location``."""
        return decode_redirect(self._send(method, path, query, headers, accept=ACCEPT_ANY))

    def request_node_file(
        self,
        method: HttpMethod,
        path: str,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> NodeFileResult:
        """Sends a request and maps 307 / 202 / 200 to a :class:`NodeFileResult`."""
        return decode_node_file(self._send(method, path, query, headers, accept=ACCEPT_ANY))

    def request_multipart(
        self,
        method: HttpMethod,
        path: str,
        files: Sequence[tuple[str, FileInput]],
        fields: MultipartFields | None = None,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> Any:
        """Sends ``multipart/form-data`` (``(field, file)`` parts plus text
        ``fields``) and returns the decoded payload (``data`` unwrapped)."""
        resp = self._send(method, path, query, headers, multipart=(files, fields))
        return decode_response(resp.status_code, resp.text)

    def _send(
        self,
        method: str,
        path: str,
        query: Mapping[str, Any] | None,
        headers: Mapping[str, str] | None,
        *,
        body: Any = None,
        multipart: tuple[Sequence[tuple[str, FileInput]], MultipartFields | None] | None = None,
        accept: str = ACCEPT_JSON,
    ) -> httpx.Response:
        content = encode_body(body)
        files, data = encode_multipart(*multipart) if multipart is not None else (None, None)
        kind: BodyKind = (
            "multipart" if multipart is not None else "json" if content is not None else "none"
        )
        try:
            return self._http.request(
                method,
                self._url(path),
                params=encode_query(query),
                content=content,
                data=data,
                files=files,
                headers=self._headers(kind, accept, headers),
                timeout=self._timeout,
                follow_redirects=False,
            )
        except httpx.HTTPError as exc:
            raise transport_error(exc) from exc


class AsyncHttpClient(BaseHttpClient):
    """Asyncio transport used by every resource of :class:`AsyncDocsClient`.

    Same surface as :class:`HttpClient`; the ``request*`` methods are
    coroutines and ``close`` is ``aclose``.
    """

    def __init__(
        self,
        token: str,
        *,
        org_id: str,
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
        """Sends a JSON request and returns the decoded payload (``data`` unwrapped).

        ``body=None`` sends no body. Raises :class:`DocsError` on a non-2xx
        status (``status`` = HTTP status) or a transport failure (``status`` = 0).
        """
        resp = await self._send(method, path, query, headers, body=body)
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
        resp = await self._send(method, path, query, headers, body=body)
        check_response(resp.status_code, resp.text)

    async def request_text(
        self,
        method: HttpMethod,
        path: str,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> str:
        """Sends a request and returns the 2xx body as text."""
        resp = await self._send(method, path, query, headers, accept=ACCEPT_ANY)
        return decode_text(resp.status_code, resp.text)

    async def request_binary(
        self,
        method: HttpMethod,
        path: str,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> Binary:
        """Sends a request and returns the 2xx body as :class:`Binary`."""
        return decode_binary(await self._send(method, path, query, headers, accept=ACCEPT_ANY))

    async def request_redirect(
        self,
        method: HttpMethod,
        path: str,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> str:
        """Sends a request without following the redirect and returns its ``Location``."""
        return decode_redirect(await self._send(method, path, query, headers, accept=ACCEPT_ANY))

    async def request_node_file(
        self,
        method: HttpMethod,
        path: str,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> NodeFileResult:
        """Sends a request and maps 307 / 202 / 200 to a :class:`NodeFileResult`."""
        return decode_node_file(await self._send(method, path, query, headers, accept=ACCEPT_ANY))

    async def request_multipart(
        self,
        method: HttpMethod,
        path: str,
        files: Sequence[tuple[str, FileInput]],
        fields: MultipartFields | None = None,
        *,
        query: Mapping[str, Any] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> Any:
        """Sends ``multipart/form-data`` (``(field, file)`` parts plus text
        ``fields``) and returns the decoded payload (``data`` unwrapped)."""
        resp = await self._send(method, path, query, headers, multipart=(files, fields))
        return decode_response(resp.status_code, resp.text)

    async def _send(
        self,
        method: str,
        path: str,
        query: Mapping[str, Any] | None,
        headers: Mapping[str, str] | None,
        *,
        body: Any = None,
        multipart: tuple[Sequence[tuple[str, FileInput]], MultipartFields | None] | None = None,
        accept: str = ACCEPT_JSON,
    ) -> httpx.Response:
        content = encode_body(body)
        files, data = encode_multipart(*multipart) if multipart is not None else (None, None)
        kind: BodyKind = (
            "multipart" if multipart is not None else "json" if content is not None else "none"
        )
        try:
            return await self._http.request(
                method,
                self._url(path),
                params=encode_query(query),
                content=content,
                data=data,
                files=files,
                headers=self._headers(kind, accept, headers),
                timeout=self._timeout,
                follow_redirects=False,
            )
        except httpx.HTTPError as exc:
            raise transport_error(exc) from exc
