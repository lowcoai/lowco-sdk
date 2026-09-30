"""``/v1/wf/executions`` (mirrors ``resources/executions.ts``)."""

from __future__ import annotations

import builtins
from collections.abc import Mapping
from typing import Any

from .._base import seg
from .._http import AsyncHttpClient, HttpClient
from ..types import Execution, ListExecutionsQuery, PaginationQuery

__all__ = ["AsyncExecutionsResource", "ExecutionsResource"]


class ExecutionsResource:
    """Workflow executions (runs) and their logs."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list(self, query: ListExecutionsQuery | Mapping[str, Any] | None = None) -> list[Execution]:
        """Lists executions; ``query`` also accepts ``full`` (bool)."""
        return self._http.request("GET", "/v1/wf/executions", query=query)

    def count(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> int | dict[str, Any]:
        return self._http.request("GET", "/v1/wf/executions/count", query=query)

    def get_by_id(self, id: str) -> Execution:
        return self._http.request("GET", f"/v1/wf/executions/{seg(id)}")

    def logs(self, id: str) -> builtins.list[Any]:
        return self._http.request("GET", f"/v1/wf/executions/{seg(id)}/logs")


class AsyncExecutionsResource:
    """Asyncio variant of :class:`ExecutionsResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list(
        self, query: ListExecutionsQuery | Mapping[str, Any] | None = None
    ) -> list[Execution]:
        """Lists executions; ``query`` also accepts ``full`` (bool)."""
        return await self._http.request("GET", "/v1/wf/executions", query=query)

    async def count(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> int | dict[str, Any]:
        return await self._http.request("GET", "/v1/wf/executions/count", query=query)

    async def get_by_id(self, id: str) -> Execution:
        return await self._http.request("GET", f"/v1/wf/executions/{seg(id)}")

    async def logs(self, id: str) -> builtins.list[Any]:
        return await self._http.request("GET", f"/v1/wf/executions/{seg(id)}/logs")
