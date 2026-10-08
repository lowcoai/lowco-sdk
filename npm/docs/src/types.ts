// Types for the lowco document service. Payload and request shapes mirror the
// `definitions` of the service's OpenAPI spec
// (document/services/manager/docs/swagger.json). The spec marks no property as
// required, so response fields are optional; request fields the server rejects
// when missing are marked required here.

export type Primitive = string | number | boolean | null;
export type JsonValue = Primitive | JsonObject | JsonValue[];
export type JsonObject = { [key: string]: JsonValue };
/** A free-form JSON object (the spec's untyped `object`). */
export type JsonMap = Record<string, unknown>;

export type HttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

// ---------------------------------------------------------------------------
// Client configuration and transport
// ---------------------------------------------------------------------------

export interface DocsClientConfig {
  /** User token or API key sent as `Authorization: Bearer <token>` on every request. Required. */
  token: string;
  /** Organization id sent as `X-Org-Id` on every request. Required: the service rejects requests without it. */
  orgId: string;
  /** Per-request timeout in milliseconds. Defaults to 30000. */
  timeoutMs?: number;
  /** Extra headers sent with every request. */
  headers?: Record<string, string>;
  /** Custom `fetch` implementation. Defaults to the global `fetch` (Node 18+). */
  fetch?: typeof globalThis.fetch;
}

/** Alias of {@link DocsClientConfig}, matching the other lowco SDKs. */
export type SDKConfig = DocsClientConfig;

export interface RequestOptions {
  query?: Record<string, unknown>;
  headers?: Record<string, string>;
  signal?: AbortSignal;
}

/** Success envelope of every JSON response: `{ "status": 1, "data": <payload> }`. */
export interface ApiEnvelope<T> {
  status?: number;
  data?: T;
  [key: string]: unknown;
}

/** Error body built by the service's response builder: `{ "status": 0, "error": { ... } }`. */
export interface ErrorBody {
  /** Platform error code (e.g. `AAS-00106`) or a readable message. */
  message?: string;
  /** HTTP status the server meant. */
  code?: number;
  /** Readable detail when `message` is a platform code. */
  details?: string;
}

/** `{ "status": 0, "error": { message, code, details } }` */
export interface ErrorResponse {
  status?: number;
  error?: ErrorBody;
}

/** `{ "message": "..." }`: auth, access and validation failures. */
export interface HttpErrorBody {
  message?: string;
}

/** Current state of a file whose conditional save failed (412), found in `DocsError.payload.data`. */
export interface PreconditionState {
  currentEtag?: string;
  updatedAt?: string;
  updatedBy?: string;
}

/** Error part of a 412 response. */
export interface PreconditionErrorBody {
  /** "the file was changed by someone else", "the file no longer exists" or "the file already exists". */
  message?: string;
  code?: number;
}

