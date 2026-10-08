"""``/v1/documents/triggers``."""

from __future__ import annotations

import builtins

from .._base import API_PREFIX, seg
from .._http import AsyncHttpClient, HttpClient
from ..types import Trigger, TriggerRequest

__all__ = ["AsyncTriggersResource", "TriggersResource"]

_PATH = f"{API_PREFIX}/triggers"


class TriggersResource:
    """Workflow triggers: run a workflow when an object event happens under a prefix."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list(self) -> builtins.list[Trigger]:
        """Lists the org's triggers visible to the caller."""
        return self._http.request("GET", _PATH)

    def create(self, body: TriggerRequest) -> Trigger:
        """Creates a trigger (``prefix`` and ``workflowId`` are required)."""
        return self._http.request("POST", _PATH, body)

    def get(self, id: str) -> Trigger:
        """Returns one trigger."""
        return self._http.request("GET", f"{_PATH}/{seg(id)}")

    def update(self, id: str, body: TriggerRequest) -> Trigger:
        """Replaces every field of a trigger (it keeps its author)."""
        return self._http.request("PUT", f"{_PATH}/{seg(id)}", body)

    def delete(self, id: str) -> None:
        """Deletes a trigger."""
        self._http.request_void("DELETE", f"{_PATH}/{seg(id)}")


class AsyncTriggersResource:
    """Asyncio variant of :class:`TriggersResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list(self) -> builtins.list[Trigger]:
        """Lists the org's triggers visible to the caller."""
        return await self._http.request("GET", _PATH)

    async def create(self, body: TriggerRequest) -> Trigger:
        """Creates a trigger (``prefix`` and ``workflowId`` are required)."""
        return await self._http.request("POST", _PATH, body)

    async def get(self, id: str) -> Trigger:
        """Returns one trigger."""
        return await self._http.request("GET", f"{_PATH}/{seg(id)}")

    async def update(self, id: str, body: TriggerRequest) -> Trigger:
        """Replaces every field of a trigger (it keeps its author)."""
        return await self._http.request("PUT", f"{_PATH}/{seg(id)}", body)

    async def delete(self, id: str) -> None:
        """Deletes a trigger."""
        await self._http.request_void("DELETE", f"{_PATH}/{seg(id)}")
