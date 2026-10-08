package docs

import "net/http"

// HeaderOrgID is the tenancy header sent on every request.
const HeaderOrgID = "X-Org-Id"

// Config configures a Client.
type Config struct {
	// Token is required. It may hold a user token or an API key and is sent
	// as "Authorization: Bearer <token>" on every request.
	Token string
	// OrgID is required: the document service rejects every request without
	// the X-Org-Id header.
	OrgID string
	// TimeoutMS is the request timeout of the default HTTP client in
	// milliseconds (30s when zero). It is not applied to HTTPClient.
	TimeoutMS int
	// Headers are extra headers sent on every request.
	Headers map[string]string
	// HTTPClient replaces the default HTTP client. URL methods never mutate
	// it: they send through a shallow copy that does not follow redirects.
	HTTPClient *http.Client
}

// NodeType tells files from folders.
type NodeType string

// Node types.
const (
	NodeTypeFile   NodeType = "file"
	NodeTypeFolder NodeType = "folder"
)

// NodeSpace is the area of the bucket a node lives in.
type NodeSpace string

// Node spaces.
const (
	// NodeSpaceOrg is the visible root: the org libraries.
	NodeSpaceOrg NodeSpace = "org"
	// NodeSpaceUser is .users/{userId}/: personal drives.
	NodeSpaceUser NodeSpace = "user"
	// NodeSpaceApp is .apps/{appKey}/: app data.
	NodeSpaceApp NodeSpace = "app"
	// NodeSpaceSystem is any other dot-prefixed area.
	NodeSpaceSystem NodeSpace = "system"
)

// NodeVisibility is who can see a node by default.
type NodeVisibility string

// Node visibilities.
const (
	NodeVisibilityPrivate NodeVisibility = "private"
	NodeVisibilityOrg     NodeVisibility = "org"
	NodeVisibilityCustom  NodeVisibility = "custom"
)

// Role is the caller's role on a file or folder.
type Role string

// Caller roles.
const (
	RoleOwner  Role = "owner"
	RoleEditor Role = "editor"
	RoleViewer Role = "viewer"
)

// ShareRole is the access a share grants.
type ShareRole string

// Share roles.
const (
	ShareRoleViewer ShareRole = "viewer"
	ShareRoleEditor ShareRole = "editor"
)

// ShareSubjectType is who a share is granted to.
type ShareSubjectType string

// Share subject types.
const (
	// ShareSubjectUser is one org member (SubjectID = user id).
	ShareSubjectUser ShareSubjectType = "user"
	// ShareSubjectOrg is every member of the org.
	ShareSubjectOrg ShareSubjectType = "org"
)

// EventType is an object event that fires triggers, webhooks and folder
// automations.
type EventType string

// Event types.
const (
	EventTypeCreate EventType = "create"
	EventTypeUpdate EventType = "update"
	EventTypeDelete EventType = "delete"
)

// PipelineType is the pipeline a folder automation runs. The service accepts
// PipelineCustomWorkflow, PipelineExtractText and PipelineThumbnail on new
// rules; the others may appear on existing rules and jobs.
type PipelineType string

// Pipeline types.
const (
	PipelineCustomWorkflow PipelineType = "custom_workflow"
	PipelineExtractText    PipelineType = "extract_text"
	PipelineOCR            PipelineType = "ocr"
	PipelineSummarize      PipelineType = "summarize"
	PipelineClassifyTag    PipelineType = "classify_tag"
	PipelineKBIngest       PipelineType = "kb_ingest"
	PipelineThumbnail      PipelineType = "thumbnail"
)

// ProcessingJobStatus is the state of a folder automation run.
type ProcessingJobStatus string

// Processing job states.
const (
	JobQueued     ProcessingJobStatus = "queued"
	JobDispatched ProcessingJobStatus = "dispatched"
	JobSucceeded  ProcessingJobStatus = "succeeded"
	JobFailed     ProcessingJobStatus = "failed"
)

// OnConflict is what an upload does when the name is already taken.
type OnConflict string

