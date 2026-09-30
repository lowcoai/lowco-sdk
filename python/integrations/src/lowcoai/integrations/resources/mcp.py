"""Published MCP endpoints of applications (mirrors ``resources/mcp.ts``)."""

from __future__ import annotations

from typing import Any

from .._base import seg
from .._http import AsyncHttpClient, HttpClient
from ..types import JsonRpcRequest, JsonRpcResponse

__all__ = ["AsyncMcpResource", "McpResource"]


class McpResource:
    """JSON-RPC (MCP) calls against an application published under its MCP key."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def call_published(self, key: str, payload: JsonRpcRequest) -> JsonRpcResponse:
        return self._http.request(
            "POST", f"/v1/integrations/applications/published/{seg(key)}", payload
        )

    def info_published(self, key: str) -> dict[str, Any]:
        return self._http.request("GET", f"/v1/integrations/applications/published/{seg(key)}")


class AsyncMcpResource:
    """Asyncio variant of :class:`McpResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def call_published(self, key: str, payload: JsonRpcRequest) -> JsonRpcResponse:
        return await self._http.request(
            "POST", f"/v1/integrations/applications/published/{seg(key)}", payload
        )

    async def info_published(self, key: str) -> dict[str, Any]:
        return await self._http.request(
            "GET", f"/v1/integrations/applications/published/{seg(key)}"
        )
