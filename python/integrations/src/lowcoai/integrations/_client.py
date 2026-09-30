from __future__ import annotations

from collections.abc import Mapping

import httpx
from typing_extensions import Self

from ._base import DEFAULT_TIMEOUT
from ._http import AsyncHttpClient, HttpClient
from .resources import (
    ActionsResource,
    ApplicationsResource,
    AsyncActionsResource,
    AsyncApplicationsResource,
    AsyncConfigurationsResource,
    AsyncConnectionsResource,
    AsyncMcpResource,
    AsyncOAuthResource,
    AsyncTriggersResource,
    ConfigurationsResource,
    ConnectionsResource,
    McpResource,
    OAuthResource,
    TriggersResource,
)

__all__ = ["AsyncIntegrationsClient", "IntegrationsClient"]


class IntegrationsClient:
    """Client for the integrations-manager product (routes under ``/v1/integrations/*``).

    ``token`` (a user token or API key) is required and sent as
    ``Authorization: Bearer <token>`` on every request. Endpoints are grouped
    into resources: ``client.applications``, ``client.actions``,
    ``client.connections``, ``client.triggers``, ``client.oauth``,
    ``client.configurations`` and ``client.mcp``. Use it as a context manager,
    or call :meth:`close`, to release the underlying connection pool.
    """

    applications: ApplicationsResource
    actions: ActionsResource
    connections: ConnectionsResource
    triggers: TriggersResource
    oauth: OAuthResource
    configurations: ConfigurationsResource
    mcp: McpResource

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
        self.applications = ApplicationsResource(self._http)
        self.actions = ActionsResource(self._http)
        self.connections = ConnectionsResource(self._http)
        self.triggers = TriggersResource(self._http)
        self.oauth = OAuthResource(self._http)
        self.configurations = ConfigurationsResource(self._http)
        self.mcp = McpResource(self._http)

    def close(self) -> None:
        self._http.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()


class AsyncIntegrationsClient:
    """Asyncio client for the integrations-manager product (same surface as
    :class:`IntegrationsClient`; every endpoint method is a coroutine).

    Use it as an async context manager, or call :meth:`aclose`, to release the
    underlying connection pool.
    """

    applications: AsyncApplicationsResource
    actions: AsyncActionsResource
    connections: AsyncConnectionsResource
    triggers: AsyncTriggersResource
    oauth: AsyncOAuthResource
    configurations: AsyncConfigurationsResource
    mcp: AsyncMcpResource

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
        self.applications = AsyncApplicationsResource(self._http)
        self.actions = AsyncActionsResource(self._http)
        self.connections = AsyncConnectionsResource(self._http)
        self.triggers = AsyncTriggersResource(self._http)
        self.oauth = AsyncOAuthResource(self._http)
        self.configurations = AsyncConfigurationsResource(self._http)
        self.mcp = AsyncMcpResource(self._http)

    async def aclose(self) -> None:
        await self._http.aclose()

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        await self.aclose()
