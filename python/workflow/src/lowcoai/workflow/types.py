"""Wire types for the workflow-orchestrator API (routes under ``/v1/wf/*``).

Every type is a ``TypedDict`` whose keys match the JSON the service sends and
accepts (camelCase), so a value returned by one call can be passed straight
back as the body of another. Fields are optional unless marked ``Required``
(i.e. non-optional in the TypeScript SDK).
"""

from typing import Any, Generic, Literal, TypeVar, Union

from typing_extensions import Required, TypedDict

__all__ = [
    "ActivityExecutionHistory",
    "ActivityHistoryResponse",
    "ApiEnvelope",
    "BaseEntity",
    "DryRunRequest",
    "Environment",
    "Execution",
    "FunctionEntity",
    "FunctionVersionRequest",
    "HEADER_ORG_ID",
    "HttpMethod",
    "HumanTask",
    "HumanTaskAction",
    "JsonObject",
    "JsonValue",
    "ListExecutionsQuery",
    "PaginationQuery",
    "Primitive",
    "RunWorkflowRequest",
    "Variable",
    "Workflow",
    "WorkflowPublish",
    "WorkflowPublishRequest",
    "WorkflowUI",
    "WorkflowUIEdge",
    "WorkflowUINode",
    "WorkflowUpdateRequest",
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
    """Query string for list / count endpoints.

    The TypeScript type is open-ended (``[key: string]: string | number |
    boolean``); methods therefore also accept any ``Mapping[str, Any]`` so
    extra filters pass straight through.
    """

    page: int
    limit: int
    sortBy: str
    sortOrder: Literal["asc", "desc"]
    where: str


class ListExecutionsQuery(PaginationQuery, total=False):
    """``PaginationQuery & { full?: boolean }`` for ``executions.list``."""

    full: bool


# --- Environments ---------------------------------------------------------------


class Variable(TypedDict, total=False):
    id: str
    name: Required[str]
    value: Required[str]


class Environment(BaseEntity, total=False):
    name: Required[str]
    description: str
    isDefaultEnv: bool
    variables: list[Variable]


# --- Workflows ------------------------------------------------------------------


class WorkflowUINode(TypedDict, total=False):
    """A canvas node. The TypeScript interface also allows arbitrary extra keys."""

    id: Required[str]
    type: str
    data: JsonObject


class WorkflowUIEdge(TypedDict, total=False):
    id: Required[str]
    source: Required[str]
    target: Required[str]
    type: str
    label: str


class WorkflowUI(TypedDict, total=False):
    nodes: Required[list[WorkflowUINode]]
    edges: Required[list[WorkflowUIEdge]]


class Workflow(BaseEntity, total=False):
    name: Required[str]
    description: str
    inputData: dict[str, Any]
    ui: Required[WorkflowUI]
    tags: list[str]
    version: int
    published: bool


class WorkflowUpdateRequest(Workflow, total=False):
    comment: str


class RunWorkflowRequest(TypedDict, total=False):
    """Starts a workflow; pass ``activityId`` + ``executionId`` to resume one."""

    workflowId: Required[str]
    inputData: dict[str, Any]
    environmentId: str
    triggeredBy: str
    orgId: str
    activityId: str
    executionId: str


class WorkflowPublishRequest(TypedDict, total=False):
    """Body of ``workflows.publish`` / ``workflows.update_published``.

    Inline ``{ category: string; longDescription: string }`` in the TypeScript SDK.
    """

    category: Required[str]
    longDescription: Required[str]


class WorkflowPublish(BaseEntity, total=False):
    workflowId: Required[str]
    sourceOrgId: str
    category: str
    longDescription: str
    workflow: Workflow


# --- Functions ------------------------------------------------------------------


class FunctionEntity(BaseEntity, total=False):
    name: Required[str]
    description: str
    body: Required[str]
    version: int
    isActive: bool


class FunctionVersionRequest(TypedDict, total=False):
    function: Required[FunctionEntity]
    comment: str


# --- Human tasks ----------------------------------------------------------------


class HumanTaskAction(TypedDict, total=False):
    text: Required[str]
    value: Required[str]


class HumanTask(BaseEntity, total=False):
    message: Required[str]
    actions: list[HumanTaskAction]
    assignedTo: str
    executionId: Required[str]
    workflowId: Required[str]
    answer: str
    completed: bool
    completedAt: str
    activityId: Required[str]


# --- Executions & activities ----------------------------------------------------


class Execution(BaseEntity, total=False):
    workflowId: Required[str]
    correlationId: str
    version: int
    status: str
    context: dict[str, Any]
    failedReason: str
    inputData: Any
    outputData: Any
    workflow: Workflow


class ActivityExecutionHistory(BaseEntity, total=False):
    activityId: Required[str]
    workflowId: Required[str]
    executionId: Required[str]
    type: str
    typeId: str
    status: str
    inputData: Any
    outputData: Any
    failedReason: str


class ActivityHistoryResponse(TypedDict, total=False):
    id: Required[str]
    history: Required[ActivityExecutionHistory]
    activity: dict[str, Any]
    workflow: Workflow
    execution: Execution


# --- Dry run & webhooks ---------------------------------------------------------


class DryRunRequest(TypedDict, total=False):
    executionId: Required[str]
    expression: Required[str]
    typeOfExpression: Required[Literal["object", "string", "statement", "map"]]
    activityId: Required[str]
