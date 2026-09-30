"""Wire types for the agentx services (agent-manager, agent-kb, agent-executor).

Every type is a ``TypedDict`` whose keys match the JSON the services send and
accept (camelCase), so a value returned by one call can be passed straight
back as the body of another. Fields are optional unless marked ``Required``.
"""

from typing import Any, Final, Literal

from typing_extensions import Required, TypedDict

__all__ = [
    "A2AMessage",
    "A2A_ERROR_CODES",
    "APIErrorPayload",
    "Agent",
    "AgentCapabilities",
    "AgentConfiguration",
    "AgentHistory",
    "AgentInfo",
    "AgentMemoryType",
    "AgentOutputMode",
    "AgentPatch",
    "AgentPublish",
    "AgentSkill",
    "AgentTool",
    "BaseEntity",
    "Conversation",
    "ConversationMessage",
    "CustomRoutingConfig",
    "DEFAULT_EXECUTOR_API_BASE_PATH",
    "DEFAULT_KB_API_BASE_PATH",
    "DEFAULT_MANAGER_API_BASE_PATH",
    "DataPart",
    "Dataset",
    "EmbeddingDbRequest",
    "FilePart",
    "FilePayload",
    "FileWithBytes",
    "FileWithURI",
    "HEADER_ORG_ID",
    "ISODateString",
    "JSONRPCError",
    "JSONRPCRequest",
    "JSONRPCResponse",
    "JSONRPC_ERROR_CODES",
    "KnowledgeBase",
    "ListParams",
    "LlmModel",
    "METHOD_MESSAGE_SEND",
    "MessageContent",
    "MessageRole",
    "MessageSendConfiguration",
    "MessageSendParams",
    "MultiAgentPattern",
    "Part",
    "PartKind",
    "PublishAgentRequest",
    "PushNotificationAuthenticationInfo",
    "PushNotificationConfig",
    "TextPart",
    "UpdatePublishedAgentRequest",
]

HEADER_ORG_ID: Final = "X-Org-Id"

DEFAULT_MANAGER_API_BASE_PATH: Final = "/v1/agentx/manager"
DEFAULT_KB_API_BASE_PATH: Final = "/v1/agentx/kb"
DEFAULT_EXECUTOR_API_BASE_PATH: Final = "/v1/agentx/executors"

ISODateString = str


class BaseEntity(TypedDict, total=False):
    id: str
    orgId: str
    prn: str
    createdAt: ISODateString
    updatedAt: ISODateString | None
    createdBy: str
    updatedBy: str


class ListParams(TypedDict, total=False):
    """Wire names of the list query. List methods take these as keyword arguments
    (``page_no``, ``size``, ``filter``, ``sort``)."""

    pageNo: int
    size: int
    filter: str
    sort: str


class APIErrorPayload(TypedDict, total=False):
    code: str | int
    message: str
    details: dict[str, Any]


# ---------------------------------------------------------------------------
# Manager: agents
# ---------------------------------------------------------------------------

AgentOutputMode = Literal["full_response", "last_message"]

MultiAgentPattern = Literal["hierarchy", "supervisor", "network", "planner"]

AgentMemoryType = Literal["lowco"]


class CustomRoutingConfig(TypedDict, total=False):
    haltCondition: str
    routerFunction: str


class AgentTool(TypedDict, total=False):
    id: str
    source: str
    sourceId: str
    name: str


class AgentCapabilities(TypedDict, total=False):
    streaming: bool
    pushNotifications: bool
    stateTransitionHistory: bool
    extensions: bool


class AgentSkill(TypedDict, total=False):
    id: str
    description: str
    name: list[str]
    tags: list[str]
    examples: str
    inputModes: list[str]
    outputModes: list[str]


class AgentConfiguration(TypedDict, total=False):
    maxTokens: int
    maxIterations: int
    temperature: float
    topK: int


class Agent(BaseEntity, total=False):
    name: str
    description: str
    modelName: str
    prompt: str
    provider: str
    tools: list[AgentTool]
    knowledgeBaseIds: list[str]
    configurations: AgentConfiguration
    outputMode: AgentOutputMode
    iconUrl: str | None
    documentationUrl: str | None
    capabilities: AgentCapabilities
    skills: list[AgentSkill]
    memoryType: AgentMemoryType | None
    subAgentPattern: MultiAgentPattern | None
    subAgents: list[str]
    routingConfig: CustomRoutingConfig | None
    published: bool
    version: int
    applicationWithCredential: dict[str, str]
    welcomeMessage: str | None
    tags: list[str]
    modelId: str
    """Server-enriched field populated by ``list_agents``."""


class AgentInfo(TypedDict, total=False):
    id: str
    name: str
    modelName: str
    welcomeMessage: str


class AgentHistory(BaseEntity, total=False):
    agent: Agent
    comment: str


class AgentPatch(TypedDict, total=False):
    tags: list[str]


class AgentPublish(BaseEntity, total=False):
    agent: Agent | None
    sourceOrgId: str
    agentId: str
    longDescription: str
    category: str
    latestVersion: int
    """Server-enriched field populated by ``list_published_agents``."""


class PublishAgentRequest(TypedDict, total=False):
    longDescription: str
    category: str


class UpdatePublishedAgentRequest(TypedDict, total=False):
    longDescription: str
    category: str
    agentId: str


