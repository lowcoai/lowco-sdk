type Primitive = string | number | boolean | null;
type JsonValue = Primitive | JsonObject | JsonValue[];
type JsonObject = {
    [key: string]: JsonValue;
};
type HttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
interface SDKConfig {
    baseUrl: string;
    token?: string;
    orgId?: string;
    userId?: string;
    timeoutMs?: number;
    headers?: Record<string, string>;
    fetch?: typeof globalThis.fetch;
}
interface RequestOptions {
    query?: Record<string, unknown>;
    headers?: Record<string, string>;
    signal?: AbortSignal;
}
interface ApiEnvelope<T> {
    success?: boolean;
    code?: string;
    message?: string;
    data?: T;
    error?: unknown;
    [key: string]: unknown;
}
interface BaseEntity {
    id?: string;
    orgId?: string;
    createdBy?: string;
    updatedBy?: string;
    createdAt?: string;
    updatedAt?: string;
}
interface PaginationQuery {
    [key: string]: string | number | boolean | undefined;
    page?: number;
    limit?: number;
    sortBy?: string;
    sortOrder?: "asc" | "desc";
    filter?: string;
    tags?: string;
}
type ApplicationType = "http" | "database" | "queue" | "storage" | (string & {});
type ApplicationSubType = "http" | "oauth2" | "postgres" | "mysql" | "clickhouse" | "nats" | "mongodb" | "redis" | "rabbitmq" | "kafka" | "sqs" | "qdrant" | "zep" | "opensearch" | (string & {});
type ConnectionType = "oauth2" | (string & {});
type ConnectionStatus = "active" | "inactive" | "revoked" | "expired" | "pending" | (string & {});
interface Application extends BaseEntity {
    name: string;
    description?: string;
    icon?: string;
    type: ApplicationType;
    subType: ApplicationSubType;
    operationConfig?: Record<string, unknown>;
    authConfig?: Record<string, unknown>;
    supportProtocol?: unknown;
    tags?: string[];
    version?: number;
    mcpKey?: string;
    publishedUrl?: string;
}
interface ApplicationWithCount extends Application {
    count: number;
}
interface ApplicationWithConnection extends Application {
    connections: Connection[];
    actionId?: string;
}
interface ApplicationHistory extends BaseEntity {
    application: Application;
    comment?: string;
}
type SubApplicationConfig = Record<ApplicationType, ApplicationSubType[]>;
interface PatchTagsRequest {
    tags: string[];
}
interface RunApplicationRequest {
    credentialId?: string;
    inputBody: Record<string, unknown>;
}
type HttpInput = Record<string, unknown>;
interface HttpActionType {
    type: string;
    metadata?: HttpInput;
}
interface ApplicationAction extends BaseEntity {
    applicationId: string;
    name: string;
    groupName?: string;
    description?: string;
    action: HttpActionType;
    properties?: unknown;
}
interface RunActionRequest {
    credentialId?: string;
    inputBody: Record<string, unknown>;
}
interface PostmanFolder {
    name?: string;
    item?: PostmanFolder[];
    request?: Record<string, unknown>;
    [key: string]: unknown;
}
interface Connection extends BaseEntity {
    name: string;
    description?: string;
    connectionType: ConnectionType;
    applicationType?: ApplicationType;
    applicationSubType?: ApplicationSubType;
    connectionStatus?: ConnectionStatus;
    applicationId: string;
    properties?: Record<string, unknown>;
    isDefault?: boolean;
}
interface ConnectionResponse extends Connection {
    applicationType?: ApplicationType;
    applicationSubType?: ApplicationSubType;
}
interface SetAsDefaultRequest {
    applicationId: string;
}
interface ApplicationTrigger extends BaseEntity {
    name: string;
    description?: string;
    operationConfig?: Record<string, unknown>;
    applicationId: string;
    webhookUrl?: string;
}
interface TriggerState {
    triggerId: string;
    orgId?: string;
    cursor?: Record<string, unknown>;
    lastRunAt?: string;
    lastError?: string;
    runCount: number;
    leasedBy?: string;
    leasedUntil?: string;
    updatedAt?: string;
}
interface ConnectionCreateRequest {
    applicationId: string;
    name?: string;
    description?: string;
}
interface CallbackRequest {
    state: string;
    code: string;
}
interface OAuthLoginUrl {
    url: string;
}
interface OAuthCallbackResult {
    success: string;
}
interface AuthToken extends BaseEntity {
    requestId?: string;
    applicationId: string;
    credentialId: string;
    token: string;
    refreshToken?: string;
    expiresIn?: number;
    expiry?: string;
    tokenType?: string;
}
interface RefreshExpiringTokensResult {
    checked: number;
    refreshed: number;
    skipped: number;
    failed: number;
    refreshedTokens: AuthToken[];
    failures: Array<Record<string, unknown>>;
}
interface JsonRpcRequest {
    jsonrpc: string;
    id?: string | number | null;
    method: string;
    params?: unknown;
}
interface JsonRpcError {
    code: number;
    message: string;
    data?: unknown;
}
interface JsonRpcResponse {
    jsonrpc: string;
    id?: string | number | null;
    result?: unknown;
    error?: JsonRpcError;
}
interface McpToolsResponse {
    tools: Array<Record<string, unknown>>;
}

