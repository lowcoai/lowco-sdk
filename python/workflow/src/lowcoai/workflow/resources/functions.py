"""``/v1/wf/functions`` (mirrors ``resources/functions.ts``)."""

from __future__ import annotations

import builtins
from collections.abc import Mapping
from typing import Any

from .._base import seg
from .._http import AsyncHttpClient, HttpClient
from ..types import FunctionEntity, FunctionVersionRequest, PaginationQuery

__all__ = ["AsyncFunctionsResource", "FunctionsResource"]


class FunctionsResource:
    """Reusable script functions callable from workflows."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[FunctionEntity]:
        return self._http.request("GET", "/v1/wf/functions", query=query)

    def get_by_id(self, id: str) -> FunctionEntity:
        return self._http.request("GET", f"/v1/wf/functions/{seg(id)}")

    def create(self, payload: FunctionEntity) -> FunctionEntity:
        return self._http.request("POST", "/v1/wf/functions", payload)

    def update(self, id: str, payload: FunctionVersionRequest) -> FunctionEntity:
        return self._http.request("PUT", f"/v1/wf/functions/{seg(id)}", payload)

    def delete(self, id: str) -> None:
        self._http.request_void("DELETE", f"/v1/wf/functions/{seg(id)}")

    def versions(
        self, id: str, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> builtins.list[FunctionEntity]:
        return self._http.request("GET", f"/v1/wf/functions/{seg(id)}/versions", query=query)

    def execute(self, id: str, params: Mapping[str, Any] | None = None) -> dict[str, Any]:
        """Runs the function; ``params`` defaults to ``{}``."""
        return self._http.request(
            "POST", f"/v1/wf/functions/{seg(id)}/execute", {} if params is None else params
        )


class AsyncFunctionsResource:
    """Asyncio variant of :class:`FunctionsResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[FunctionEntity]:
        return await self._http.request("GET", "/v1/wf/functions", query=query)

    async def get_by_id(self, id: str) -> FunctionEntity:
        return await self._http.request("GET", f"/v1/wf/functions/{seg(id)}")

    async def create(self, payload: FunctionEntity) -> FunctionEntity:
        return await self._http.request("POST", "/v1/wf/functions", payload)

    async def update(self, id: str, payload: FunctionVersionRequest) -> FunctionEntity:
        return await self._http.request("PUT", f"/v1/wf/functions/{seg(id)}", payload)

    async def delete(self, id: str) -> None:
        await self._http.request_void("DELETE", f"/v1/wf/functions/{seg(id)}")

    async def versions(
        self, id: str, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> builtins.list[FunctionEntity]:
        return await self._http.request("GET", f"/v1/wf/functions/{seg(id)}/versions", query=query)

    async def execute(self, id: str, params: Mapping[str, Any] | None = None) -> dict[str, Any]:
        """Runs the function; ``params`` defaults to ``{}``."""
        return await self._http.request(
            "POST", f"/v1/wf/functions/{seg(id)}/execute", {} if params is None else params
        )