# ---------------------------------------------------------------------------
# Manager: LLM models
# ---------------------------------------------------------------------------


class LlmModel(BaseEntity, total=False):
    name: str
    description: str
    provider: str
    icon: str
    disabled: bool
    config: dict[str, Any]
    embedding: bool


# ---------------------------------------------------------------------------
# Manager: conversations
# ---------------------------------------------------------------------------

MessageContent = str | list[dict[str, Any]]
"""Either a plain string or a list of block objects (opaque polymorphic JSON)."""


class Conversation(BaseEntity, total=False):
    chatType: str
    lastMessage: MessageContent | None
    """Server-enriched on ``list_conversations_by_agent``."""
    count: int
    welcomeMessage: str
    """Server-enriched on ``create_conversation`` when this is the first conversation."""


class ConversationMessage(BaseEntity, total=False):
    conversationId: str
    role: str
    content: MessageContent
    memberId: str | None
    chatType: str
    metadata: dict[str, Any]


# ---------------------------------------------------------------------------
# KB
# ---------------------------------------------------------------------------


class KnowledgeBase(BaseEntity, total=False):
    name: str
    description: str
    connectionId: str
    modelId: str


class Dataset(BaseEntity, total=False):
    name: str
    knowledgeBaseId: str
    content: str


class EmbeddingDbRequest(TypedDict, total=False):
    """Body for ``POST /v1/agentx/kb/embeddings``.

    ``distance`` values are Qdrant distance-metric names (e.g. ``"Cosine"``,
    ``"Dot"``, ``"Euclid"``).
    """

    modelId: str
    credentialId: str
    texts: str
    payload: dict[str, Any]
    collection: str
    distance: str


# ---------------------------------------------------------------------------
# Executor (A2A JSON-RPC + SSE)
# ---------------------------------------------------------------------------

METHOD_MESSAGE_SEND: Final = "message/send"
"""The only JSON-RPC method handled by the executor today."""

PartKind = Literal["text", "file", "data"]

MessageRole = Literal["user", "assistant"]


class TextPart(TypedDict, total=False):
    kind: Required[Literal["text"]]
    text: Required[str]
    metadata: dict[str, Any]


class FileWithBytes(TypedDict, total=False):
    name: str | None
    mimeType: str | None
    bytes: Required[str]
    """Base64-encoded file content."""


class FileWithURI(TypedDict, total=False):
    name: str | None
    mimeType: str | None
    uri: Required[str]


FilePayload = FileWithBytes | FileWithURI


class FilePart(TypedDict, total=False):
    kind: Required[Literal["file"]]
    file: Required[FilePayload]
    metadata: dict[str, Any]


class DataPart(TypedDict, total=False):
    kind: Required[Literal["data"]]
    data: Required[dict[str, Any]]
    metadata: dict[str, Any]


Part = TextPart | FilePart | DataPart


class A2AMessage(TypedDict, total=False):
    """Single A2A communication turn (executor input/output).

    Named ``A2AMessage`` to avoid colliding with the manager's ``ConversationMessage``.
    """

    role: Required[MessageRole]
    parts: Required[list[Part]]
    metadata: dict[str, Any]
    extensions: list[str]
    referenceTaskIds: list[str]
    messageId: Required[str]
    taskId: str | None
    contextId: str | None
    kind: Required[Literal["message"]]


class PushNotificationAuthenticationInfo(TypedDict, total=False):
    schemes: Required[list[str]]
    credentials: str | None


class PushNotificationConfig(TypedDict, total=False):
    id: str | None
    url: Required[str]
    token: str | None
    authentication: PushNotificationAuthenticationInfo


class MessageSendConfiguration(TypedDict, total=False):
    acceptedOutputModes: list[str]
    historyLength: int
    pushNotificationConfig: PushNotificationConfig
    blocking: bool


class MessageSendParams(TypedDict, total=False):
    message: Required[A2AMessage]
    configuration: MessageSendConfiguration
    metadata: dict[str, Any]
    chatType: str


class JSONRPCRequest(TypedDict, total=False):
    jsonrpc: Required[Literal["2.0"]]
    method: Required[str]
    params: Any
    id: str | int | None
    """The executor reuses the JSON-RPC ``id`` as the target agent identifier."""


class JSONRPCError(TypedDict, total=False):
    code: Required[int]
    message: Required[str]
    data: Any


class JSONRPCResponse(TypedDict, total=False):
    jsonrpc: Required[Literal["2.0"]]
    result: Any
    error: JSONRPCError
    id: str | int | None


JSONRPC_ERROR_CODES: Final[dict[str, int]] = {
    "ParseError": -32700,
    "InvalidRequest": -32600,
    "MethodNotFound": -32601,
    "InvalidParams": -32602,
    "InternalError": -32603,
}
"""Standard JSON-RPC error codes."""

A2A_ERROR_CODES: Final[dict[str, int]] = {
    "TaskNotFound": -32001,
    "TaskNotCancelable": -32002,
    "PushNotificationNotSupported": -32003,
    "UnsupportedOperation": -32004,
    "ContentTypeNotSupported": -32005,
    "InvalidAgentResponse": -32006,
}
"""A2A-specific error codes (-32000 to -32099)."""
