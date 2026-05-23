import { LowcodbError } from "./errors.js";
import {
  HEADER_ORG_ID,
  HEADER_USER_ID,
  type APIErrorPayload,
  type Base,
  type Column,
  type ColumnsBulkResult,
  type CountResponse,
  type DashboardOverviewParams,
  type DashboardResponse,
  type DeleteCountResponse,
  type Field,
  type ListParams,
  type LowcodbRecord,
  type MetricsDashboardParams,
  type OverviewCounts,
  type RecordsBulkResult,
  type RowsResponse,
  type RunQueryRequest,
  type SuggestionsResponse,
  type SyncTablesResult,
  type Table,
  type TableIndex,
  type TableTrigger,
  type TableView,
  type TableWebhook,
  type TableWithColumns,
  type ValidationResponse,
  type ViewRefreshRequest,
  type ViewRefreshResponse,
} from "./types.js";

const DEFAULT_API_BASE_PATH = "/v1/lowcodb";

export interface LowcodbClientOptions {
  /** Manager URL (e.g. "http://localhost:8080"). Required. */
  baseURL: string;
  /** X-Org-Id header value. */
  orgId?: string;
  /** X-User-Id header value. */
  userId?: string;
  /** Extra headers added to every request. */
  defaultHeaders?: Record<string, string>;
  /** Route prefix; defaults to "/v1/lowcodb". */
  apiBasePath?: string;
  /** Custom fetch implementation (defaults to global fetch). */
  fetch?: typeof fetch;
  /** Per-request timeout in milliseconds (default 30 000). 0 disables. */
  timeoutMs?: number;
}

interface RequestInternalOptions {
  method: string;
  path: string;
  query?: URLSearchParams | null;
  body?: unknown;
  enveloped?: boolean;
  raw?: boolean;
}

export class LowcodbClient {
  private readonly baseURL: string;
  private readonly apiBasePath: string;
  private readonly fetchFn: typeof fetch;
  private readonly timeoutMs: number;
  private readonly headers: Record<string, string>;

  constructor(opts: LowcodbClientOptions) {
    if (!opts.baseURL || !opts.baseURL.trim()) {
      throw new Error("LowcodbClient: baseURL is required");
    }
    this.baseURL = opts.baseURL.replace(/\/+$/, "");
    this.apiBasePath = "/" + (opts.apiBasePath ?? DEFAULT_API_BASE_PATH).replace(/^\/+|\/+$/g, "");
    this.fetchFn = opts.fetch ?? fetch;
    this.timeoutMs = opts.timeoutMs ?? 30_000;

    this.headers = { ...(opts.defaultHeaders ?? {}) };
    if (opts.orgId) this.headers[HEADER_ORG_ID] = opts.orgId;
    if (opts.userId) this.headers[HEADER_USER_ID] = opts.userId;
  }

  setOrgId(orgId: string | null): void {
    if (orgId) this.headers[HEADER_ORG_ID] = orgId;
    else delete this.headers[HEADER_ORG_ID];
  }

  setUserId(userId: string | null): void {
    if (userId) this.headers[HEADER_USER_ID] = userId;
    else delete this.headers[HEADER_USER_ID];
  }

  /** Sets / overwrites an arbitrary default header. Pass null to delete. */
  setHeader(key: string, value: string | null): void {
    if (value === null) delete this.headers[key];
    else this.headers[key] = value;
  }

  // --- Health ------------------------------------------------------------

  async health(): Promise<void> {
    await this.request({ method: "GET", path: "/health", enveloped: false });
  }

  // --- Bases -------------------------------------------------------------