declare const HEADER_ORG_ID = "X-Org-Id";
declare const HEADER_USER_ID = "X-User-Id";
declare class IntegrationsError extends Error {
    readonly status: number;
    readonly payload: unknown;
    constructor(message: string, status: number, payload: unknown);
}
declare class HttpClient {
    private readonly baseUrl;
    private readonly token?;
    private readonly orgId?;
    private readonly userId?;
    private readonly timeoutMs;
    private readonly extraHeaders;
    private readonly fetchImpl;
    constructor(config: SDKConfig);
    request<T>(method: HttpMethod, path: string, body?: unknown, options?: RequestOptions): Promise<T>;
    private buildUrl;
    private unwrapEnvelope;
}

declare class ActionsResource {
    private readonly http;
    constructor(http: HttpClient);
    list(query?: PaginationQuery): Promise<ApplicationAction[]>;
    getById(id: string): Promise<ApplicationAction>;
    create(applicationId: string, payload: ApplicationAction): Promise<ApplicationAction>;
    update(id: string, payload: ApplicationAction): Promise<ApplicationAction>;
    delete(id: string): Promise<void>;
    listByApplication(applicationId: string): Promise<ApplicationAction[]>;
    run(id: string, payload: RunActionRequest): Promise<unknown>;
    resolveCredentials(actionIds: string[]): Promise<ApplicationWithConnection[]>;
}

declare class ApplicationsResource {
    private readonly http;
    constructor(http: HttpClient);
    list(query?: PaginationQuery): Promise<ApplicationWithCount[]>;
    getById(id: string): Promise<Application>;
    create(payload: Application): Promise<Application>;
    update(id: string, payload: Application): Promise<Application>;
    delete(id: string): Promise<void>;
    patchTags(id: string, tags: string[]): Promise<Application>;
    run(id: string, payload: RunApplicationRequest): Promise<unknown>;
    loadActions(id: string, folder: PostmanFolder): Promise<ApplicationAction[]>;
    versions(id: string, query?: PaginationQuery): Promise<ApplicationHistory[]>;
    regenerateMcpKey(id: string): Promise<Application>;
    getMcpTools(id: string): Promise<McpToolsResponse>;
    getSubApplications(): Promise<SubApplicationConfig>;
    getApplicationsWithTriggers(): Promise<Application[]>;
}

declare class ConfigurationsResource {
    private readonly http;
    constructor(http: HttpClient);
    get(): Promise<Record<ApplicationType, ApplicationSubType[]>>;
}

declare class ConnectionsResource {
    private readonly http;
    constructor(http: HttpClient);
    list(query?: PaginationQuery): Promise<Connection[]>;
    getById(id: string): Promise<ConnectionResponse>;
    create(payload: Connection): Promise<Connection>;
    update(id: string, payload: Connection): Promise<Connection>;
    delete(id: string): Promise<void>;
    listByApplication(applicationId: string): Promise<Connection[]>;
    setAsDefault(id: string, applicationId: string): Promise<Connection>;
}

declare class McpResource {
    private readonly http;
    constructor(http: HttpClient);
    callPublished(key: string, payload: JsonRpcRequest): Promise<JsonRpcResponse>;
    infoPublished(key: string): Promise<Record<string, unknown>>;
}

declare class OAuthResource {
    private readonly http;
    constructor(http: HttpClient);
    login(applicationId: string, payload: ConnectionCreateRequest): Promise<OAuthLoginUrl>;
    callback(payload: CallbackRequest): Promise<OAuthCallbackResult>;
    getTokenByCredentialId(credentialId: string): Promise<AuthToken>;
    refreshTokenByCredentialId(credentialId: string): Promise<AuthToken>;
    refreshExpiringTokens(): Promise<RefreshExpiringTokensResult>;
}

declare class TriggersResource {
    private readonly http;
    constructor(http: HttpClient);
    listByApplication(applicationId: string, query?: PaginationQuery): Promise<ApplicationTrigger[]>;
    getById(id: string): Promise<ApplicationTrigger>;
    create(payload: ApplicationTrigger): Promise<ApplicationTrigger>;
    update(id: string, payload: ApplicationTrigger): Promise<ApplicationTrigger>;
    delete(id: string): Promise<void>;
    getState(id: string): Promise<TriggerState>;
}

declare class IntegrationsClient {
    readonly applications: ApplicationsResource;
    readonly actions: ActionsResource;
    readonly connections: ConnectionsResource;
    readonly triggers: TriggersResource;
    readonly oauth: OAuthResource;
    readonly configurations: ConfigurationsResource;
    readonly mcp: McpResource;
    constructor(config: SDKConfig);
}

export { type ApiEnvelope, type Application, type ApplicationAction, type ApplicationHistory, type ApplicationSubType, type ApplicationTrigger, type ApplicationType, type ApplicationWithConnection, type ApplicationWithCount, type AuthToken, type BaseEntity, type CallbackRequest, type Connection, type ConnectionCreateRequest, type ConnectionResponse, type ConnectionStatus, type ConnectionType, HEADER_ORG_ID, HEADER_USER_ID, type HttpActionType, HttpClient, type HttpInput, type HttpMethod, IntegrationsClient, IntegrationsError, type JsonObject, type JsonRpcError, type JsonRpcRequest, type JsonRpcResponse, type JsonValue, type McpToolsResponse, type OAuthCallbackResult, type OAuthLoginUrl, type PaginationQuery, type PatchTagsRequest, type PostmanFolder, type Primitive, type RefreshExpiringTokensResult, type RequestOptions, type RunActionRequest, type RunApplicationRequest, type SDKConfig, type SetAsDefaultRequest, type SubApplicationConfig, type TriggerState };
