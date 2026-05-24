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
    where?: string;
}
interface Variable {
    id?: string;
    name: string;
    value: string;
}
interface Environment extends BaseEntity {
    name: string;
    description?: string;
    isDefaultEnv?: boolean;
    variables?: Variable[];
}
interface WorkflowUINode {
    id: string;
    type?: string;
    data?: JsonObject;
    [key: string]: unknown;
}
interface WorkflowUIEdge {
    id: string;
    source: string;
    target: string;
    type?: string;
    label?: string;
}
interface WorkflowUI {
    nodes: WorkflowUINode[];
    edges: WorkflowUIEdge[];
}
interface Workflow extends BaseEntity {
    name: string;
    description?: string;
    inputData?: Record<string, unknown>;
    ui: WorkflowUI;
    tags?: string[];
    version?: number;
    published?: boolean;
}
interface WorkflowUpdateRequest extends Workflow {
    comment?: string;
}
interface RunWorkflowRequest {
    workflowId: string;
    inputData?: Record<string, unknown>;
    environmentId?: string;
    triggeredBy?: string;
    orgId?: string;
    activityId?: string;
    executionId?: string;
}
interface FunctionEntity extends BaseEntity {
    name: string;
    description?: string;
    body: string;
    version?: number;
    isActive?: boolean;
}
interface FunctionVersionRequest {
    function: FunctionEntity;
    comment?: string;
}
interface HumanTaskAction {
    text: string;
    value: string;
}
interface HumanTask extends BaseEntity {
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
interface Execution extends BaseEntity {
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
interface ActivityExecutionHistory extends BaseEntity {
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
interface ActivityHistoryResponse {
    id: string;
    history: ActivityExecutionHistory;
    activity?: Record<string, unknown>;
    workflow?: Workflow;
    execution?: Execution;
}
interface WorkflowPublish extends BaseEntity {
    workflowId: string;
    sourceOrgId?: string;
    category?: string;
    longDescription?: string;
    workflow?: Workflow;
}
interface DryRunRequest {
    executionId: string;
    expression: string;
    typeOfExpression: "object" | "string" | "statement" | "map";
    activityId: string;
}
interface WebhookCreateRequest {
    url: string;
    authenticationType?: string;
    authDetails?: Record<string, unknown>;
}

declare const HEADER_ORG_ID = "X-Org-Id";
declare const HEADER_USER_ID = "X-User-Id";
declare class WorkflowError extends Error {
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

declare class ActivitiesResource {
    private readonly http;
    constructor(http: HttpClient);
    list(query?: PaginationQuery): Promise<ActivityHistoryResponse[]>;
    count(query?: PaginationQuery): Promise<number | Record<string, unknown>>;
    getById(id: string): Promise<ActivityHistoryResponse>;
    logs(id: string): Promise<unknown[]>;
}

declare class AnalyticsResource {
    private readonly http;
    constructor(http: HttpClient);
    default(): Promise<Record<string, unknown>>;
    getById(id: string): Promise<Record<string, unknown>>;
}

declare class DryRunResource {
    private readonly http;
    constructor(http: HttpClient);
    execute(payload: DryRunRequest): Promise<unknown>;
}

declare class EnvironmentsResource {
    private readonly http;
    constructor(http: HttpClient);
    list(query?: PaginationQuery): Promise<Environment[]>;
    getById(id: string): Promise<Environment>;
    create(payload: Environment): Promise<Environment>;
    update(id: string, payload: Environment): Promise<Environment>;
    delete(id: string): Promise<void>;
    setDefault(id: string): Promise<Environment>;
}

declare class ExecutionsResource {
    private readonly http;
    constructor(http: HttpClient);
    list(query?: PaginationQuery & {
        full?: boolean;
    }): Promise<Execution[]>;
    count(query?: PaginationQuery): Promise<number | Record<string, unknown>>;
    getById(id: string): Promise<Execution>;
    logs(id: string): Promise<unknown[]>;
}

declare class FunctionsResource {
    private readonly http;
    constructor(http: HttpClient);
    list(query?: PaginationQuery): Promise<FunctionEntity[]>;
    getById(id: string): Promise<FunctionEntity>;
    create(payload: FunctionEntity): Promise<FunctionEntity>;
    update(id: string, payload: FunctionVersionRequest): Promise<FunctionEntity>;
    delete(id: string): Promise<void>;
    versions(id: string, query?: PaginationQuery): Promise<FunctionEntity[]>;
    execute(id: string, params?: Record<string, unknown>): Promise<Record<string, unknown>>;
}

declare class HumanTasksResource {
    private readonly http;
    constructor(http: HttpClient);
    list(query?: PaginationQuery): Promise<HumanTask[]>;
    getById(id: string): Promise<HumanTask>;
    complete(id: string, action: string): Promise<HumanTask>;
}

declare class WebhooksResource {
    private readonly http;
    constructor(http: HttpClient);
    trigger(workflowId: string, payload?: Record<string, unknown>, query?: {
        env?: string;
        triggeredBy?: string;
        async?: boolean;
    }): Promise<Record<string, unknown>>;
    listByWorkflow(workflowId: string): Promise<Record<string, unknown>[]>;
    create(workflowId: string, payload: WebhookCreateRequest): Promise<Record<string, unknown>>;
    update(webhookId: string, payload: WebhookCreateRequest): Promise<Record<string, unknown>>;
    delete(workflowId: string): Promise<Record<string, unknown>>;
}

declare class WorkflowsResource {
    private readonly http;
    constructor(http: HttpClient);
    list(query?: PaginationQuery): Promise<Workflow[]>;
    count(query?: PaginationQuery): Promise<number | Record<string, unknown>>;
    getById(id: string): Promise<Workflow>;
    create(payload: WorkflowUpdateRequest): Promise<Workflow>;
    update(id: string, payload: WorkflowUpdateRequest): Promise<Workflow>;
    delete(id: string): Promise<void>;
    run(payload: RunWorkflowRequest): Promise<Record<string, unknown>>;
    versions(id: string, query?: PaginationQuery): Promise<Workflow[]>;
    publish(id: string, payload: {
        category: string;
        longDescription: string;
    }): Promise<WorkflowPublish>;
    published(query?: PaginationQuery): Promise<WorkflowPublish[]>;
    publishedCount(query?: PaginationQuery): Promise<number | Record<string, unknown>>;
    getPublishedById(id: string): Promise<WorkflowPublish>;
    updatePublished(id: string, payload: {
        category: string;
        longDescription: string;
    }): Promise<WorkflowPublish>;
    deletePublished(id: string): Promise<void>;
    webPublished(query?: PaginationQuery): Promise<WorkflowPublish[]>;
    webPublishedById(id: string): Promise<WorkflowPublish>;
    searchPublishedTemplates(params: {
        q?: string;
        category?: string;
        limit?: number;
    }): Promise<WorkflowPublish[]>;
}

declare class WorkflowClient {
    readonly workflows: WorkflowsResource;
    readonly environments: EnvironmentsResource;
    readonly functions: FunctionsResource;
    readonly executions: ExecutionsResource;
    readonly activities: ActivitiesResource;
    readonly humanTasks: HumanTasksResource;
    readonly analytics: AnalyticsResource;
    readonly dryRun: DryRunResource;
    readonly webhooks: WebhooksResource;
    constructor(config: SDKConfig);
}

export { type ActivityExecutionHistory, type ActivityHistoryResponse, type ApiEnvelope, type BaseEntity, type DryRunRequest, type Environment, type Execution, type FunctionEntity, type FunctionVersionRequest, HEADER_ORG_ID, HEADER_USER_ID, HttpClient, type HttpMethod, type HumanTask, type HumanTaskAction, type JsonObject, type JsonValue, type PaginationQuery, type Primitive, type RequestOptions, type RunWorkflowRequest, type SDKConfig, type Variable, type WebhookCreateRequest, type Workflow, WorkflowClient, WorkflowError, type WorkflowPublish, type WorkflowUI, type WorkflowUIEdge, type WorkflowUINode, type WorkflowUpdateRequest };
