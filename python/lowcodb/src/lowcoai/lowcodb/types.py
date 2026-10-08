"""Wire types for the lowcodb manager API.

Every type is a ``TypedDict`` whose keys match the JSON the manager sends and
accepts (camelCase), so a value returned by one call can be passed straight
back as the body of another. Fields are optional unless marked ``Required``.
"""

from typing import Any, Literal

from typing_extensions import Required, TypedDict

__all__ = [
    "APIErrorPayload",
    "Base",
    "BaseEntity",
    "BaseType",
    "Column",
    "ColumnMetadata",
    "ColumnTrimmed",
    "ColumnsBulkResult",
    "CountResponse",
    "DBFunction",
    "DBFunctionMetadata",
    "DBFunctionUpsertInput",
    "DBFunctionVersion",
    "DashboardResponse",
    "DeleteCountResponse",
    "DropdownOption",
    "Field",
    "FunctionExecuteError",
    "FunctionExecuteResult",
    "FunctionHTTPMethod",
    "HEADER_ORG_ID",
    "ISODateString",
    "LowcodbRecord",
    "OverviewCounts",
    "PublishEventInput",
    "PublishEventResult",
    "RecordsBulkResult",
    "RowsResponse",
    "RunQueryRequest",
    "SuggestionsResponse",
    "SyncTablesResult",
    "Table",
    "TableIndex",
    "TableIndexUpdateInput",
    "TableTrigger",
    "TableView",
    "TableViewKind",
    "TableWebhook",
    "TableWithColumns",
    "TransactionOperation",
    "TransactionOperationType",
    "TransactionResult",
    "ValidationError",
    "ValidationResponse",
    "ViewRefreshResponse",
]

HEADER_ORG_ID = "X-Org-Id"

ISODateString = str


class BaseEntity(TypedDict, total=False):
    id: str
    orgId: str
    prn: str
    createdAt: ISODateString
    updatedAt: ISODateString | None
    createdBy: str
    updatedBy: str


BaseType = Literal["internal", "external"]


class Base(BaseEntity, total=False):
    name: str
    description: str
    connectionId: str
    baseType: BaseType
    schema: str


class Table(BaseEntity, total=False):
    baseId: str
    name: str
    description: str
    tableKey: str
    metadata: dict[str, Any]


class ColumnTrimmed(TypedDict, total=False):
    name: str
    dataType: str


class TableWithColumns(Table, total=False):
    columns: list[ColumnTrimmed]


class ColumnMetadata(TypedDict, total=False):
    option: list[str]
    isNotNull: bool
    isPrimaryKey: bool
    isUnique: bool
    isAutoIncrement: bool
    maxLength: int
    selectType: str


class ValidationError(TypedDict, total=False):
    rule: str
    error: str


class DropdownOption(TypedDict, total=False):
    label: str
    value: str


class Field(TypedDict, total=False):
    value: Any
    dataType: str
    options: list[DropdownOption]
    validations: list[ValidationError]


class ValidationResponse(TypedDict, total=False):
    value: Any
    errors: list[ValidationError]


class Column(BaseEntity, total=False):
    baseId: str
    tableId: str
    name: str
    dataType: str
    metadata: ColumnMetadata
    defaultValue: str
    validations: list[ValidationError]


class TableIndex(BaseEntity, total=False):
    baseId: str
    tableId: str
    indexName: str
    columns: list[str]
    isUnique: bool


class TableIndexUpdateInput(TypedDict, total=False):
    """Rename-only payload accepted by ``PUT /tables/{tableId}/index/{id}``."""

    indexName: str


class TableTrigger(BaseEntity, total=False):
    baseId: str
    tableId: str
    eventType: str
    eventTime: str
    workflowId: str
    workflowName: str
    """Populated only by ``list_triggers`` (enrichment from the workflow service)."""


class TableWebhook(BaseEntity, total=False):
    baseId: str
    tableId: str
    url: str
    headers: dict[str, str]
    eventTypes: list[str]
    method: str
    active: bool


FunctionHTTPMethod = Literal["GET", "POST", "PUT", "PATCH", "DELETE"]


