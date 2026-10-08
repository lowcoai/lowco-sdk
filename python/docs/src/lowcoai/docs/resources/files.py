"""File operations under ``/v1/documents/{bucket}``."""

from __future__ import annotations

from .._base import API_PREFIX, flag, seg, wildcard
from .._http import AsyncHttpClient, HttpClient
from ..types import (
    ArchiveListing,
    CreateBlankFileRequest,
    Document,
    FileContent,
    FileInput,
    OnConflict,
    RenameRequest,
    UpdateFileRequest,
)

__all__ = ["AsyncFilesResource", "FilesResource"]


def _b(bucket: str) -> str:
    return f"{API_PREFIX}/{seg(bucket)}"


class FilesResource:
    """Reads, saves, uploads, renames and deletes files; download / preview URLs
    and zip listings.

    ``path`` is the file key (``"projects/plan.md"``); in URL paths each segment
    is percent-encoded and ``/`` is kept.
    """

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def get(self, bucket: str, path: str) -> Document:
        """Returns the file's metadata, URLs and body (as text) and records a view."""
        return self._http.request("GET", f"{_b(bucket)}/file/{wildcard(path)}")

    def read(self, bucket: str, path: str, *, meta: bool | None = None) -> FileContent:
        """Reads the file at ``path`` with the ``etag`` of exactly that version (send
        it back as ``ifMatch``) and the caller's role. ``meta=True`` skips the body."""
        return self._http.request(
            "GET", f"{_b(bucket)}/file", query={"path": path, "meta": flag(meta)}
        )

    def create_blank(self, bucket: str, body: CreateBlankFileRequest) -> Document:
        """Creates an empty file at ``parentName/fileName``."""
        return self._http.request("POST", f"{_b(bucket)}/file", body)

    def update(self, bucket: str, body: UpdateFileRequest) -> Document:
        """Saves the whole body of ``parentName/fileName`` (creating it when missing).
        A failed ``ifMatch`` / ``ifNoneMatch`` condition raises ``DocsError`` 412."""
        return self._http.request("PUT", f"{_b(bucket)}/file", body)

    def update_at(self, bucket: str, path: str, body: UpdateFileRequest) -> Document:
        """Same as :meth:`update` (path form); the service ignores the URL ``path``."""
        return self._http.request("PUT", f"{_b(bucket)}/file/{wildcard(path)}", body)

    def rename(self, bucket: str, body: RenameRequest) -> Document:
        """Renames (or moves, when ``newName`` holds a path) a file; its node id survives."""
        return self._http.request("PUT", f"{_b(bucket)}/file/rename", body)

    def delete(self, bucket: str, path: str) -> str:
        """Deletes the file (library and personal files go to the trash); returns the
        service's confirmation."""
        return self._http.request("DELETE", f"{_b(bucket)}/file/{wildcard(path)}")

    def delete_by_path(self, bucket: str, path: str) -> str:
        """Same as :meth:`delete`, with the key sent as ``?path=``."""
        return self._http.request("DELETE", f"{_b(bucket)}/file", query={"path": path})

    def upload(
        self,
        bucket: str,
        file: FileInput,
        *,
        parent_id: str | None = None,
        on_conflict: OnConflict | None = None,
    ) -> Document:
        """Uploads one file (multipart ``file``) into the folder ``parent_id`` (form
        field ``ParentID``; empty = library root). ``on_conflict="rename"`` keeps
        both files instead of replacing."""
        return self._http.request_multipart(
            "POST",
            f"{_b(bucket)}/upload-file",
            [("file", file)],
            {"ParentID": parent_id, "onConflict": on_conflict},
        )

    def download_url(self, bucket: str, path: str) -> str:
        """Returns a short-lived URL that downloads the file under its real name
        (the 307 ``Location``; the redirect is not followed)."""
        return self._http.request_redirect("GET", f"{_b(bucket)}/download/{wildcard(path)}")

    def preview_url(self, bucket: str, path: str) -> str:
        """Returns the URL of a PDF rendition of the file (PDFs and office documents;
        the 307 ``Location``; the redirect is not followed)."""
        return self._http.request_redirect("GET", f"{_b(bucket)}/preview/{wildcard(path)}")

    def list_archive(self, bucket: str, path: str) -> ArchiveListing:
        """Lists the entries of a stored ``.zip`` without extracting it."""
        return self._http.request("GET", f"{_b(bucket)}/archive/{wildcard(path)}")