  getBase(id: string): Promise<Base> {
    return this.request({ method: "GET", path: this.api("bases", id), enveloped: true });
  }
  createBase(base: Base): Promise<Base> {
    return this.request({ method: "POST", path: this.api("bases"), body: base, enveloped: true });
  }
  updateBase(id: string, base: Base): Promise<Base> {
    return this.request({ method: "PUT", path: this.api("bases", id), body: base, enveloped: true });
  }
  async deleteBase(id: string): Promise<void> {
    await this.request({ method: "DELETE", path: this.api("bases", id), enveloped: true });
  }
  listBases(params?: ListParams): Promise<Base[]> {
    return this.request({
      method: "GET",
      path: this.api("bases"),
      query: this.listQuery(params),
      enveloped: true,
    });
  }
  /** Postman collection bytes (returned as an ArrayBuffer). */
  exportBaseCollection(id: string): Promise<ArrayBuffer> {
    return this.request({ method: "GET", path: this.api("bases", id, "export"), raw: true });
  }
  syncBaseTables(id: string): Promise<SyncTablesResult> {
    return this.request({
      method: "POST",
      path: this.api("bases", id, "sync-tables"),
      enveloped: true,
    });
  }

  // --- Tables ------------------------------------------------------------

  getTable(id: string): Promise<TableWithColumns> {
    return this.request({ method: "GET", path: this.api("tables", id), enveloped: true });
  }
  createTable(table: Table): Promise<TableWithColumns> {
    return this.request({ method: "POST", path: this.api("tables"), body: table, enveloped: true });
  }
  updateTable(id: string, table: Table): Promise<TableWithColumns> {
    return this.request({ method: "PUT", path: this.api("tables", id), body: table, enveloped: true });
  }
  async deleteTable(id: string): Promise<void> {
    await this.request({ method: "DELETE", path: this.api("tables", id), enveloped: true });
  }
  listTables(params?: ListParams): Promise<Table[]> {
    return this.request({
      method: "GET",
      path: this.api("tables"),
      query: this.listQuery(params),
      enveloped: true,
    });
  }

  // --- Columns -----------------------------------------------------------

  getColumn(tableId: string, id: string): Promise<Column> {
    return this.request({
      method: "GET",
      path: this.api("tables", tableId, "columns", id),
      enveloped: true,
    });
  }
  createColumn(tableId: string, column: Column): Promise<Column> {
    return this.request({
      method: "POST",
      path: this.api("tables", tableId, "columns"),
      body: column,
      enveloped: true,
    });
  }
  bulkCreateColumns(tableId: string, columns: Column[]): Promise<ColumnsBulkResult> {
    return this.request({
      method: "POST",
      path: this.api("tables", tableId, "columns", "bulk"),
      body: columns,
      enveloped: true,
    });
  }
  updateColumn(tableId: string, id: string, column: Column): Promise<Column> {
    return this.request({
      method: "PUT",
      path: this.api("tables", tableId, "columns", id),
      body: column,
      enveloped: true,
    });
  }
  bulkUpdateColumns(tableId: string, columns: Column[]): Promise<Record<string, unknown>> {
    return this.request({
      method: "PUT",
      path: this.api("tables", tableId, "columns", "bulk"),
      body: columns,
      enveloped: true,
    });
  }
  async deleteColumn(tableId: string, id: string): Promise<void> {
    await this.request({
      method: "DELETE",
      path: this.api("tables", tableId, "columns", id),
      enveloped: true,
    });
  }
  listColumns(tableId: string, params?: ListParams): Promise<Column[]> {
    return this.request({
      method: "GET",
      path: this.api("tables", tableId, "columns"),
      query: this.listQuery(params),
      enveloped: true,
    });
  }
  /** Runs the manager's field validator without persisting anything. */
  validateField(field: Field): Promise<ValidationResponse> {
    return this.request({
      method: "POST",
      path: this.api("validate"),
      body: field,
      enveloped: false,
    });
  }

  // --- Table indexes -----------------------------------------------------

  createTableIndex(tableId: string, index: TableIndex): Promise<TableIndex> {
    return this.request({
      method: "POST",
      path: this.api("tables", tableId, "index"),
      body: index,
      enveloped: true,
    });
  }
  updateTableIndex(tableId: string, id: string, index: TableIndex): Promise<TableIndex> {
    return this.request({
      method: "PUT",
      path: this.api("tables", tableId, "index", id),
      body: index,
      enveloped: true,
    });
  }
  listTableIndexes(tableId: string, params?: ListParams): Promise<TableIndex[]> {
    return this.request({
      method: "GET",
      path: this.api("tables", tableId, "indexes"),
      query: this.listQuery(params),
      enveloped: true,
    });
  }
  async deleteTableIndex(tableId: string, id: string): Promise<void> {
    await this.request({
      method: "DELETE",
      path: this.api("tables", tableId, "index", id),
      enveloped: true,
    });
  }

