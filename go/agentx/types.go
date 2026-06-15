package agentx

import (
	"encoding/json"
	"fmt"
	"time"
)

const (
	HeaderOrgID = "X-Org-Id"
)

// BaseEntity mirrors core.model.BaseEntity – the embedded audit fields used by
// every entity across agentx services.
type BaseEntity struct {
	ID        string     `json:"id,omitempty"`
	OrgID     string     `json:"orgId,omitempty"`
	PRN       string     `json:"prn,omitempty"`
	CreatedAt time.Time  `json:"createdAt,omitempty"`
	UpdatedAt *time.Time `json:"updatedAt,omitempty"`
	CreatedBy string     `json:"createdBy,omitempty"`
	UpdatedBy string     `json:"updatedBy,omitempty"`
}

// ListParams is the conventional pageNo / size / filter / sort query builder.
type ListParams struct {
	PageNo int
	Size   int
	Filter string
	Sort   string
}

// ---------------------------------------------------------------------------
// Manager: agents
// ---------------------------------------------------------------------------

type AgentOutputMode string

const (
	AgentOutputModeFullResponse AgentOutputMode = "full_response"
	AgentOutputModeLastMessage  AgentOutputMode = "last_message"
)

type MultiAgentPattern string

const (
	MultiAgentPatternHierarchy  MultiAgentPattern = "hierarchy"
	MultiAgentPatternSupervisor MultiAgentPattern = "supervisor"
	MultiAgentPatternNetwork    MultiAgentPattern = "network"
	MultiAgentPatternPlanner    MultiAgentPattern = "planner"
)

type AgentMemoryType string

const AgentMemoryTypeLowco AgentMemoryType = "lowco"

// CustomRoutingConfig holds JavaScript expressions used by multi-agent routing patterns.
type CustomRoutingConfig struct {
	HaltCondition  string `json:"haltCondition,omitempty"`
	RouterFunction string `json:"routerFunction,omitempty"`
}

// AgentTool represents a tool attached to an agent.
type AgentTool struct {
	ID       string `json:"id,omitempty"`
	Source   string `json:"source,omitempty"`
	SourceID string `json:"sourceId,omitempty"`
	Name     string `json:"name,omitempty"`
}

// AgentCapabilities mirrors the A2A agent-card capabilities object.
type AgentCapabilities struct {
	Streaming              bool `json:"streaming,omitempty"`
	PushNotifications      bool `json:"pushNotifications,omitempty"`
	StateTransitionHistory bool `json:"stateTransitionHistory,omitempty"`
	Extensions             bool `json:"extensions,omitempty"`
}

// AgentSkill follows the A2A agent-card skill format.
type AgentSkill struct {
	ID          string   `json:"id,omitempty"`
	Description string   `json:"description,omitempty"`
	Name        []string `json:"name,omitempty"`
	Tags        []string `json:"tags,omitempty"`
	Examples    string   `json:"examples,omitempty"`
	InputModes  []string `json:"inputModes,omitempty"`
	OutputModes []string `json:"outputModes,omitempty"`
}

// AgentConfiguration carries LLM sampling parameters and execution limits.
type AgentConfiguration struct {
	MaxTokens     int     `json:"maxTokens,omitempty"`
	MaxIterations int     `json:"maxIterations,omitempty"`
	Temperature   float64 `json:"temperature,omitempty"`
	TopK          int     `json:"topK,omitempty"`
}

// Agent represents an AI agent configuration.
type Agent struct {
	BaseEntity
	Name                      string               `json:"name,omitempty"`
	Description               string               `json:"description,omitempty"`
	ModelName                 string               `json:"modelName,omitempty"`
	Prompt                    string               `json:"prompt,omitempty"`
	Provider                  string               `json:"provider,omitempty"`
	Tools                     *[]AgentTool         `json:"tools,omitempty"`
	KnowledgeBaseIDs          *[]string            `json:"knowledgeBaseIds,omitempty"`
	Configurations            AgentConfiguration   `json:"configurations,omitempty"`
	OutputMode                AgentOutputMode      `json:"outputMode,omitempty"`
	IconURL                   *string              `json:"iconUrl,omitempty"`
	DocumentationURL          *string              `json:"documentationUrl,omitempty"`
	Capabilities              *AgentCapabilities   `json:"capabilities,omitempty"`
	Skills                    *[]AgentSkill        `json:"skills,omitempty"`
	MemoryType                *AgentMemoryType     `json:"memoryType,omitempty"`
	SubAgentPattern           *MultiAgentPattern   `json:"subAgentPattern,omitempty"`
	SubAgents                 []string             `json:"subAgents,omitempty"`
	RoutingConfig             *CustomRoutingConfig `json:"routingConfig,omitempty"`
	Published                 bool                 `json:"published,omitempty"`
	Version                   int                  `json:"version,omitempty"`
	ApplicationWithCredential map[string]string    `json:"applicationWithCredential,omitempty"`
	WelcomeMessage            *string              `json:"welcomeMessage,omitempty"`
	Tags                      []string             `json:"tags,omitempty"`
	// Server-enriched field populated by ListAgents.
	ModelID string `json:"modelId,omitempty"`
}

