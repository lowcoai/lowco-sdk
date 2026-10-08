"""Wire types for the lowco document service (routes under ``/v1/documents``).

Request and response bodies are ``TypedDict``s generated from the service's
OpenAPI ``definitions`` (``api.*`` / ``model.*``, prefix dropped); their keys
match the JSON on the wire (camelCase), so a value returned by one call can be
passed straight back as the body of another. The spec marks no field as
required, so every key is optional; docstrings note what the service insists on.

:class:`Binary`, :class:`NodeFileResult` and :class:`UploadFile` are not JSON:
they are small frozen dataclasses the SDK builds for downloads, permalink
resolution and multipart uploads.
"""

from dataclasses import dataclass
from typing import IO, Any, Generic, Literal, TypeVar, Union

from typing_extensions import TypedDict

__all__ = [
    "AccessRole",
    "ApiEnvelope",
    "AppFileUpload",
    "AppFilesSweep",
    "ArchiveEntry",
    "ArchiveListing",
    "ArchiveRestoring",
    "BaseEntity",
    "Binary",
    "BucketStats",
    "CreateBlankFileRequest",
    "CreateFolderRequest",
    "CreateShareLinkRequest",
    "CreateShareRequest",
    "Document",
    "DuplicateRequest",
    "ErrorBody",
    "ErrorResponse",
    "EventType",
    "FileContent",
    "FileData",
    "FileInput",
    "FolderConfig",
    "FolderConfigRequest",
    "HEADER_ORG_ID",
    "HTTPErrorBody",
    "HttpMethod",
    "ItemType",
    "JsonObject",
    "JsonValue",
    "NodeFileResult",
    "NodeSpace",
    "NodeType",
    "NodeView",
    "NodeVisibility",
    "OnConflict",
    "PipelineType",
    "PreconditionErrorBody",
    "PreconditionFailedResponse",
    "PreconditionState",
    "Primitive",
    "ProcessingJob",
    "ProcessingJobStatus",
    "RenameRequest",
    "Share",
    "ShareLink",
    "ShareLinkCreated",
    "ShareRole",
    "ShareSubjectType",
    "StarByPathRequest",
    "SweepRequest",
    "Trigger",
    "TriggerRequest",
    "UpdateFileRequest",
    "UploadFile",
    "UploadFolderResult",
    "Webhook",
    "WebhookRequest",
]

HEADER_ORG_ID = "X-Org-Id"

_T = TypeVar("_T")

# --- JSON helpers -------------------------------------------------------------

Primitive = str | int | float | bool | None
# ``Union`` rather than ``|``: the recursive members are quoted forward references.
JsonValue = Union[Primitive, "JsonObject", list["JsonValue"]]
JsonObject = dict[str, JsonValue]

HttpMethod = Literal["GET", "POST", "PUT", "PATCH", "DELETE"]

# --- Enums (``model.*`` string enums and inline ``enum`` lists) ---------------

NodeType = Literal["file", "folder"]
"""``model.NodeType``."""
ItemType = Literal["file", "folder"]
"""The ``type`` of an item addressed by path (shares, stars, duplicates)."""
NodeSpace = Literal["org", "user", "app", "system"]
"""``model.NodeSpace``: the org library, a personal drive, app data or system data."""
NodeVisibility = Literal["private", "org", "custom"]
"""``model.NodeVisibility``."""
AccessRole = Literal["owner", "editor", "viewer"]
"""The caller's role on a file or node."""
EventType = Literal["create", "update", "delete"]
"""``model.EventType``."""
PipelineType = Literal[
    "custom_workflow", "extract_text", "ocr", "summarize", "classify_tag", "kb_ingest", "thumbnail"
]
"""``model.PipelineType``. Rules can currently be created for ``custom_workflow``,
``extract_text`` and ``thumbnail``."""
ProcessingJobStatus = Literal["queued", "dispatched", "succeeded", "failed"]
"""``model.ProcessingJobStatus``."""
ShareRole = Literal["viewer", "editor"]
"""``model.ShareRole``."""
ShareSubjectType = Literal["user", "org"]
"""``model.ShareSubjectType``."""
OnConflict = Literal["replace", "rename"]
"""Upload behaviour when the name is taken (``replace`` is the service default)."""


