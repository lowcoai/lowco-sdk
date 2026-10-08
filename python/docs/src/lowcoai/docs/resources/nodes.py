"""Nodes by stable id: ``/v1/documents/nodes/{nodeId}`` and permalinks ``/d/{nodeId}``."""

from __future__ import annotations

from .._base import API_PREFIX, flag, seg
from .._http import AsyncHttpClient, HttpClient
from ..types import NodeFileResult, NodeView

__all__ = ["AsyncNodesResource", "NodesResource"]


class NodesResource:
    """Node metadata and permalink resolution by stable node id (survives renames).

    ``resolve`` and ``content`` return a :class:`NodeFileResult`: a file in cold
    storage answers 202 (``restoring`` set) while its restore runs; retry after
    ``retry_after`` seconds.
    """

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def get(self, node_id: str) -> NodeView:
        """Returns a live node the caller can read, with the caller's ``role``."""
        return self._http.request("GET", f"{API_PREFIX}/nodes/{seg(node_id)}")

    def resolve(self, node_id: str, *, download: bool = False) -> NodeFileResult:
        """Resolves a permalink: ``url`` (the 307 ``Location``, not followed) to a fresh
        short-lived URL, ``content`` for a file just restored from cold storage, or
        ``restoring``. ``download=True`` (``?download=1``) makes the URL force a download;
        ``False`` sends no ``download`` parameter (the service treats any value as true)."""
        return self._http.request_node_file(
            "GET", f"{API_PREFIX}/d/{seg(node_id)}", query={"download": flag(download)}
        )

    def content(self, node_id: str) -> NodeFileResult:
        """Streams the file's bytes (``content``) for callers that cannot follow a
        redirect, or ``restoring`` while a cold-storage restore runs."""
        return self._http.request_node_file("GET", f"{API_PREFIX}/d/{seg(node_id)}/content")


class AsyncNodesResource:
    """Asyncio variant of :class:`NodesResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def get(self, node_id: str) -> NodeView:
        """Returns a live node the caller can read, with the caller's ``role``."""
        return await self._http.request("GET", f"{API_PREFIX}/nodes/{seg(node_id)}")

    async def resolve(self, node_id: str, *, download: bool = False) -> NodeFileResult:
        """Resolves a permalink: ``url`` (the 307 ``Location``, not followed) to a fresh
        short-lived URL, ``content`` for a file just restored from cold storage, or
        ``restoring``. ``download=True`` (``?download=1``) makes the URL force a download;
        ``False`` sends no ``download`` parameter (the service treats any value as true)."""
        return await self._http.request_node_file(
            "GET", f"{API_PREFIX}/d/{seg(node_id)}", query={"download": flag(download)}
        )

    async def content(self, node_id: str) -> NodeFileResult:
        """Streams the file's bytes (``content``) for callers that cannot follow a
        redirect, or ``restoring`` while a cold-storage restore runs."""
        return await self._http.request_node_file("GET", f"{API_PREFIX}/d/{seg(node_id)}/content")