// AgentInfo is the trimmed agent shape returned by some endpoints.
type AgentInfo struct {
	ID             string `json:"id,omitempty"`
	Name           string `json:"name,omitempty"`
	ModelName      string `json:"modelName,omitempty"`
	WelcomeMessage string `json:"welcomeMessage,omitempty"`
}

// AgentHistory is a snapshot of an Agent at a point in time.
type AgentHistory struct {
	BaseEntity
	Agent   Agent  `json:"agent,omitempty"`
	Comment string `json:"comment,omitempty"`
}

// AgentPatch is the body for PATCH /agents/:id. Only listed fields are applied.
type AgentPatch struct {
	Tags *[]string `json:"tags,omitempty"`
}

// AgentPublish is a record of an agent published to the shared catalogue.
type AgentPublish struct {
	BaseEntity
	Agent           *Agent `json:"agent,omitempty"`
	SourceOrgID     string `json:"sourceOrgId,omitempty"`
	AgentID         string `json:"agentId,omitempty"`
	LongDescription string `json:"longDescription,omitempty"`
	Category        string `json:"category,omitempty"`
	// Server-enriched field populated by ListPublishedAgents.
	LatestVersion int `json:"latestVersion,omitempty"`
}

// PublishAgentRequest is the body for POST /agents/:id/publish.
type PublishAgentRequest struct {
	LongDescription string `json:"longDescription,omitempty"`
	Category        string `json:"category,omitempty"`
}

// UpdatePublishedAgentRequest is the body for PUT /agents/published/:id.
type UpdatePublishedAgentRequest struct {
	LongDescription string `json:"longDescription,omitempty"`
	Category        string `json:"category,omitempty"`
	AgentID         string `json:"agentId,omitempty"`
}

// BulkDeleteRequest is the body for POST /agents/bulk-delete.
type BulkDeleteRequest struct {
	IDs []string `json:"ids"`
}

// ---------------------------------------------------------------------------
// Manager: LLM models
// ---------------------------------------------------------------------------

// LlmModel represents an LLM model configuration.
type LlmModel struct {
	BaseEntity
	Name        string         `json:"name,omitempty"`
	Description string         `json:"description,omitempty"`
	Provider    string         `json:"provider,omitempty"`
	Icon        string         `json:"icon,omitempty"`
	Disabled    bool           `json:"disabled,omitempty"`
	Config      map[string]any `json:"config,omitempty"`
	Embedding   bool           `json:"embedding,omitempty"`
}

// EnableModelRequest is the body for PATCH /models/:id/enable.
type EnableModelRequest struct {
	Properties map[string]any `json:"properties,omitempty"`
}

// ---------------------------------------------------------------------------
// Manager: conversations
// ---------------------------------------------------------------------------

// Conversation represents a chat session.
type Conversation struct {
	BaseEntity
	ChatType string `json:"chatType,omitempty"`
	// Server-enriched fields populated by ListConversationsByAgent.
	LastMessage *MessageContent `json:"lastMessage,omitempty"`
	Count       int             `json:"count,omitempty"`
	// Server-enriched field populated by CreateConversation on the first conversation.
	WelcomeMessage string `json:"welcomeMessage,omitempty"`
}

// CreateConversationRequest is the body for POST /conversations.
type CreateConversationRequest struct {
	AgentID string `json:"agentId"`
}

// ConversationMessage stores a single message turn within a Conversation.
type ConversationMessage struct {
	BaseEntity
	ConversationID string         `json:"conversationId,omitempty"`
	Role           string         `json:"role,omitempty"`
	Content        MessageContent `json:"content,omitempty"`
	MemberID       *string        `json:"memberId,omitempty"`
	ChatType       string         `json:"chatType,omitempty"`
	Metadata       map[string]any `json:"metadata,omitempty"`
}

// MessageContent wraps the polymorphic content value of a ConversationMessage.
// Value is either a string (plain text) or a slice of block objects.
type MessageContent struct {
	Value any
}