# --- Envelopes and errors -----------------------------------------------------


class ApiEnvelope(TypedDict, Generic[_T], total=False):
    """The service's success envelope ``{"status": 1, "data": ...}``.

    The client unwraps ``data`` for you.
    """

    status: int
    data: _T


class ErrorBody(TypedDict, total=False):
    """``api.ErrorBody``: ``message`` is an error code (e.g. ``AAS-00106``),
    ``details`` the human-readable reason and ``code`` the HTTP status."""

    message: str
    code: int
    details: str


class ErrorResponse(TypedDict, total=False):
    """``api.ErrorResponse``: ``{"status": 0, "error": {...}}``."""

    status: int
    error: ErrorBody


class HTTPErrorBody(TypedDict, total=False):
    """``api.HTTPError``: ``{"message": "..."}`` (auth, access and validation failures)."""

    message: str


class PreconditionState(TypedDict, total=False):
    """``api.PreconditionState``: the current state of a file whose conditional save failed."""

    currentEtag: str
    updatedAt: str
    updatedBy: str


class PreconditionErrorBody(TypedDict, total=False):
    """``api.PreconditionErrorBody``."""

    message: str
    code: int


class PreconditionFailedResponse(TypedDict, total=False):
    """``api.PreconditionFailedResponse``: the 412 body of a failed conditional save
    (``DocsError.payload`` of :meth:`FilesResource.update`)."""

    status: int
    data: PreconditionState
    error: PreconditionErrorBody


# --- Entities -----------------------------------------------------------------


class BaseEntity(TypedDict, total=False):
    """Fields every stored entity carries."""

    id: str
    orgId: str
    prn: str
    createdAt: str
    createdBy: str
    updatedAt: str
    updatedBy: str
    deletedAt: str
    deletedBy: str


class Document(BaseEntity, total=False):
    """``model.Document``: a file or folder as listings and file calls return it.

    ``metadata`` carries per-view extras (``role``, ``etag``, ``sharing``,
    ``thumbnailUrl``, ...). ``content`` is set only by reads and saves of one file.
    """

    name: str
    path: str
    parentId: str
    type: NodeType
    category: str
    size: int
    contentType: str
    metadata: dict[str, str]
    isTrashed: bool
    publicUrl: str
    signedUrl: str
    baseUrl: str
    content: str
    etag: str


class NodeView(BaseEntity, total=False):
    """``api.NodeView``: node metadata with the caller's ``role``.

    ``ownerId`` is the owner of the personal space holding the key (``""``
    outside ``.users/``).
    """

    bucket: str
    key: str
    parentKey: str
    name: str
    type: NodeType
    category: str
    size: int
    contentType: str
    checksum: str
    ownerId: str
    space: NodeSpace
    appKey: str
    visibility: NodeVisibility
    isTrashed: bool
    trashedAt: str | None
    trashedBy: str
    restoreKey: str
    metadata: dict[str, Any]
    role: AccessRole


class FileContent(TypedDict, total=False):
    """``api.FileContent``: a file read by path, with the ``etag`` of exactly that
    version (send it back as ``ifMatch``) and the caller's ``role``.
    ``content`` is absent when read with ``meta=True``."""

    id: str
    name: str
    path: str
    type: NodeType
    size: int
    contentType: str
    etag: str
    role: AccessRole
    ownerId: str
    updatedAt: str
    updatedBy: str
    content: str


class BucketStats(TypedDict, total=False):
    """``service.BucketStats``: storage usage, split between visible content and
    hidden system content (dot-prefixed areas)."""

    folderCount: int
    totalFiles: int
    totalSize: int
    visibleFiles: int
    visibleSize: int
    systemFiles: int
    systemSize: int


class ArchiveEntry(TypedDict, total=False):
    """``api.ArchiveEntry``: one row of a zip listing."""

    name: str
    size: int
    compressedSize: int
    isDir: bool


class ArchiveListing(TypedDict, total=False):
    """``api.ArchiveListing``: the entries of a stored zip."""

    path: str
    count: int
    entries: list[ArchiveEntry]


class ArchiveRestoring(TypedDict, total=False):
    """``api.ArchiveRestoring``: the 202 body for a file in cold storage whose
    restore was requested; retry after ``retryAfterSeconds``."""

    status: Literal["restoring"]
    nodeId: str
    name: str
    retryAfterSeconds: int
    message: str


