"""Stars, recent items and trash under ``/v1/documents/{bucket}``."""

from __future__ import annotations

from typing import Any

from .._base import API_PREFIX, seg
from .._http import AsyncHttpClient, HttpClient
from ..types import Document, ItemType

__all__ = ["AsyncLibraryResource", "LibraryResource"]


def _b(bucket: str) -> str:
    return f"{API_PREFIX}/{seg(bucket)}"


def _star_body(path: str, type: ItemType | None) -> dict[str, Any]:
    body: dict[str, Any] = {"path": path}
    if type is not None:
        body["type"] = type
    return body


class LibraryResource:
    """The caller's starred items, recent items and trash."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def star(self, bucket: str, node_id: str) -> str:
        """Stars a node; returns the service's confirmation."""
        return self._http.request("POST", f"{_b(bucket)}/nodes/{seg(node_id)}/star")

    def unstar(self, bucket: str, node_id: str) -> str:
        """Unstars a node; returns the service's confirmation."""
        return self._http.request("DELETE", f"{_b(bucket)}/nodes/{seg(node_id)}/star")

    def star_path(self, bucket: str, path: str, *, type: ItemType | None = None) -> Document:
        """Stars the item at ``path`` (``type`` defaults to ``"file"`` on the service)
        and returns it."""
        return self._http.request("POST", f"{_b(bucket)}/star", _star_body(path, type))

    def unstar_path(self, bucket: str, path: str) -> str:
        """Unstars the item at ``path`` (sent as ``?path=``)."""
        return self._http.request("DELETE", f"{_b(bucket)}/star", query={"path": path})

    def starred(self, bucket: str) -> list[Document]:
        """Lists the caller's starred items that still exist and are readable."""
        return self._http.request("GET", f"{_b(bucket)}/starred")

    def recent(self, bucket: str, *, limit: int | None = None) -> list[Document]:
        """Lists items the caller recently uploaded, edited or viewed, newest first
        (``limit`` 1-200, service default 50)."""
        return self._http.request("GET", f"{_b(bucket)}/recent", query={"limit": limit})

    def trash(self, bucket: str) -> list[Document]:
        """Lists trashed items the caller may manage (paths show the original location)."""
        return self._http.request("GET", f"{_b(bucket)}/trash")

    def restore(self, bucket: str, node_id: str) -> Document:
        """Puts a trashed file or folder back at its original location."""
        return self._http.request("POST", f"{_b(bucket)}/trash/{seg(node_id)}/restore")

    def purge(self, bucket: str, node_id: str) -> str:
        """Permanently deletes a trashed item; returns the service's confirmation."""
        return self._http.request("DELETE", f"{_b(bucket)}/trash/{seg(node_id)}")


class AsyncLibraryResource:
    """Asyncio variant of :class:`LibraryResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def star(self, bucket: str, node_id: str) -> str:
        """Stars a node; returns the service's confirmation."""
        return await self._http.request("POST", f"{_b(bucket)}/nodes/{seg(node_id)}/star")

    async def unstar(self, bucket: str, node_id: str) -> str:
        """Unstars a node; returns the service's confirmation."""
        return await self._http.request("DELETE", f"{_b(bucket)}/nodes/{seg(node_id)}/star")

    async def star_path(self, bucket: str, path: str, *, type: ItemType | None = None) -> Document:
        """Stars the item at ``path`` (``type`` defaults to ``"file"`` on the service)
        and returns it."""
        return await self._http.request("POST", f"{_b(bucket)}/star", _star_body(path, type))

    async def unstar_path(self, bucket: str, path: str) -> str:
        """Unstars the item at ``path`` (sent as ``?path=``)."""
        return await self._http.request("DELETE", f"{_b(bucket)}/star", query={"path": path})

    async def starred(self, bucket: str) -> list[Document]:
        """Lists the caller's starred items that still exist and are readable."""
        return await self._http.request("GET", f"{_b(bucket)}/starred")

    async def recent(self, bucket: str, *, limit: int | None = None) -> list[Document]:
        """Lists items the caller recently uploaded, edited or viewed, newest first
        (``limit`` 1-200, service default 50)."""
        return await self._http.request("GET", f"{_b(bucket)}/recent", query={"limit": limit})

    async def trash(self, bucket: str) -> list[Document]:
        """Lists trashed items the caller may manage (paths show the original location)."""
        return await self._http.request("GET", f"{_b(bucket)}/trash")

    async def restore(self, bucket: str, node_id: str) -> Document:
        """Puts a trashed file or folder back at its original location."""
        return await self._http.request("POST", f"{_b(bucket)}/trash/{seg(node_id)}/restore")

    async def purge(self, bucket: str, node_id: str) -> str:
        """Permanently deletes a trashed item; returns the service's confirmation."""
        return await self._http.request("DELETE", f"{_b(bucket)}/trash/{seg(node_id)}")