// MarshalJSON serialises MessageContent. A string value is marshalled as a JSON
// string; any other value is marshalled directly (typically a JSON array of blocks).
func (m MessageContent) MarshalJSON() ([]byte, error) {
	if m.Value == nil {
		return []byte("null"), nil
	}
	return json.Marshal(m.Value)
}

// UnmarshalJSON deserialises MessageContent. It tries a plain string first;
// otherwise it stores the raw JSON value as-is for the caller to interpret.
func (m *MessageContent) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		m.Value = s
		return nil
	}
	var v any
	if err := json.Unmarshal(data, &v); err != nil {
		return err
	}
	m.Value = v
	return nil
}

// ---------------------------------------------------------------------------
// KB
// ---------------------------------------------------------------------------

// KnowledgeBase stores metadata for a knowledge base that can be attached to agents.
type KnowledgeBase struct {
	BaseEntity
	Name         string `json:"name,omitempty"`
	Description  string `json:"description,omitempty"`
	ConnectionID string `json:"connectionId,omitempty"`
	ModelID      string `json:"modelId,omitempty"`
}

// Dataset stores the content entries that belong to a KnowledgeBase.
type Dataset struct {
	BaseEntity
	Name            string `json:"name,omitempty"`
	KnowledgeBaseID string `json:"knowledgeBaseId,omitempty"`
	Content         string `json:"content,omitempty"`
}

// EmbeddingDbRequest is the body for POST /embeddings.
// Distance values are Qdrant distance metric names (e.g. "Cosine", "Dot", "Euclid").
type EmbeddingDbRequest struct {
	ModelID      string         `json:"modelId,omitempty"`
	CredentialID string         `json:"credentialId,omitempty"`
	Texts        string         `json:"texts,omitempty"`
	Payload      map[string]any `json:"payload,omitempty"`
	Collection   string         `json:"collection,omitempty"`
	Distance     string         `json:"distance,omitempty"`
}

// ---------------------------------------------------------------------------
// Executor (A2A JSON-RPC + SSE)
// ---------------------------------------------------------------------------

// MethodMessageSend is the only JSON-RPC method handled by the executor today.
const MethodMessageSend = "message/send"

// PartKind identifies the type of a Message Part.
type PartKind string

const (
	PartKindText PartKind = "text"
	PartKindFile PartKind = "file"
	PartKindData PartKind = "data"
)

// MessageRole is the originator of a Message.
type MessageRole string

const (
	MessageRoleUser  MessageRole = "user"
	MessageRoleAgent MessageRole = "assistant"
)

// Part is the polymorphic interface for Message parts (text / file / data).
type Part interface {
	GetKind() PartKind
}

// TextPart represents a text segment within a Message.
type TextPart struct {
	Kind     PartKind       `json:"kind"`
	Text     string         `json:"text"`
	Metadata map[string]any `json:"metadata,omitempty"`
}

func (t TextPart) GetKind() PartKind { return PartKindText }

// FilePart represents a file segment within a Message. File is either
// FileWithBytes or FileWithURI.
type FilePart struct {
	Kind     PartKind       `json:"kind"`
	File     any            `json:"file"`
	Metadata map[string]any `json:"metadata,omitempty"`
}

func (f FilePart) GetKind() PartKind { return PartKindFile }

// DataPart represents a structured data segment within a Message.
type DataPart struct {
	Kind     PartKind       `json:"kind"`
	Data     map[string]any `json:"data"`
	Metadata map[string]any `json:"metadata,omitempty"`
}

func (d DataPart) GetKind() PartKind { return PartKindData }

// FileWithBytes is a base64-encoded inline file payload.
type FileWithBytes struct {
	Name     *string `json:"name,omitempty"`
	MimeType *string `json:"mimeType,omitempty"`
	Bytes    string  `json:"bytes"`
}

// FileWithURI is a file referenced by URI.
type FileWithURI struct {
	Name     *string `json:"name,omitempty"`
	MimeType *string `json:"mimeType,omitempty"`
	URI      string  `json:"uri"`
}

// A2AMessage represents a single A2A communication turn (executor input/output).
// Named A2AMessage to avoid colliding with manager's ConversationMessage usage.
type A2AMessage struct {
	Role             MessageRole    `json:"role"`
	Parts            []Part         `json:"parts"`
	Metadata         map[string]any `json:"metadata,omitempty"`
	Extensions       []string       `json:"extensions,omitempty"`
	ReferenceTaskIDs []string       `json:"referenceTaskIds,omitempty"`
	MessageID        string         `json:"messageId"`
	TaskID           *string        `json:"taskId,omitempty"`
	ContextID        *string        `json:"contextId,omitempty"`
	Kind             string         `json:"kind"` // "message"
}

