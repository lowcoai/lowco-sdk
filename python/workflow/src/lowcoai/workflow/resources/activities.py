"""``/v1/wf/activities`` (mirrors ``resources/activities.ts``)."""

from __future__ import annotations

import builtins
from collections.abc import Mapping
from typing import Any

from .._base import seg
from .._http import AsyncHttpClient, HttpClient
from ..types import ActivityHistoryResponse, PaginationQuery

__all__ = ["ActivitiesResource", "AsyncActivitiesResource"]


class ActivitiesResource:
    """Per-activity execution history and logs."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[ActivityHistoryResponse]:
        return self._http.request("GET", "/v1/wf/activities", query=query)

    def count(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> int | dict[str, Any]:
        return self._http.request("GET", "/v1/wf/activities/count", query=query)

    def get_by_id(self, id: str) -> ActivityHistoryResponse:
        return self._http.request("GET", f"/v1/wf/activities/{seg(id)}")

    def logs(self, id: str) -> builtins.list[Any]:
        return self._http.request("GET", f"/v1/wf/activities/{seg(id)}/logs")


class AsyncActivitiesResource:
    """Asyncio variant of :class:`ActivitiesResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[ActivityHistoryResponse]:
        return await self._http.request("GET", "/v1/wf/activities", query=query)

    async def count(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> int | dict[str, Any]:
        return await self._http.request("GET", "/v1/wf/activities/count", query=query)

    async def get_by_id(self, id: str) -> ActivityHistoryResponse:
        return await self._http.request("GET", f"/v1/wf/activities/{seg(id)}")

    async def logs(self, id: str) -> builtins.list[Any]:
        return await self._http.request("GET", f"/v1/wf/activities/{seg(id)}/logs")
