from __future__ import annotations

from collections.abc import Mapping

import httpx
from typing_extensions import Self

from ._base import API_PREFIX, DEFAULT_TIMEOUT, seg
from ._http import AsyncHttpClient, HttpClient
from .resources import (
    AppFilesResource,
    AsyncAppFilesResource,
    AsyncAutomationResource,
    AsyncBucketsResource,
    AsyncFilesResource,
    AsyncFoldersResource,
    AsyncLibraryResource,
    AsyncNodesResource,
    AsyncSharingResource,
    AsyncTriggersResource,
    AsyncWebhooksResource,
    AutomationResource,
    BucketsResource,
    FilesResource,
    FoldersResource,
    LibraryResource,
    NodesResource,
    SharingResource,
    TriggersResource,
    WebhooksResource,
)
from .types import Document

__all__ = ["AsyncDocsClient", "DocsClient"]


class DocsClient:
    """Client for the lowco document service (routes under ``/v1/documents``).

    ``token`` (a user token or API key) and ``org_id`` are required: they are
    sent as ``Authorization: Bearer <token>`` and ``X-Org-Id`` on every
    request. Endpoints are grouped into resources: ``client.buckets``,
    ``client.folders``, ``client.files``, ``client.nodes``, ``client.library``,
    ``client.sharing``, ``client.automation``, ``client.app_files``,
    ``client.triggers`` and ``client.webhooks``; :meth:`health` and
    :meth:`search` live on the client. Use it as a context manager, or call
    :meth:`close`, to release the underlying connection pool.
    """

    buckets: BucketsResource
    folders: FoldersResource
    files: FilesResource
    nodes: NodesResource
    library: LibraryResource
    sharing: SharingResource
    automation: AutomationResource
    app_files: AppFilesResource
    triggers: TriggersResource
    webhooks: WebhooksResource

    def __init__(
        self,
        token: str,
        *,
        org_id: str,
        timeout: float | None = DEFAULT_TIMEOUT,
        headers: Mapping[str, str] | None = None,
        http_client: httpx.Client | None = None,
    ) -> None:
        """
        Args:
            token: User token or API key. Required.
            org_id: Organization id, sent as the ``X-Org-Id`` header. Required.
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
            headers: Extra headers added to every request. An ``Authorization`` or
                ``X-Org-Id`` entry here takes precedence over ``token`` / ``org_id``.
            http_client: Custom ``httpx.Client`` (proxies, retries, mocks). It is
                not closed by :meth:`close`.

        Raises:
            ValueError: ``token`` or ``org_id`` is empty.
        """
        self._http = HttpClient(
            token, org_id=org_id, timeout=timeout, headers=headers, http_client=http_client
        )
        self.buckets = BucketsResource(self._http)
        self.folders = FoldersResource(self._http)
        self.files = FilesResource(self._http)
        self.nodes = NodesResource(self._http)
        self.library = LibraryResource(self._http)
        self.sharing = SharingResource(self._http)
        self.automation = AutomationResource(self._http)
        self.app_files = AppFilesResource(self._http)
        self.triggers = TriggersResource(self._http)
        self.webhooks = WebhooksResource(self._http)

    def health(self) -> str:
        """Liveness probe (``GET /health``); returns the service's text, ``"Working!"``."""
        return self._http.request_text("GET", "/health")

    def search(self, bucket: str, q: str) -> list[Document]:
        """Finds files and folders whose name matches ``q``, then documents whose
        extracted text matches (``metadata.matchedBy == "content"``)."""
        return self._http.request("GET", f"{API_PREFIX}/{seg(bucket)}/search", query={"q": q})

    def close(self) -> None:
        """Closes the internally created ``httpx.Client`` (an injected one is left open)."""
        self._http.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()


class AsyncDocsClient:
    """Asyncio client for the lowco document service (same surface as
    :class:`DocsClient`; every endpoint method is a coroutine).

    Use it as an async context manager, or call :meth:`aclose`, to release the
    underlying connection pool.
    """

    buckets: AsyncBucketsResource
    folders: AsyncFoldersResource
    files: AsyncFilesResource
    nodes: AsyncNodesResource
    library: AsyncLibraryResource
    sharing: AsyncSharingResource
    automation: AsyncAutomationResource
    app_files: AsyncAppFilesResource
    triggers: AsyncTriggersResource
    webhooks: AsyncWebhooksResource

    def __init__(
        self,
        token: str,
        *,
        org_id: str,
        timeout: float | None = DEFAULT_TIMEOUT,
        headers: Mapping[str, str] | None = None,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        """
        Args:
            token: User token or API key. Required.
            org_id: Organization id, sent as the ``X-Org-Id`` header. Required.
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
            headers: Extra headers added to every request. An ``Authorization`` or
                ``X-Org-Id`` entry here takes precedence over ``token`` / ``org_id``.
            http_client: Custom ``httpx.AsyncClient`` (proxies, retries, mocks). It
                is not closed by :meth:`aclose`.

        Raises:
            ValueError: ``token`` or ``org_id`` is empty.
        """
        self._http = AsyncHttpClient(
            token, org_id=org_id, timeout=timeout, headers=headers, http_client=http_client
        )
        self.buckets = AsyncBucketsResource(self._http)
        self.folders = AsyncFoldersResource(self._http)
        self.files = AsyncFilesResource(self._http)
        self.nodes = AsyncNodesResource(self._http)
        self.library = AsyncLibraryResource(self._http)
        self.sharing = AsyncSharingResource(self._http)
        self.automation = AsyncAutomationResource(self._http)
        self.app_files = AsyncAppFilesResource(self._http)
        self.triggers = AsyncTriggersResource(self._http)
        self.webhooks = AsyncWebhooksResource(self._http)

    async def health(self) -> str:
        """Liveness probe (``GET /health``); returns the service's text, ``"Working!"``."""
        return await self._http.request_text("GET", "/health")

    async def search(self, bucket: str, q: str) -> list[Document]:
        """Finds files and folders whose name matches ``q``, then documents whose
        extracted text matches (``metadata.matchedBy == "content"``)."""
        return await self._http.request("GET", f"{API_PREFIX}/{seg(bucket)}/search", query={"q": q})

    async def aclose(self) -> None:
        """Closes the internally created ``httpx.AsyncClient`` (an injected one is left open)."""
        await self._http.aclose()

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        await self.aclose()