class UploadFolderResult(TypedDict, total=False):
    """``api.UploadFolderResult``: the folder and the files written. Files that
    failed to upload are missing from ``files``."""

    folder: Document
    files: list[Document]


class AppFileUpload(TypedDict, total=False):
    """``api.AppFileUpload``: a file stored under ``.apps/{appKey}/``.

    Store ``permalink`` (or ``nodeId``) instead of a storage URL: it survives
    renames. ``nodeId`` / ``permalink`` are absent when the node index is
    unavailable; ``signedUrl`` only when presigning is enabled.
    """

    appKey: str
    name: str
    path: str
    size: int
    contentType: str
    nodeId: str
    permalink: str
    publicUrl: str
    signedUrl: str


class AppFilesSweep(TypedDict, total=False):
    """``api.AppFilesSweep``: an app retention sweep report. With no archive tier
    configured ``skipped`` is true, ``reason`` says why and nothing changes."""

    prefix: str
    skipped: bool
    reason: str
    olderThan: str
    candidates: int
    archived: int
    failed: int


class Share(BaseEntity, total=False):
    """``model.Share``: a grant on a My Drive item."""

    nodeId: str
    bucket: str
    subjectType: ShareSubjectType
    subjectId: str
    role: ShareRole
    expiresAt: str | None


class ShareLink(BaseEntity, total=False):
    """``model.ShareLink``: an org-scope link to a My Drive file."""

    nodeId: str
    bucket: str
    token: str
    scope: str
    role: ShareRole
    expiresAt: str | None
    active: bool


class ShareLinkCreated(TypedDict, total=False):
    """``api.ShareLinkCreated``: a newly minted share link. ``url`` is the API path
    that resolves it (see :meth:`SharingResource.resolve_link`)."""

    id: str
    token: str
    url: str
    scope: Literal["org"]
    expiresAt: str | None


class FolderConfig(BaseEntity, total=False):
    """``model.FolderConfig``: a folder automation rule."""

    bucket: str
    prefix: str
    pipelineType: PipelineType
    workflowId: str
    workflowName: str
    fileSuffixes: list[str]
    eventTypes: list[Literal["create", "update"]]
    active: bool
    config: dict[str, Any]


class ProcessingJob(BaseEntity, total=False):
    """``model.ProcessingJob``: one run of a folder-automation pipeline."""

    folderConfigId: str
    bucket: str
    nodeId: str
    key: str
    pipelineType: PipelineType
    eventType: EventType
    status: ProcessingJobStatus
    attempts: int
    error: str
    result: dict[str, Any]


class Trigger(BaseEntity, total=False):
    """``model.Trigger``: runs a workflow when a matching object event happens."""

    eventType: EventType
    active: bool
    workflowId: str
    workflowName: str
    prefix: str
    suffix: str


class Webhook(BaseEntity, total=False):
    """``model.Webhook``: calls ``url`` when a matching object event happens."""

    url: str
    headers: dict[str, str]
    eventTypes: list[EventType]
    method: str
    active: bool
    prefix: str
    suffix: str


# --- Request bodies -----------------------------------------------------------


class CreateFolderRequest(TypedDict, total=False):
    """``api.CreateFolderRequest``: creates ``folderName`` (required; a nested name
    like ``"a/b/c"`` creates every level) inside ``parentName`` (``""`` = root)."""

    parentName: str
    folderName: str


class RenameRequest(TypedDict, total=False):
    """``api.RenameRequest``: renames ``parentName/oldName`` to ``parentName/newName``
    (``newName`` may hold a path to move the item)."""

    parentName: str
    oldName: str
    newName: str


class CreateBlankFileRequest(TypedDict, total=False):
    """``api.CreateBlankFileRequest``: creates an empty ``parentName/fileName``."""

    parentName: str
    fileName: str


class UpdateFileRequest(TypedDict, total=False):
    """``api.UpdateFileRequest``: writes the whole body of ``parentName/fileName``.

    ``ifMatch`` (the etag last read) or ``ifNoneMatch="*"`` (create-only) make the
    save conditional; a failed condition raises ``DocsError`` with status 412.
    ``id`` is ignored on input.
    """

    id: str
    parentName: str
    fileName: str
    content: str
    ifMatch: str
    ifNoneMatch: str


