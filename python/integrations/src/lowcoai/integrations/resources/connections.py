"""``/v1/integrations/connections`` (mirrors ``resources/connections.ts``)."""

from __future__ import annotations

import builtins
from collections.abc import Mapping
from typing import Any

from .._base import seg
from .._http import AsyncHttpClient, HttpClient
from ..types import Connection, ConnectionResponse, PaginationQuery

__all__ = ["AsyncConnectionsResource", "ConnectionsResource"]


class ConnectionsResource:
    """Connections (credentials) used to call an application."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list(self, query: PaginationQuery | Mapping[str, Any] | None = None) -> list[Connection]:
        return self._http.request("GET", "/v1/integrations/connections", query=query)

    def get_by_id(self, id: str) -> ConnectionResponse:
        return self._http.request("GET", f"/v1/integrations/connections/{seg(id)}")

    def create(self, payload: Connection) -> Connection:
        return self._http.request("POST", "/v1/integrations/connections", payload)

    def update(self, id: str, payload: Connection) -> Connection:
        return self._http.request("PUT", f"/v1/integrations/connections/{seg(id)}", payload)

    def delete(self, id: str) -> None:
        self._http.request_void("DELETE", f"/v1/integrations/connections/{seg(id)}")

    def list_by_application(self, application_id: str) -> builtins.list[Connection]:
        return self._http.request(
            "GET", f"/v1/integrations/applications/{seg(application_id)}/connections"
        )

    def set_as_default(self, id: str, application_id: str) -> Connection:
        """Makes the connection the application's default."""
        return self._http.request(
            "PATCH",
            f"/v1/integrations/connections/{seg(id)}/setDefault",
            {"applicationId": application_id},
        )


class AsyncConnectionsResource:
    """Asyncio variant of :class:`ConnectionsResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[Connection]:
        return await self._http.request("GET", "/v1/integrations/connections", query=query)

    async def get_by_id(self, id: str) -> ConnectionResponse:
        return await self._http.request("GET", f"/v1/integrations/connections/{seg(id)}")

    async def create(self, payload: Connection) -> Connection:
        return await self._http.request("POST", "/v1/integrations/connections", payload)

    async def update(self, id: str, payload: Connection) -> Connection:
        return await self._http.request("PUT", f"/v1/integrations/connections/{seg(id)}", payload)

    async def delete(self, id: str) -> None:
        await self._http.request_void("DELETE", f"/v1/integrations/connections/{seg(id)}")

    async def list_by_application(self, application_id: str) -> builtins.list[Connection]:
        return await self._http.request(
            "GET", f"/v1/integrations/applications/{seg(application_id)}/connections"
        )

    async def set_as_default(self, id: str, application_id: str) -> Connection:
        """Makes the connection the application's default."""
        return await self._http.request(
            "PATCH",
            f"/v1/integrations/connections/{seg(id)}/setDefault",
            {"applicationId": application_id},
        )
