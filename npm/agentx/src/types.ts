export const HEADER_ORG_ID = "X-Org-Id";

export const DEFAULT_MANAGER_API_BASE_PATH = "/v1/agentx/manager";
export const DEFAULT_KB_API_BASE_PATH = "/v1/agentx/kb";
export const DEFAULT_EXECUTOR_API_BASE_PATH = "/v1/agentx/executors";

export type ISODateString = string;

export interface BaseEntity {
  id?: string;
  orgId?: string;
  prn?: string;
  createdAt?: ISODateString;
  updatedAt?: ISODateString | null;
  createdBy?: string;
  updatedBy?: string;
}

export interface ListParams {
  pageNo?: number;
  size?: number;
  filter?: string;
  sort?: string;
}

export interface APIErrorPayload {
  code?: string;
  message?: string;
  details?: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Manager: agents
// ---------------------------------------------------------------------------

export type AgentOutputMode = "full_response" | "last_message";

export type MultiAgentPattern = "hierarchy" | "supervisor" | "network" | "planner";

export type AgentMemoryType = "lowco";

export interface CustomRoutingConfig {
  haltCondition?: string;
  routerFunction?: string;
}

export interface AgentTool {
  id?: string;
  source?: string;
  sourceId?: string;
  name?: string;
}

export interface AgentCapabilities {
  streaming?: boolean;
  pushNotifications?: boolean;
  stateTransitionHistory?: boolean;
  extensions?: boolean;
}

export interface AgentSkill {
  id?: string;
  description?: string;
  name?: string[];
  tags?: string[];
  examples?: string;
  inputModes?: string[];
  outputModes?: string[];
}

export interface AgentConfiguration {
  maxTokens?: number;
  maxIterations?: number;
  temperature?: number;
  topK?: number;
}

export interface Agent extends BaseEntity {
  name?: string;
  description?: string;
  modelName?: string;
  prompt?: string;
  provider?: string;
  tools?: AgentTool[];
  knowledgeBaseIds?: string[];
  configurations?: AgentConfiguration;
  outputMode?: AgentOutputMode;
  iconUrl?: string | null;
  documentationUrl?: string | null;
  capabilities?: AgentCapabilities;
  skills?: AgentSkill[];
  memoryType?: AgentMemoryType | null;
  subAgentPattern?: MultiAgentPattern | null;
  subAgents?: string[];
  routingConfig?: CustomRoutingConfig | null;
  published?: boolean;
  version?: number;
  applicationWithCredential?: Record<string, string>;
  welcomeMessage?: string | null;
  tags?: string[];
  /** Server-enriched field populated by listAgents. */
  modelId?: string;
}

export interface AgentInfo {
  id?: string;
  name?: string;
  modelName?: string;
  welcomeMessage?: string;
}

export interface AgentHistory extends BaseEntity {
  agent?: Agent;
  comment?: string;
}

export interface AgentPatch {
  tags?: string[];
}

export interface AgentPublish extends BaseEntity {
  agent?: Agent | null;
  sourceOrgId?: string;
  agentId?: string;
  longDescription?: string;
  category?: string;
  /** Server-enriched field populated by listPublishedAgents. */
  latestVersion?: number;
}

export interface PublishAgentRequest {
  longDescription?: string;
  category?: string;
}

export interface UpdatePublishedAgentRequest {
  longDescription?: string;
  category?: string;
  agentId?: string;
}

// ---------------------------------------------------------------------------
// Manager: LLM models
// ---------------------------------------------------------------------------

export interface LlmModel extends BaseEntity {
  name?: string;
  description?: string;
  provider?: string;
  icon?: string;
  disabled?: boolean;
  config?: Record<string, unknown>;
  embedding?: boolean;
}

// ---------------------------------------------------------------------------
// Manager: conversations
// ---------------------------------------------------------------------------

/**
 * MessageContent is either a plain string or an array of block objects.
 * The agent-manager service treats it as opaque polymorphic JSON.
 */
export type MessageContent = string | Array<Record<string, unknown>>;

export interface Conversation extends BaseEntity {
  chatType?: string;
  /** Server-enriched on listConversationsByAgent. */
  lastMessage?: MessageContent | null;
  count?: number;
  /** Server-enriched on createConversation when this is the first conversation. */
  welcomeMessage?: string;
}

export interface ConversationMessage extends BaseEntity {
  conversationId?: string;
  role?: string;
  content?: MessageContent;
  memberId?: string | null;
  chatType?: string;
  metadata?: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// KB
// ---------------------------------------------------------------------------

export interface KnowledgeBase extends BaseEntity {
  name?: string;
  description?: string;
  connectionId?: string;
  modelId?: string;
}

export interface Dataset extends BaseEntity {
  name?: string;
  knowledgeBaseId?: string;
  content?: string;
}

/**
 * Body for POST /v1/agentx/kb/embeddings.
 * `distance` values are Qdrant distance-metric names (e.g. "Cosine", "Dot", "Euclid").
 */
export interface EmbeddingDbRequest {
  modelId?: string;
  credentialId?: string;
  texts?: string;
  payload?: Record<string, unknown>;
  collection?: string;
  distance?: string;
}

// ---------------------------------------------------------------------------
// Executor (A2A JSON-RPC + SSE)
// ---------------------------------------------------------------------------

/** The only JSON-RPC method handled by the executor today. */
export const METHOD_MESSAGE_SEND = "message/send";

export type PartKind = "text" | "file" | "data";

export type MessageRole = "user" | "assistant";

export interface TextPart {
  kind: "text";
  text: string;
  metadata?: Record<string, unknown>;
}

export interface FileWithBytes {
  name?: string | null;
  mimeType?: string | null;
  bytes: string;
}

export interface FileWithURI {
  name?: string | null;
  mimeType?: string | null;
  uri: string;
}

export type FilePayload = FileWithBytes | FileWithURI;

export interface FilePart {
  kind: "file";
  file: FilePayload;
  metadata?: Record<string, unknown>;
}

export interface DataPart {
  kind: "data";
  data: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}

export type Part = TextPart | FilePart | DataPart;

/**
 * Single A2A communication turn (executor input/output).
 * Named A2AMessage to avoid colliding with manager's ConversationMessage.
 */
export interface A2AMessage {
  role: MessageRole;
  parts: Part[];
  metadata?: Record<string, unknown>;
  extensions?: string[];
  referenceTaskIds?: string[];
  messageId: string;
  taskId?: string | null;
  contextId?: string | null;
  kind: "message";
}

export interface PushNotificationAuthenticationInfo {
  schemes: string[];
  credentials?: string | null;
}

export interface PushNotificationConfig {
  id?: string | null;
  url: string;
  token?: string | null;
  authentication?: PushNotificationAuthenticationInfo;
}

export interface MessageSendConfiguration {
  acceptedOutputModes?: string[];
  historyLength?: number;
  pushNotificationConfig?: PushNotificationConfig;
  blocking?: boolean;
}

export interface MessageSendParams {
  message: A2AMessage;
  configuration?: MessageSendConfiguration;
  metadata?: Record<string, unknown>;
  chatType?: string;
}

export interface JSONRPCRequest {
  jsonrpc: "2.0";
  method: string;
  params?: unknown;
  /** The executor reuses the JSON-RPC `id` as the target agent identifier. */
  id?: string | number | null;
}

export interface JSONRPCError {
  code: number;
  message: string;
  data?: unknown;
}

export interface JSONRPCResponse<T = unknown> {
  jsonrpc: "2.0";
  result?: T;
  error?: JSONRPCError;
  id?: string | number | null;
}

/** Standard JSON-RPC error codes. */
export const JSONRPC_ERROR_CODES = {
  ParseError: -32700,
  InvalidRequest: -32600,
  MethodNotFound: -32601,
  InvalidParams: -32602,
  InternalError: -32603,
} as const;

/** A2A-specific error codes (-32000 to -32099). */
export const A2A_ERROR_CODES = {
  TaskNotFound: -32001,
  TaskNotCancelable: -32002,
  PushNotificationNotSupported: -32003,
  UnsupportedOperation: -32004,
  ContentTypeNotSupported: -32005,
  InvalidAgentResponse: -32006,
} as const;
