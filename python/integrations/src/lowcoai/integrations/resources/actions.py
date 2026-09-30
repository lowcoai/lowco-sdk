"""``/v1/integrations/actions`` (mirrors ``resources/actions.ts``)."""

from __future__ import annotations

import builtins
from collections.abc import Mapping
from typing import Any

from .._base import seg
from .._http import AsyncHttpClient, HttpClient
from ..types import (
    ApplicationAction,
    ApplicationWithConnection,
    PaginationQuery,
    RunActionRequest,
)

__all__ = ["ActionsResource", "AsyncActionsResource"]


class ActionsResource:
    """Application actions (individual operations an application exposes)."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[ApplicationAction]:
        return self._http.request("GET", "/v1/integrations/actions", query=query)

    def get_by_id(self, id: str) -> ApplicationAction:
        return self._http.request("GET", f"/v1/integrations/actions/{seg(id)}")

    def create(self, application_id: str, payload: ApplicationAction) -> ApplicationAction:
        return self._http.request(
            "POST", f"/v1/integrations/applications/{seg(application_id)}/action", payload
        )

    def update(self, id: str, payload: ApplicationAction) -> ApplicationAction:
        return self._http.request("PUT", f"/v1/integrations/actions/{seg(id)}", payload)

    def delete(self, id: str) -> None:
        self._http.request_void("DELETE", f"/v1/integrations/actions/{seg(id)}")

    def list_by_application(self, application_id: str) -> builtins.list[ApplicationAction]:
        return self._http.request(
            "GET", f"/v1/integrations/applications/{seg(application_id)}/actions"
        )

    def run(self, id: str, payload: RunActionRequest) -> Any:
        return self._http.request("POST", f"/v1/integrations/actions/{seg(id)}/run", payload)

    def resolve_credentials(
        self, action_ids: builtins.list[str]
    ) -> builtins.list[ApplicationWithConnection]:
        """Resolves the applications (with connections) behind ``action_ids``.

        The id list is sent as the raw JSON body.
        """
        return self._http.request("POST", "/v1/integrations/actions/allCredential", action_ids)


class AsyncActionsResource:
    """Asyncio variant of :class:`ActionsResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[ApplicationAction]:
        return await self._http.request("GET", "/v1/integrations/actions", query=query)

    async def get_by_id(self, id: str) -> ApplicationAction:
        return await self._http.request("GET", f"/v1/integrations/actions/{seg(id)}")

    async def create(self, application_id: str, payload: ApplicationAction) -> ApplicationAction:
        return await self._http.request(
            "POST", f"/v1/integrations/applications/{seg(application_id)}/action", payload
        )

    async def update(self, id: str, payload: ApplicationAction) -> ApplicationAction:
        return await self._http.request("PUT", f"/v1/integrations/actions/{seg(id)}", payload)

    async def delete(self, id: str) -> None:
        await self._http.request_void("DELETE", f"/v1/integrations/actions/{seg(id)}")

    async def list_by_application(self, application_id: str) -> builtins.list[ApplicationAction]:
        return await self._http.request(
            "GET", f"/v1/integrations/applications/{seg(application_id)}/actions"
        )

    async def run(self, id: str, payload: RunActionRequest) -> Any:
        return await self._http.request("POST", f"/v1/integrations/actions/{seg(id)}/run", payload)

    async def resolve_credentials(
        self, action_ids: builtins.list[str]
    ) -> builtins.list[ApplicationWithConnection]:
        """Resolves the applications (with connections) behind ``action_ids``.

        The id list is sent as the raw JSON body.
        """
        return await self._http.request(
            "POST", "/v1/integrations/actions/allCredential", action_ids
        )
