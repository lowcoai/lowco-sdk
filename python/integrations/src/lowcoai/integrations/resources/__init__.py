"""Resource classes behind :class:`IntegrationsClient` / :class:`AsyncIntegrationsClient`.

One module per resource of the TypeScript SDK (``src/resources/*.ts``); each
holds a sync class and its asyncio twin. They are normally reached through the
client (``client.applications``, ``client.oauth``, ...) but can be built
directly on top of an :class:`HttpClient` / :class:`AsyncHttpClient`.
"""

from .actions import ActionsResource, AsyncActionsResource
from .applications import ApplicationsResource, AsyncApplicationsResource
from .configurations import AsyncConfigurationsResource, ConfigurationsResource
from .connections import AsyncConnectionsResource, ConnectionsResource
from .mcp import AsyncMcpResource, McpResource
from .oauth import AsyncOAuthResource, OAuthResource
from .triggers import AsyncTriggersResource, TriggersResource

__all__ = [
    "ActionsResource",
    "ApplicationsResource",
    "AsyncActionsResource",
    "AsyncApplicationsResource",
    "AsyncConfigurationsResource",
    "AsyncConnectionsResource",
    "AsyncMcpResource",
    "AsyncOAuthResource",
    "AsyncTriggersResource",
    "ConfigurationsResource",
    "ConnectionsResource",
    "McpResource",
    "OAuthResource",
    "TriggersResource",
]
