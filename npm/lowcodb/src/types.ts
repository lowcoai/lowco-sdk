export const HEADER_ORG_ID = "X-Org-Id";

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

export type BaseType = "internal" | "external";

export interface Base extends BaseEntity {
  name?: string;
  description?: string;
  connectionId?: string;
  baseType?: BaseType;
  schema?: string;
}

export interface Table extends BaseEntity {
  baseId?: string;
  name?: string;
  description?: string;
  tableKey?: string;
  metadata?: Record<string, unknown>;
}

export interface ColumnTrimmed {
  name?: string;
  dataType?: string;
}

export interface TableWithColumns extends Table {
  columns?: ColumnTrimmed[];
}

export interface ColumnMetadata {
  option?: string[];
  isNotNull?: boolean;
  isPrimaryKey?: boolean;
  isUnique?: boolean;
  isAutoIncrement?: boolean;
  maxLength?: number;
  selectType?: string;
}

export interface ValidationError {
  rule?: string;
  error?: string;
}

export interface DropdownOption {
  label?: string;
  value?: string;
}

export interface Field {
  value?: unknown;
  dataType?: string;
  options?: DropdownOption[];
  validations?: ValidationError[];
}

export interface ValidationResponse {
  value?: unknown;
  errors?: ValidationError[];
}

export interface Column extends BaseEntity {
  baseId?: string;
  tableId?: string;
  name?: string;
  dataType?: string;
  metadata?: ColumnMetadata;
  defaultValue?: string;
  validations?: ValidationError[];
}

export interface TableIndex extends BaseEntity {
  baseId?: string;
  tableId?: string;
  indexName?: string;
  columns?: string[];
  isUnique?: boolean;
}

/** Rename-only payload accepted by PUT /tables/{tableId}/index/{id}. */
export interface TableIndexUpdateInput {
  indexName?: string;
}

export interface TableTrigger extends BaseEntity {
  baseId?: string;
  tableId?: string;
  eventType?: string;
  eventTime?: string;
  workflowId?: string;
  /** Populated only by listTriggers (enrichment from the workflow service). */
  workflowName?: string;
}

export interface TableWebhook extends BaseEntity {
  baseId?: string;
  tableId?: string;
  url?: string;
  headers?: Record<string, string>;
  eventTypes?: string[];
  method?: string;
  active?: boolean;
}

export type FunctionHTTPMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

export interface DBFunctionMetadata {
  /** Execution timeout in ms; server default 10 000, capped at 55 000. */
  timeoutMs?: number;
  /** HTTP methods the invoke route accepts; defaults to ["POST"]. */
  methods?: FunctionHTTPMethod[];
  /** Reserved: invokable without gateway auth. Defaults to false. */
  public?: boolean;
}

/** A user-authored JavaScript function scoped to a base. */
export interface DBFunction extends BaseEntity {
  baseId?: string;
  name?: string;
  /** URL slug the function is invoked under (/v1/fn/{functionKey}). */
  functionKey?: string;
  description?: string;
  /** JavaScript source. Top-level `return` and `await` are allowed. */
  body?: string;
  version?: number;
  isActive?: boolean;
  metadata?: DBFunctionMetadata;
}

/** Create/update payload; a body change auto-creates a version snapshot. */
export interface DBFunctionUpsertInput {
  baseId?: string;
  name?: string;
  functionKey?: string;
  description?: string;
  body?: string;
  isActive?: boolean;
  metadata?: DBFunctionMetadata;
  /** Label for the version snapshot created when the body changes. */
  comment?: string;
}

export interface DBFunctionVersion extends BaseEntity {
  functionId?: string;
  version?: number;
  body?: string;
  comment?: string;
}

export interface FunctionExecuteError {
  /** "TIMEOUT" | "COMPILE_ERROR" | "FUNCTION_ERROR" */
  code?: string;
  message?: string;
  stack?: string;
}

/** Full console-execution result (returned even when the function itself failed). */
export interface FunctionExecuteResult {
  success?: boolean;
  result?: unknown;
  logs?: string[];
  error?: FunctionExecuteError;
  durationMs?: number;
}

export interface FunctionInvokeOptions {
  /** HTTP method for the invocation; must be allowed by the function. Default POST. */
  method?: FunctionHTTPMethod;
}

export type TransactionOperationType = "create" | "update" | "delete";

/** One step of an atomic record transaction. */
export interface TransactionOperation {
  type: TransactionOperationType;
  table: string;
  /** Required for update and delete. */
  id?: string;
  /** Fields for create and update. */
  record?: LowcodbRecord;
}

/** Per-operation results, in order: the written row, or {deletedCount} for deletes. */
export interface TransactionResult {
  results?: LowcodbRecord[];
}

/** Payload of publishEvent (ctx.events.publish in DB functions). */
export interface PublishEventInput {
  /** Event name, e.g. "lead.qualified" (alphanumeric tokens separated by dots). */
  eventType: string;
  /** Scopes the NATS subject's table segment; "_" when omitted. */
  tableName?: string;
  record?: LowcodbRecord;
  correlationId?: string;
}

export interface PublishEventResult {
  published?: boolean;
  subject?: string;
}

export type TableViewKind = "view" | "materialized_view";

export interface TableView extends BaseEntity {
  baseId?: string;
  name?: string;
  description?: string;
  viewKey?: string;
  kind?: TableViewKind;
  definition?: string;
  metadata?: Record<string, unknown>;
}

/**
 * A user-table row. System fields (`id`, `createdAt`, ...) are always
 * present alongside whatever columns the table defines.
 */
export type LowcodbRecord = Record<string, unknown>;

export interface RunQueryRequest {
  query: string;
  baseId?: string;
}

export interface RowsResponse {
  rows?: Array<Record<string, unknown>>;
}

export interface SuggestionsResponse {
  suggestions?: string[];
}

export interface CountResponse {
  count?: number;
}

export interface DeleteCountResponse {
  deletedCount?: number;
}

export interface ViewRefreshRequest {
  concurrent: boolean;
}

export interface ViewRefreshResponse {
  status?: string;
}

export interface ColumnsBulkResult {
  created?: Column[];
  failed?: Array<Record<string, unknown>>;
}

export interface RecordsBulkResult {
  updated?: LowcodbRecord[];
  failed?: Array<Record<string, unknown>>;
}

export interface OverviewCounts {
  totals?: Record<string, number>;
  bases?: Array<Record<string, unknown>>;
}

export interface SyncTablesResult {
  tablesAdded?: string[];
  tablesRemoved?: string[];
  tablesUpdated?: string[];
  errors?: string[];
}

export type DashboardResponse = Record<string, unknown>;

export interface APIErrorPayload {
  /** The manager sends the numeric HTTP status here, not a string code. */
  code?: string | number;
  /** The opaque platform code ("AAS-00105"), *not* the human message. */
  message?: string;
  /** Where the real message actually lives. A string on the wire. */
  details?: string | Record<string, unknown>;
}

export interface ListParams {
  pageNo?: number;
  size?: number;
  filter?: string;
  sort?: string;
}

export interface MetricsDashboardParams {
  /** Go duration string, e.g. "5m", "24h". */
  range?: string;
  from?: Date;
  to?: Date;
  baseId?: string;
}

export interface DashboardOverviewParams {
  baseId?: string;
  tableId?: string;
  startDate?: Date;
  endDate?: Date;
}
