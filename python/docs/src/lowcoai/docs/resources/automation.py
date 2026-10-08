"""Folder automations: ``/v1/documents/{bucket}/folder-configs`` and ``processing-jobs``."""

from __future__ import annotations

import builtins

from .._base import API_PREFIX, seg
from .._http import AsyncHttpClient, HttpClient
from ..types import FolderConfig, FolderConfigRequest, ProcessingJob

__all__ = ["AsyncAutomationResource", "AutomationResource"]


def _configs(bucket: str) -> str:
    return f"{API_PREFIX}/{seg(bucket)}/folder-configs"


class AutomationResource:
    """Folder automation rules (run a pipeline when files land in a folder) and
    their run history."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list(self, bucket: str, *, prefix: str | None = None) -> builtins.list[FolderConfig]:
        """Lists the bucket's rules visible to the caller, optionally for one folder."""
        return self._http.request("GET", _configs(bucket), query={"prefix": prefix})

    def create(self, bucket: str, body: FolderConfigRequest) -> FolderConfig:
        """Creates a rule that runs ``pipelineType`` on files created (or updated) under
        ``prefix``."""
        return self._http.request("POST", _configs(bucket), body)

    def get(self, bucket: str, id: str) -> FolderConfig:
        """Returns one rule."""
        return self._http.request("GET", f"{_configs(bucket)}/{seg(id)}")

    def update(self, bucket: str, id: str, body: FolderConfigRequest) -> FolderConfig:
        """Replaces a rule."""
        return self._http.request("PUT", f"{_configs(bucket)}/{seg(id)}", body)

    def delete(self, bucket: str, id: str) -> str:
        """Deletes a rule; returns the service's confirmation."""
        return self._http.request("DELETE", f"{_configs(bucket)}/{seg(id)}")

    def jobs(
        self, bucket: str, *, config_id: str | None = None, limit: int | None = None
    ) -> builtins.list[ProcessingJob]:
        """Lists pipeline runs, newest first, optionally of one rule (``config_id``;
        ``limit`` 1-200, service default 50)."""
        return self._http.request(
            "GET",
            f"{API_PREFIX}/{seg(bucket)}/processing-jobs",
            query={"configId": config_id, "limit": limit},
        )


class AsyncAutomationResource:
    """Asyncio variant of :class:`AutomationResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list(self, bucket: str, *, prefix: str | None = None) -> builtins.list[FolderConfig]:
        """Lists the bucket's rules visible to the caller, optionally for one folder."""
        return await self._http.request("GET", _configs(bucket), query={"prefix": prefix})

    async def create(self, bucket: str, body: FolderConfigRequest) -> FolderConfig:
        """Creates a rule that runs ``pipelineType`` on files created (or updated) under
        ``prefix``."""
        return await self._http.request("POST", _configs(bucket), body)

    async def get(self, bucket: str, id: str) -> FolderConfig:
        """Returns one rule."""
        return await self._http.request("GET", f"{_configs(bucket)}/{seg(id)}")

    async def update(self, bucket: str, id: str, body: FolderConfigRequest) -> FolderConfig:
        """Replaces a rule."""
        return await self._http.request("PUT", f"{_configs(bucket)}/{seg(id)}", body)

    async def delete(self, bucket: str, id: str) -> str:
        """Deletes a rule; returns the service's confirmation."""
        return await self._http.request("DELETE", f"{_configs(bucket)}/{seg(id)}")

    async def jobs(
        self, bucket: str, *, config_id: str | None = None, limit: int | None = None
    ) -> builtins.list[ProcessingJob]:
        """Lists pipeline runs, newest first, optionally of one rule (``config_id``;
        ``limit`` 1-200, service default 50)."""
        return await self._http.request(
            "GET",
            f"{API_PREFIX}/{seg(bucket)}/processing-jobs",
            query={"configId": config_id, "limit": limit},
        )
