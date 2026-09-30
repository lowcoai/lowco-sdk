"""``/v1/wf/workflows`` (mirrors ``resources/workflows.ts``)."""

from __future__ import annotations

import builtins
from collections.abc import Mapping
from typing import Any

from .._base import seg
from .._http import AsyncHttpClient, HttpClient
from ..types import (
    PaginationQuery,
    RunWorkflowRequest,
    Workflow,
    WorkflowPublish,
    WorkflowPublishRequest,
    WorkflowUpdateRequest,
)

__all__ = ["AsyncWorkflowsResource", "WorkflowsResource"]


class WorkflowsResource:
    """Workflow definitions, runs, versions and published templates."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list(self, query: PaginationQuery | Mapping[str, Any] | None = None) -> list[Workflow]:
        return self._http.request("GET", "/v1/wf/workflows", query=query)

    def count(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> int | dict[str, Any]:
        return self._http.request("GET", "/v1/wf/workflows/count", query=query)

    def get_by_id(self, id: str) -> Workflow:
        return self._http.request("GET", f"/v1/wf/workflows/{seg(id)}")

    def create(self, payload: WorkflowUpdateRequest | Workflow) -> Workflow:
        return self._http.request("POST", "/v1/wf/workflows", payload)

    def update(self, id: str, payload: WorkflowUpdateRequest | Workflow) -> Workflow:
        return self._http.request("PUT", f"/v1/wf/workflows/{seg(id)}", payload)

    def delete(self, id: str) -> None:
        self._http.request_void("DELETE", f"/v1/wf/workflows/{seg(id)}")

    def run(self, payload: RunWorkflowRequest) -> dict[str, Any]:
        """Starts a workflow, or resumes one when ``activityId`` + ``executionId`` are set."""
        return self._http.request("POST", "/v1/wf/workflows/run", payload)

    def versions(
        self, id: str, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> builtins.list[Workflow]:
        return self._http.request("GET", f"/v1/wf/workflows/{seg(id)}/versions", query=query)

    def publish(self, id: str, payload: WorkflowPublishRequest) -> WorkflowPublish:
        return self._http.request("POST", f"/v1/wf/workflows/{seg(id)}/publish", payload)

    def published(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> builtins.list[WorkflowPublish]:
        return self._http.request("GET", "/v1/wf/workflows/published", query=query)

    def published_count(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> int | dict[str, Any]:
        return self._http.request("GET", "/v1/wf/workflows/published/count", query=query)

    def get_published_by_id(self, id: str) -> WorkflowPublish:
        return self._http.request("GET", f"/v1/wf/workflows/published/{seg(id)}")

    def update_published(self, id: str, payload: WorkflowPublishRequest) -> WorkflowPublish:
        return self._http.request("PUT", f"/v1/wf/workflows/published/{seg(id)}", payload)

    def delete_published(self, id: str) -> None:
        self._http.request_void("DELETE", f"/v1/wf/workflows/published/{seg(id)}")

    def web_published(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> builtins.list[WorkflowPublish]:
        return self._http.request("GET", "/v1/wf/workflows/published/web", query=query)

    def web_published_by_id(self, id: str) -> WorkflowPublish:
        return self._http.request("GET", f"/v1/wf/workflows/published/web/{seg(id)}")

    def search_published_templates(
        self,
        *,
        q: str | None = None,
        category: str | None = None,
        limit: int | None = None,
    ) -> builtins.list[WorkflowPublish]:
        return self._http.request(
            "GET",
            "/v1/wf/workflows/published/web/search",
            query={"q": q, "category": category, "limit": limit},
        )


class AsyncWorkflowsResource:
    """Asyncio variant of :class:`WorkflowsResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> list[Workflow]:
        return await self._http.request("GET", "/v1/wf/workflows", query=query)

    async def count(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> int | dict[str, Any]:
        return await self._http.request("GET", "/v1/wf/workflows/count", query=query)

    async def get_by_id(self, id: str) -> Workflow:
        return await self._http.request("GET", f"/v1/wf/workflows/{seg(id)}")

    async def create(self, payload: WorkflowUpdateRequest | Workflow) -> Workflow:
        return await self._http.request("POST", "/v1/wf/workflows", payload)

    async def update(self, id: str, payload: WorkflowUpdateRequest | Workflow) -> Workflow:
        return await self._http.request("PUT", f"/v1/wf/workflows/{seg(id)}", payload)

    async def delete(self, id: str) -> None:
        await self._http.request_void("DELETE", f"/v1/wf/workflows/{seg(id)}")

    async def run(self, payload: RunWorkflowRequest) -> dict[str, Any]:
        """Starts a workflow, or resumes one when ``activityId`` + ``executionId`` are set."""
        return await self._http.request("POST", "/v1/wf/workflows/run", payload)

    async def versions(
        self, id: str, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> builtins.list[Workflow]:
        return await self._http.request("GET", f"/v1/wf/workflows/{seg(id)}/versions", query=query)

    async def publish(self, id: str, payload: WorkflowPublishRequest) -> WorkflowPublish:
        return await self._http.request("POST", f"/v1/wf/workflows/{seg(id)}/publish", payload)

    async def published(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> builtins.list[WorkflowPublish]:
        return await self._http.request("GET", "/v1/wf/workflows/published", query=query)

    async def published_count(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> int | dict[str, Any]:
        return await self._http.request("GET", "/v1/wf/workflows/published/count", query=query)

    async def get_published_by_id(self, id: str) -> WorkflowPublish:
        return await self._http.request("GET", f"/v1/wf/workflows/published/{seg(id)}")

    async def update_published(self, id: str, payload: WorkflowPublishRequest) -> WorkflowPublish:
        return await self._http.request("PUT", f"/v1/wf/workflows/published/{seg(id)}", payload)

    async def delete_published(self, id: str) -> None:
        await self._http.request_void("DELETE", f"/v1/wf/workflows/published/{seg(id)}")

    async def web_published(
        self, query: PaginationQuery | Mapping[str, Any] | None = None
    ) -> builtins.list[WorkflowPublish]:
        return await self._http.request("GET", "/v1/wf/workflows/published/web", query=query)

    async def web_published_by_id(self, id: str) -> WorkflowPublish:
        return await self._http.request("GET", f"/v1/wf/workflows/published/web/{seg(id)}")

    async def search_published_templates(
        self,
        *,
        q: str | None = None,
        category: str | None = None,
        limit: int | None = None,
    ) -> builtins.list[WorkflowPublish]:
        return await self._http.request(
            "GET",
            "/v1/wf/workflows/published/web/search",
            query={"q": q, "category": category, "limit": limit},
        )
