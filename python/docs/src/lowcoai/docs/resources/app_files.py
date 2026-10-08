"""App data: ``/v1/documents/app-files/{appKey}``."""

from __future__ import annotations

import builtins

from .._base import API_PREFIX, seg, wildcard
from .._http import AsyncHttpClient, HttpClient
from ..types import AppFilesSweep, AppFileUpload, Document, FileInput, OnConflict, SweepRequest

__all__ = ["AppFilesResource", "AsyncAppFilesResource"]


def _app(app_key: str) -> str:
    return f"{API_PREFIX}/app-files/{seg(app_key)}"


class AppFilesResource:
    """The upload contract for suite apps: files under ``.apps/{app_key}/`` in the
    org's bucket, addressed by a stable node id / permalink."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def upload(
        self,
        app_key: str,
        file: FileInput,
        *,
        path: str | None = None,
        on_conflict: OnConflict | None = None,
    ) -> AppFileUpload:
        """Stores a file (multipart ``file``) at ``.apps/{app_key}/{path}/{name}`` and
        returns its node id and permalink (store those, not a storage URL)."""
        return self._http.request_multipart(
            "POST", _app(app_key), [("file", file)], {"path": path, "onConflict": on_conflict}
        )

    def list(self, app_key: str, *, prefix: str | None = None) -> builtins.list[Document]:
        """Lists the direct children of ``.apps/{app_key}/{prefix}``."""
        return self._http.request("GET", f"{_app(app_key)}/objects", query={"prefix": prefix})

    def delete(self, app_key: str, path: str) -> str:
        """Permanently deletes ``.apps/{app_key}/{path}`` (app data skips the trash);
        returns the service's confirmation."""
        return self._http.request("DELETE", f"{_app(app_key)}/{wildcard(path)}")

    def sweep(self, app_key: str, body: SweepRequest) -> AppFilesSweep:
        """Moves the app's files older than ``olderThanDays`` to the cold archive tier
        (never deletes; they stay reachable by permalink)."""
        return self._http.request("POST", f"{_app(app_key)}/sweep", body)


class AsyncAppFilesResource:
    """Asyncio variant of :class:`AppFilesResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def upload(
        self,
        app_key: str,
        file: FileInput,
        *,
        path: str | None = None,
        on_conflict: OnConflict | None = None,
    ) -> AppFileUpload:
        """Stores a file (multipart ``file``) at ``.apps/{app_key}/{path}/{name}`` and
        returns its node id and permalink (store those, not a storage URL)."""
        return await self._http.request_multipart(
            "POST", _app(app_key), [("file", file)], {"path": path, "onConflict": on_conflict}
        )

    async def list(self, app_key: str, *, prefix: str | None = None) -> builtins.list[Document]:
        """Lists the direct children of ``.apps/{app_key}/{prefix}``."""
        return await self._http.request("GET", f"{_app(app_key)}/objects", query={"prefix": prefix})

    async def delete(self, app_key: str, path: str) -> str:
        """Permanently deletes ``.apps/{app_key}/{path}`` (app data skips the trash);
        returns the service's confirmation."""
        return await self._http.request("DELETE", f"{_app(app_key)}/{wildcard(path)}")

    async def sweep(self, app_key: str, body: SweepRequest) -> AppFilesSweep:
        """Moves the app's files older than ``olderThanDays`` to the cold archive tier
        (never deletes; they stay reachable by permalink)."""
        return await self._http.request("POST", f"{_app(app_key)}/sweep", body)
