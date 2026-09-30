from __future__ import annotations

from typing import Any

from ._base import join_path, list_query
from ._transport import AsyncTransport, SyncTransport
from .types import (
    Agent,
    AgentHistory,
    AgentPatch,
    AgentPublish,
    Conversation,
    ConversationMessage,
    LlmModel,
    PublishAgentRequest,
    UpdatePublishedAgentRequest,
)

__all__ = ["AsyncManagerClient", "ManagerClient"]


class ManagerClient:
    """Agent-manager service routes. Obtain it as ``AgentxClient(...).manager``."""

    def __init__(self, transport: SyncTransport, api_base_path: str) -> None:
        self._t = transport
        self._api_base_path = api_base_path

    def _path(self, *parts: str) -> str:
        return join_path(self._api_base_path, *parts)

    # --- Health ------------------------------------------------------------

    def health(self) -> None:
        """``GET /health`` at the host root."""
        self._t.request_void("GET", "/health")

    # --- Agents ------------------------------------------------------------

    def list_agents(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[Agent]:
        return self._t.request(
            "GET",
            self._path("agents"),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    def get_agent(self, id: str) -> Agent:
        return self._t.request("GET", self._path("agents", id), enveloped=True)

    def create_agent(self, agent: Agent) -> Agent:
        return self._t.request("POST", self._path("agents"), body=agent, enveloped=True)

    def update_agent(self, id: str, agent: Agent) -> Agent:
        return self._t.request("PUT", self._path("agents", id), body=agent, enveloped=True)

    def patch_agent(self, id: str, patch: AgentPatch) -> Agent:
        return self._t.request("PATCH", self._path("agents", id), body=patch, enveloped=True)

    def get_agent_count(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> int:
        """The ``/agents/count`` endpoint returns a raw integer, not an envelope."""
        return self._t.request(
            "GET",
            self._path("agents", "count"),
            query=list_query(page_no, size, filter, sort),
            enveloped=False,
        )

    def delete_agent(self, id: str) -> None:
        self._t.request_void("DELETE", self._path("agents", id))

    def bulk_delete_agents(self, ids: list[str]) -> None:
        self._t.request_void("POST", self._path("agents", "bulk-delete"), body={"ids": ids})

    def get_agent_versions(
        self,
        id: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[AgentHistory]:
        return self._t.request(
            "GET",
            self._path("agents", id, "versions"),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    # --- Published agents --------------------------------------------------

    def publish_agent(self, agent_id: str, req: PublishAgentRequest) -> AgentPublish:
        return self._t.request(
            "POST", self._path("agents", agent_id, "publish"), body=req, enveloped=True
        )

    def get_published_agent(self, id: str) -> AgentPublish:
        return self._t.request("GET", self._path("agents", "published", id), enveloped=True)

    def update_published_agent(self, id: str, req: UpdatePublishedAgentRequest) -> AgentPublish:
        return self._t.request(
            "PUT", self._path("agents", "published", id), body=req, enveloped=True
        )

    def delete_published_agent(self, id: str) -> None:
        self._t.request_void("DELETE", self._path("agents", "published", id))

    def list_published_agents(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[AgentPublish]:
        return self._t.request(
            "GET",
            self._path("agents", "published"),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    # --- LLM models --------------------------------------------------------

    def create_model(self, model: LlmModel) -> LlmModel:
        return self._t.request("POST", self._path("models"), body=model, enveloped=True)

    def get_model(self, id: str) -> LlmModel:
        return self._t.request("GET", self._path("models", id), enveloped=True)

    def update_model(self, id: str, model: LlmModel) -> LlmModel:
        return self._t.request("PUT", self._path("models", id), body=model, enveloped=True)

    def list_models(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[LlmModel]:
        return self._t.request(
            "GET",
            self._path("models"),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    def delete_model(self, id: str) -> None:
        self._t.request_void("DELETE", self._path("models", id))

    def enable_model(self, id: str, properties: dict[str, Any]) -> LlmModel:
        return self._t.request(
            "PATCH",
            self._path("models", id, "enable"),
            body={"properties": properties},
            enveloped=True,
        )

    def disable_model(self, id: str) -> LlmModel:
        return self._t.request("PATCH", self._path("models", id, "disable"), enveloped=True)

    # --- Conversations -----------------------------------------------------

    def list_conversations_by_agent(
        self,
        agent_id: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[Conversation]:
        return self._t.request(
            "GET",
            self._path("conversations", agent_id),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    def create_conversation(self, agent_id: str) -> Conversation:
        return self._t.request(
            "POST", self._path("conversations"), body={"agentId": agent_id}, enveloped=True
        )

    def delete_conversation(self, id: str) -> None:
        self._t.request_void("DELETE", self._path("conversations", id))

    def get_conversation_messages(self, conversation_id: str) -> list[ConversationMessage]:
        return self._t.request(
            "GET", self._path("conversations", conversation_id, "messages"), enveloped=True
        )


class AsyncManagerClient:
    """Agent-manager service routes. Obtain it as ``AsyncAgentxClient(...).manager``."""

    def __init__(self, transport: AsyncTransport, api_base_path: str) -> None:
        self._t = transport
        self._api_base_path = api_base_path

    def _path(self, *parts: str) -> str:
        return join_path(self._api_base_path, *parts)

    # --- Health ------------------------------------------------------------

    async def health(self) -> None:
        """``GET /health`` at the host root."""
        await self._t.request_void("GET", "/health")

    # --- Agents ------------------------------------------------------------

    async def list_agents(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[Agent]:
        return await self._t.request(
            "GET",
            self._path("agents"),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    async def get_agent(self, id: str) -> Agent:
        return await self._t.request("GET", self._path("agents", id), enveloped=True)

    async def create_agent(self, agent: Agent) -> Agent:
        return await self._t.request("POST", self._path("agents"), body=agent, enveloped=True)

    async def update_agent(self, id: str, agent: Agent) -> Agent:
        return await self._t.request("PUT", self._path("agents", id), body=agent, enveloped=True)

    async def patch_agent(self, id: str, patch: AgentPatch) -> Agent:
        return await self._t.request("PATCH", self._path("agents", id), body=patch, enveloped=True)

    async def get_agent_count(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> int:
        """The ``/agents/count`` endpoint returns a raw integer, not an envelope."""
        return await self._t.request(
            "GET",
            self._path("agents", "count"),
            query=list_query(page_no, size, filter, sort),
            enveloped=False,
        )

    async def delete_agent(self, id: str) -> None:
        await self._t.request_void("DELETE", self._path("agents", id))

    async def bulk_delete_agents(self, ids: list[str]) -> None:
        await self._t.request_void("POST", self._path("agents", "bulk-delete"), body={"ids": ids})

    async def get_agent_versions(
        self,
        id: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[AgentHistory]:
        return await self._t.request(
            "GET",
            self._path("agents", id, "versions"),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    # --- Published agents --------------------------------------------------

    async def publish_agent(self, agent_id: str, req: PublishAgentRequest) -> AgentPublish:
        return await self._t.request(
            "POST", self._path("agents", agent_id, "publish"), body=req, enveloped=True
        )

    async def get_published_agent(self, id: str) -> AgentPublish:
        return await self._t.request("GET", self._path("agents", "published", id), enveloped=True)

    async def update_published_agent(
        self, id: str, req: UpdatePublishedAgentRequest
    ) -> AgentPublish:
        return await self._t.request(
            "PUT", self._path("agents", "published", id), body=req, enveloped=True
        )

    async def delete_published_agent(self, id: str) -> None:
        await self._t.request_void("DELETE", self._path("agents", "published", id))

    async def list_published_agents(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[AgentPublish]:
        return await self._t.request(
            "GET",
            self._path("agents", "published"),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    # --- LLM models --------------------------------------------------------

    async def create_model(self, model: LlmModel) -> LlmModel:
        return await self._t.request("POST", self._path("models"), body=model, enveloped=True)

    async def get_model(self, id: str) -> LlmModel:
        return await self._t.request("GET", self._path("models", id), enveloped=True)

    async def update_model(self, id: str, model: LlmModel) -> LlmModel:
        return await self._t.request("PUT", self._path("models", id), body=model, enveloped=True)

    async def list_models(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[LlmModel]:
        return await self._t.request(
            "GET",
            self._path("models"),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    async def delete_model(self, id: str) -> None:
        await self._t.request_void("DELETE", self._path("models", id))

    async def enable_model(self, id: str, properties: dict[str, Any]) -> LlmModel:
        return await self._t.request(
            "PATCH",
            self._path("models", id, "enable"),
            body={"properties": properties},
            enveloped=True,
        )

    async def disable_model(self, id: str) -> LlmModel:
        return await self._t.request("PATCH", self._path("models", id, "disable"), enveloped=True)

    # --- Conversations -----------------------------------------------------

    async def list_conversations_by_agent(
        self,
        agent_id: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[Conversation]:
        return await self._t.request(
            "GET",
            self._path("conversations", agent_id),
            query=list_query(page_no, size, filter, sort),
            enveloped=True,
        )

    async def create_conversation(self, agent_id: str) -> Conversation:
        return await self._t.request(
            "POST", self._path("conversations"), body={"agentId": agent_id}, enveloped=True
        )

    async def delete_conversation(self, id: str) -> None:
        await self._t.request_void("DELETE", self._path("conversations", id))

    async def get_conversation_messages(self, conversation_id: str) -> list[ConversationMessage]:
        return await self._t.request(
            "GET", self._path("conversations", conversation_id, "messages"), enveloped=True
        )