  // --- Records -----------------------------------------------------------

  createRecord(schema: string, tableName: string, record: LowcodbRecord): Promise<LowcodbRecord> {
    return this.request({
      method: "POST",
      path: this.data(schema, "tables", tableName, "records"),
      body: record,
      enveloped: true,
    });
  }
  getRecord(schema: string, tableName: string, id: string): Promise<LowcodbRecord> {
    return this.request({
      method: "GET",
      path: this.data(schema, "tables", tableName, "records", id),
      enveloped: true,
    });
  }
  updateRecord(
    schema: string,
    tableName: string,
    id: string,
    record: LowcodbRecord,
  ): Promise<LowcodbRecord> {
    return this.request({
      method: "PUT",
      path: this.data(schema, "tables", tableName, "records", id),
      body: record,
      enveloped: true,
    });
  }
  deleteRecord(schema: string, tableName: string, id: string): Promise<DeleteCountResponse> {
    return this.request({
      method: "DELETE",
      path: this.data(schema, "tables", tableName, "records", id),
      enveloped: true,
    });
  }
  listRecords(
    schema: string,
    tableName: string,
    params?: ListParams,
  ): Promise<LowcodbRecord[]> {
    return this.request({
      method: "GET",
      path: this.data(schema, "tables", tableName, "records"),
      query: this.listQuery(params),
      enveloped: true,
    });
  }
  countRecords(schema: string, tableName: string, params?: ListParams): Promise<CountResponse> {
    return this.request({
      method: "GET",
      path: this.data(schema, "tables", tableName, "records", "count"),
      query: this.listQuery(params),
      enveloped: true,
    });
  }
  async createBulkRecords(
    schema: string,
    tableName: string,
    records: LowcodbRecord[],
  ): Promise<void> {
    await this.request({
      method: "POST",
      path: this.data(schema, "tables", tableName, "records", "bulk"),
      body: records,
      enveloped: true,
    });
  }
  updateBulkRecords(
    schema: string,
    tableName: string,
    records: LowcodbRecord[],
  ): Promise<RecordsBulkResult> {
    return this.request({
      method: "PUT",
      path: this.data(schema, "tables", tableName, "records", "bulk"),
      body: records,
      enveloped: true,
    });
  }
  /**
   * Bulk delete. The manager treats `body` as the deletion criterion
   * (typically an array of ids or a filter clause).
   */
  async deleteBulkRecords(
    schema: string,
    tableName: string,
    body: unknown,
  ): Promise<void> {
    await this.request({
      method: "DELETE",
      path: this.data(schema, "tables", tableName, "records", "bulk"),
      body,
      enveloped: true,
    });
  }

  // --- View data --------------------------------------------------------

  getViewRecord(schema: string, viewName: string, id: string): Promise<LowcodbRecord> {
    return this.request({
      method: "GET",
      path: this.data(schema, "views", viewName, "records", id),
      enveloped: true,
    });
  }
  listViewRecords(
    schema: string,
    viewName: string,
    params?: ListParams,
  ): Promise<LowcodbRecord[]> {
    return this.request({
      method: "GET",
      path: this.data(schema, "views", viewName, "records"),
      query: this.listQuery(params),
      enveloped: true,
    });
  }
  countViewRecords(
    schema: string,
    viewName: string,
    params?: ListParams,
  ): Promise<CountResponse> {
    return this.request({
      method: "GET",
      path: this.data(schema, "views", viewName, "records", "count"),
      query: this.listQuery(params),
      enveloped: true,
    });
  }

  // --- Overview / dashboards --------------------------------------------

  getOverviewCounts(): Promise<OverviewCounts> {
    return this.request({
      method: "GET",
      path: this.api("overview", "counts"),
      enveloped: true,
    });
  }