class DuplicateRequest(TypedDict, total=False):
    """``api.DuplicateRequest``: copies the item at ``path`` next to itself."""

    path: str
    type: ItemType


class StarByPathRequest(TypedDict, total=False):
    """``api.StarByPathRequest``: stars the item at ``path``."""

    path: str
    type: ItemType


class CreateShareRequest(TypedDict, total=False):
    """``api.CreateShareRequest``: grants one member (``subjectType="user"`` with
    ``subjectId``) or the whole org access to a My Drive item.
    ``expiresAt`` is an optional RFC 3339 expiry."""

    path: str
    type: ItemType
    subjectType: ShareSubjectType
    subjectId: str
    role: ShareRole
    expiresAt: str


class CreateShareLinkRequest(TypedDict, total=False):
    """``api.CreateShareLinkRequest``: mints an org-scope link for a My Drive file.
    ``expiresAt`` is an optional RFC 3339 expiry."""

    path: str
    type: Literal["file"]
    expiresAt: str


class FolderConfigRequest(TypedDict, total=False):
    """``api.FolderConfigRequest``: an automation rule on the folder ``prefix``.

    ``custom_workflow`` needs ``workflowId``; empty ``eventTypes`` = create only;
    ``active`` defaults to true; ``config`` is free-form pipeline configuration.
    """

    prefix: str
    pipelineType: Literal["custom_workflow", "extract_text", "thumbnail"]
    workflowId: str
    workflowName: str
    fileSuffixes: list[str]
    eventTypes: list[Literal["create", "update"]]
    active: bool
    config: dict[str, Any]


class SweepRequest(TypedDict, total=False):
    """``api.SweepRequest``: archives files under ``.apps/{appKey}/{prefix}`` older
    than ``olderThanDays`` (``<= 0`` = the archive tier's retention), at most
    ``limit`` per sweep (``<= 0`` = 500)."""

    prefix: str
    olderThanDays: int
    limit: int


class TriggerRequest(TypedDict, total=False):
    """``api.TriggerRequest``: runs ``workflowId`` on ``eventType`` events under
    ``prefix`` (both required), optionally filtered by ``suffix``."""

    eventType: EventType
    active: bool
    workflowId: str
    workflowName: str
    prefix: str
    suffix: str


class WebhookRequest(TypedDict, total=False):
    """``api.WebhookRequest``: calls ``url`` with ``method`` on ``eventTypes`` events
    under ``prefix`` (all required), optionally filtered by ``suffix``.
    ``headers`` are sent with every delivery."""

    url: str
    headers: dict[str, str]
    eventTypes: list[EventType]
    method: str
    active: bool
    prefix: str
    suffix: str


# --- SDK values (not JSON) ----------------------------------------------------


@dataclass(frozen=True)
class Binary:
    """A downloaded file body.

    ``file_name`` comes from the ``X-File-Name`` header, else from the
    ``Content-Disposition`` ``filename``; ``None`` when neither is sent.
    """

    data: bytes
    content_type: str
    file_name: str | None = None


@dataclass(frozen=True)
class NodeFileResult:
    """What a permalink (``nodes.resolve`` / ``nodes.content``) answered.

    Exactly one of ``url`` (a 307 redirect to a short-lived URL), ``content``
    (the bytes, 200) or ``restoring`` (202: the file is being restored from cold
    storage) is set. ``retry_after`` is the ``Retry-After`` header in seconds,
    when present.
    """

    url: str | None = None
    content: Binary | None = None
    restoring: ArchiveRestoring | None = None
    retry_after: int | None = None


FileData = bytes | IO[bytes]
"""File content for an upload: bytes or a binary file object (streamed)."""


@dataclass(frozen=True)
class UploadFile:
    """One file of a multipart upload.

    ``content_type`` defaults to a guess from ``name`` (else
    ``application/octet-stream``).
    """

    name: str
    data: FileData
    content_type: str | None = None


FileInput = UploadFile | tuple[str, FileData] | tuple[str, FileData, str]
"""An :class:`UploadFile`, or a ``(name, data)`` / ``(name, data, content_type)`` tuple."""
