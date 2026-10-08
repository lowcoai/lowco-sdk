"""``/v1/wf/human-tasks`` (mirrors ``resources/humanTasks.ts``)."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from .._base import seg
from .._http import AsyncHttpClient, HttpClient
from ..types import HumanTask, PaginationQuery

__all__ = ["AsyncHumanTasksResource", "HumanTasksResource"]


class HumanTasksResource:
    """Human-in-the-loop tasks raised by Human Task nodes."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list(self, query: PaginationQuery | Mapping[str, Any] | None = None) -> list[HumanTask]:
        return self._http.request("GET", "/v1/wf/human-tasks", query=query)

    def get_by_id(self, id: str) -> HumanTask:
        return self._http.request("GET", f"/v1/wf/human-tasks/{seg(id)}")

    def complete(self, id: str, action: str) -> HumanTask:
        """Answers the task with one of its action values; the workflow resumes."""
        return self._http.request(
            "PATCH", f"/v1/wf/human-tasks/{seg(id)}/complete", {"action": action}
        )


class AsyncHumanTasksResource:
    """Asyncio variant of :class:`HumanTasksResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[HumanTask]:
        return await self._http.request("GET", "/v1/wf/human-tasks", query=query)

    async def get_by_id(self, id: str) -> HumanTask:
        return await self._http.request("GET", f"/v1/wf/human-tasks/{seg(id)}")

    async def complete(self, id: str, action: str) -> HumanTask:
        """Answers the task with one of its action values; the workflow resumes."""
        return await self._http.request(
            "PATCH", f"/v1/wf/human-tasks/{seg(id)}/complete", {"action": action}
        )
