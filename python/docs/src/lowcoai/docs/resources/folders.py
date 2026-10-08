"""Folder listings and folder operations under ``/v1/documents/{bucket}``."""

from __future__ import annotations

import builtins
from collections.abc import Sequence

from .._base import API_PREFIX, seg, wildcard
from .._http import AsyncHttpClient, HttpClient
from ..types import (
    Binary,
    CreateFolderRequest,
    Document,
    DuplicateRequest,
    FileInput,
    RenameRequest,
    UploadFolderResult,
)

__all__ = ["AsyncFoldersResource", "FoldersResource"]


def _b(bucket: str) -> str:
    return f"{API_PREFIX}/{seg(bucket)}"


def _upload_parts(
    files: Sequence[FileInput], relative_paths: Sequence[str] | None
) -> builtins.list[tuple[str, FileInput]]:
    if relative_paths is not None and len(relative_paths) != len(files):
        raise ValueError(
            f"relative_paths has {len(relative_paths)} entries for {len(files)} files; "
            "pass one relative path per file, in the same order"
        )
    return [("files", file) for file in files]


class FoldersResource:
    """Lists folders (library, personal drives, app data) and creates, deletes,
    uploads, zips, duplicates and renames folders.

    ``sizes=False`` skips recursive folder sizes in listings (folders then
    report size 0).
    """

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list(
        self, bucket: str, *, prefix: str | None = None, sizes: bool | None = None
    ) -> builtins.list[Document]:
        """Lists the direct children of ``prefix`` (the library root when omitted)."""
        return self._http.request(
            "GET", f"{_b(bucket)}/objects", query={"prefix": prefix, "sizes": sizes}
        )

    def list_at(
        self, bucket: str, path: str, *, sizes: bool | None = None
    ) -> builtins.list[Document]:
        """Same listing as :meth:`list`, with the folder path in the URL."""
        return self._http.request(
            "GET", f"{_b(bucket)}/objects/{wildcard(path)}", query={"sizes": sizes}
        )

    def list_public(
        self, bucket: str, *, prefix: str | None = None, sizes: bool | None = None
    ) -> builtins.list[Document]:
        """Lists an org-library folder (same listing as :meth:`list`)."""
        return self._http.request(
            "GET", f"{_b(bucket)}/public/objects", query={"prefix": prefix, "sizes": sizes}
        )

    def list_user(
        self,
        bucket: str,
        user_id: str,
        *,
        prefix: str | None = None,
        sizes: bool | None = None,
    ) -> builtins.list[Document]:
        """Lists ``.users/{user_id}/{prefix}`` (the owner's personal drive, or one shared
        with the caller)."""
        return self._http.request(
            "GET",
            f"{_b(bucket)}/users/{seg(user_id)}/objects",
            query={"prefix": prefix, "sizes": sizes},
        )

    def list_app(
        self,
        bucket: str,
        app_id: str,
        *,
        prefix: str | None = None,
        sizes: bool | None = None,
    ) -> builtins.list[Document]:
        """Lists an app's data folder ``.apps/{app_id}/{prefix}``."""
        return self._http.request(
            "GET",
            f"{_b(bucket)}/apps/{seg(app_id)}/objects",
            query={"prefix": prefix, "sizes": sizes},
        )

    def get(self, bucket: str, key: str) -> builtins.list[Document]:
        """Raw listing of the folder named by one path segment ``key`` (full keys,
        no role / sharing / size enrichment)."""
        return self._http.request("GET", f"{_b(bucket)}/folder/{seg(key)}")

    def create(self, bucket: str, body: CreateFolderRequest) -> builtins.list[Document]:
        """Creates ``folderName`` inside ``parentName``; returns every level created,
        outermost first."""
        return self._http.request("POST", f"{_b(bucket)}/folder", body)

    def delete(self, bucket: str, key: str) -> str:
        """Deletes the top-level folder named by one path segment ``key`` (library and
        personal folders go to the trash); returns the service's confirmation."""
        return self._http.request("DELETE", f"{_b(bucket)}/folder/{seg(key)}")

    def delete_by_path(self, bucket: str, path: str) -> str:
        """Deletes the folder at ``path``, at any depth (sent as ``?path=``)."""
        return self._http.request("DELETE", f"{_b(bucket)}/folder", query={"path": path})

    def upload(
        self,
        bucket: str,
        files: Sequence[FileInput],
        *,
        relative_paths: Sequence[str] | None = None,
        parent_id: str | None = None,
        prefix: str | None = None,
    ) -> UploadFolderResult:
        """Uploads many files (multipart ``files`` parts) with their
        ``relative_paths`` (one per file, same order; e.g. ``photos/a.jpg``) under
        the destination folder ``parent_id`` (form field ``parentID``), or
        ``prefix`` when ``parent_id`` is empty (both empty = library root)."""
        return self._http.request_multipart(
            "POST",
            f"{_b(bucket)}/upload-folder",
            _upload_parts(files, relative_paths),
            {"relativePaths": relative_paths, "parentID": parent_id, "prefix": prefix},
        )

    def download_zip(self, bucket: str, path: str) -> Binary:
        """Downloads every object under the folder ``path`` as a zip archive."""
        return self._http.request_binary("GET", f"{_b(bucket)}/folder-zip/{wildcard(path)}")

    def duplicate(self, bucket: str, body: DuplicateRequest) -> Document:
        """Copies a file or folder next to itself as ``"<name> copy"``; returns the copy."""
        return self._http.request("POST", f"{_b(bucket)}/duplicate", body)

    def rename(self, bucket: str, body: RenameRequest) -> Document:
        """Renames (or moves, when ``newName`` holds a path) a folder."""
        return self._http.request("PUT", f"{_b(bucket)}/folder/rename", body)


