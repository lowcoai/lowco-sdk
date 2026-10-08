"""``/v1/wf/webhook`` (mirrors ``resources/webhooks.ts``).

Only the trigger is ported. The workflow orchestrator no longer serves the
webhook list / register / update / delete routes (webhook registration lives in
the integrations service), and ``POST /v1/wf/webhook/{id}`` is the trigger, so
the TS SDK's ``create`` would run the workflow instead of registering anything.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from .._base import seg
from .._http import AsyncHttpClient, HttpClient

__all__ = ["AsyncWebhooksResource", "WebhooksResource"]


class WebhooksResource:
    """Fires a workflow through its webhook trigger."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def trigger(
        self,
        workflow_id: str,
        payload: Mapping[str, Any] | None = None,
        *,
        env: str | None = None,
        triggered_by: str | None = None,
        async_: bool | None = None,
    ) -> dict[str, Any]:
        """Fires the workflow's webhook trigger with ``payload`` (default ``{}``).

        ``env``, ``triggered_by`` and ``async_`` are sent as the ``env``,
        ``triggeredBy`` and ``async`` query parameters.
        """
        return self._http.request(
            "POST",
            f"/v1/wf/webhook/{seg(workflow_id)}",
            {} if payload is None else payload,
            query={"env": env, "triggeredBy": triggered_by, "async": async_},
        )


class AsyncWebhooksResource:
    """Asyncio variant of :class:`WebhooksResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def trigger(
        self,
        workflow_id: str,
        payload: Mapping[str, Any] | None = None,
        *,
        env: str | None = None,
        triggered_by: str | None = None,
        async_: bool | None = None,
    ) -> dict[str, Any]:
        """Fires the workflow's webhook trigger with ``payload`` (default ``{}``).

        ``env``, ``triggered_by`` and ``async_`` are sent as the ``env``,
        ``triggeredBy`` and ``async`` query parameters.
        """
        return await self._http.request(
            "POST",
            f"/v1/wf/webhook/{seg(workflow_id)}",
            {} if payload is None else payload,
            query={"env": env, "triggeredBy": triggered_by, "async": async_},
        )
