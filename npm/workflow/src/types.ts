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
  where?: string;
}

export interface Variable {
  id?: string;
  name: string;
  value: string;
}

export interface Environment extends BaseEntity {
  name: string;
  description?: string;
  isDefaultEnv?: boolean;
  variables?: Variable[];
}

export interface WorkflowUINode {
  id: string;
  type?: string;
  data?: JsonObject;
  [key: string]: unknown;
}

export interface WorkflowUIEdge {
  id: string;
  source: string;
  target: string;
  type?: string;
  label?: string;
}

export interface WorkflowUI {
  nodes: WorkflowUINode[];
  edges: WorkflowUIEdge[];
}

export interface Workflow extends BaseEntity {
  name: string;
  description?: string;
  inputData?: Record<string, unknown>;
  ui: WorkflowUI;
  tags?: string[];
  version?: number;
  published?: boolean;
}

export interface WorkflowUpdateRequest extends Workflow {
  comment?: string;
}

export interface RunWorkflowRequest {
  workflowId: string;
  inputData?: Record<string, unknown>;
  environmentId?: string;
  triggeredBy?: string;
  orgId?: string;
  activityId?: string;
  executionId?: string;
}

export interface FunctionEntity extends BaseEntity {
  name: string;
  description?: string;
  body: string;
  version?: number;
  isActive?: boolean;
}

export interface FunctionVersionRequest {
  function: FunctionEntity;
  comment?: string;
}

export interface HumanTaskAction {
  text: string;
  value: string;
}

export interface HumanTask extends BaseEntity {
  message: string;
  actions?: HumanTaskAction[];
  assignedTo?: string;
  executionId: string;
  workflowId: string;
  answer?: string;
  completed?: boolean;
  completedAt?: string;
  activityId: string;
}

export interface Execution extends BaseEntity {
  workflowId: string;
  correlationId?: string;
  version?: number;
  status?: string;
  context?: Record<string, unknown>;
  failedReason?: string;
  inputData?: unknown;
  outputData?: unknown;
  workflow?: Workflow;
}

export interface ActivityExecutionHistory extends BaseEntity {
  activityId: string;
  workflowId: string;
  executionId: string;
  type?: string;
  typeId?: string;
  status?: string;
  inputData?: unknown;
  outputData?: unknown;
  failedReason?: string;
}

export interface ActivityHistoryResponse {
  id: string;
  history: ActivityExecutionHistory;
  activity?: Record<string, unknown>;
  workflow?: Workflow;
  execution?: Execution;
}

export interface WorkflowPublish extends BaseEntity {
  workflowId: string;
  sourceOrgId?: string;
  category?: string;
  longDescription?: string;
  workflow?: Workflow;
}

export interface DryRunRequest {
  executionId: string;
  expression: string;
  typeOfExpression: "object" | "string" | "statement" | "map";
  activityId: string;
}

/**
 * @deprecated Only used by the deprecated `webhooks.create` and
 * `webhooks.update`, which always reject. Will be removed in a future major
 * version.
 */
export interface WebhookCreateRequest {
  url: string;
  authenticationType?: string;
  authDetails?: Record<string, unknown>;
}