class AsyncFoldersResource:
    """Asyncio variant of :class:`FoldersResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list(
        self, bucket: str, *, prefix: str | None = None, sizes: bool | None = None
    ) -> builtins.list[Document]:
        """Lists the direct children of ``prefix`` (the library root when omitted)."""
        return await self._http.request(
            "GET", f"{_b(bucket)}/objects", query={"prefix": prefix, "sizes": sizes}
        )

    async def list_at(
        self, bucket: str, path: str, *, sizes: bool | None = None
    ) -> builtins.list[Document]:
        """Same listing as :meth:`list`, with the folder path in the URL."""
        return await self._http.request(
            "GET", f"{_b(bucket)}/objects/{wildcard(path)}", query={"sizes": sizes}
        )

    async def list_public(
        self, bucket: str, *, prefix: str | None = None, sizes: bool | None = None
    ) -> builtins.list[Document]:
        """Lists an org-library folder (same listing as :meth:`list`)."""
        return await self._http.request(
            "GET", f"{_b(bucket)}/public/objects", query={"prefix": prefix, "sizes": sizes}
        )

    async def list_user(
        self,
        bucket: str,
        user_id: str,
        *,
        prefix: str | None = None,
        sizes: bool | None = None,
    ) -> builtins.list[Document]:
        """Lists ``.users/{user_id}/{prefix}`` (the owner's personal drive, or one shared
        with the caller)."""
        return await self._http.request(
            "GET",
            f"{_b(bucket)}/users/{seg(user_id)}/objects",
            query={"prefix": prefix, "sizes": sizes},
        )

    async def list_app(
        self,
        bucket: str,
        app_id: str,
        *,
        prefix: str | None = None,
        sizes: bool | None = None,
    ) -> builtins.list[Document]:
        """Lists an app's data folder ``.apps/{app_id}/{prefix}``."""
        return await self._http.request(
            "GET",
            f"{_b(bucket)}/apps/{seg(app_id)}/objects",
            query={"prefix": prefix, "sizes": sizes},
        )

    async def get(self, bucket: str, key: str) -> builtins.list[Document]:
        """Raw listing of the folder named by one path segment ``key`` (full keys,
        no role / sharing / size enrichment)."""
        return await self._http.request("GET", f"{_b(bucket)}/folder/{seg(key)}")

    async def create(self, bucket: str, body: CreateFolderRequest) -> builtins.list[Document]:
        """Creates ``folderName`` inside ``parentName``; returns every level created,
        outermost first."""
        return await self._http.request("POST", f"{_b(bucket)}/folder", body)

    async def delete(self, bucket: str, key: str) -> str:
        """Deletes the top-level folder named by one path segment ``key`` (library and
        personal folders go to the trash); returns the service's confirmation."""
        return await self._http.request("DELETE", f"{_b(bucket)}/folder/{seg(key)}")

    async def delete_by_path(self, bucket: str, path: str) -> str:
        """Deletes the folder at ``path``, at any depth (sent as ``?path=``)."""
        return await self._http.request("DELETE", f"{_b(bucket)}/folder", query={"path": path})

    async def upload(
        self,
        bucket: str,
        files: Sequence[FileInput],
        *,
        relative_paths: Sequence[str] | None = None,
        parent_id: str | None = None,
        prefix: str | None = None,
    ) -> UploadFolderResult:
        """Uploads many files (multipart ``files`` parts) with their
        ``relative_paths`` (one per file, same order; e.g. ``photos/a.jpg``) under
        the destination folder ``parent_id`` (form field ``parentID``), or
        ``prefix`` when ``parent_id`` is empty (both empty = library root)."""
        return await self._http.request_multipart(
            "POST",
            f"{_b(bucket)}/upload-folder",
            _upload_parts(files, relative_paths),
            {"relativePaths": relative_paths, "parentID": parent_id, "prefix": prefix},
        )

    async def download_zip(self, bucket: str, path: str) -> Binary:
        """Downloads every object under the folder ``path`` as a zip archive."""
        return await self._http.request_binary("GET", f"{_b(bucket)}/folder-zip/{wildcard(path)}")

    async def duplicate(self, bucket: str, body: DuplicateRequest) -> Document:
        """Copies a file or folder next to itself as ``"<name> copy"``; returns the copy."""
        return await self._http.request("POST", f"{_b(bucket)}/duplicate", body)

    async def rename(self, bucket: str, body: RenameRequest) -> Document:
        """Renames (or moves, when ``newName`` holds a path) a folder."""
        return await self._http.request("PUT", f"{_b(bucket)}/folder/rename", body)
