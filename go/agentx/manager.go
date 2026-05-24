package agentx

import (
	"context"
	"net/http"
	"net/url"
)

// ManagerClient exposes the agent-manager service routes.
// Obtain it from Client.Manager.
type ManagerClient struct {
	c *Client
}

func (m *ManagerClient) path(parts ...string) string {
	return joinPath(m.c.managerBasePath, parts...)
}

func (m *ManagerClient) do(ctx context.Context, method, endpoint string, query url.Values, body, out any, enveloped bool) error {
	return m.c.do(ctx, m.c.managerURL, method, endpoint, query, body, out, enveloped)
}

// Health pings the agent-manager /health endpoint.
func (m *ManagerClient) Health(ctx context.Context) error {
	return m.do(ctx, http.MethodGet, "/health", nil, nil, nil, false)
}

// --- Agents --------------------------------------------------------------

func (m *ManagerClient) ListAgents(ctx context.Context, params *ListParams) ([]Agent, error) {
	var out []Agent
	if err := m.do(ctx, http.MethodGet, m.path("agents"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

func (m *ManagerClient) GetAgent(ctx context.Context, id string) (*Agent, error) {
	var out Agent
	if err := m.do(ctx, http.MethodGet, m.path("agents", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (m *ManagerClient) CreateAgent(ctx context.Context, agent Agent) (*Agent, error) {
	var out Agent
	if err := m.do(ctx, http.MethodPost, m.path("agents"), nil, agent, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (m *ManagerClient) UpdateAgent(ctx context.Context, id string, agent Agent) (*Agent, error) {
	var out Agent
	if err := m.do(ctx, http.MethodPut, m.path("agents", id), nil, agent, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (m *ManagerClient) PatchAgent(ctx context.Context, id string, patch AgentPatch) (*Agent, error) {
	var out Agent
	if err := m.do(ctx, http.MethodPatch, m.path("agents", id), nil, patch, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

// GetAgentCount returns the total number of agents for the requesting org.
// The endpoint returns a raw integer, not an enveloped payload.
func (m *ManagerClient) GetAgentCount(ctx context.Context, params *ListParams) (int64, error) {
	var out int64
	if err := m.do(ctx, http.MethodGet, m.path("agents", "count"), params.values(), nil, &out, false); err != nil {
		return 0, err
	}
	return out, nil
}

func (m *ManagerClient) DeleteAgent(ctx context.Context, id string) error {
	return m.do(ctx, http.MethodDelete, m.path("agents", id), nil, nil, nil, false)
}

func (m *ManagerClient) BulkDeleteAgents(ctx context.Context, ids []string) error {
	return m.do(ctx, http.MethodPost, m.path("agents", "bulk-delete"), nil, BulkDeleteRequest{IDs: ids}, nil, false)
}

func (m *ManagerClient) GetAgentVersions(ctx context.Context, id string, params *ListParams) ([]AgentHistory, error) {
	var out []AgentHistory
	if err := m.do(ctx, http.MethodGet, m.path("agents", id, "versions"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

// --- Published agents ----------------------------------------------------

func (m *ManagerClient) PublishAgent(ctx context.Context, agentID string, req PublishAgentRequest) (*AgentPublish, error) {
	var out AgentPublish
	if err := m.do(ctx, http.MethodPost, m.path("agents", agentID, "publish"), nil, req, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (m *ManagerClient) GetPublishedAgent(ctx context.Context, id string) (*AgentPublish, error) {
	var out AgentPublish
	if err := m.do(ctx, http.MethodGet, m.path("agents", "published", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (m *ManagerClient) UpdatePublishedAgent(ctx context.Context, id string, req UpdatePublishedAgentRequest) (*AgentPublish, error) {
	var out AgentPublish
	if err := m.do(ctx, http.MethodPut, m.path("agents", "published", id), nil, req, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (m *ManagerClient) DeletePublishedAgent(ctx context.Context, id string) error {
	return m.do(ctx, http.MethodDelete, m.path("agents", "published", id), nil, nil, nil, false)
}

func (m *ManagerClient) ListPublishedAgents(ctx context.Context, params *ListParams) ([]AgentPublish, error) {
	var out []AgentPublish
	if err := m.do(ctx, http.MethodGet, m.path("agents", "published"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

// --- LLM models ----------------------------------------------------------

func (m *ManagerClient) CreateModel(ctx context.Context, model LlmModel) (*LlmModel, error) {
	var out LlmModel
	if err := m.do(ctx, http.MethodPost, m.path("models"), nil, model, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (m *ManagerClient) GetModel(ctx context.Context, id string) (*LlmModel, error) {
	var out LlmModel
	if err := m.do(ctx, http.MethodGet, m.path("models", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (m *ManagerClient) UpdateModel(ctx context.Context, id string, model LlmModel) (*LlmModel, error) {
	var out LlmModel
	if err := m.do(ctx, http.MethodPut, m.path("models", id), nil, model, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (m *ManagerClient) ListModels(ctx context.Context, params *ListParams) ([]LlmModel, error) {
	var out []LlmModel
	if err := m.do(ctx, http.MethodGet, m.path("models"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

func (m *ManagerClient) DeleteModel(ctx context.Context, id string) error {
	return m.do(ctx, http.MethodDelete, m.path("models", id), nil, nil, nil, false)
}

func (m *ManagerClient) EnableModel(ctx context.Context, id string, properties map[string]any) (*LlmModel, error) {
	var out LlmModel
	if err := m.do(ctx, http.MethodPatch, m.path("models", id, "enable"), nil, EnableModelRequest{Properties: properties}, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (m *ManagerClient) DisableModel(ctx context.Context, id string) (*LlmModel, error) {
	var out LlmModel
	if err := m.do(ctx, http.MethodPatch, m.path("models", id, "disable"), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

// --- Conversations -------------------------------------------------------

// ListConversationsByAgent returns conversations for an agent, enriched with
// last-message and message-count metadata. Conversations with no messages
// are excluded by the server.
func (m *ManagerClient) ListConversationsByAgent(ctx context.Context, agentID string, params *ListParams) ([]Conversation, error) {
	var out []Conversation
	if err := m.do(ctx, http.MethodGet, m.path("conversations", agentID), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

func (m *ManagerClient) CreateConversation(ctx context.Context, agentID string) (*Conversation, error) {
	var out Conversation
	if err := m.do(ctx, http.MethodPost, m.path("conversations"), nil, CreateConversationRequest{AgentID: agentID}, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (m *ManagerClient) DeleteConversation(ctx context.Context, id string) error {
	return m.do(ctx, http.MethodDelete, m.path("conversations", id), nil, nil, nil, true)
}

func (m *ManagerClient) GetConversationMessages(ctx context.Context, conversationID string) ([]ConversationMessage, error) {
	var out []ConversationMessage
	if err := m.do(ctx, http.MethodGet, m.path("conversations", conversationID, "messages"), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}