// UnmarshalJSON decodes the polymorphic Parts slice by inspecting each part's "kind" tag.
func (m *A2AMessage) UnmarshalJSON(data []byte) error {
	type alias A2AMessage
	aux := &struct {
		Parts []json.RawMessage `json:"parts"`
		*alias
	}{alias: (*alias)(m)}
	if err := json.Unmarshal(data, aux); err != nil {
		return err
	}
	m.Parts = nil
	for _, raw := range aux.Parts {
		var k struct {
			Kind PartKind `json:"kind"`
		}
		if err := json.Unmarshal(raw, &k); err != nil {
			return err
		}
		switch k.Kind {
		case PartKindText:
			var tp TextPart
			if err := json.Unmarshal(raw, &tp); err != nil {
				return err
			}
			m.Parts = append(m.Parts, tp)
		case PartKindFile:
			var fp FilePart
			if err := json.Unmarshal(raw, &fp); err != nil {
				return err
			}
			m.Parts = append(m.Parts, fp)
		case PartKindData:
			var dp DataPart
			if err := json.Unmarshal(raw, &dp); err != nil {
				return err
			}
			m.Parts = append(m.Parts, dp)
		default:
			return fmt.Errorf("agentx: unknown part kind %q", k.Kind)
		}
	}
	return nil
}

// PushNotificationConfig configures push notifications for task updates.
type PushNotificationConfig struct {
	ID             *string                             `json:"id,omitempty"`
	URL            string                              `json:"url"`
	Token          *string                             `json:"token,omitempty"`
	Authentication *PushNotificationAuthenticationInfo `json:"authentication,omitempty"`
}

// PushNotificationAuthenticationInfo carries auth details for push notifications.
type PushNotificationAuthenticationInfo struct {
	Schemes     []string `json:"schemes"`
	Credentials *string  `json:"credentials,omitempty"`
}

// MessageSendConfiguration is the optional config block on a "message/send" call.
type MessageSendConfiguration struct {
	AcceptedOutputModes    []string                `json:"acceptedOutputModes,omitempty"`
	HistoryLength          *int                    `json:"historyLength,omitempty"`
	PushNotificationConfig *PushNotificationConfig `json:"pushNotificationConfig,omitempty"`
	Blocking               *bool                   `json:"blocking,omitempty"`
}

// MessageSendParams is the params block for the "message/send" JSON-RPC method.
type MessageSendParams struct {
	Message       A2AMessage                `json:"message"`
	Configuration *MessageSendConfiguration `json:"configuration,omitempty"`
	Metadata      map[string]any            `json:"metadata,omitempty"`
	ChatType      string                    `json:"chatType,omitempty"`
}

// JSONRPCRequest is the over-the-wire request envelope.
// The executor interprets the JSON-RPC "id" as the target agent ID.
type JSONRPCRequest struct {
	JSONRPC string `json:"jsonrpc"`
	Method  string `json:"method"`
	Params  any    `json:"params,omitempty"`
	ID      any    `json:"id,omitempty"`
}

// JSONRPCResponse is the over-the-wire response envelope.
type JSONRPCResponse struct {
	JSONRPC string        `json:"jsonrpc"`
	Result  any           `json:"result,omitempty"`
	Error   *JSONRPCError `json:"error,omitempty"`
	ID      any           `json:"id"`
}

// JSONRPCError is a JSON-RPC 2.0 error object.
type JSONRPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

func (e *JSONRPCError) Error() string {
	return fmt.Sprintf("agentx: rpc error code=%d %s", e.Code, e.Message)
}

// Standard JSON-RPC and A2A error codes.
const (
	JSONRPCErrorCodeParseError     = -32700
	JSONRPCErrorCodeInvalidRequest = -32600
	JSONRPCErrorCodeMethodNotFound = -32601
	JSONRPCErrorCodeInvalidParams  = -32602
	JSONRPCErrorCodeInternalError  = -32603

	A2AErrorCodeTaskNotFound                 = -32001
	A2AErrorCodeTaskNotCancelable            = -32002
	A2AErrorCodePushNotificationNotSupported = -32003
	A2AErrorCodeUnsupportedOperation         = -32004
	A2AErrorCodeContentTypeNotSupported      = -32005
	A2AErrorCodeInvalidAgentResponse         = -32006
)
