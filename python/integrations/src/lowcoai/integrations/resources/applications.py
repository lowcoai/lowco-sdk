"""``/v1/integrations/applications`` (mirrors ``resources/applications.ts``)."""

from __future__ import annotations

import builtins
from collections.abc import Mapping
from typing import Any

from .._base import seg
from .._http import AsyncHttpClient, HttpClient
from ..types import (
    Application,
    ApplicationAction,
    ApplicationHistory,
    ApplicationWithCount,
    McpToolsResponse,
    PaginationQuery,
    PostmanFolder,
    RunApplicationRequest,
    SubApplicationConfig,
)

__all__ = ["ApplicationsResource", "AsyncApplicationsResource"]


class ApplicationsResource:
    """Applications (HTTP APIs, databases, queues, storage, ...) and their MCP exposure."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[ApplicationWithCount]:
        return self._http.request("GET", "/v1/integrations/applications", query=query)

    def get_by_id(self, id: str) -> Application:
        return self._http.request("GET", f"/v1/integrations/applications/{seg(id)}")

    def create(self, payload: Application) -> Application:
        return self._http.request("POST", "/v1/integrations/applications", payload)

    def update(self, id: str, payload: Application) -> Application:
        return self._http.request("PUT", f"/v1/integrations/applications/{seg(id)}", payload)

    def delete(self, id: str) -> None:
        self._http.request_void("DELETE", f"/v1/integrations/applications/{seg(id)}")

    def patch_tags(self, id: str, tags: builtins.list[str]) -> Application:
        """Replaces the application's tags."""
        return self._http.request(
            "PATCH", f"/v1/integrations/applications/{seg(id)}/tags", {"tags": tags}
        )

    def run(self, id: str, payload: RunApplicationRequest) -> Any:
        return self._http.request("POST", f"/v1/integrations/applications/{seg(id)}/run", payload)

    def load_actions(self, id: str, folder: PostmanFolder) -> builtins.list[ApplicationAction]:
        """Imports actions from a Postman collection folder."""
        return self._http.request(
            "POST", f"/v1/integrations/applications/{seg(id)}/load-actions", folder
        )

    def versions(
        self, id: str, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> builtins.list[ApplicationHistory]:
        return self._http.request(
            "GET", f"/v1/integrations/applications/{seg(id)}/versions", query=query
        )

    def regenerate_mcp_key(self, id: str) -> Application:
        return self._http.request(
            "GET", f"/v1/integrations/applications/{seg(id)}/regenerate-mcp-key"
        )

    def get_mcp_tools(self, id: str) -> McpToolsResponse:
        return self._http.request("GET", f"/v1/integrations/applications/{seg(id)}/mcp/tools")

    def get_sub_applications(self) -> SubApplicationConfig:
        """Application type -> supported sub types."""
        return self._http.request("GET", "/v1/integrations/applications/types")

    def get_applications_with_triggers(self) -> builtins.list[Application]:
        return self._http.request("GET", "/v1/integrations/applications/by-trigger")


class AsyncApplicationsResource:
    """Asyncio variant of :class:`ApplicationsResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[ApplicationWithCount]:
        return await self._http.request("GET", "/v1/integrations/applications", query=query)

    async def get_by_id(self, id: str) -> Application:
        return await self._http.request("GET", f"/v1/integrations/applications/{seg(id)}")

    async def create(self, payload: Application) -> Application:
        return await self._http.request("POST", "/v1/integrations/applications", payload)

    async def update(self, id: str, payload: Application) -> Application:
        return await self._http.request("PUT", f"/v1/integrations/applications/{seg(id)}", payload)

    async def delete(self, id: str) -> None:
        await self._http.request_void("DELETE", f"/v1/integrations/applications/{seg(id)}")

    async def patch_tags(self, id: str, tags: builtins.list[str]) -> Application:
        """Replaces the application's tags."""
        return await self._http.request(
            "PATCH", f"/v1/integrations/applications/{seg(id)}/tags", {"tags": tags}
        )

    async def run(self, id: str, payload: RunApplicationRequest) -> Any:
        return await self._http.request(
            "POST", f"/v1/integrations/applications/{seg(id)}/run", payload
        )

    async def load_actions(
        self, id: str, folder: PostmanFolder
    ) -> builtins.list[ApplicationAction]:
        """Imports actions from a Postman collection folder."""
        return await self._http.request(
            "POST", f"/v1/integrations/applications/{seg(id)}/load-actions", folder
        )

    async def versions(
        self, id: str, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> builtins.list[ApplicationHistory]:
        return await self._http.request(
            "GET", f"/v1/integrations/applications/{seg(id)}/versions", query=query
        )

    async def regenerate_mcp_key(self, id: str) -> Application:
        return await self._http.request(
            "GET", f"/v1/integrations/applications/{seg(id)}/regenerate-mcp-key"
        )

    async def get_mcp_tools(self, id: str) -> McpToolsResponse:
        return await self._http.request("GET", f"/v1/integrations/applications/{seg(id)}/mcp/tools")

    async def get_sub_applications(self) -> SubApplicationConfig:
        """Application type -> supported sub types."""
        return await self._http.request("GET", "/v1/integrations/applications/types")

    async def get_applications_with_triggers(self) -> builtins.list[Application]:
        return await self._http.request("GET", "/v1/integrations/applications/by-trigger")
