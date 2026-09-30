package workflow

import "net/http"

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
	ID        string `json:"id,omitempty"`
	OrgID     string `json:"orgId,omitempty"`
	CreatedBy string `json:"createdBy,omitempty"`
	UpdatedBy string `json:"updatedBy,omitempty"`
	CreatedAt string `json:"createdAt,omitempty"`
	UpdatedAt string `json:"updatedAt,omitempty"`
}

type PaginationQuery struct {
	Page      *int   `json:"page,omitempty"`
	Limit     *int   `json:"limit,omitempty"`
	SortBy    string `json:"sortBy,omitempty"`
	SortOrder string `json:"sortOrder,omitempty"`
	Where     string `json:"where,omitempty"`
}

type Variable struct {
	ID    string `json:"id,omitempty"`
	Name  string `json:"name"`
	Value string `json:"value"`
}

type Environment struct {
	BaseEntity
	Name         string     `json:"name"`
	Description  string     `json:"description,omitempty"`
	IsDefaultEnv *bool      `json:"isDefaultEnv,omitempty"`
	Variables    []Variable `json:"variables,omitempty"`
}

type WorkflowUINode struct {
	ID   string         `json:"id"`
	Type string         `json:"type,omitempty"`
	Data map[string]any `json:"data,omitempty"`
}

type WorkflowUIEdge struct {
	ID     string `json:"id"`
	Source string `json:"source"`
	Target string `json:"target"`
	Type   string `json:"type,omitempty"`
	Label  string `json:"label,omitempty"`
}

type WorkflowUI struct {
	Nodes []WorkflowUINode `json:"nodes"`
	Edges []WorkflowUIEdge `json:"edges"`
}

type Workflow struct {
	BaseEntity
	Name        string         `json:"name"`
	Description string         `json:"description,omitempty"`
	InputData   map[string]any `json:"inputData,omitempty"`
	UI          WorkflowUI     `json:"ui"`
	Tags        []string       `json:"tags,omitempty"`
	Version     *int           `json:"version,omitempty"`
	Published   *bool          `json:"published,omitempty"`
}

type WorkflowUpdateRequest struct {
	Workflow
	Comment string `json:"comment,omitempty"`
}

type RunWorkflowRequest struct {
	WorkflowID    string         `json:"workflowId"`
	InputData     map[string]any `json:"inputData,omitempty"`
	EnvironmentID string         `json:"environmentId,omitempty"`
	TriggeredBy   string         `json:"triggeredBy,omitempty"`
	OrgID         string         `json:"orgId,omitempty"`
	ActivityID    string         `json:"activityId,omitempty"`
	ExecutionID   string         `json:"executionId,omitempty"`
}

type FunctionEntity struct {
	BaseEntity
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
	Body        string `json:"body"`
	Version     *int   `json:"version,omitempty"`
	IsActive    *bool  `json:"isActive,omitempty"`
}

type FunctionVersionRequest struct {
	Function FunctionEntity `json:"function"`
	Comment  string         `json:"comment,omitempty"`
}

type HumanTaskAction struct {
	Text  string `json:"text"`
	Value string `json:"value"`
}

type HumanTask struct {
	BaseEntity
	Message     string            `json:"message"`
	Actions     []HumanTaskAction `json:"actions,omitempty"`
	AssignedTo  string            `json:"assignedTo,omitempty"`
	ExecutionID string            `json:"executionId"`
	WorkflowID  string            `json:"workflowId"`
	Answer      string            `json:"answer,omitempty"`
	Completed   *bool             `json:"completed,omitempty"`
	CompletedAt string            `json:"completedAt,omitempty"`
	ActivityID  string            `json:"activityId"`
}

type Execution struct {
	BaseEntity
	WorkflowID    string         `json:"workflowId"`
	CorrelationID string         `json:"correlationId,omitempty"`
	Version       *int           `json:"version,omitempty"`
	Status        string         `json:"status,omitempty"`
	Context       map[string]any `json:"context,omitempty"`
	FailedReason  string         `json:"failedReason,omitempty"`
	InputData     any            `json:"inputData,omitempty"`
	OutputData    any            `json:"outputData,omitempty"`
	Workflow      *Workflow      `json:"workflow,omitempty"`
}

type ActivityExecutionHistory struct {
	BaseEntity
	ActivityID   string `json:"activityId"`
	WorkflowID   string `json:"workflowId"`
	ExecutionID  string `json:"executionId"`
	Type         string `json:"type,omitempty"`
	TypeID       string `json:"typeId,omitempty"`
	Status       string `json:"status,omitempty"`
	InputData    any    `json:"inputData,omitempty"`
	OutputData   any    `json:"outputData,omitempty"`
	FailedReason string `json:"failedReason,omitempty"`
}

type ActivityHistoryResponse struct {
	ID        string                   `json:"id"`
	History   ActivityExecutionHistory `json:"history"`
	Activity  map[string]any           `json:"activity,omitempty"`
	Workflow  *Workflow                `json:"workflow,omitempty"`
	Execution *Execution               `json:"execution,omitempty"`
}

type WorkflowPublish struct {
	BaseEntity
	WorkflowID      string    `json:"workflowId"`
	SourceOrgID     string    `json:"sourceOrgId,omitempty"`
	Category        string    `json:"category,omitempty"`
	LongDescription string    `json:"longDescription,omitempty"`
	Workflow        *Workflow `json:"workflow,omitempty"`
}

type DryRunRequest struct {
	ExecutionID      string `json:"executionId"`
	Expression       string `json:"expression"`
	TypeOfExpression string `json:"typeOfExpression"`
	ActivityID       string `json:"activityId"`
}

// WebhookCreateRequest is the payload of the deprecated Webhooks.Create and
// Webhooks.Update.
//
// Deprecated: both methods always return an error. Will be removed in a future
// major version.
type WebhookCreateRequest struct {
	URL                string         `json:"url"`
	AuthenticationType string         `json:"authenticationType,omitempty"`
	AuthDetails        map[string]any `json:"authDetails,omitempty"`
}
