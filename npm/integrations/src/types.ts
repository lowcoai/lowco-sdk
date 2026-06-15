export type Primitive = string | number | boolean | null;
export type JsonValue = Primitive | JsonObject | JsonValue[];
export type JsonObject = { [key: string]: JsonValue };

export type HttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

export interface SDKConfig {
  /** User token or API key sent as `Authorization: Bearer <token>` on every request. Required. */
  token: string;
  orgId?: string;
  timeoutMs?: number;
  headers?: Record<string, string>;
  fetch?: typeof globalThis.fetch;
}

export interface RequestOptions {
  query?: Record<string, unknown>;
  headers?: Record<string, string>;
  signal?: AbortSignal;
}

export interface ApiEnvelope<T> {
  success?: boolean;
  code?: string;
  message?: string;
  data?: T;
  error?: unknown;
  [key: string]: unknown;
}

export interface BaseEntity {
  id?: string;
  orgId?: string;
  createdBy?: string;
  updatedBy?: string;
  createdAt?: string;
  updatedAt?: string;
}

export interface PaginationQuery {
  [key: string]: string | number | boolean | undefined;
  page?: number;
  limit?: number;
  sortBy?: string;
  sortOrder?: "asc" | "desc";
  filter?: string;
  tags?: string;
}

export type ApplicationType = "http" | "database" | "queue" | "storage" | (string & {});

export type ApplicationSubType =
  | "http"
  | "oauth2"
  | "postgres"
  | "mysql"
  | "clickhouse"
  | "nats"
  | "mongodb"
  | "redis"
  | "rabbitmq"
  | "kafka"
  | "sqs"
  | "qdrant"
  | "zep"
  | "opensearch"
  | (string & {});

export type ConnectionType = "oauth2" | (string & {});

export type ConnectionStatus =
  | "active"
  | "inactive"
  | "revoked"
  | "expired"
  | "pending"
  | (string & {});

export interface Application extends BaseEntity {
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

export interface ApplicationWithCount extends Application {
  count: number;
}

export interface ApplicationWithConnection extends Application {
  connections: Connection[];
  actionId?: string;
}

export interface ApplicationHistory extends BaseEntity {
  application: Application;
  comment?: string;
}

export type SubApplicationConfig = Record<ApplicationType, ApplicationSubType[]>;

export interface PatchTagsRequest {
  tags: string[];
}

export interface RunApplicationRequest {
  credentialId?: string;
  inputBody: Record<string, unknown>;
}

export type HttpInput = Record<string, unknown>;

export interface HttpActionType {
  type: string;
  metadata?: HttpInput;
}

export interface ApplicationAction extends BaseEntity {
  applicationId: string;
  name: string;
  groupName?: string;
  description?: string;
  action: HttpActionType;
  properties?: unknown;
}

export interface RunActionRequest {
  credentialId?: string;
  inputBody: Record<string, unknown>;
}

export interface PostmanFolder {
  name?: string;
  item?: PostmanFolder[];
  request?: Record<string, unknown>;
  [key: string]: unknown;
}

export interface Connection extends BaseEntity {
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

export interface ConnectionResponse extends Connection {
  applicationType?: ApplicationType;
  applicationSubType?: ApplicationSubType;
}

export interface SetAsDefaultRequest {
  applicationId: string;
}

export interface ApplicationTrigger extends BaseEntity {
  name: string;
  description?: string;
  operationConfig?: Record<string, unknown>;
  applicationId: string;
  webhookUrl?: string;
}

export interface TriggerState {
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

export interface ConnectionCreateRequest {
  applicationId: string;
  name?: string;
  description?: string;
}

export interface CallbackRequest {
  state: string;
  code: string;
}

export interface OAuthLoginUrl {
  url: string;
}

export interface OAuthCallbackResult {
  success: string;
}

export interface AuthToken extends BaseEntity {
  requestId?: string;
  applicationId: string;
  credentialId: string;
  token: string;
  refreshToken?: string;
  expiresIn?: number;
  expiry?: string;
  tokenType?: string;
}

export interface RefreshExpiringTokensResult {
  checked: number;
  refreshed: number;
  skipped: number;
  failed: number;
  refreshedTokens: AuthToken[];
  failures: Array<Record<string, unknown>>;
}

export interface JsonRpcRequest {
  jsonrpc: string;
  id?: string | number | null;
  method: string;
  params?: unknown;
}

export interface JsonRpcError {
  code: number;
  message: string;
  data?: unknown;
}

export interface JsonRpcResponse {
  jsonrpc: string;
  id?: string | number | null;
  result?: unknown;
  error?: JsonRpcError;
}

export interface McpToolsResponse {
  tools: Array<Record<string, unknown>>;
}