// Upload conflict policies.
const (
	// OnConflictReplace overwrites the existing file (the service default).
	OnConflictReplace OnConflict = "replace"
	// OnConflictRename keeps both by uploading as "name(1).ext", "name(2).ext", ...
	OnConflictRename OnConflict = "rename"
)

// BaseEntity holds the fields every stored entity carries. Timestamps are
// RFC 3339 strings.
type BaseEntity struct {
	ID        string `json:"id,omitempty"`
	OrgID     string `json:"orgId,omitempty"`
	PRN       string `json:"prn,omitempty"`
	CreatedAt string `json:"createdAt,omitempty"`
	CreatedBy string `json:"createdBy,omitempty"`
	UpdatedAt string `json:"updatedAt,omitempty"`
	UpdatedBy string `json:"updatedBy,omitempty"`
	DeletedAt string `json:"deletedAt,omitempty"`
	DeletedBy string `json:"deletedBy,omitempty"`
}

// Document is a file or folder as returned by listings and file operations.
// Listings put the caller's role, the file etag and a sharing badge in
// Metadata ("role", "etag", "sharing").
type Document struct {
	BaseEntity
	Name        string            `json:"name"`
	Path        string            `json:"path"`
	ParentID    string            `json:"parentId"`
	Type        NodeType          `json:"type"`
	Category    string            `json:"category"`
	Size        int64             `json:"size"`
	ContentType string            `json:"contentType"`
	Metadata    map[string]string `json:"metadata,omitempty"`
	IsTrashed   bool              `json:"isTrashed"`
	PublicURL   string            `json:"publicUrl"`
	SignedURL   string            `json:"signedUrl,omitempty"`
	BaseURL     string            `json:"baseUrl"`
	Content     string            `json:"content"`
	ETag        string            `json:"etag,omitempty"`
}

// NodeView is a node's metadata with the caller's role. OwnerID is the owner
// of the personal space holding the key ("" outside .users/).
type NodeView struct {
	BaseEntity
	Bucket      string         `json:"bucket"`
	Key         string         `json:"key"`
	ParentKey   string         `json:"parentKey"`
	Name        string         `json:"name"`
	Type        NodeType       `json:"type"`
	Category    string         `json:"category"`
	Size        int64          `json:"size"`
	ContentType string         `json:"contentType"`
	Checksum    string         `json:"checksum"`
	OwnerID     string         `json:"ownerId"`
	Space       NodeSpace      `json:"space"`
	AppKey      string         `json:"appKey"`
	Visibility  NodeVisibility `json:"visibility"`
	IsTrashed   bool           `json:"isTrashed"`
	TrashedAt   string         `json:"trashedAt,omitempty"`
	TrashedBy   string         `json:"trashedBy"`
	RestoreKey  string         `json:"restoreKey"`
	Metadata    map[string]any `json:"metadata,omitempty"`
	Role        Role           `json:"role"`
}

// FileContent is a file read by path: the body (empty with Meta) plus what a
// careful editor needs for a conditional save.
type FileContent struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Path        string   `json:"path"`
	Type        NodeType `json:"type"`
	Size        int64    `json:"size"`
	ContentType string   `json:"contentType"`
	// ETag is the etag of exactly the version read; send it back as
	// UpdateFileRequest.IfMatch.
	ETag string `json:"etag"`
	// Role is the caller's role on the file.
	Role Role `json:"role"`
	// OwnerID is the owner of the personal space holding the file ("" outside .users/).
	OwnerID   string `json:"ownerId"`
	UpdatedAt string `json:"updatedAt"`
	UpdatedBy string `json:"updatedBy"`
	// Content is the file body; empty when read with Meta.
	Content string `json:"content,omitempty"`
}

// BucketStats is a bucket's storage usage, split between visible content and
// hidden system content (dot-prefixed areas).
type BucketStats struct {
	TotalSize    int64 `json:"totalSize"`
	TotalFiles   int64 `json:"totalFiles"`
	VisibleSize  int64 `json:"visibleSize"`
	VisibleFiles int64 `json:"visibleFiles"`
	SystemSize   int64 `json:"systemSize"`
	SystemFiles  int64 `json:"systemFiles"`
	FolderCount  int64 `json:"folderCount"`
}

