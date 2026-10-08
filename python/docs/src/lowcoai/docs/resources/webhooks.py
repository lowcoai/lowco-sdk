"""``/v1/documents/webhooks``."""

from __future__ import annotations

import builtins

from .._base import API_PREFIX, seg
from .._http import AsyncHttpClient, HttpClient
from ..types import Webhook, WebhookRequest

__all__ = ["AsyncWebhooksResource", "WebhooksResource"]

_PATH = f"{API_PREFIX}/webhooks"


class WebhooksResource:
    """Webhooks: call a URL when an object event happens under a prefix."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def list(self, *, page: int | None = None, limit: int | None = None) -> builtins.list[Webhook]:
        """Lists the org's webhooks visible to the caller (``page`` / ``limit`` are the
        platform's standard list query)."""
        return self._http.request("GET", _PATH, query={"page": page, "limit": limit})

    def create(self, body: WebhookRequest) -> Webhook:
        """Creates a webhook (``url``, ``method``, ``prefix`` and one event type are
        required)."""
        return self._http.request("POST", _PATH, body)

    def get(self, id: str) -> Webhook:
        """Returns one webhook."""
        return self._http.request("GET", f"{_PATH}/{seg(id)}")

    def update(self, id: str, body: WebhookRequest) -> Webhook:
        """Replaces every field of a webhook (it keeps its author)."""
        return self._http.request("PUT", f"{_PATH}/{seg(id)}", body)

    def delete(self, id: str) -> None:
        """Deletes a webhook."""
        self._http.request_void("DELETE", f"{_PATH}/{seg(id)}")


class AsyncWebhooksResource:
    """Asyncio variant of :class:`WebhooksResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def list(
        self, *, page: int | None = None, limit: int | None = None
    ) -> builtins.list[Webhook]:
        """Lists the org's webhooks visible to the caller (``page`` / ``limit`` are the
        platform's standard list query)."""
        return await self._http.request("GET", _PATH, query={"page": page, "limit": limit})

    async def create(self, body: WebhookRequest) -> Webhook:
        """Creates a webhook (``url``, ``method``, ``prefix`` and one event type are
        required)."""
        return await self._http.request("POST", _PATH, body)

    async def get(self, id: str) -> Webhook:
        """Returns one webhook."""
        return await self._http.request("GET", f"{_PATH}/{seg(id)}")

    async def update(self, id: str, body: WebhookRequest) -> Webhook:
        """Replaces every field of a webhook (it keeps its author)."""
        return await self._http.request("PUT", f"{_PATH}/{seg(id)}", body)

    async def delete(self, id: str) -> None:
        """Deletes a webhook."""
        await self._http.request_void("DELETE", f"{_PATH}/{seg(id)}")
