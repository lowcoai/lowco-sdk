package integrations

import (
	"net/http"
	"time"
)

// Header keys used for tenancy.
const (
	HeaderOrgID = "X-Org-Id"
)

type Config struct {
	// Token is required. It may hold a user token or an API key and is sent
	// as "Authorization: Bearer <token>" on every request.
	Token      string
	OrgID      string
	TimeoutMS  int
	Headers    map[string]string
	HTTPClient *http.Client
}

type RequestOptions struct {
	Query   map[string]any
	Headers map[string]string
}

type APIEnvelope[T any] struct {
	Success *bool  `json:"success,omitempty"`
	Code    string `json:"code,omitempty"`
	Message string `json:"message,omitempty"`
	Data    T      `json:"data"`
	Error   any    `json:"error,omitempty"`
}

type BaseEntity struct {
	ID        string     `json:"id,omitempty"`
	OrgID     string     `json:"orgId,omitempty"`
	CreatedBy string     `json:"createdBy,omitempty"`
	UpdatedBy string     `json:"updatedBy,omitempty"`
	CreatedAt time.Time  `json:"createdAt,omitempty"`
	UpdatedAt *time.Time `json:"updatedAt,omitempty"`
}

type PaginationQuery struct {
	Page      *int   `json:"page,omitempty"`
	Limit     *int   `json:"limit,omitempty"`
	SortBy    string `json:"sortBy,omitempty"`
	SortOrder string `json:"sortOrder,omitempty"`
	Filter    string `json:"filter,omitempty"`
	Tags      string `json:"tags,omitempty"`
}

// ApplicationType and ApplicationSubType mirror the server-side enums under
// integrations/core/types.
type ApplicationType string
type ApplicationSubType string

const (
	ApplicationTypeHTTP     ApplicationType = "http"
	ApplicationTypeDatabase ApplicationType = "database"
	ApplicationTypeQueue    ApplicationType = "queue"
	ApplicationTypeStorage  ApplicationType = "storage"
)

const (
	ApplicationSubTypeHTTP       ApplicationSubType = "http"
	ApplicationSubTypeOAuth2     ApplicationSubType = "oauth2"
	ApplicationSubTypePostgreSQL ApplicationSubType = "postgres"
	ApplicationSubTypeMySQL      ApplicationSubType = "mysql"
	ApplicationSubTypeClickhouse ApplicationSubType = "clickhouse"
	ApplicationSubTypeNats       ApplicationSubType = "nats"
	ApplicationSubTypeMongoDB    ApplicationSubType = "mongodb"
	ApplicationSubTypeRedis      ApplicationSubType = "redis"
	ApplicationSubTypeRabbitMQ   ApplicationSubType = "rabbitmq"
	ApplicationSubTypeKafka      ApplicationSubType = "kafka"
	ApplicationSubTypeSQS        ApplicationSubType = "sqs"
	ApplicationSubTypeQdrant     ApplicationSubType = "qdrant"
	ApplicationSubTypeZep        ApplicationSubType = "zep"
	ApplicationSubTypeOpenSearch ApplicationSubType = "opensearch"
)

type ConnectionType string

const (
	ConnectionTypeOAuth2 ConnectionType = "oauth2"
)

type ConnectionStatus string

const (
	ConnectionStatusActive   ConnectionStatus = "active"
	ConnectionStatusInactive ConnectionStatus = "inactive"
	ConnectionStatusRevoked  ConnectionStatus = "revoked"
	ConnectionStatusExpired  ConnectionStatus = "expired"
	ConnectionStatusPending  ConnectionStatus = "pending"
)

// Application is a server-side integration definition (e.g. Slack, Postgres,
// HTTP). It carries the auth and operation config used to power its actions.
type Application struct {
	BaseEntity
	Name            string             `json:"name"`
	Description     string             `json:"description,omitempty"`
	Icon            string             `json:"icon,omitempty"`
	Type            ApplicationType    `json:"type"`
	SubType         ApplicationSubType `json:"subType"`
	OperationConfig map[string]any     `json:"operationConfig,omitempty"`
	AuthConfig      map[string]any     `json:"authConfig,omitempty"`
	SupportProtocol any                `json:"supportProtocol,omitempty"`
	Tags            []string           `json:"tags,omitempty"`
	Version         int                `json:"version,omitempty"`
	McpKey          string             `json:"mcpKey,omitempty"`
	PublishedUrl    string             `json:"publishedUrl,omitempty"`
}

type ApplicationWithCount struct {
	Application
	Count int `json:"count"`
}

type ApplicationWithConnection struct {
	Application
	Connections []Connection `json:"connections"`
	ActionID    string       `json:"actionId,omitempty"`
}

type ApplicationHistory struct {
	BaseEntity
	Application Application `json:"application"`
	Comment     string      `json:"comment,omitempty"`
}

type SubApplicationConfig map[ApplicationType][]ApplicationSubType

type PatchTagsRequest struct {
	Tags []string `json:"tags"`
}

type RunApplicationRequest struct {
	CredentialID string         `json:"credentialId,omitempty"`
	InputBody    map[string]any `json:"inputBody"`
}

// HttpInput is the request shape an HTTP-style action runs. Server side, the
// shape is rich (headers, query, body, auth, etc.); the SDK keeps it generic
// so callers can supply whatever the server expects.
type HttpInput map[string]any

