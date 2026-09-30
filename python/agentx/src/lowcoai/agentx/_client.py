from __future__ import annotations

from collections.abc import Mapping

import httpx
from typing_extensions import Self

from . import _base
from ._base import DEFAULT_TIMEOUT, build_headers, normalize_prefix
from ._executor import AsyncExecutorClient, ExecutorClient
from ._kb import AsyncKBClient, KBClient
from ._manager import AsyncManagerClient, ManagerClient
from ._transport import AsyncTransport, SyncTransport
from .types import (
    DEFAULT_EXECUTOR_API_BASE_PATH,
    DEFAULT_KB_API_BASE_PATH,
    DEFAULT_MANAGER_API_BASE_PATH,
)

__all__ = ["AgentxClient", "AsyncAgentxClient"]


class AgentxClient:
    """Unified agentx client.

    Wraps three sub-clients -- :attr:`manager`, :attr:`kb` and :attr:`executor`
    -- that share one HTTP connection pool, one set of default headers and the
    request options. All requests go to ``https://api.lowco.ai``.

    ``token`` (a user token or API key) is required and sent as
    ``Authorization: Bearer <token>`` on every request. Use it as a context
    manager, or call :meth:`close`, to release the underlying connection pool.
    """

    manager: ManagerClient
    """Agent-manager sub-client (agents, published agents, LLM models, conversations)."""
    kb: KBClient
    """Agent-kb sub-client (knowledge bases, datasets, embeddings)."""
    executor: ExecutorClient
    """Agent-executor sub-client (A2A ``message/send``, plain and streamed)."""

    def __init__(
        self,
        token: str,
        *,
        org_id: str | None = None,
        manager_api_base_path: str | None = None,
        kb_api_base_path: str | None = None,
        executor_api_base_path: str | None = None,
        default_headers: Mapping[str, str] | None = None,
        timeout: float | None = DEFAULT_TIMEOUT,
        http_client: httpx.Client | None = None,
    ) -> None:
        """
        Args:
            token: User token or API key. Required.
            org_id: ``X-Org-Id`` header value.
            manager_api_base_path: Agent-manager route prefix; defaults to
                ``"/v1/agentx/manager"``.
            kb_api_base_path: Agent-kb route prefix; defaults to ``"/v1/agentx/kb"``.
            executor_api_base_path: Agent-executor route prefix; defaults to
                ``"/v1/agentx/executors"``.
            default_headers: Extra headers added to every request.
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
                ``executor.stream_message`` does not apply it to reading the stream.
            http_client: Custom ``httpx.Client`` (proxies, retries, mocks). It is
                not closed by :meth:`close`.
        """
        self._headers = build_headers(token, org_id, default_headers)
        self._transport = SyncTransport(self._headers, timeout, http_client)
        self.manager = ManagerClient(
            self._transport,
            normalize_prefix(manager_api_base_path or DEFAULT_MANAGER_API_BASE_PATH),
        )
        self.kb = KBClient(
            self._transport, normalize_prefix(kb_api_base_path or DEFAULT_KB_API_BASE_PATH)
        )
        self.executor = ExecutorClient(
            self._transport,
            normalize_prefix(executor_api_base_path or DEFAULT_EXECUTOR_API_BASE_PATH),
        )

    def set_org_id(self, org_id: str | None) -> None:
        """Sets the ``X-Org-Id`` header for later requests; ``None`` removes it."""
        _base.set_org_id(self._headers, org_id)

    def set_header(self, key: str, value: str | None) -> None:
        """Sets / overwrites an arbitrary default header. Pass ``None`` to delete."""
        _base.set_header(self._headers, key, value)

    def close(self) -> None:
        self._transport.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()


class AsyncAgentxClient:
    """Asyncio agentx client (same surface as :class:`AgentxClient`).

    Wraps three sub-clients -- :attr:`manager`, :attr:`kb` and :attr:`executor`
    -- that share one HTTP connection pool, one set of default headers and the
    request options. All requests go to ``https://api.lowco.ai``.

    ``token`` (a user token or API key) is required and sent as
    ``Authorization: Bearer <token>`` on every request. Use it as an async context
    manager, or call :meth:`aclose`, to release the underlying connection pool.
    """

    manager: AsyncManagerClient
    """Agent-manager sub-client (agents, published agents, LLM models, conversations)."""
    kb: AsyncKBClient
    """Agent-kb sub-client (knowledge bases, datasets, embeddings)."""
    executor: AsyncExecutorClient
    """Agent-executor sub-client (A2A ``message/send``, plain and streamed)."""

    def __init__(
        self,
        token: str,
        *,
        org_id: str | None = None,
        manager_api_base_path: str | None = None,
        kb_api_base_path: str | None = None,
        executor_api_base_path: str | None = None,
        default_headers: Mapping[str, str] | None = None,
        timeout: float | None = DEFAULT_TIMEOUT,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        """
        Args:
            token: User token or API key. Required.
            org_id: ``X-Org-Id`` header value.
            manager_api_base_path: Agent-manager route prefix; defaults to
                ``"/v1/agentx/manager"``.
            kb_api_base_path: Agent-kb route prefix; defaults to ``"/v1/agentx/kb"``.
            executor_api_base_path: Agent-executor route prefix; defaults to
                ``"/v1/agentx/executors"``.
            default_headers: Extra headers added to every request.
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
                ``executor.stream_message`` does not apply it to reading the stream.
            http_client: Custom ``httpx.AsyncClient`` (proxies, retries, mocks). It is
                not closed by :meth:`aclose`.
        """
        self._headers = build_headers(token, org_id, default_headers)
        self._transport = AsyncTransport(self._headers, timeout, http_client)
        self.manager = AsyncManagerClient(
            self._transport,
            normalize_prefix(manager_api_base_path or DEFAULT_MANAGER_API_BASE_PATH),
        )
        self.kb = AsyncKBClient(
            self._transport, normalize_prefix(kb_api_base_path or DEFAULT_KB_API_BASE_PATH)
        )
        self.executor = AsyncExecutorClient(
            self._transport,
            normalize_prefix(executor_api_base_path or DEFAULT_EXECUTOR_API_BASE_PATH),
        )

    def set_org_id(self, org_id: str | None) -> None:
        """Sets the ``X-Org-Id`` header for later requests; ``None`` removes it."""
        _base.set_org_id(self._headers, org_id)

    def set_header(self, key: str, value: str | None) -> None:
        """Sets / overwrites an arbitrary default header. Pass ``None`` to delete."""
        _base.set_header(self._headers, key, value)

    async def aclose(self) -> None:
        await self._transport.aclose()

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        await self.aclose()
