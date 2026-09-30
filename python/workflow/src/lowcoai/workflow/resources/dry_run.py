"""``/v1/wf/dryrun`` (mirrors ``resources/dryRun.ts``)."""

from __future__ import annotations

from typing import Any

from .._http import AsyncHttpClient, HttpClient
from ..types import DryRunRequest

__all__ = ["AsyncDryRunResource", "DryRunResource"]


class DryRunResource:
    """Evaluates an expression against a past execution's context."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def execute(self, payload: DryRunRequest) -> Any:
        return self._http.request("POST", "/v1/wf/dryrun", payload)


class AsyncDryRunResource:
    """Asyncio variant of :class:`DryRunResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def execute(self, payload: DryRunRequest) -> Any:
        return await self._http.request("POST", "/v1/wf/dryrun", payload)
