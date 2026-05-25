declare const HEADER_ORG_ID = "X-Org-Id";
declare const HEADER_USER_ID = "X-User-Id";
declare const DEFAULT_MANAGER_API_BASE_PATH = "/v1/agentx/manager";
declare const DEFAULT_KB_API_BASE_PATH = "/v1/agentx/kb";
declare const DEFAULT_EXECUTOR_API_BASE_PATH = "/v1/agentx/executors";
type ISODateString = string;
interface BaseEntity {
    id?: string;
    orgId?: string;
    prn?: string;
    createdAt?: ISODateString;
    updatedAt?: ISODateString | null;
    createdBy?: string;
    updatedBy?: string;
}
interface ListParams {
    pageNo?: number;
    size?: number;
    filter?: string;
    sort?: string;
}
interface APIErrorPayload {
    code?: string;
    message?: string;
    details?: Record<string, unknown>;
}
type AgentOutputMode = "full_response" | "last_message";
type MultiAgentPattern = "hierarchy" | "supervisor" | "network" | "planner";
type AgentMemoryType = "lowco";
interface CustomRoutingConfig {
    haltCondition?: string;
    routerFunction?: string;
}
interface AgentTool {
    id?: string;
    source?: string;
    sourceId?: string;
    name?: string;
}
interface AgentCapabilities {
    streaming?: boolean;
    pushNotifications?: boolean;
    stateTransitionHistory?: boolean;
    extensions?: boolean;
}
interface AgentSkill {
    id?: string;
    description?: string;
    name?: string[];
    tags?: string[];
    examples?: string;
    inputModes?: string[];
    outputModes?: string[];
}
interface AgentConfiguration {
    maxTokens?: number;
    maxIterations?: number;
    temperature?: number;
    topK?: number;
}
interface Agent extends BaseEntity {
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
interface AgentInfo {
    id?: string;
    name?: string;
    modelName?: string;
    welcomeMessage?: string;
}
interface AgentHistory extends BaseEntity {
    agent?: Agent;
    comment?: string;
}
interface AgentPatch {
    tags?: string[];
}
interface AgentPublish extends BaseEntity {
    agent?: Agent | null;
    sourceOrgId?: string;
    agentId?: string;
    longDescription?: string;
    category?: string;
    /** Server-enriched field populated by listPublishedAgents. */
    latestVersion?: number;
}
interface PublishAgentRequest {
    longDescription?: string;
    category?: string;
}
interface UpdatePublishedAgentRequest {
    longDescription?: string;
    category?: string;
    agentId?: string;
}
interface LlmModel extends BaseEntity {
    name?: string;
    description?: string;
    provider?: string;
    icon?: string;
    disabled?: boolean;
    config?: Record<string, unknown>;
    embedding?: boolean;
}
/**
 * MessageContent is either a plain string or an array of block objects.
 * The agent-manager service treats it as opaque polymorphic JSON.
 */
type MessageContent = string | Array<Record<string, unknown>>;
interface Conversation extends BaseEntity {
    chatType?: string;
    /** Server-enriched on listConversationsByAgent. */
    lastMessage?: MessageContent | null;
    count?: number;
    /** Server-enriched on createConversation when this is the first conversation. */
    welcomeMessage?: string;
}
interface ConversationMessage extends BaseEntity {
    conversationId?: string;
    role?: string;
    content?: MessageContent;
    memberId?: string | null;
    chatType?: string;
    metadata?: Record<string, unknown>;
}
interface KnowledgeBase extends BaseEntity {
    name?: string;
    description?: string;
    connectionId?: string;
    modelId?: string;
}
interface Dataset extends BaseEntity {
    name?: string;
    knowledgeBaseId?: string;
    content?: string;
}
/**
 * Body for POST /v1/agentx/kb/embeddings.
 * `distance` values are Qdrant distance-metric names (e.g. "Cosine", "Dot", "Euclid").
 */
interface EmbeddingDbRequest {
    modelId?: string;
    credentialId?: string;
    texts?: string;
    payload?: Record<string, unknown>;
    collection?: string;
    distance?: string;
}
/** The only JSON-RPC method handled by the executor today. */
declare const METHOD_MESSAGE_SEND = "message/send";
type PartKind = "text" | "file" | "data";
type MessageRole = "user" | "assistant";
interface TextPart {
    kind: "text";
    text: string;
    metadata?: Record<string, unknown>;
}
interface FileWithBytes {
    name?: string | null;
    mimeType?: string | null;
    bytes: string;
}
interface FileWithURI {
    name?: string | null;
    mimeType?: string | null;
    uri: string;
}
type FilePayload = FileWithBytes | FileWithURI;
interface FilePart {
    kind: "file";
    file: FilePayload;
    metadata?: Record<string, unknown>;
}
interface DataPart {
    kind: "data";
    data: Record<string, unknown>;
    metadata?: Record<string, unknown>;
}
type Part = TextPart | FilePart | DataPart;
/**
 * Single A2A communication turn (executor input/output).
 * Named A2AMessage to avoid colliding with manager's ConversationMessage.
 */
interface A2AMessage {
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
interface PushNotificationAuthenticationInfo {
    schemes: string[];
    credentials?: string | null;
}
interface PushNotificationConfig {
    id?: string | null;
    url: string;
    token?: string | null;
    authentication?: PushNotificationAuthenticationInfo;
}
interface MessageSendConfiguration {
    acceptedOutputModes?: string[];
    historyLength?: number;
    pushNotificationConfig?: PushNotificationConfig;
    blocking?: boolean;
}
interface MessageSendParams {
    message: A2AMessage;
    configuration?: MessageSendConfiguration;
    metadata?: Record<string, unknown>;
    chatType?: string;
}
interface JSONRPCRequest {
    jsonrpc: "2.0";
    method: string;
    params?: unknown;
    /** The executor reuses the JSON-RPC `id` as the target agent identifier. */
    id?: string | number | null;
}
interface JSONRPCError {
    code: number;
    message: string;
    data?: unknown;
}
interface JSONRPCResponse<T = unknown> {
    jsonrpc: "2.0";
    result?: T;
    error?: JSONRPCError;
    id?: string | number | null;
}
/** Standard JSON-RPC error codes. */
declare const JSONRPC_ERROR_CODES: {
    readonly ParseError: -32700;
    readonly InvalidRequest: -32600;
    readonly MethodNotFound: -32601;
    readonly InvalidParams: -32602;
    readonly InternalError: -32603;
};
/** A2A-specific error codes (-32000 to -32099). */
declare const A2A_ERROR_CODES: {
    readonly TaskNotFound: -32001;
    readonly TaskNotCancelable: -32002;
    readonly PushNotificationNotSupported: -32003;
    readonly UnsupportedOperation: -32004;
    readonly ContentTypeNotSupported: -32005;
    readonly InvalidAgentResponse: -32006;
};

/**
 * Thrown for HTTP-level non-2xx responses from any agentx service.
 *
 * `statusCode` is always set. `message` and `code` are populated when the
 * service returns its standard JSON error envelope; otherwise `message`
 * falls back to the raw response text and `code` is undefined.
 *
 * JSON-RPC level errors from the executor are surfaced inside the `error`
 * field of [JSONRPCResponse], not thrown.
 */
declare class AgentxError extends Error {
    readonly statusCode: number;
    readonly code?: string;
    readonly body: string;
    constructor(opts: {
        statusCode: number;
        message: string;
        code?: string;
        body: string;
    });
}

/** Per-service URL + route prefix, shared by all three sub-clients. */
interface ServiceTarget {
    baseURL: string;
    apiBasePath: string;
}
interface TransportOptions {
    fetch: typeof fetch;
    /** Mutable header bag – the parent Client owns it. */
    headers: Record<string, string>;
    /** Per-request timeout for non-streaming calls; 0 disables. */
    timeoutMs: number;
}
interface RequestOptions {
    method: string;
    path: string;
    query?: URLSearchParams | null;
    body?: unknown;
    enveloped?: boolean;
}
/**
 * Shared HTTP transport used by every sub-client.
 * Pass the target service to each request.
 */
declare class Transport {
    private readonly fetchFn;
    readonly headers: Record<string, string>;
    private readonly timeoutMs;
    constructor(opts: TransportOptions);
    joinPath(apiBasePath: string, ...parts: string[]): string;
    listQuery(params?: ListParams): URLSearchParams | null;
    /** Send a JSON request and decode (optionally enveloped) JSON response. */
    request<T>(target: ServiceTarget, opts: RequestOptions): Promise<T>;
    /**
     * Send a request and return the raw Response, without decoding.
     * Used by the executor's SSE stream.
     */
    sendRaw(target: ServiceTarget, opts: RequestOptions & {
        accept?: string;
        signal?: AbortSignal;
    }): Promise<Response>;
    private send;
}

/**
 * A single SSE event delivered by [ExecutorClient.streamMessage]. `data` is
 * the raw JSON payload of the event, which is typically an [A2AMessage] but
 * may also be a tool/status frame. Call [tryParseMessage] for a Message-typed view.
 */
interface StreamEvent {
    data: string;
}
declare function tryParseMessage(ev: StreamEvent): A2AMessage | null;
/** Exposes the agent-executor service routes. */
declare class ExecutorClient {
    private readonly transport;
    private readonly target;
    constructor(transport: Transport, target: ServiceTarget);
    private path;
    health(): Promise<void>;
    /**
     * Performs a synchronous `message/send` call. The JSON-RPC id doubles as
     * the target agent identifier (matching the service convention).
     */
    sendMessage<T = unknown>(agentId: string, params: MessageSendParams): Promise<JSONRPCResponse<T>>;
    /**
     * Streams a `message/send` call, yielding one [StreamEvent] per SSE event
     * the server emits. Pass an AbortSignal to cancel mid-stream.
     *
     * ```ts
     * for await (const ev of client.Executor.streamMessage(agentId, params)) {
     *   const msg = tryParseMessage(ev);
     *   if (msg) console.log("delta:", msg);
     *   else console.log("raw:", ev.data);
     * }
     * ```
     */
    streamMessage(agentId: string, params: MessageSendParams, options?: {
        signal?: AbortSignal;
    }): AsyncGenerator<StreamEvent, void, void>;
}

/** Exposes the agent-kb (knowledge-base) service routes. */
declare class KBClient {
    private readonly transport;
    private readonly target;
    constructor(transport: Transport, target: ServiceTarget);
    private path;
    health(): Promise<void>;
    listKnowledgeBases(params?: ListParams): Promise<KnowledgeBase[]>;
    createKnowledgeBase(kb: KnowledgeBase): Promise<KnowledgeBase>;
    getKnowledgeBase(id: string): Promise<KnowledgeBase>;
    updateKnowledgeBase(id: string, kb: KnowledgeBase): Promise<KnowledgeBase>;
    /** The /knowledges/count endpoint returns a raw integer, not an envelope. */
    getKnowledgeBaseCount(params?: ListParams): Promise<number>;
    listDatasets(params?: ListParams): Promise<Dataset[]>;
    createDataset(dataset: Dataset): Promise<Dataset>;
    getDataset(id: string): Promise<Dataset>;
    updateDataset(id: string, dataset: Dataset): Promise<Dataset>;
    deleteDataset(id: string): Promise<void>;
    /** The /datasets/count endpoint returns a raw integer, not an envelope. */
    getDatasetCount(params?: ListParams): Promise<number>;
    /** Persists embeddings into the vector store; returns the service's success message. */
    storeEmbeddings(req: EmbeddingDbRequest): Promise<string>;
}

/** Exposes the agent-manager service routes. */
declare class ManagerClient {
    private readonly transport;
    private readonly target;
    constructor(transport: Transport, target: ServiceTarget);
    private path;
    health(): Promise<void>;
    listAgents(params?: ListParams): Promise<Agent[]>;
    getAgent(id: string): Promise<Agent>;
    createAgent(agent: Agent): Promise<Agent>;
    updateAgent(id: string, agent: Agent): Promise<Agent>;
    patchAgent(id: string, patch: AgentPatch): Promise<Agent>;
    /** The /agents/count endpoint returns a raw integer, not an envelope. */
    getAgentCount(params?: ListParams): Promise<number>;
    deleteAgent(id: string): Promise<void>;
    bulkDeleteAgents(ids: string[]): Promise<void>;
    getAgentVersions(id: string, params?: ListParams): Promise<AgentHistory[]>;
    publishAgent(agentId: string, req: PublishAgentRequest): Promise<AgentPublish>;
    getPublishedAgent(id: string): Promise<AgentPublish>;
    updatePublishedAgent(id: string, req: UpdatePublishedAgentRequest): Promise<AgentPublish>;
    deletePublishedAgent(id: string): Promise<void>;
    listPublishedAgents(params?: ListParams): Promise<AgentPublish[]>;
    createModel(model: LlmModel): Promise<LlmModel>;
    getModel(id: string): Promise<LlmModel>;
    updateModel(id: string, model: LlmModel): Promise<LlmModel>;
    listModels(params?: ListParams): Promise<LlmModel[]>;
    deleteModel(id: string): Promise<void>;
    enableModel(id: string, properties: Record<string, unknown>): Promise<LlmModel>;
    disableModel(id: string): Promise<LlmModel>;
    listConversationsByAgent(agentId: string, params?: ListParams): Promise<Conversation[]>;
    createConversation(agentId: string): Promise<Conversation>;
    deleteConversation(id: string): Promise<void>;
    getConversationMessages(conversationId: string): Promise<ConversationMessage[]>;
}

interface AgentxClientOptions {
    /**
     * Base URL applied to all three services (e.g. "http://localhost:8080").
     * When the services live on different hosts, omit this and use the
     * `managerURL` / `kbURL` / `executorURL` per-service overrides.
     */
    baseURL?: string;
    /** Override the agent-manager base URL. */
    managerURL?: string;
    /** Override the agent-kb base URL. */
    kbURL?: string;
    /** Override the agent-executor base URL. */
    executorURL?: string;
    /** Override the agent-manager route prefix (default "/v1/agentx/manager"). */
    managerApiBasePath?: string;
    /** Override the agent-kb route prefix (default "/v1/agentx/kb"). */
    kbApiBasePath?: string;
    /** Override the agent-executor route prefix (default "/v1/agentx/executors"). */
    executorApiBasePath?: string;
    /** X-Org-Id header value. */
    orgId?: string;
    /** X-User-Id header value. */
    userId?: string;
    /** Extra headers added to every request. */
    defaultHeaders?: Record<string, string>;
    /** Custom fetch implementation (defaults to global fetch). */
    fetch?: typeof fetch;
    /**
     * Per-request timeout in milliseconds for non-streaming calls
     * (default 30 000; `0` disables). Executor `streamMessage` ignores this –
     * pass an AbortSignal to cancel a stream instead.
     */
    timeoutMs?: number;
}
/**
 * Unified agentx client.
 *
 * Wraps three sub-clients – [Manager], [KB], [Executor] – that share HTTP
 * transport, tenancy headers and request options. Pass a single `baseURL`
 * for a unified deployment, or per-service URLs when the services live on
 * different hosts.
 */
declare class AgentxClient {
    private readonly headers;
    /** Agent-manager sub-client. */
    readonly Manager: ManagerClient;
    /** Agent-kb (knowledge-base) sub-client. */
    readonly KB: KBClient;
    /** Agent-executor sub-client. */
    readonly Executor: ExecutorClient;
    constructor(opts: AgentxClientOptions);
    setOrgId(orgId: string | null): void;
    setUserId(userId: string | null): void;
    /** Sets / overwrites an arbitrary default header. Pass null to delete. */
    setHeader(key: string, value: string | null): void;
}

export { type A2AMessage, A2A_ERROR_CODES, type APIErrorPayload, type Agent, type AgentCapabilities, type AgentConfiguration, type AgentHistory, type AgentInfo, type AgentMemoryType, type AgentOutputMode, type AgentPatch, type AgentPublish, type AgentSkill, type AgentTool, AgentxClient, type AgentxClientOptions, AgentxError, type BaseEntity, type Conversation, type ConversationMessage, type CustomRoutingConfig, DEFAULT_EXECUTOR_API_BASE_PATH, DEFAULT_KB_API_BASE_PATH, DEFAULT_MANAGER_API_BASE_PATH, type DataPart, type Dataset, type EmbeddingDbRequest, ExecutorClient, type FilePart, type FilePayload, type FileWithBytes, type FileWithURI, HEADER_ORG_ID, HEADER_USER_ID, type ISODateString, type JSONRPCError, type JSONRPCRequest, type JSONRPCResponse, JSONRPC_ERROR_CODES, KBClient, type KnowledgeBase, type ListParams, type LlmModel, METHOD_MESSAGE_SEND, ManagerClient, type MessageContent, type MessageRole, type MessageSendConfiguration, type MessageSendParams, type MultiAgentPattern, type Part, type PartKind, type PublishAgentRequest, type PushNotificationAuthenticationInfo, type PushNotificationConfig, type StreamEvent, type TextPart, type UpdatePublishedAgentRequest, tryParseMessage };