// ArchiveEntry is one row of a zip listing.
type ArchiveEntry struct {
	Name           string `json:"name"`
	Size           uint64 `json:"size"`
	CompressedSize uint64 `json:"compressedSize"`
	IsDir          bool   `json:"isDir"`
}

// ArchiveListing lists the entries of a stored zip.
type ArchiveListing struct {
	Path    string         `json:"path"`
	Count   int            `json:"count"`
	Entries []ArchiveEntry `json:"entries"`
}

// ArchiveRestoring is the 202 body for a file in cold storage whose restore
// was requested; retry after RetryAfterSeconds.
type ArchiveRestoring struct {
	// Status is always "restoring".
	Status            string `json:"status"`
	NodeID            string `json:"nodeId"`
	Name              string `json:"name"`
	RetryAfterSeconds int    `json:"retryAfterSeconds"`
	Message           string `json:"message"`
}

// UploadFolderResult is a folder upload: the folder and the files written.
// Files that failed to upload are missing from Files.
type UploadFolderResult struct {
	Folder Document   `json:"folder"`
	Files  []Document `json:"files"`
}

// PreconditionState is the current state of a file whose conditional save
// failed with 412; see Error.PreconditionState.
type PreconditionState struct {
	CurrentETag string `json:"currentEtag"`
	UpdatedAt   string `json:"updatedAt"`
	UpdatedBy   string `json:"updatedBy"`
}

// Share is a grant of access to a My Drive item.
type Share struct {
	BaseEntity
	NodeID      string           `json:"nodeId"`
	Bucket      string           `json:"bucket"`
	SubjectType ShareSubjectType `json:"subjectType"`
	SubjectID   string           `json:"subjectId"`
	Role        ShareRole        `json:"role"`
	ExpiresAt   string           `json:"expiresAt,omitempty"`
}

// ShareLink is an org-scope link to a My Drive file.
type ShareLink struct {
	BaseEntity
	NodeID    string    `json:"nodeId"`
	Bucket    string    `json:"bucket"`
	Token     string    `json:"token"`
	Scope     string    `json:"scope"`
	Role      ShareRole `json:"role"`
	ExpiresAt string    `json:"expiresAt,omitempty"`
	Active    bool      `json:"active"`
}

// ShareLinkCreated is a newly minted share link.
type ShareLinkCreated struct {
	ID    string `json:"id"`
	Token string `json:"token"`
	// URL is the API path that resolves the link; see Sharing.ResolveLink.
	URL string `json:"url"`
	// Scope is always "org".
	Scope     string `json:"scope"`
	ExpiresAt string `json:"expiresAt,omitempty"`
}

// FolderConfig is a folder automation rule.
type FolderConfig struct {
	BaseEntity
	Bucket       string         `json:"bucket"`
	Prefix       string         `json:"prefix"`
	PipelineType PipelineType   `json:"pipelineType"`
	WorkflowID   string         `json:"workflowId"`
	WorkflowName string         `json:"workflowName"`
	FileSuffixes []string       `json:"fileSuffixes"`
	EventTypes   []EventType    `json:"eventTypes"`
	Active       bool           `json:"active"`
	Config       map[string]any `json:"config,omitempty"`
}

// ProcessingJob is one run of a folder automation pipeline.
type ProcessingJob struct {
	BaseEntity
	FolderConfigID string              `json:"folderConfigId"`
	Bucket         string              `json:"bucket"`
	NodeID         string              `json:"nodeId"`
	Key            string              `json:"key"`
	PipelineType   PipelineType        `json:"pipelineType"`
	EventType      EventType           `json:"eventType"`
	Status         ProcessingJobStatus `json:"status"`
	Attempts       int                 `json:"attempts"`
	Error          string              `json:"error"`
	Result         map[string]any      `json:"result,omitempty"`
}

// AppFileUpload is a file stored under .apps/{appKey}/. Store Permalink (or
// NodeID) instead of a storage URL; both are empty when the node index is
// unavailable.
type AppFileUpload struct {
	AppKey      string `json:"appKey"`
	Name        string `json:"name"`
	Path        string `json:"path"`
	Size        int64  `json:"size"`
	ContentType string `json:"contentType"`
	NodeID      string `json:"nodeId,omitempty"`
	Permalink   string `json:"permalink,omitempty"`
	PublicURL   string `json:"publicUrl,omitempty"`
	// SignedURL is present only when presigning is enabled.
	SignedURL string `json:"signedUrl,omitempty"`
}

