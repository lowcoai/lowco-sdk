"""``/v1/integrations/triggers`` (mirrors ``resources/triggers.ts``)."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from .._base import seg
from .._http import AsyncHttpClient, HttpClient
from ..types import ApplicationTrigger, PaginationQuery, TriggerState

__all__ = ["AsyncTriggersResource", "TriggersResource"]


class TriggersResource:
    """Application triggers (events that start workflows) and their poll state."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list_by_application(
        self, application_id: str, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[ApplicationTrigger]:
        return self._http.request(
            "GET",
            f"/v1/integrations/applications/{seg(application_id)}/triggers",
            query=query,
        )

    def get_by_id(self, id: str) -> ApplicationTrigger:
        return self._http.request("GET", f"/v1/integrations/triggers/{seg(id)}")

    def create(self, payload: ApplicationTrigger) -> ApplicationTrigger:
        return self._http.request("POST", "/v1/integrations/triggers", payload)

    def update(self, id: str, payload: ApplicationTrigger) -> ApplicationTrigger:
        return self._http.request("PUT", f"/v1/integrations/triggers/{seg(id)}", payload)

    def delete(self, id: str) -> None:
        self._http.request_void("DELETE", f"/v1/integrations/triggers/{seg(id)}")

    def get_state(self, id: str) -> TriggerState:
        return self._http.request("GET", f"/v1/integrations/triggers/{seg(id)}/state")


class AsyncTriggersResource:
    """Asyncio variant of :class:`TriggersResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list_by_application(
        self, application_id: str, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[ApplicationTrigger]:
        return await self._http.request(
            "GET",
            f"/v1/integrations/applications/{seg(application_id)}/triggers",
            query=query,
        )

    async def get_by_id(self, id: str) -> ApplicationTrigger:
        return await self._http.request("GET", f"/v1/integrations/triggers/{seg(id)}")

    async def create(self, payload: ApplicationTrigger) -> ApplicationTrigger:
        return await self._http.request("POST", "/v1/integrations/triggers", payload)

    async def update(self, id: str, payload: ApplicationTrigger) -> ApplicationTrigger:
        return await self._http.request("PUT", f"/v1/integrations/triggers/{seg(id)}", payload)

    async def delete(self, id: str) -> None:
        await self._http.request_void("DELETE", f"/v1/integrations/triggers/{seg(id)}")

    async def get_state(self, id: str) -> TriggerState:
        return await self._http.request("GET", f"/v1/integrations/triggers/{seg(id)}/state")