type ApplicationAction struct {
	BaseEntity
	ApplicationID string         `json:"applicationId"`
	Name          string         `json:"name"`
	GroupName     string         `json:"groupName,omitempty"`
	Description   string         `json:"description,omitempty"`
	Action        HttpActionType `json:"action"`
	Properties    any            `json:"properties,omitempty"`
}

type HttpActionType struct {
	Type     string    `json:"type"`
	Metadata HttpInput `json:"metadata,omitempty"`
}

type RunActionRequest struct {
	CredentialID string         `json:"credentialId,omitempty"`
	InputBody    map[string]any `json:"inputBody"`
}

// PostmanFolder mirrors the recursive Postman collection shape consumed by
// /applications/{id}/load-actions. Items can nest folders or requests.
type PostmanFolder struct {
	Name    string          `json:"name,omitempty"`
	Items   []PostmanFolder `json:"item,omitempty"`
	Request map[string]any  `json:"request,omitempty"`
}

type Connection struct {
	BaseEntity
	Name               string             `json:"name"`
	Description        string             `json:"description,omitempty"`
	ConnectionType     ConnectionType     `json:"connectionType"`
	ApplicationType    ApplicationType    `json:"applicationType,omitempty"`
	ApplicationSubType ApplicationSubType `json:"applicationSubType,omitempty"`
	ConnectionStatus   ConnectionStatus   `json:"connectionStatus,omitempty"`
	ApplicationID      string             `json:"applicationId"`
	Properties         map[string]any     `json:"properties,omitempty"`
	IsDefault          bool               `json:"isDefault,omitempty"`
}

type ConnectionResponse struct {
	Connection
	ApplicationType    string `json:"applicationType,omitempty"`
	ApplicationSubType string `json:"applicationSubType,omitempty"`
}

type SetAsDefaultRequest struct {
	ApplicationID string `json:"applicationId"`
}

// ApplicationTrigger is a webhook/poll/stream trigger attached to an
// application. The OperationConfig shape varies by trigger type — parse it
// with the runtime that owns the trigger kind.
type ApplicationTrigger struct {
	BaseEntity
	Name            string         `json:"name"`
	Description     string         `json:"description,omitempty"`
	OperationConfig map[string]any `json:"operationConfig,omitempty"`
	ApplicationID   string         `json:"applicationId"`
	WebhookURL      string         `json:"webhookUrl,omitempty"`
}

// TriggerState is the runner-owned runtime state for a trigger (last run,
// last error, cursor, lease). Surfaced for UI observability.
type TriggerState struct {
	TriggerID   string         `json:"triggerId"`
	OrgID       string         `json:"orgId,omitempty"`
	Cursor      map[string]any `json:"cursor,omitempty"`
	LastRunAt   *time.Time     `json:"lastRunAt,omitempty"`
	LastError   string         `json:"lastError,omitempty"`
	RunCount    int64          `json:"runCount"`
	LeasedBy    string         `json:"leasedBy,omitempty"`
	LeasedUntil *time.Time     `json:"leasedUntil,omitempty"`
	UpdatedAt   time.Time      `json:"updatedAt,omitempty"`
}

type ConnectionCreateRequest struct {
	ApplicationID string `json:"applicationId"`
	Name          string `json:"name,omitempty"`
	Description   string `json:"description,omitempty"`
}

type CallbackRequest struct {
	State string `json:"state"`
	Code  string `json:"code"`
}

type OAuthLoginURL struct {
	URL string `json:"url"`
}

type OAuthCallbackResult struct {
	Success string `json:"success"`
}

type AuthToken struct {
	BaseEntity
	RequestID     string    `json:"requestId,omitempty"`
	ApplicationID string    `json:"applicationId"`
	CredentialID  string    `json:"credentialId"`
	Token         string    `json:"token"`
	RefreshToken  string    `json:"refreshToken,omitempty"`
	ExpiresIn     int64     `json:"expiresIn,omitempty"`
	Expiry        time.Time `json:"expiry,omitempty"`
	TokenType     string    `json:"tokenType,omitempty"`
}

type RefreshExpiringTokensResult struct {
	Checked         int              `json:"checked"`
	Refreshed       int              `json:"refreshed"`
	Skipped         int              `json:"skipped"`
	Failed          int              `json:"failed"`
	RefreshedTokens []AuthToken      `json:"refreshedTokens"`
	Failures        []map[string]any `json:"failures"`
}

// JSONRPCRequest / JSONRPCResponse are the MCP JSON-RPC envelopes served by
// /applications/published/{key}.
type JSONRPCRequest struct {
	JSONRPC string `json:"jsonrpc"`
	ID      any    `json:"id,omitempty"`
	Method  string `json:"method"`
	Params  any    `json:"params,omitempty"`
}

type JSONRPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

type JSONRPCResponse struct {
	JSONRPC string        `json:"jsonrpc"`
	ID      any           `json:"id,omitempty"`
	Result  any           `json:"result,omitempty"`
	Error   *JSONRPCError `json:"error,omitempty"`
}

// McpToolsResponse is the shape returned by /applications/{id}/mcp/tools.
type McpToolsResponse struct {
	Tools []map[string]any `json:"tools"`
}