// AppFilesSweep reports an app retention sweep. With no archive tier
// configured, Skipped is true, Reason says why and nothing changes.
type AppFilesSweep struct {
	Prefix     string `json:"prefix"`
	Skipped    bool   `json:"skipped,omitempty"`
	Reason     string `json:"reason,omitempty"`
	OlderThan  string `json:"olderThan,omitempty"`
	Candidates int    `json:"candidates"`
	Archived   int    `json:"archived"`
	Failed     int    `json:"failed"`
}

// Trigger runs a workflow when a matching object event happens.
type Trigger struct {
	BaseEntity
	EventType    EventType `json:"eventType"`
	Active       bool      `json:"active"`
	WorkflowID   string    `json:"workflowId"`
	WorkflowName string    `json:"workflowName"`
	Prefix       string    `json:"prefix"`
	Suffix       string    `json:"suffix"`
}

// Webhook calls a URL when a matching object event happens.
type Webhook struct {
	BaseEntity
	URL        string            `json:"url"`
	Headers    map[string]string `json:"headers,omitempty"`
	EventTypes []EventType       `json:"eventTypes"`
	Method     string            `json:"method"`
	Active     bool              `json:"active"`
	Prefix     string            `json:"prefix"`
	Suffix     string            `json:"suffix"`
}

// CreateFolderRequest creates a folder; a nested FolderName ("a/b/c") creates
// every missing level.
type CreateFolderRequest struct {
	// ParentName is the folder to create in ("" = library root).
	ParentName string `json:"parentName,omitempty"`
	FolderName string `json:"folderName"`
}

// RenameRequest renames (or moves, when NewName holds a path) a file or
// folder that lives in ParentName.
type RenameRequest struct {
	ParentName string `json:"parentName,omitempty"`
	OldName    string `json:"oldName"`
	NewName    string `json:"newName"`
}

// CreateBlankFileRequest creates an empty file at ParentName/FileName.
type CreateBlankFileRequest struct {
	ParentName string `json:"parentName,omitempty"`
	FileName   string `json:"fileName"`
}

// UpdateFileRequest saves a text file's whole body at ParentName/FileName,
// creating it when missing.
type UpdateFileRequest struct {
	// ID is ignored by the service; the response carries the real node id.
	ID         string `json:"id,omitempty"`
	ParentName string `json:"parentName,omitempty"`
	FileName   string `json:"fileName"`
	Content    string `json:"content"`
	// IfMatch is the etag last read: the save fails with 412 when the file
	// is missing or its etag differs. Send at most one of IfMatch and
	// IfNoneMatch; neither means an unconditional save.
	IfMatch string `json:"ifMatch,omitempty"`
	// IfNoneMatch "*" (the only value accepted) makes the save create-only.
	IfNoneMatch string `json:"ifNoneMatch,omitempty"`
}

// DuplicateRequest copies a file or folder next to itself.
type DuplicateRequest struct {
	Path string   `json:"path"`
	Type NodeType `json:"type"`
}

// StarByPathRequest stars the item at a bucket path. Type defaults to file
// on the service; set NodeTypeFolder for folders.
type StarByPathRequest struct {
	Path string   `json:"path"`
	Type NodeType `json:"type,omitempty"`
}

// CreateShareRequest grants a member (or the whole org) access to a My Drive
// item the caller owns.
type CreateShareRequest struct {
	Path        string           `json:"path"`
	Type        NodeType         `json:"type,omitempty"`
	SubjectType ShareSubjectType `json:"subjectType"`
	// SubjectID is the grantee's user id; required for user shares, ignored
	// for org shares.
	SubjectID string    `json:"subjectId,omitempty"`
	Role      ShareRole `json:"role"`
	// ExpiresAt is an optional RFC 3339 expiry.
	ExpiresAt string `json:"expiresAt,omitempty"`
}