class DBFunctionMetadata(TypedDict, total=False):
    timeoutMs: int
    """Execution timeout in ms; server default 10 000, capped at 55 000."""
    methods: list[FunctionHTTPMethod]
    """HTTP methods the invoke route accepts; defaults to ``["POST"]``."""
    public: bool
    """Reserved: invokable without gateway auth. Defaults to ``False``."""


class DBFunction(BaseEntity, total=False):
    """A user-authored JavaScript function scoped to a base."""

    baseId: str
    name: str
    functionKey: str
    """URL slug the function is invoked under (``/v1/fn/{functionKey}``)."""
    description: str
    body: str
    """JavaScript source. Top-level ``return`` and ``await`` are allowed."""
    version: int
    isActive: bool
    metadata: DBFunctionMetadata


class DBFunctionUpsertInput(TypedDict, total=False):
    """Create/update payload; a body change auto-creates a version snapshot."""

    baseId: str
    name: str
    functionKey: str
    description: str
    body: str
    isActive: bool
    metadata: DBFunctionMetadata
    comment: str
    """Label for the version snapshot created when the body changes."""


class DBFunctionVersion(BaseEntity, total=False):
    functionId: str
    version: int
    body: str
    comment: str


class FunctionExecuteError(TypedDict, total=False):
    code: str
    """``"TIMEOUT"`` | ``"COMPILE_ERROR"`` | ``"FUNCTION_ERROR"``"""
    message: str
    stack: str


class FunctionExecuteResult(TypedDict, total=False):
    """Full console-execution result (returned even when the function itself failed)."""

    success: bool
    result: Any
    logs: list[str]
    error: FunctionExecuteError
    durationMs: int


LowcodbRecord = dict[str, Any]
"""A user-table row. System fields (``id``, ``createdAt``, ...) are always
present alongside whatever columns the table defines."""

TransactionOperationType = Literal["create", "update", "delete"]


class TransactionOperation(TypedDict, total=False):
    """One step of an atomic record transaction."""

    type: Required[TransactionOperationType]
    table: Required[str]
    id: str
    """Required for update and delete."""
    record: LowcodbRecord
    """Fields for create and update."""


class TransactionResult(TypedDict, total=False):
    results: list[LowcodbRecord]
    """Per-operation results, in order: the written row, or ``{deletedCount}`` for deletes."""


class PublishEventInput(TypedDict, total=False):
    """Payload of ``publish_event`` (``ctx.events.publish`` in DB functions)."""

    eventType: Required[str]
    """Event name, e.g. ``"lead.qualified"`` (alphanumeric tokens separated by dots)."""
    tableName: str
    """Scopes the NATS subject's table segment; ``"_"`` when omitted."""
    record: LowcodbRecord
    correlationId: str


class PublishEventResult(TypedDict, total=False):
    published: bool
    subject: str


TableViewKind = Literal["view", "materialized_view"]


class TableView(BaseEntity, total=False):
    baseId: str
    name: str
    description: str
    viewKey: str
    kind: TableViewKind
    definition: str
    metadata: dict[str, Any]


class RunQueryRequest(TypedDict, total=False):
    query: Required[str]
    baseId: str


class RowsResponse(TypedDict, total=False):
    rows: list[dict[str, Any]]


class SuggestionsResponse(TypedDict, total=False):
    suggestions: list[str]


class CountResponse(TypedDict, total=False):
    count: int


class DeleteCountResponse(TypedDict, total=False):
    deletedCount: int


class ViewRefreshResponse(TypedDict, total=False):
    status: str


class ColumnsBulkResult(TypedDict, total=False):
    created: list[Column]
    failed: list[dict[str, Any]]


class RecordsBulkResult(TypedDict, total=False):
    updated: list[LowcodbRecord]
    failed: list[dict[str, Any]]


class OverviewCounts(TypedDict, total=False):
    totals: dict[str, int]
    bases: list[dict[str, Any]]


class SyncTablesResult(TypedDict, total=False):
    tablesAdded: list[str]
    tablesRemoved: list[str]
    tablesUpdated: list[str]
    errors: list[str]


DashboardResponse = dict[str, Any]


class APIErrorPayload(TypedDict, total=False):
    code: str | int
    """The manager sends the numeric HTTP status here, not a string code."""
    message: str
    """The opaque platform code (``"AAS-00105"``), *not* the human message."""
    details: str | dict[str, Any]
    """Where the real message actually lives. A string on the wire."""
