"""``/v1/wf/environments`` (mirrors ``resources/environments.ts``)."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from .._base import seg
from .._http import AsyncHttpClient, HttpClient
from ..types import Environment, PaginationQuery

__all__ = ["AsyncEnvironmentsResource", "EnvironmentsResource"]


class EnvironmentsResource:
    """Environments (named variable sets a workflow run executes against)."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list(self, query: PaginationQuery | Mapping[str, Any] | None = None) -> list[Environment]:
        return self._http.request("GET", "/v1/wf/environments", query=query)

    def get_by_id(self, id: str) -> Environment:
        return self._http.request("GET", f"/v1/wf/environments/{seg(id)}")

    def create(self, payload: Environment) -> Environment:
        return self._http.request("POST", "/v1/wf/environments", payload)

    def update(self, id: str, payload: Environment) -> Environment:
        return self._http.request("PUT", f"/v1/wf/environments/{seg(id)}", payload)

    def delete(self, id: str) -> None:
        self._http.request_void("DELETE", f"/v1/wf/environments/{seg(id)}")

    def set_default(self, id: str) -> Environment:
        return self._http.request("PATCH", f"/v1/wf/environments/{seg(id)}/default")


class AsyncEnvironmentsResource:
    """Asyncio variant of :class:`EnvironmentsResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[Environment]:
        return await self._http.request("GET", "/v1/wf/environments", query=query)

    async def get_by_id(self, id: str) -> Environment:
        return await self._http.request("GET", f"/v1/wf/environments/{seg(id)}")

    async def create(self, payload: Environment) -> Environment:
        return await self._http.request("POST", "/v1/wf/environments", payload)

    async def update(self, id: str, payload: Environment) -> Environment:
        return await self._http.request("PUT", f"/v1/wf/environments/{seg(id)}", payload)

    async def delete(self, id: str) -> None:
        await self._http.request_void("DELETE", f"/v1/wf/environments/{seg(id)}")

    async def set_default(self, id: str) -> Environment:
        return await self._http.request("PATCH", f"/v1/wf/environments/{seg(id)}/default")