// CreateShareLinkRequest mints an org-scope link for a My Drive file.
type CreateShareLinkRequest struct {
	Path string `json:"path"`
	// Type may only be NodeTypeFile.
	Type NodeType `json:"type,omitempty"`
	// ExpiresAt is an optional RFC 3339 expiry.
	ExpiresAt string `json:"expiresAt,omitempty"`
}

// FolderConfigRequest is a folder automation rule.
type FolderConfigRequest struct {
	// Prefix is the watched folder; a trailing "/" is added when missing.
	Prefix string `json:"prefix"`
	// PipelineType is custom_workflow (needs WorkflowID), extract_text or
	// thumbnail.
	PipelineType PipelineType `json:"pipelineType"`
	WorkflowID   string       `json:"workflowId,omitempty"`
	WorkflowName string       `json:"workflowName,omitempty"`
	FileSuffixes []string     `json:"fileSuffixes,omitempty"`
	// EventTypes filters which events run the pipeline (create, update);
	// empty means create only.
	EventTypes []EventType `json:"eventTypes,omitempty"`
	// Active defaults to true when nil.
	Active *bool `json:"active,omitempty"`
	// Config is free-form pipeline configuration stored with the rule.
	Config map[string]any `json:"config,omitempty"`
}

// SweepRequest archives an app's files past their retention window:
// everything under .apps/{appKey}/{Prefix} older than OlderThanDays.
type SweepRequest struct {
	Prefix string `json:"prefix,omitempty"`
	// OlderThanDays <= 0 uses the archive tier's configured retention.
	OlderThanDays int `json:"olderThanDays,omitempty"`
	// Limit caps the files archived in one sweep (<= 0 means 500).
	Limit int `json:"limit,omitempty"`
}

// TriggerRequest runs a workflow when a matching object event happens. Prefix
// and WorkflowID are required. Update replaces every field, and Active is
// stored exactly as sent, so set it to true to enable the trigger.
type TriggerRequest struct {
	EventType    EventType `json:"eventType"`
	Active       bool      `json:"active"`
	WorkflowID   string    `json:"workflowId"`
	WorkflowName string    `json:"workflowName,omitempty"`
	Prefix       string    `json:"prefix"`
	Suffix       string    `json:"suffix,omitempty"`
}

// WebhookRequest calls URL with Method when an event in EventTypes happens
// under Prefix. URL, Method, Prefix and at least one event type are
// required. Update replaces every field, and Active is stored exactly as
// sent, so set it to true to enable the webhook.
type WebhookRequest struct {
	URL string `json:"url"`
	// Headers are sent with every delivery.
	Headers    map[string]string `json:"headers,omitempty"`
	EventTypes []EventType       `json:"eventTypes"`
	Method     string            `json:"method"`
	Active     bool              `json:"active"`
	Prefix     string            `json:"prefix"`
	Suffix     string            `json:"suffix,omitempty"`
}

// UploadFile is one file of a multipart upload.
type UploadFile struct {
	// FileName is the name the file is stored under. The service keeps only
	// its last path element; use FolderUploadOptions.RelativePaths for
	// nested folder uploads.
	FileName string
	// Data is the file's content.
	Data []byte
	// ContentType of the part; "application/octet-stream" when empty.
	ContentType string
}

// Binary is a downloaded file.
type Binary struct {
	Data        []byte
	ContentType string
	// FileName comes from the X-File-Name header, else from the
	// Content-Disposition filename; empty when neither is present.
	FileName string
}

// NodeFileResult is the outcome of Nodes.Resolve and Nodes.Content. Exactly
// one of URL, Content and Restoring is set.
type NodeFileResult struct {
	// URL is the short-lived file URL the permalink redirected to (307).
	URL string
	// Content holds the file's bytes when the service served them directly
	// (200), as it does for files restored from cold storage.
	Content *Binary
	// Restoring is set when the file is in cold storage and a restore is
	// running (202); retry after RetryAfter seconds.
	Restoring *ArchiveRestoring
	// RetryAfter is the delay in seconds from the Retry-After header (or
	// Restoring.RetryAfterSeconds when the header is absent); 0 otherwise.
	RetryAfter int
}
