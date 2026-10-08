"""Grants, share links and shared-with-me under ``/v1/documents``."""

from __future__ import annotations

import builtins

from .._base import API_PREFIX, seg
from .._http import AsyncHttpClient, HttpClient
from ..types import (
    CreateShareLinkRequest,
    CreateShareRequest,
    Document,
    ItemType,
    Share,
    ShareLink,
    ShareLinkCreated,
)

__all__ = ["AsyncSharingResource", "SharingResource"]


def _b(bucket: str) -> str:
    return f"{API_PREFIX}/{seg(bucket)}"


class SharingResource:
    """Shares My Drive items with members or the whole org, and mints org-scope
    share links. Managing grants and links is owner only."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def create(self, bucket: str, body: CreateShareRequest) -> Share:
        """Grants one member (``subjectType="user"``) or the whole org viewer or editor
        access to a My Drive item the caller owns."""
        return self._http.request("POST", f"{_b(bucket)}/shares", body)

    def list(self, bucket: str, path: str, *, type: ItemType | None = None) -> builtins.list[Share]:
        """Lists the grants on the item at ``path`` (required by the service;
        ``type`` defaults to ``"file"``)."""
        return self._http.request("GET", f"{_b(bucket)}/shares", query={"path": path, "type": type})

    def delete(self, bucket: str, id: str) -> str:
        """Revokes a grant; returns the service's confirmation."""
        return self._http.request("DELETE", f"{_b(bucket)}/shares/{seg(id)}")

    def shared_with_me(self, bucket: str, *, app_key: str | None = None) -> builtins.list[Document]:
        """Lists items other members shared with the caller. Without ``app_key`` app
        data is left out; with it only that app's items are returned."""
        return self._http.request("GET", f"{_b(bucket)}/shared-with-me", query={"appKey": app_key})

    def create_link(self, bucket: str, body: CreateShareLinkRequest) -> ShareLinkCreated:
        """Mints an org-scope viewer link for a My Drive file the caller owns."""
        return self._http.request("POST", f"{_b(bucket)}/share-links", body)

    def list_links(
        self, bucket: str, path: str, *, type: ItemType | None = None
    ) -> builtins.list[ShareLink]:
        """Lists the share links of the item at ``path`` (required by the service;
        ``type`` defaults to ``"file"``)."""
        return self._http.request(
            "GET", f"{_b(bucket)}/share-links", query={"path": path, "type": type}
        )

    def delete_link(self, bucket: str, id: str) -> str:
        """Revokes a share link; returns the service's confirmation."""
        return self._http.request("DELETE", f"{_b(bucket)}/share-links/{seg(id)}")

    def resolve_link(self, token: str) -> str:
        """Follows a share link: returns the short-lived file URL it redirects to (the
        307 ``Location``; the redirect is not followed)."""
        return self._http.request_redirect("GET", f"{API_PREFIX}/link/{seg(token)}")


class AsyncSharingResource:
    """Asyncio variant of :class:`SharingResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def create(self, bucket: str, body: CreateShareRequest) -> Share:
        """Grants one member (``subjectType="user"``) or the whole org viewer or editor
        access to a My Drive item the caller owns."""
        return await self._http.request("POST", f"{_b(bucket)}/shares", body)

    async def list(
        self, bucket: str, path: str, *, type: ItemType | None = None
    ) -> builtins.list[Share]:
        """Lists the grants on the item at ``path`` (required by the service;
        ``type`` defaults to ``"file"``)."""
        return await self._http.request(
            "GET", f"{_b(bucket)}/shares", query={"path": path, "type": type}
        )

    async def delete(self, bucket: str, id: str) -> str:
        """Revokes a grant; returns the service's confirmation."""
        return await self._http.request("DELETE", f"{_b(bucket)}/shares/{seg(id)}")

    async def shared_with_me(
        self, bucket: str, *, app_key: str | None = None
    ) -> builtins.list[Document]:
        """Lists items other members shared with the caller. Without ``app_key`` app
        data is left out; with it only that app's items are returned."""
        return await self._http.request(
            "GET", f"{_b(bucket)}/shared-with-me", query={"appKey": app_key}
        )

    async def create_link(self, bucket: str, body: CreateShareLinkRequest) -> ShareLinkCreated:
        """Mints an org-scope viewer link for a My Drive file the caller owns."""
        return await self._http.request("POST", f"{_b(bucket)}/share-links", body)

    async def list_links(
        self, bucket: str, path: str, *, type: ItemType | None = None
    ) -> builtins.list[ShareLink]:
        """Lists the share links of the item at ``path`` (required by the service;
        ``type`` defaults to ``"file"``)."""
        return await self._http.request(
            "GET", f"{_b(bucket)}/share-links", query={"path": path, "type": type}
        )

    async def delete_link(self, bucket: str, id: str) -> str:
        """Revokes a share link; returns the service's confirmation."""
        return await self._http.request("DELETE", f"{_b(bucket)}/share-links/{seg(id)}")

    async def resolve_link(self, token: str) -> str:
        """Follows a share link: returns the short-lived file URL it redirects to (the
        307 ``Location``; the redirect is not followed)."""
        return await self._http.request_redirect("GET", f"{API_PREFIX}/link/{seg(token)}")
