"""``/v1/wf/analytics`` (mirrors ``resources/analytics.ts``)."""

from __future__ import annotations

from typing import Any

from .._base import seg
from .._http import AsyncHttpClient, HttpClient

__all__ = ["AnalyticsResource", "AsyncAnalyticsResource"]


class AnalyticsResource:
    """Execution analytics."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def default(self) -> dict[str, Any]:
        """Org-wide analytics (``GET /v1/wf/analytics``)."""
        return self._http.request("GET", "/v1/wf/analytics")

    def get_by_id(self, id: str) -> dict[str, Any]:
        return self._http.request("GET", f"/v1/wf/analytics/{seg(id)}")


class AsyncAnalyticsResource:
    """Asyncio variant of :class:`AnalyticsResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def default(self) -> dict[str, Any]:
        """Org-wide analytics (``GET /v1/wf/analytics``)."""
        return await self._http.request("GET", "/v1/wf/analytics")

    async def get_by_id(self, id: str) -> dict[str, Any]:
        return await self._http.request("GET", f"/v1/wf/analytics/{seg(id)}")
