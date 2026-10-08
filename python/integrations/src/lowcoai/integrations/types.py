"""Wire types for the integrations-manager API (routes under ``/v1/integrations/*``).

Every type is a ``TypedDict`` whose keys match the JSON the service sends and
accepts (camelCase), so a value returned by one call can be passed straight
back as the body of another. Fields are optional unless marked ``Required``
(i.e. non-optional in the TypeScript SDK).
"""

from typing import Any, Generic, Literal, TypeVar, Union

from typing_extensions import Required, TypedDict

__all__ = [
    "ApiEnvelope",
    "Application",
    "ApplicationAction",
    "ApplicationHistory",
    "ApplicationSubType",
    "ApplicationTrigger",
    "ApplicationType",
    "ApplicationWithConnection",
    "ApplicationWithCount",
    "AuthToken",
    "BaseEntity",
    "CallbackRequest",
    "Connection",
    "ConnectionCreateRequest",
    "ConnectionResponse",
    "ConnectionStatus",
    "ConnectionType",
    "HEADER_ORG_ID",
    "HttpActionType",
    "HttpInput",
    "HttpMethod",
    "JsonObject",
    "JsonRpcError",
    "JsonRpcRequest",
    "JsonRpcResponse",
    "JsonValue",
    "McpToolsResponse",
    "OAuthCallbackResult",
    "OAuthLoginUrl",
    "PaginationQuery",
    "PatchTagsRequest",
    "PostmanFolder",
    "Primitive",
    "RefreshExpiringTokensResult",
    "RunActionRequest",
    "RunApplicationRequest",
    "SetAsDefaultRequest",
    "SubApplicationConfig",
    "TriggerState",
]

HEADER_ORG_ID = "X-Org-Id"

_T = TypeVar("_T")

# --- JSON helpers -------------------------------------------------------------

Primitive = str | int | float | bool | None
# ``Union`` rather than ``|``: the recursive members are quoted forward references.
JsonValue = Union[Primitive, "JsonObject", list["JsonValue"]]
JsonObject = dict[str, JsonValue]

HttpMethod = Literal["GET", "POST", "PUT", "PATCH", "DELETE"]


class ApiEnvelope(TypedDict, Generic[_T], total=False):
    """The service's response envelope. The client unwraps ``data`` for you.

    The TypeScript interface also allows arbitrary extra keys.
    """

    success: bool
    code: str
    message: str
    data: _T
    error: Any


class BaseEntity(TypedDict, total=False):
    id: str
    orgId: str
    createdBy: str
    updatedBy: str
    createdAt: str
    updatedAt: str


class PaginationQuery(TypedDict, total=False):
    """Query string for list endpoints.

    The TypeScript type is open-ended (``[key: string]: string | number |
    boolean``); methods therefore also accept any ``Mapping[str, Any]`` so
    extra filters pass straight through. ``tags`` is a comma-separated list.
    """

    page: int
    limit: int
    sortBy: str
    sortOrder: Literal["asc", "desc"]
    filter: str
    tags: str


# --- String unions (open-ended in the TS SDK via ``(string & {})``) -------------

ApplicationType = str
"""Known values: ``"http"``, ``"database"``, ``"queue"``, ``"storage"``."""

ApplicationSubType = str
"""Known values: ``"http"``, ``"oauth2"``, ``"postgres"``, ``"mysql"``,
``"clickhouse"``, ``"nats"``, ``"mongodb"``, ``"redis"``, ``"rabbitmq"``,
``"kafka"``, ``"sqs"``, ``"qdrant"``, ``"zep"``, ``"opensearch"``."""

ConnectionType = str
"""Known values: ``"oauth2"``."""

ConnectionStatus = str
"""Known values: ``"active"``, ``"inactive"``, ``"revoked"``, ``"expired"``, ``"pending"``."""


# --- Applications ---------------------------------------------------------------


class Application(BaseEntity, total=False):
    name: Required[str]
    description: str
    icon: str
    type: Required[ApplicationType]
    subType: Required[ApplicationSubType]
    operationConfig: dict[str, Any]
    authConfig: dict[str, Any]
    supportProtocol: Any
    tags: list[str]
    version: int
    mcpKey: str
    publishedUrl: str