/** 412 body of a failed conditional save (`files.update` / `files.updateAt`). */
export interface PreconditionFailedResponse {
  status?: number;
  data?: PreconditionState;
  error?: PreconditionErrorBody;
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

export type NodeType = "file" | "folder";
/** `org` = visible library root, `user` = `.users/{userId}/`, `app` = `.apps/{appKey}/`, `system` = other dot-prefixed areas. */
export type NodeSpace = "org" | "user" | "app" | "system";
export type NodeVisibility = "private" | "org" | "custom";
/** The caller's role on a file or node. */
export type AccessRole = "owner" | "editor" | "viewer";
export type EventType = "create" | "update" | "delete";
export type PipelineType =
  | "custom_workflow"
  | "extract_text"
  | "ocr"
  | "summarize"
  | "classify_tag"
  | "kb_ingest"
  | "thumbnail";
/** Pipelines a folder automation can be created with. */
export type EnabledPipelineType = "custom_workflow" | "extract_text" | "thumbnail";
/** Events a folder automation can run on. */
export type FolderConfigEventType = "create" | "update";
export type ProcessingJobStatus = "queued" | "dispatched" | "succeeded" | "failed";
export type ShareRole = "viewer" | "editor";
/** `user` = one org member (subjectId = user id), `org` = every member of the org. */
export type ShareSubjectType = "user" | "org";
/** Behaviour of an upload when the name is taken: `replace` (default) or `rename` ("name(1).ext"). */
export type OnConflict = "replace" | "rename";

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/** Fields every stored entity carries. */
export interface BaseEntity {
  id?: string;
  orgId?: string;
  prn?: string;
  createdAt?: string;
  createdBy?: string;
  updatedAt?: string;
  updatedBy?: string;
  deletedAt?: string;
  deletedBy?: string;
}

/** A file or folder as listings and file operations return it. */
export interface Document {
  id?: string;
  name?: string;
  path?: string;
  type?: NodeType;
  /** Parent folder path. */
  parentId?: string;
  size?: number;
  category?: string;
  contentType?: string;
  /** File body; set only by reads and saves of one file. */
  content?: string;
  /** Stored object's entity tag (unquoted); set by saves so the next save can be conditional. */
  etag?: string;
  baseUrl?: string;
  publicUrl?: string;
  /** Short-lived presigned URL; present only when presigning is enabled. */
  signedUrl?: string;
  /** Per-view extras, e.g. role, etag, sharing, thumbnailUrl. */
  metadata?: Record<string, string>;
  isTrashed?: boolean;
  orgId?: string;
  prn?: string;
  createdAt?: string;
  createdBy?: string;
  updatedAt?: string;
  updatedBy?: string;
  deletedAt?: string;
  deletedBy?: string;
}

/** Node metadata with the caller's role. */
export interface NodeView {
  id?: string;
  orgId?: string;
  prn?: string;
  appKey?: string;
  bucket?: string;
  key?: string;
  parentKey?: string;
  name?: string;
  type?: NodeType;
  space?: NodeSpace;
  visibility?: NodeVisibility;
  /** Owner of the personal space holding the key (`""` outside `.users/`). */
  ownerId?: string;
  /** The caller's role on the node. */
  role?: AccessRole;
  size?: number;
  category?: string;
  checksum?: string;
  contentType?: string;
  metadata?: JsonMap;
  isTrashed?: boolean;
  trashedAt?: string;
  trashedBy?: string;
  restoreKey?: string;
  createdAt?: string;
  createdBy?: string;
  updatedAt?: string;
  updatedBy?: string;
  deletedAt?: string;
  deletedBy?: string;
}

/** A file read by path (`files.read`): body plus what a conditional save needs. */
export interface FileContent {
  id?: string;
  name?: string;
  path?: string;
  type?: "file";
  size?: number;
  contentType?: string;
  /** Etag of exactly the version read; send it back as `ifMatch`. */
  etag?: string;
  /** The caller's role on the file. */
  role?: AccessRole;
  /** Owner of the personal space holding the file (`""` outside `.users/`). */
  ownerId?: string;
  updatedAt?: string;
  updatedBy?: string;
  /** File body; absent when read with `meta: true`. */
  content?: string;
}

/** Storage usage of a bucket, split between visible and system (dot-prefixed) content. */
export interface BucketStats {
  folderCount?: number;
  totalFiles?: number;
  totalSize?: number;
  visibleFiles?: number;
  visibleSize?: number;
  systemFiles?: number;
  systemSize?: number;
}

/** One row of a zip listing. */
export interface ArchiveEntry {
  name?: string;
  size?: number;
  compressedSize?: number;
  isDir?: boolean;
}

/** Entries of a stored zip. */
export interface ArchiveListing {
  path?: string;
  count?: number;
  entries?: ArchiveEntry[];
}

/** 202 body for a file in cold storage whose restore was requested. */
export interface ArchiveRestoring {
  status?: "restoring";
  nodeId?: string;
  name?: string;
  retryAfterSeconds?: number;
  message?: string;
}

/** Result of a folder upload: the folder and the files written. */
export interface UploadFolderResult {
  folder?: Document;
  files?: Document[];
}

/** A file stored under `.apps/{appKey}/`. */
export interface AppFileUpload {
  appKey?: string;
  name?: string;
  path?: string;
  size?: number;
  contentType?: string;
  /** Absent when the node index is unavailable. */
  nodeId?: string;
  /** Survives renames: store it instead of a storage URL. */
  permalink?: string;
  publicUrl?: string;
  /** Present only when presigning is enabled. */
  signedUrl?: string;
}

/** Report of an app retention sweep. With no archive tier, `skipped` is true and nothing changes. */
export interface AppFilesSweep {
  prefix?: string;
  skipped?: boolean;
  reason?: string;
  olderThan?: string;
  candidates?: number;
  archived?: number;
  failed?: number;
}

/** A share grant on a My Drive item. */
export interface Share extends BaseEntity {
  bucket?: string;
  nodeId?: string;
  subjectType?: ShareSubjectType;
  subjectId?: string;
  role?: ShareRole;
  expiresAt?: string;
}

/** An org-scope share link. */
export interface ShareLink extends BaseEntity {
  bucket?: string;
  nodeId?: string;
  token?: string;
  scope?: string;
  role?: ShareRole;
  active?: boolean;
  expiresAt?: string;
}

/** A newly minted share link. */
export interface ShareLinkCreated {
  id?: string;
  token?: string;
  /** API path that resolves the link (see `sharing.resolveLink`). */
  url?: string;
  scope?: "org";
  expiresAt?: string;
}

/** A folder automation rule. */
export interface FolderConfig extends BaseEntity {
  bucket?: string;
  /** Folder key the rule is attached to (trailing slash). */
  prefix?: string;
  pipelineType?: PipelineType;
  workflowId?: string;
  workflowName?: string;
  /** Which files run (e.g. `[".pdf"]`); empty = all. */
  fileSuffixes?: string[];
  /** Which events fire; empty = create only. */
  eventTypes?: FolderConfigEventType[];
  active?: boolean;
  config?: JsonMap;
}

/** One run of a folder automation pipeline. */
export interface ProcessingJob extends BaseEntity {
  bucket?: string;
  key?: string;
  nodeId?: string;
  folderConfigId?: string;
  eventType?: EventType;
  pipelineType?: PipelineType;
  status?: ProcessingJobStatus;
  attempts?: number;
  error?: string;
  result?: JsonMap;
}

/** Runs a workflow when a matching object event happens. */
export interface Trigger extends BaseEntity {
  eventType?: EventType;
  active?: boolean;
  workflowId?: string;
  workflowName?: string;
  prefix?: string;
  suffix?: string;
}

/** Calls a URL when a matching object event happens. */
export interface Webhook extends BaseEntity {
  url?: string;
  method?: string;
  headers?: Record<string, string>;
  eventTypes?: EventType[];
  active?: boolean;
  prefix?: string;
  suffix?: string;
}

// ---------------------------------------------------------------------------
// Request bodies
// ---------------------------------------------------------------------------

/** Creates `folderName` inside `parentName`; a nested name ("a/b/c") creates every missing level. */
export interface CreateFolderRequest {
  folderName: string;
  /** Folder to create in (`""` or omitted = library root). */
  parentName?: string;
}

/** Renames (or moves, when `newName` holds a path) `parentName/oldName` to `parentName/newName`. */
export interface RenameRequest {
  oldName: string;
  newName: string;
  parentName?: string;
}

/** Creates an empty file at `parentName/fileName`. */
export interface CreateBlankFileRequest {
  fileName: string;
  parentName?: string;
}

/** Saves the whole body of a text file at `parentName/fileName`, creating it when missing. */
export interface UpdateFileRequest {
  fileName: string;
  content: string;
  parentName?: string;
  /** Ignored on input; the response carries the real node id. */
  id?: string;
  /** Etag last read: the save fails with 412 when the file is missing or its etag differs. */
  ifMatch?: string;
  /** `"*"` (the only value accepted) makes the save create-only. Send at most one of ifMatch/ifNoneMatch. */
  ifNoneMatch?: "*" | "";
}

/** Copies a file or folder next to itself. */
export interface DuplicateRequest {
  path: string;
  /** Defaults to `file`. */
  type?: NodeType;
}

/** Stars the item at a bucket path. */
export interface StarByPathRequest {
  path: string;
  /** Defaults to `file`. */
  type?: NodeType;
}

/** Grants a member (or the whole org) access to a My Drive item. */
export interface CreateShareRequest {
  path: string;
  type?: NodeType;
  subjectType: ShareSubjectType;
  /** Grantee's user id; required for user shares, ignored for org shares. */
  subjectId?: string;
  role: ShareRole;
  /** Optional RFC3339 expiry. */
  expiresAt?: string;
}

/** Mints an org-scope link for a My Drive file. */
export interface CreateShareLinkRequest {
  path: string;
  type?: "file";
  /** Optional RFC3339 expiry. */
  expiresAt?: string;
}

/** A folder automation rule. */
export interface FolderConfigRequest {
  /** Watched folder; a trailing "/" is added when missing. */
  prefix: string;
  pipelineType: EnabledPipelineType;
  /** Required for `custom_workflow`. */
  workflowId?: string;
  workflowName?: string;
  fileSuffixes?: string[];
  /** Empty = create only. */
  eventTypes?: FolderConfigEventType[];
  /** Defaults to true when omitted. */
  active?: boolean;
  /** Free-form pipeline configuration stored with the rule. */
  config?: JsonMap;
}

/** Scope of an app retention sweep: `.apps/{appKey}/{prefix}` older than `olderThanDays`. */
export interface SweepRequest {
  prefix?: string;
  /** `<= 0` uses the archive tier's configured retention. */
  olderThanDays?: number;
  /** Caps the files archived in one sweep (`<= 0` = 500). */
  limit?: number;
}

/** Runs `workflowId` when an object event of `eventType` happens under `prefix`. */
export interface TriggerRequest {
  prefix: string;
  workflowId: string;
  eventType?: EventType;
  /** Not defaulted by the server: omitted means `false`. */
  active?: boolean;
  workflowName?: string;
  suffix?: string;
}

/** Calls `url` with `method` when an event in `eventTypes` happens under `prefix`. */
export interface WebhookRequest {
  url: string;
  method: string;
  prefix: string;
  /** At least one of create, update, delete. */
  eventTypes: EventType[];
  /** Sent with every delivery. */
  headers?: Record<string, string>;
  /** Not defaulted by the server: omitted means `false`. */
  active?: boolean;
  suffix?: string;
}

// ---------------------------------------------------------------------------
// Method options
// ---------------------------------------------------------------------------

export interface ListFolderOptions {
  /** Folder path to list (empty = root). */
  prefix?: string;
  /** `false` skips recursive folder sizes (folders then report size 0). */
  sizes?: boolean;
}

export interface ListAtOptions {
  /** `false` skips recursive folder sizes (folders then report size 0). */
  sizes?: boolean;
}

export interface ReadFileOptions {
  /** `true`: metadata only, no content. */
  meta?: boolean;
}

export interface UploadFileOptions {
  /** Destination folder path (empty = library root). Sent as the `ParentID` form field. */
  parentId?: string;
  onConflict?: OnConflict;
}

export interface UploadFolderOptions {
  /** Relative path of each file (same order as the files), e.g. `photos/2026/a.jpg`. Defaults to each file's name. */
  relativePaths?: string[];
  /** Destination folder (empty or the bucket name = root). Sent as the `parentID` form field. */
  parentId?: string;
  /** Destination folder, used when `parentId` is empty. */
  prefix?: string;
}

export interface AppFileUploadOptions {
  /** Folder inside the app area, e.g. `2026/invoices`. */
  path?: string;
  onConflict?: OnConflict;
}

export interface PrefixOptions {
  prefix?: string;
}

export interface ResolveNodeOptions {
  /** `true` makes the resolved URL force a download under the file's name. */
  download?: boolean;
}

export interface StarPathOptions {
  /** Defaults to `file`. */
  type?: NodeType;
}

export interface RecentOptions {
  /** Maximum items (1-200, default 50). */
  limit?: number;
}

export interface ShareQuery {
  /** Item path. */
  path: string;
  /** Defaults to `file`. */
  type?: NodeType;
}

export interface SharedWithMeOptions {
  /** Only items of this app, e.g. `notes`. */
  appKey?: string;
}

export interface JobsOptions {
  /** Only runs of this rule. */
  configId?: string;
  /** Maximum runs (1-200, default 50). */
  limit?: number;
}

export interface PageOptions {
  page?: number;
  limit?: number;
}

// ---------------------------------------------------------------------------
// Uploads and downloads
// ---------------------------------------------------------------------------

/** File bytes plus the name (and optional content type) to upload them under. */
export interface UploadFile {
  data: Blob | ArrayBuffer | ArrayBufferView | string;
  fileName: string;
  contentType?: string;
}

/**
 * Anything an upload method accepts: an {@link UploadFile}, a `File` (its name is
 * used), or a `Blob` (uploaded as "blob" unless wrapped in an {@link UploadFile}).
 */
export type UploadInput = UploadFile | Blob;

/** A downloaded file. */
export interface Binary {
  data: Uint8Array;
  contentType: string;
  /** From `X-File-Name`, else `Content-Disposition`. */
  fileName?: string;
}

/** Alias of {@link Binary}. */
export type FileDownload = Binary;

/**
 * Result of a node endpoint that may answer 202 while a file is restored from
 * cold storage. Exactly one of `url`, `content` and `restoring` is set.
 */
export interface NodeFileResult {
  /** Short-lived URL of the file (`nodes.resolve` answering 307). */
  url?: string;
  /** The file's bytes (200). */
  content?: Binary;
  /** Restore in progress (202): retry later. */
  restoring?: ArchiveRestoring;
  /** Seconds to wait before retrying, from `Retry-After` (else the body's `retryAfterSeconds`). */
  retryAfter?: number;
}
