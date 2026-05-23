export const HEADER_ORG_ID = "X-Org-Id";
export const HEADER_USER_ID = "X-User-Id";

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
  code?: string;
  message?: string;
  details?: Record<string, unknown>;
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
