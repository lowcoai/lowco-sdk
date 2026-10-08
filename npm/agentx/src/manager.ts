import type { ServiceTarget, Transport } from "./transport.js";
import type {
  Agent,
  AgentHistory,
  AgentPatch,
  AgentPublish,
  Conversation,
  ConversationMessage,
  ListParams,
  LlmModel,
  PublishAgentRequest,
  UpdatePublishedAgentRequest,
} from "./types.js";

/** Exposes the agent-manager service routes. */
export class ManagerClient {
  constructor(
    private readonly transport: Transport,
    private readonly target: ServiceTarget,
  ) {}

  private path(...parts: string[]): string {
    return this.transport.joinPath(this.target.apiBasePath, ...parts);
  }

  // --- Health ------------------------------------------------------------

  async health(): Promise<void> {
    await this.transport.request<void>(this.target, {
      method: "GET",
      path: "/health",
      enveloped: false,
    });
  }

  // --- Agents ------------------------------------------------------------

  listAgents(params?: ListParams): Promise<Agent[]> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("agents"),
      query: this.transport.listQuery(params),
      enveloped: true,
    });
  }
  getAgent(id: string): Promise<Agent> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("agents", id),
      enveloped: true,
    });
  }
  createAgent(agent: Agent): Promise<Agent> {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("agents"),
      body: agent,
      enveloped: true,
    });
  }
  updateAgent(id: string, agent: Agent): Promise<Agent> {
    return this.transport.request(this.target, {
      method: "PUT",
      path: this.path("agents", id),
      body: agent,
      enveloped: true,
    });
  }
  patchAgent(id: string, patch: AgentPatch): Promise<Agent> {
    return this.transport.request(this.target, {
      method: "PATCH",
      path: this.path("agents", id),
      body: patch,
      enveloped: true,
    });
  }
  /** The /agents/count endpoint returns a raw integer, not an envelope. */
  getAgentCount(params?: ListParams): Promise<number> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("agents", "count"),
      query: this.transport.listQuery(params),
      enveloped: false,
    });
  }
  async deleteAgent(id: string): Promise<void> {
    await this.transport.request<void>(this.target, {
      method: "DELETE",
      path: this.path("agents", id),
      enveloped: false,
    });
  }
  async bulkDeleteAgents(ids: string[]): Promise<void> {
    await this.transport.request<void>(this.target, {
      method: "POST",
      path: this.path("agents", "bulk-delete"),
      body: { ids },
      enveloped: false,
    });
  }
  getAgentVersions(id: string, params?: ListParams): Promise<AgentHistory[]> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("agents", id, "versions"),
      query: this.transport.listQuery(params),
      enveloped: true,
    });
  }

  // --- Published agents -------------------------------------------------

  publishAgent(agentId: string, req: PublishAgentRequest): Promise<AgentPublish> {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("agents", agentId, "publish"),
      body: req,
      enveloped: true,
    });
  }
  getPublishedAgent(id: string): Promise<AgentPublish> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("agents", "published", id),
      enveloped: true,
    });
  }
  updatePublishedAgent(id: string, req: UpdatePublishedAgentRequest): Promise<AgentPublish> {
    return this.transport.request(this.target, {
      method: "PUT",
      path: this.path("agents", "published", id),
      body: req,
      enveloped: true,
    });
  }
  async deletePublishedAgent(id: string): Promise<void> {
    await this.transport.request<void>(this.target, {
      method: "DELETE",
      path: this.path("agents", "published", id),
      enveloped: false,
    });
  }
  listPublishedAgents(params?: ListParams): Promise<AgentPublish[]> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("agents", "published"),
      query: this.transport.listQuery(params),
      enveloped: true,
    });
  }

  // --- LLM models -------------------------------------------------------

  createModel(model: LlmModel): Promise<LlmModel> {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("models"),
      body: model,
      enveloped: true,
    });
  }
  getModel(id: string): Promise<LlmModel> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("models", id),
      enveloped: true,
    });
  }
  updateModel(id: string, model: LlmModel): Promise<LlmModel> {
    return this.transport.request(this.target, {
      method: "PUT",
      path: this.path("models", id),
      body: model,
      enveloped: true,
    });
  }
  listModels(params?: ListParams): Promise<LlmModel[]> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("models"),
      query: this.transport.listQuery(params),
      enveloped: true,
    });
  }
  async deleteModel(id: string): Promise<void> {
    await this.transport.request<void>(this.target, {
      method: "DELETE",
      path: this.path("models", id),
      enveloped: false,
    });
  }
  enableModel(id: string, properties: Record<string, unknown>): Promise<LlmModel> {
    return this.transport.request(this.target, {
      method: "PATCH",
      path: this.path("models", id, "enable"),
      body: { properties },
      enveloped: true,
    });
  }
  disableModel(id: string): Promise<LlmModel> {
    return this.transport.request(this.target, {
      method: "PATCH",
      path: this.path("models", id, "disable"),
      enveloped: true,
    });
  }

  // --- Conversations ----------------------------------------------------

  listConversationsByAgent(agentId: string, params?: ListParams): Promise<Conversation[]> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("conversations", agentId),
      query: this.transport.listQuery(params),
      enveloped: true,
    });
  }
  createConversation(agentId: string): Promise<Conversation> {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("conversations"),
      body: { agentId },
      enveloped: true,
    });
  }
  async deleteConversation(id: string): Promise<void> {
    await this.transport.request<void>(this.target, {
      method: "DELETE",
      path: this.path("conversations", id),
      enveloped: true,
    });
  }
  getConversationMessages(conversationId: string): Promise<ConversationMessage[]> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("conversations", conversationId, "messages"),
      enveloped: true,
    });
  }
}
