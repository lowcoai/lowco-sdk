from __future__ import annotations

from ._base import join_path, list_query
from ._transport import AsyncTransport, SyncTransport
from .types import Dataset, EmbeddingDbRequest, KnowledgeBase

__all__ = ["AsyncKBClient", "KBClient"]


class KBClient:
    """Agent-kb (knowledge-base) service routes. Obtain it as ``AgentxClient(...).kb``."""

    def __init__(self, transport: SyncTransport, api_base_path: str) -> None:
        self._t = transport
        self._api_base_path = api_base_path

    def _path(self, *parts: str) -> str:
        return join_path(self._api_base_path, *parts)

    # --- Health ------------------------------------------------------------

    def health(self) -> None:
        """``GET /health`` at the host root."""
        self._t.request_void("GET", "/health")

    # --- Knowledge bases ---------------------------------------------------

    def list_knowledge_bases(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[KnowledgeBase]:
        return self._t.request(
            "GET",
            self._path("knowledges"),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    def create_knowledge_base(self, kb: KnowledgeBase) -> KnowledgeBase:
        return self._t.request("POST", self._path("knowledges"), body=kb, enveloped=True)

    def get_knowledge_base(self, id: str) -> KnowledgeBase:
        return self._t.request("GET", self._path("knowledges", id), enveloped=True)

    def update_knowledge_base(self, id: str, kb: KnowledgeBase) -> KnowledgeBase:
        return self._t.request("PUT", self._path("knowledges", id), body=kb, enveloped=True)

    def get_knowledge_base_count(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> int:
        """The ``/knowledges/count`` endpoint returns a raw integer, not an envelope."""
        return self._t.request(
            "GET",
            self._path("knowledges", "count"),
            query=list_query(page_no, size, filter, sort),
            enveloped=False,
        )

    # --- Datasets ----------------------------------------------------------

    def list_datasets(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[Dataset]:
        return self._t.request(
            "GET",
            self._path("datasets"),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    def create_dataset(self, dataset: Dataset) -> Dataset:
        return self._t.request("POST", self._path("datasets"), body=dataset, enveloped=True)

    def get_dataset(self, id: str) -> Dataset:
        return self._t.request("GET", self._path("datasets", id), enveloped=True)

    def update_dataset(self, id: str, dataset: Dataset) -> Dataset:
        return self._t.request("PUT", self._path("datasets", id), body=dataset, enveloped=True)

    def delete_dataset(self, id: str) -> None:
        self._t.request_void("DELETE", self._path("datasets", id))

    def get_dataset_count(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> int:
        """The ``/datasets/count`` endpoint returns a raw integer, not an envelope."""
        return self._t.request(
            "GET",
            self._path("datasets", "count"),
            query=list_query(page_no, size, filter, sort),
            enveloped=False,
        )

    # --- Embeddings --------------------------------------------------------

    def store_embeddings(self, req: EmbeddingDbRequest) -> str:
        """Persists embeddings into the vector store; returns the service's success message."""
        return self._t.request("POST", self._path("embeddings"), body=req, enveloped=True)


class AsyncKBClient:
    """Agent-kb (knowledge-base) service routes. Obtain it as ``AsyncAgentxClient(...).kb``."""

    def __init__(self, transport: AsyncTransport, api_base_path: str) -> None:
        self._t = transport
        self._api_base_path = api_base_path

    def _path(self, *parts: str) -> str:
        return join_path(self._api_base_path, *parts)

    # --- Health ------------------------------------------------------------

    async def health(self) -> None:
        """``GET /health`` at the host root."""
        await self._t.request_void("GET", "/health")

    # --- Knowledge bases ---------------------------------------------------

    async def list_knowledge_bases(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[KnowledgeBase]:
        return await self._t.request(
            "GET",
            self._path("knowledges"),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    async def create_knowledge_base(self, kb: KnowledgeBase) -> KnowledgeBase:
        return await self._t.request("POST", self._path("knowledges"), body=kb, enveloped=True)

    async def get_knowledge_base(self, id: str) -> KnowledgeBase:
        return await self._t.request("GET", self._path("knowledges", id), enveloped=True)

    async def update_knowledge_base(self, id: str, kb: KnowledgeBase) -> KnowledgeBase:
        return await self._t.request("PUT", self._path("knowledges", id), body=kb, enveloped=True)

    async def get_knowledge_base_count(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> int:
        """The ``/knowledges/count`` endpoint returns a raw integer, not an envelope."""
        return await self._t.request(
            "GET",
            self._path("knowledges", "count"),
            query=list_query(page_no, size, filter, sort),
            enveloped=False,
        )

    # --- Datasets ----------------------------------------------------------

    async def list_datasets(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[Dataset]:
        return await self._t.request(
            "GET",
            self._path("datasets"),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    async def create_dataset(self, dataset: Dataset) -> Dataset:
        return await self._t.request("POST", self._path("datasets"), body=dataset, enveloped=True)

    async def get_dataset(self, id: str) -> Dataset:
        return await self._t.request("GET", self._path("datasets", id), enveloped=True)

    async def update_dataset(self, id: str, dataset: Dataset) -> Dataset:
        return await self._t.request(
            "PUT", self._path("datasets", id), body=dataset, enveloped=True
        )

    async def delete_dataset(self, id: str) -> None:
        await self._t.request_void("DELETE", self._path("datasets", id))

    async def get_dataset_count(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> int:
        """The ``/datasets/count`` endpoint returns a raw integer, not an envelope."""
        return await self._t.request(
            "GET",
            self._path("datasets", "count"),
            query=list_query(page_no, size, filter, sort),
            enveloped=False,
        )

    # --- Embeddings --------------------------------------------------------

    async def store_embeddings(self, req: EmbeddingDbRequest) -> str:
        """Persists embeddings into the vector store; returns the service's success message."""
        return await self._t.request("POST", self._path("embeddings"), body=req, enveloped=True)