class ApplicationWithCount(Application, total=False):
    count: Required[int]


class ApplicationHistory(BaseEntity, total=False):
    application: Required[Application]
    comment: str


SubApplicationConfig = dict[ApplicationType, list[ApplicationSubType]]
"""Application type -> its sub types (``Record<ApplicationType, ApplicationSubType[]>``)."""


class PatchTagsRequest(TypedDict, total=False):
    tags: Required[list[str]]


class RunApplicationRequest(TypedDict, total=False):
    credentialId: str
    inputBody: Required[dict[str, Any]]


# --- Actions --------------------------------------------------------------------

HttpInput = dict[str, Any]


class HttpActionType(TypedDict, total=False):
    type: Required[str]
    metadata: HttpInput


class ApplicationAction(BaseEntity, total=False):
    applicationId: Required[str]
    name: Required[str]
    groupName: str
    description: str
    action: Required[HttpActionType]
    properties: Any


class RunActionRequest(TypedDict, total=False):
    credentialId: str
    inputBody: Required[dict[str, Any]]


class PostmanFolder(TypedDict, total=False):
    """A Postman collection folder / item. The TS interface also allows extra keys."""

    name: str
    item: list["PostmanFolder"]
    request: dict[str, Any]


# --- Connections ----------------------------------------------------------------


class Connection(BaseEntity, total=False):
    name: Required[str]
    description: str
    connectionType: Required[ConnectionType]
    applicationType: ApplicationType
    applicationSubType: ApplicationSubType
    connectionStatus: ConnectionStatus
    applicationId: Required[str]
    properties: dict[str, Any]
    isDefault: bool


class ConnectionResponse(Connection, total=False):
    """``Connection`` as returned by ``connections.get_by_id`` (TS re-declares
    ``applicationType`` / ``applicationSubType``; they are inherited here)."""


class ApplicationWithConnection(Application, total=False):
    connections: Required[list[Connection]]
    actionId: str


class SetAsDefaultRequest(TypedDict, total=False):
    applicationId: Required[str]


# --- Triggers -------------------------------------------------------------------


class ApplicationTrigger(BaseEntity, total=False):
    name: Required[str]
    description: str
    operationConfig: dict[str, Any]
    applicationId: Required[str]
    webhookUrl: str


class TriggerState(TypedDict, total=False):
    triggerId: Required[str]
    orgId: str
    cursor: dict[str, Any]
    lastRunAt: str
    lastError: str
    runCount: Required[int]
    leasedBy: str
    leasedUntil: str
    updatedAt: str


# --- OAuth ----------------------------------------------------------------------


class ConnectionCreateRequest(TypedDict, total=False):
    applicationId: Required[str]
    name: str
    description: str


class CallbackRequest(TypedDict, total=False):
    state: Required[str]
    code: Required[str]


class OAuthLoginUrl(TypedDict, total=False):
    url: Required[str]


class OAuthCallbackResult(TypedDict, total=False):
    success: Required[str]


class AuthToken(BaseEntity, total=False):
    requestId: str
    applicationId: Required[str]
    credentialId: Required[str]
    token: Required[str]
    refreshToken: str
    expiresIn: int
    expiry: str
    tokenType: str


class RefreshExpiringTokensResult(TypedDict, total=False):
    checked: Required[int]
    refreshed: Required[int]
    skipped: Required[int]
    failed: Required[int]
    refreshedTokens: Required[list[AuthToken]]
    failures: Required[list[dict[str, Any]]]


# --- MCP (JSON-RPC) -------------------------------------------------------------


class JsonRpcRequest(TypedDict, total=False):
    jsonrpc: Required[str]
    id: str | int | None
    method: Required[str]
    params: Any


class JsonRpcError(TypedDict, total=False):
    code: Required[int]
    message: Required[str]
    data: Any


class JsonRpcResponse(TypedDict, total=False):
    jsonrpc: Required[str]
    id: str | int | None
    result: Any
    error: JsonRpcError


class McpToolsResponse(TypedDict, total=False):
    tools: Required[list[dict[str, Any]]]