  getMetricsDashboard(params?: MetricsDashboardParams): Promise<DashboardResponse> {
    const q = new URLSearchParams();
    if (params?.range) q.set("range", params.range);
    if (params?.from) q.set("from", params.from.toISOString());
    if (params?.to) q.set("to", params.to.toISOString());
    if (params?.baseId) q.set("baseId", params.baseId);
    return this.request({
      method: "GET",
      path: this.api("metrics", "dashboard"),
      query: q,
      enveloped: true,
    });
  }

  getDashboardOverview(params?: DashboardOverviewParams): Promise<DashboardResponse> {
    const q = new URLSearchParams();
    if (params?.baseId) q.set("baseId", params.baseId);
    if (params?.tableId) q.set("tableId", params.tableId);
    if (params?.startDate) q.set("startDate", params.startDate.toISOString());
    if (params?.endDate) q.set("endDate", params.endDate.toISOString());
    return this.request({
      method: "GET",
      path: this.api("dashboard", "overview"),
      query: q,
      enveloped: true,
    });
  }

  // --- Triggers ----------------------------------------------------------

  getTrigger(id: string): Promise<TableTrigger> {
    return this.request({ method: "GET", path: this.api("triggers", id), enveloped: true });
  }
  createTrigger(trigger: TableTrigger): Promise<TableTrigger> {
    return this.request({
      method: "POST",
      path: this.api("triggers"),
      body: trigger,
      enveloped: true,
    });
  }
  updateTrigger(id: string, trigger: TableTrigger): Promise<TableTrigger> {
    return this.request({
      method: "PUT",
      path: this.api("triggers", id),
      body: trigger,
      enveloped: true,
    });
  }
  async deleteTrigger(id: string): Promise<void> {
    await this.request({
      method: "DELETE",
      path: this.api("triggers", id),
      enveloped: false,
    });
  }
  listTriggers(params?: ListParams): Promise<TableTrigger[]> {
    return this.request({
      method: "GET",
      path: this.api("triggers"),
      query: this.listQuery(params),
      enveloped: true,
    });
  }

  // --- Webhooks ----------------------------------------------------------

  getWebhook(id: string): Promise<TableWebhook> {
    return this.request({ method: "GET", path: this.api("webhooks", id), enveloped: true });
  }
  createWebhook(webhook: TableWebhook): Promise<TableWebhook> {
    return this.request({
      method: "POST",
      path: this.api("webhooks"),
      body: webhook,
      enveloped: true,
    });
  }
  updateWebhook(id: string, webhook: TableWebhook): Promise<TableWebhook> {
    return this.request({
      method: "PUT",
      path: this.api("webhooks", id),
      body: webhook,
      enveloped: true,
    });
  }
  async deleteWebhook(id: string): Promise<void> {
    await this.request({
      method: "DELETE",
      path: this.api("webhooks", id),
      enveloped: false,
    });
  }
  listWebhooks(params?: ListParams): Promise<TableWebhook[]> {
    return this.request({
      method: "GET",
      path: this.api("webhooks"),
      query: this.listQuery(params),
      enveloped: true,
    });
  }

  // --- Query -------------------------------------------------------------

  executeQuery(req: RunQueryRequest): Promise<RowsResponse> {
    return this.request({
      method: "POST",
      path: this.api("query", "execute"),
      body: req,
      enveloped: true,
    });
  }
  getQuerySuggestions(query: string, baseId?: string): Promise<SuggestionsResponse> {
    const q = new URLSearchParams({ query });
    if (baseId) q.set("baseId", baseId);
    return this.request({
      method: "GET",
      path: this.api("query", "suggestions"),
      query: q,
      enveloped: true,
    });
  }

  // --- Views (metadata) -------------------------------------------------

  listViews(params?: ListParams): Promise<TableView[]> {
    return this.request({
      method: "GET",
      path: this.api("views"),
      query: this.listQuery(params),
      enveloped: true,
    });
  }
  createView(view: TableView): Promise<TableView> {
    return this.request({
      method: "POST",
      path: this.api("views"),
      body: view,
      enveloped: true,
    });
  }
  getView(id: string): Promise<TableView> {
    return this.request({ method: "GET", path: this.api("views", id), enveloped: true });
  }
  updateView(id: string, view: TableView): Promise<TableView> {
    return this.request({
      method: "PUT",
      path: this.api("views", id),
      body: view,
      enveloped: true,
    });
  }
  async deleteView(id: string): Promise<void> {
    await this.request({ method: "DELETE", path: this.api("views", id), enveloped: true });
  }
  refreshView(id: string, req: ViewRefreshRequest): Promise<ViewRefreshResponse> {
    return this.request({
      method: "POST",
      path: this.api("views", id, "refresh"),
      body: req,
      enveloped: true,
    });
  }

