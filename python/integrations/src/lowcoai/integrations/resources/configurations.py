"""``/v1/integrations/configurations`` (mirrors ``resources/configurations.ts``)."""

from __future__ import annotations

from .._http import AsyncHttpClient, HttpClient
from ..types import SubApplicationConfig

__all__ = ["AsyncConfigurationsResource", "ConfigurationsResource"]


class ConfigurationsResource:
    """Service configuration."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def get(self) -> SubApplicationConfig:
        """Application type -> supported sub types."""
        return self._http.request("GET", "/v1/integrations/configurations")


class AsyncConfigurationsResource:
    """Asyncio variant of :class:`ConfigurationsResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def get(self) -> SubApplicationConfig:
        """Application type -> supported sub types."""
        return await self._http.request("GET", "/v1/integrations/configurations")