class AsyncFilesResource:
    """Asyncio variant of :class:`FilesResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def get(self, bucket: str, path: str) -> Document:
        """Returns the file's metadata, URLs and body (as text) and records a view."""
        return await self._http.request("GET", f"{_b(bucket)}/file/{wildcard(path)}")

    async def read(self, bucket: str, path: str, *, meta: bool | None = None) -> FileContent:
        """Reads the file at ``path`` with the ``etag`` of exactly that version (send
        it back as ``ifMatch``) and the caller's role. ``meta=True`` skips the body."""
        return await self._http.request(
            "GET", f"{_b(bucket)}/file", query={"path": path, "meta": flag(meta)}
        )

    async def create_blank(self, bucket: str, body: CreateBlankFileRequest) -> Document:
        """Creates an empty file at ``parentName/fileName``."""
        return await self._http.request("POST", f"{_b(bucket)}/file", body)

    async def update(self, bucket: str, body: UpdateFileRequest) -> Document:
        """Saves the whole body of ``parentName/fileName`` (creating it when missing).
        A failed ``ifMatch`` / ``ifNoneMatch`` condition raises ``DocsError`` 412."""
        return await self._http.request("PUT", f"{_b(bucket)}/file", body)

    async def update_at(self, bucket: str, path: str, body: UpdateFileRequest) -> Document:
        """Same as :meth:`update` (path form); the service ignores the URL ``path``."""
        return await self._http.request("PUT", f"{_b(bucket)}/file/{wildcard(path)}", body)

    async def rename(self, bucket: str, body: RenameRequest) -> Document:
        """Renames (or moves, when ``newName`` holds a path) a file; its node id survives."""
        return await self._http.request("PUT", f"{_b(bucket)}/file/rename", body)

    async def delete(self, bucket: str, path: str) -> str:
        """Deletes the file (library and personal files go to the trash); returns the
        service's confirmation."""
        return await self._http.request("DELETE", f"{_b(bucket)}/file/{wildcard(path)}")

    async def delete_by_path(self, bucket: str, path: str) -> str:
        """Same as :meth:`delete`, with the key sent as ``?path=``."""
        return await self._http.request("DELETE", f"{_b(bucket)}/file", query={"path": path})

    async def upload(
        self,
        bucket: str,
        file: FileInput,
        *,
        parent_id: str | None = None,
        on_conflict: OnConflict | None = None,
    ) -> Document:
        """Uploads one file (multipart ``file``) into the folder ``parent_id`` (form
        field ``ParentID``; empty = library root). ``on_conflict="rename"`` keeps
        both files instead of replacing."""
        return await self._http.request_multipart(
            "POST",
            f"{_b(bucket)}/upload-file",
            [("file", file)],
            {"ParentID": parent_id, "onConflict": on_conflict},
        )

    async def download_url(self, bucket: str, path: str) -> str:
        """Returns a short-lived URL that downloads the file under its real name
        (the 307 ``Location``; the redirect is not followed)."""
        return await self._http.request_redirect("GET", f"{_b(bucket)}/download/{wildcard(path)}")

    async def preview_url(self, bucket: str, path: str) -> str:
        """Returns the URL of a PDF rendition of the file (PDFs and office documents;
        the 307 ``Location``; the redirect is not followed)."""
        return await self._http.request_redirect("GET", f"{_b(bucket)}/preview/{wildcard(path)}")

    async def list_archive(self, bucket: str, path: str) -> ArchiveListing:
        """Lists the entries of a stored ``.zip`` without extracting it."""
        return await self._http.request("GET", f"{_b(bucket)}/archive/{wildcard(path)}")