  // --- internals --------------------------------------------------------

  private api(...parts: string[]): string {
    const segs = [this.apiBasePath.replace(/^\/+|\/+$/g, "")];
    for (const p of parts) segs.push(encodeURIComponent(p.replace(/^\/+|\/+$/g, "")));
    return "/" + segs.join("/");
  }

  private data(schema: string, objectType: string, objectName: string, ...parts: string[]): string {
    const segs = [
      this.apiBasePath.replace(/^\/+|\/+$/g, ""),
      "data",
      encodeURIComponent(schema),
      objectType,
      encodeURIComponent(objectName),
    ];
    for (const p of parts) segs.push(encodeURIComponent(p));
    return "/" + segs.join("/");
  }

  private listQuery(params?: ListParams): URLSearchParams | null {
    if (!params) return null;
    const q = new URLSearchParams();
    if (params.pageNo !== undefined) q.set("pageNo", String(params.pageNo));
    if (params.size !== undefined) q.set("size", String(params.size));
    if (params.filter !== undefined) q.set("filter", params.filter);
    if (params.sort !== undefined) q.set("sort", params.sort);
    return q;
  }

  private async request<T>(opts: RequestInternalOptions): Promise<T> {
    const url = new URL(this.baseURL + opts.path);
    if (opts.query) {
      opts.query.forEach((v, k) => url.searchParams.append(k, v));
    }

    const headers: Record<string, string> = {
      Accept: "application/json",
      ...this.headers,
    };
    let body: string | undefined;
    if (opts.body !== undefined && opts.body !== null) {
      body = JSON.stringify(opts.body);
      headers["Content-Type"] = "application/json";
    }

    const controller = this.timeoutMs > 0 ? new AbortController() : null;
    const timer =
      controller !== null
        ? setTimeout(() => controller.abort(), this.timeoutMs)
        : null;

    let resp: Response;
    try {
      resp = await this.fetchFn(url.toString(), {
        method: opts.method,
        headers,
        body,
        signal: controller?.signal,
      });
    } finally {
      if (timer) clearTimeout(timer);
    }

    if (opts.raw) {
      if (!resp.ok) await throwHttpError(resp);
      return (await resp.arrayBuffer()) as T;
    }

    const text = await resp.text();
    if (!resp.ok) {
      throw buildHttpError(resp.status, text);
    }

    if (resp.status === 204 || text.trim().length === 0) {
      return undefined as T;
    }

    if (opts.enveloped) {
      return decodeEnvelope<T>(text);
    }
    return JSON.parse(text) as T;
  }
}

async function throwHttpError(resp: Response): Promise<never> {
  const text = await resp.text();
  throw buildHttpError(resp.status, text);
}

function buildHttpError(status: number, text: string): LowcodbError {
  let message = text.trim();
  let code: string | undefined;
  try {
    const parsed = JSON.parse(text) as { message?: string; error?: APIErrorPayload };
    if (parsed.error?.message?.trim()) {
      message = parsed.error.message;
      code = parsed.error.code;
    } else if (parsed.message) {
      message = parsed.message;
    }
  } catch {
    /* keep raw text */
  }
  return new LowcodbError({ statusCode: status, message, code, body: text });
}

function decodeEnvelope<T>(text: string): T {
  let env: { success?: boolean; data?: unknown; message?: string; error?: APIErrorPayload };
  try {
    env = JSON.parse(text);
  } catch {
    // Not enveloped — return raw JSON.
    return JSON.parse(text) as T;
  }
  if (env && typeof env === "object" && "data" in env) {
    if (env.data === undefined || env.data === null) return undefined as T;
    return env.data as T;
  }
  return env as T;
}
