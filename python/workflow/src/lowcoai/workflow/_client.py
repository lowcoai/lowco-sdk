from __future__ import annotations

from collections.abc import Mapping

import httpx
from typing_extensions import Self

from ._base import DEFAULT_TIMEOUT
from ._http import AsyncHttpClient, HttpClient
from .resources import (
    ActivitiesResource,
    AnalyticsResource,
    AsyncActivitiesResource,
    AsyncAnalyticsResource,
    AsyncDryRunResource,
    AsyncEnvironmentsResource,
    AsyncExecutionsResource,
    AsyncFunctionsResource,
    AsyncHumanTasksResource,
    AsyncWebhooksResource,
    AsyncWorkflowsResource,
    DryRunResource,
    EnvironmentsResource,
    ExecutionsResource,
    FunctionsResource,
    HumanTasksResource,
    WebhooksResource,
    WorkflowsResource,
)

__all__ = ["AsyncWorkflowClient", "WorkflowClient"]


class WorkflowClient:
    """Client for the workflow-orchestrator product (routes under ``/v1/wf/*``).

    ``token`` (a user token or API key) is required and sent as
    ``Authorization: Bearer <token>`` on every request. Endpoints are grouped
    into resources: ``client.workflows``, ``client.environments``,
    ``client.functions``, ``client.executions``, ``client.activities``,
    ``client.human_tasks``, ``client.analytics``, ``client.dry_run`` and
    ``client.webhooks``. Use it as a context manager, or call :meth:`close`,
    to release the underlying connection pool.
    """

    workflows: WorkflowsResource
    environments: EnvironmentsResource
    functions: FunctionsResource
    executions: ExecutionsResource
    activities: ActivitiesResource
    human_tasks: HumanTasksResource
    analytics: AnalyticsResource
    dry_run: DryRunResource
    webhooks: WebhooksResource

    def __init__(
        self,
        token: str,
        *,
        org_id: str | None = None,
        timeout: float | None = DEFAULT_TIMEOUT,
        headers: Mapping[str, str] | None = None,
        http_client: httpx.Client | None = None,
    ) -> None:
        """
        Args:
            token: User token or API key. Required.
            org_id: Sent as the ``X-Org-Id`` header (unless ``headers`` already has one).
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
            headers: Extra headers added to every request. An ``Authorization`` or
                ``X-Org-Id`` entry here takes precedence over ``token`` / ``org_id``.
            http_client: Custom ``httpx.Client`` (proxies, retries, mocks). It is
                not closed by :meth:`close`.
        """
        self._http = HttpClient(
            token, org_id=org_id, timeout=timeout, headers=headers, http_client=http_client
        )
        self.workflows = WorkflowsResource(self._http)
        self.environments = EnvironmentsResource(self._http)
        self.functions = FunctionsResource(self._http)
        self.executions = ExecutionsResource(self._http)
        self.activities = ActivitiesResource(self._http)
        self.human_tasks = HumanTasksResource(self._http)
        self.analytics = AnalyticsResource(self._http)
        self.dry_run = DryRunResource(self._http)
        self.webhooks = WebhooksResource(self._http)

    def close(self) -> None:
        self._http.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()


class AsyncWorkflowClient:
    """Asyncio client for the workflow-orchestrator product (same surface as
    :class:`WorkflowClient`; every endpoint method is a coroutine).

    Use it as an async context manager, or call :meth:`aclose`, to release the
    underlying connection pool.
    """

    workflows: AsyncWorkflowsResource
    environments: AsyncEnvironmentsResource
    functions: AsyncFunctionsResource
    executions: AsyncExecutionsResource
    activities: AsyncActivitiesResource
    human_tasks: AsyncHumanTasksResource
    analytics: AsyncAnalyticsResource
    dry_run: AsyncDryRunResource
    webhooks: AsyncWebhooksResource

    def __init__(
        self,
        token: str,
        *,
        org_id: str | None = None,
        timeout: float | None = DEFAULT_TIMEOUT,
        headers: Mapping[str, str] | None = None,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        """
        Args:
            token: User token or API key. Required.
            org_id: Sent as the ``X-Org-Id`` header (unless ``headers`` already has one).
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
            headers: Extra headers added to every request. An ``Authorization`` or
                ``X-Org-Id`` entry here takes precedence over ``token`` / ``org_id``.
            http_client: Custom ``httpx.AsyncClient`` (proxies, retries, mocks). It
                is not closed by :meth:`aclose`.
        """
        self._http = AsyncHttpClient(
            token, org_id=org_id, timeout=timeout, headers=headers, http_client=http_client
        )
        self.workflows = AsyncWorkflowsResource(self._http)
        self.environments = AsyncEnvironmentsResource(self._http)
        self.functions = AsyncFunctionsResource(self._http)
        self.executions = AsyncExecutionsResource(self._http)
        self.activities = AsyncActivitiesResource(self._http)
        self.human_tasks = AsyncHumanTasksResource(self._http)
        self.analytics = AsyncAnalyticsResource(self._http)
        self.dry_run = AsyncDryRunResource(self._http)
        self.webhooks = AsyncWebhooksResource(self._http)

    async def aclose(self) -> None:
        await self._http.aclose()

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        await self.aclose()
