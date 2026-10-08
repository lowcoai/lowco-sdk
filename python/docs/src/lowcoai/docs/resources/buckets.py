"""``/v1/documents`` and ``/v1/documents/{bucket}/stats``."""

from __future__ import annotations

from .._base import API_PREFIX, seg
from .._http import AsyncHttpClient, HttpClient
from ..types import BucketStats, Document

__all__ = ["AsyncBucketsResource", "BucketsResource"]


class BucketsResource:
    """The org's bucket and its storage usage."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def get(self) -> Document:
        """Returns the org's bucket (created on first use) as a folder document;
        its ``name`` is the bucket name every other call takes."""
        return self._http.request("GET", API_PREFIX)

    def stats(self, bucket: str) -> BucketStats:
        """Returns the bucket's storage usage (visible vs. system content)."""
        return self._http.request("GET", f"{API_PREFIX}/{seg(bucket)}/stats")


class AsyncBucketsResource:
    """Asyncio variant of :class:`BucketsResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def get(self) -> Document:
        """Returns the org's bucket (created on first use) as a folder document;
        its ``name`` is the bucket name every other call takes."""
        return await self._http.request("GET", API_PREFIX)

    async def stats(self, bucket: str) -> BucketStats:
        """Returns the bucket's storage usage (visible vs. system content)."""
        return await self._http.request("GET", f"{API_PREFIX}/{seg(bucket)}/stats")
