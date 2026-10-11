import { LowcodbError, parseQuotaExceeded } from "./errors.js";
import {
  HEADER_ORG_ID,
  type APIErrorPayload,
  type Base,
  type Column,
  type ColumnsBulkResult,
  type CountResponse,
  type DashboardOverviewParams,
  type DashboardResponse,
  type DBFunction,
  type DBFunctionUpsertInput,
  type DBFunctionVersion,
  type DeleteCountResponse,
  type Field,
  type FunctionExecuteResult,
  type FunctionInvokeOptions,
  type ListParams,
  type LowcodbRecord,
  type MetricsDashboardParams,
  type OverviewCounts,
  type PublishEventInput,
  type PublishEventResult,
  type RecordsBulkResult,
  type RowsResponse,
  type RunQueryRequest,
  type SuggestionsResponse,
  type SyncTablesResult,
  type Table,
  type TableIndex,
  type TableIndexUpdateInput,
  type TableTrigger,
  type TableView,
  type TableWebhook,
  type TableWithColumns,
  type TransactionOperation,
  type TransactionResult,
  type ValidationResponse,
  type ViewRefreshRequest,
  type ViewRefreshResponse,
} from "./types.js";

const BASE_URL = "https://api.lowco.ai";

const DEFAULT_API_BASE_PATH = "/v1/lowcodb";

/** Which address of a base's gateway data calls are sent to. */
export type GatewayOrigin = "public" | "internal";

/** Where a base's data is served, as `GET /v1/lowcodb/bases/{id}/gateway` answers it. */
export interface GatewayInfo {
  gatewayId: string;
  hash?: string;
  contextPath?: string;
  url?: string;
  internalUrl?: string;
  gatewayType?: string;
  routes?: { tables: string; views: string; functions: string; transactions?: string };
  sync?: { status: string; syncedAt?: string; routeCount?: number; error?: string };
}

/** How long a resolved gateway is reused before it is looked up again. */
export const DEFAULT_GATEWAY_CACHE_TTL_MS = 10 * 60_000;

/** Header carrying an `lc_` API key; user tokens travel as `Authorization: Bearer`. */
export const HEADER_API_KEY = "X-Api-Key";

/** Whether `token` is a Lowco API key rather than a user token. */
export function isApiKey(token: string): boolean {
  return token.trim().startsWith("lc_");
}

export interface LowcodbClientOptions {
  /**
   * User token or `lc_` API key. Required. A user token is sent as
   * `Authorization: Bearer <token>`, an API key as `X-Api-Key`, which is how the
   * gateway and the API expect each.
   */
  token: string;
  /** X-Org-Id header value. */
  orgId?: string;
  /**
   * Origin of the lowcodb manager, e.g. "http://lowcodb-service:8080" for in-cluster
   * callers. Defaults to "https://api.lowco.ai".
   */
  baseUrl?: string;
  /** Extra headers added to every request. */
  defaultHeaders?: Record<string, string>;
  /** Route prefix; defaults to "/v1/lowcodb". */
  apiBasePath?: string;
  /** Custom fetch implementation (defaults to global fetch). */
  fetch?: typeof fetch;
  /** Per-request timeout in milliseconds (default 30 000). 0 disables. */
  timeoutMs?: number;
  /**
   * Pinned gateways by schema: the context path (`/gateway/<hash>`, joined to
   * `baseUrl`) or a full origin + path. A pinned schema is never looked up — for API
   * keys that may call the gateway but not the management API, and for in-cluster
   * callers that know the gateway's Service.
   */
  gateways?: Record<string, string>;
  /** `public` (default): `https://api.lowco.ai/gateway/<hash>`; `internal`: the in-cluster Service. */
  gatewayOrigin?: GatewayOrigin;
  /** Overrides DEFAULT_GATEWAY_CACHE_TTL_MS. */
  gatewayCacheTtlMs?: number;
}

interface RequestInternalOptions {
  method: string;
  /** A path on `baseUrl`, or an absolute URL when `absolute` is set. */
  path: string;
  absolute?: boolean;
  query?: URLSearchParams | null;
  body?: unknown;
  enveloped?: boolean;
  raw?: boolean;
}

export class LowcodbClient {
  private readonly baseUrl: string;
  private readonly apiBasePath: string;
  private readonly fetchFn: typeof fetch;
  private readonly timeoutMs: number;
  private readonly headers: Record<string, string>;
  private readonly gateways: Record<string, string>;
  private readonly gatewayOrigin: GatewayOrigin;
  private readonly gatewayCacheTtlMs: number;
  private readonly gatewayCache = new Map<string, { base: string; expires: number }>();

  constructor(opts: LowcodbClientOptions) {
    if (!opts.token || !opts.token.trim()) {
      throw new Error("LowcodbClient: token is required");
    }
    this.baseUrl = (opts.baseUrl ?? BASE_URL).replace(/\/+$/g, "");
    this.apiBasePath = "/" + (opts.apiBasePath ?? DEFAULT_API_BASE_PATH).replace(/^\/+|\/+$/g, "");
    this.fetchFn = opts.fetch ?? fetch;
    this.timeoutMs = opts.timeoutMs ?? 30_000;

    this.headers = { ...(opts.defaultHeaders ?? {}) };
    if (isApiKey(opts.token)) this.headers[HEADER_API_KEY] = opts.token.trim();
    else this.headers.Authorization = `Bearer ${opts.token}`;
    if (opts.orgId) this.headers[HEADER_ORG_ID] = opts.orgId;
    this.gateways = { ...(opts.gateways ?? {}) };
    this.gatewayOrigin = opts.gatewayOrigin === "internal" ? "internal" : "public";
    this.gatewayCacheTtlMs = opts.gatewayCacheTtlMs ?? DEFAULT_GATEWAY_CACHE_TTL_MS;
  }

  // --- Gateway (where a base's data is served) -----------------------------
  //
  // Records, view rows, DB functions and transactions are served by the base's API
  // gateway; the manager's data routes are cluster-internal. The schema argument of the
  // data methods names the base, whose gateway is resolved (and cached) here.

  /** Where a base's data is served, by schema. */
  getGateway(schema: string): Promise<GatewayInfo> {
    return this.request({ method: "GET", path: this.api("bases", "gateway-by-schema", schema), enveloped: true });
  }

  /** Where a base's data is served, by base id. */
  getGatewayByBaseId(baseId: string): Promise<GatewayInfo> {
    return this.request({ method: "GET", path: this.api("bases", baseId, "gateway"), enveloped: true });
  }

  /**
   * A client bound to one gateway, for callers that hold its URL or context path rather
   * than the base's schema. Its methods mirror the record, view, function and
   * transaction methods without the schema argument.
   */
  gateway(pathOrUrl: string): GatewayClient {
    return new GatewayClient(this, this.absoluteGateway(pathOrUrl));
  }

  /** @internal absolute prefix (origin + context path) of a schema's gateway. */
  async gatewayBase(schema: string): Promise<{ base: string; pinned: boolean }> {
    const key = schema.trim();
    if (!key) throw new Error("lowcodb: schema is required");
    const pinned = this.gateways[key];
    if (pinned) return { base: this.absoluteGateway(pinned), pinned: true };
    const cached = this.gatewayCache.get(key);
    if (cached && cached.expires > Date.now()) return { base: cached.base, pinned: false };
    const info = await this.getGateway(key);
    const base = this.pickGatewayBase(info);
    if (!base) {
      throw new LowcodbError({ statusCode: 404, message: `lowcodb: base ${key} has no usable gateway yet`, body: "" });
    }
    this.gatewayCache.set(key, { base, expires: Date.now() + this.gatewayCacheTtlMs });
    return { base, pinned: false };
  }

  /** @internal */
  forgetGateway(schema: string): void {
    this.gatewayCache.delete(schema.trim());
  }

  private pickGatewayBase(info: GatewayInfo): string {
    if (this.gatewayOrigin === "internal" && info.internalUrl?.trim()) {
      return info.internalUrl.trim().replace(/\/+$/g, "");
    }
    if (info.url?.trim()) return info.url.trim().replace(/\/+$/g, "");
    if (info.contextPath?.trim()) return this.absoluteGateway(info.contextPath);
    return "";
  }

  private absoluteGateway(pathOrUrl: string): string {
    const p = pathOrUrl.trim().replace(/\/+$/g, "");
    if (/^https?:\/\//i.test(p)) return p;
    return `${this.baseUrl}/${p.replace(/^\/+/g, "")}`;
  }

  /**
   * @internal One data-plane call for `schema` through its gateway. A 404 from a gateway
   * that was looked up is retried once after a fresh lookup: the base's access hash may
   * have been regenerated since it was cached.
   */
  async dataRequest<T>(schema: string, opts: Omit<RequestInternalOptions, "path"> & { route: string }): Promise<T> {
    const { base, pinned } = await this.gatewayBase(schema);
    try {
      return await this.request<T>({ ...opts, path: base + opts.route, absolute: true });
    } catch (err) {
      if (pinned || !(err instanceof LowcodbError) || err.statusCode !== 404) throw err;
      this.forgetGateway(schema);
      const fresh = await this.gatewayBase(schema);
      if (fresh.base === base) throw err;
      return this.request<T>({ ...opts, path: fresh.base + opts.route, absolute: true });
    }
  }

  setOrgId(orgId: string | null): void {
    if (orgId) this.headers[HEADER_ORG_ID] = orgId;
    else delete this.headers[HEADER_ORG_ID];
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

  getTableIndex(tableId: string, id: string): Promise<TableIndex> {
    return this.request({
      method: "GET",
      path: this.api("tables", tableId, "index", id),
      enveloped: true,
    });
  }
  createTableIndex(tableId: string, index: TableIndex): Promise<TableIndex> {
    return this.request({
      method: "POST",
      path: this.api("tables", tableId, "index"),
      body: index,
      enveloped: true,
    });
  }
  updateTableIndex(tableId: string, id: string, index: TableIndexUpdateInput): Promise<TableIndex> {
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
    return this.dataRequest(schema, {
      method: "POST",
      route: tableRoute(tableName),
      body: record,
      enveloped: true,
    });
  }
  getRecord(schema: string, tableName: string, id: string): Promise<LowcodbRecord> {
    return this.dataRequest(schema, {
      method: "GET",
      route: tableRoute(tableName, id),
      enveloped: true,
    });
  }
  updateRecord(
    schema: string,
    tableName: string,
    id: string,
    record: LowcodbRecord,
  ): Promise<LowcodbRecord> {
    return this.dataRequest(schema, {
      method: "PUT",
      route: tableRoute(tableName, id),
      body: record,
      enveloped: true,
    });
  }
  deleteRecord(schema: string, tableName: string, id: string): Promise<DeleteCountResponse> {
    return this.dataRequest(schema, {
      method: "DELETE",
      route: tableRoute(tableName, id),
      enveloped: true,
    });
  }
  listRecords(
    schema: string,
    tableName: string,
    params?: ListParams,
  ): Promise<LowcodbRecord[]> {
    return this.dataRequest(schema, {
      method: "GET",
      route: tableRoute(tableName),
      query: this.listQuery(params),
      enveloped: true,
    });
  }
  countRecords(schema: string, tableName: string, params?: ListParams): Promise<CountResponse> {
    return this.dataRequest(schema, {
      method: "GET",
      route: tableRoute(tableName, "count"),
      query: this.listQuery(params),
      enveloped: true,
    });
  }
  async createBulkRecords(
    schema: string,
    tableName: string,
    records: LowcodbRecord[],
  ): Promise<void> {
    await this.dataRequest(schema, {
      method: "POST",
      route: tableRoute(tableName, "bulk"),
      body: records,
      enveloped: true,
    });
  }
  updateBulkRecords(
    schema: string,
    tableName: string,
    records: LowcodbRecord[],
  ): Promise<RecordsBulkResult> {
    return this.dataRequest(schema, {
      method: "PUT",
      route: tableRoute(tableName, "bulk"),
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
    await this.dataRequest(schema, {
      method: "DELETE",
      route: tableRoute(tableName, "bulk"),
      body,
      enveloped: true,
    });
  }

  // --- View data --------------------------------------------------------

  getViewRecord(schema: string, viewName: string, id: string): Promise<LowcodbRecord> {
    return this.dataRequest(schema, {
      method: "GET",
      route: viewRoute(viewName, id),
      enveloped: true,
    });
  }
  listViewRecords(
    schema: string,
    viewName: string,
    params?: ListParams,
  ): Promise<LowcodbRecord[]> {
    return this.dataRequest(schema, {
      method: "GET",
      route: viewRoute(viewName),
      query: this.listQuery(params),
      enveloped: true,
    });
  }
  countViewRecords(
    schema: string,
    viewName: string,
    params?: ListParams,
  ): Promise<CountResponse> {
    return this.dataRequest(schema, {
      method: "GET",
      route: viewRoute(viewName, "count"),
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

  // --- Transactions -------------------------------------------------------

  /**
   * Runs ordered create/update/delete record operations inside one database
   * transaction — all succeed or none apply. Internal bases only.
   */
  executeTransaction(schema: string, operations: TransactionOperation[]): Promise<TransactionResult> {
    return this.dataRequest(schema, {
      method: "POST",
      route: transactionsRoute(),
      body: { operations },
      enveloped: true,
    });
  }

  // --- Events -------------------------------------------------------------

  /** Publishes a data event for a base on the platform event bus. */
  publishEvent(schema: string, input: PublishEventInput): Promise<PublishEventResult> {
    return this.request({
      method: "POST",
      path: this.api("events", "publish"),
      body: { schema, ...input },
      enveloped: true,
    });
  }

  // --- DB Functions -------------------------------------------------------

  listFunctions(params?: ListParams): Promise<DBFunction[]> {
    return this.request({
      method: "GET",
      path: this.api("functions"),
      query: this.listQuery(params),
      enveloped: true,
    });
  }
  getFunction(id: string): Promise<DBFunction> {
    return this.request({ method: "GET", path: this.api("functions", id), enveloped: true });
  }
  createFunction(fn: DBFunctionUpsertInput): Promise<DBFunction> {
    return this.request({
      method: "POST",
      path: this.api("functions"),
      body: fn,
      enveloped: true,
    });
  }
  updateFunction(id: string, fn: DBFunctionUpsertInput): Promise<DBFunction> {
    return this.request({
      method: "PUT",
      path: this.api("functions", id),
      body: fn,
      enveloped: true,
    });
  }
  async deleteFunction(id: string): Promise<void> {
    await this.request({
      method: "DELETE",
      path: this.api("functions", id),
      enveloped: false,
    });
  }
  listFunctionVersions(id: string): Promise<DBFunctionVersion[]> {
    return this.request({
      method: "GET",
      path: this.api("functions", id, "versions"),
      enveloped: true,
    });
  }
  /**
   * Console/test execution: runs the function (active or not) with `body` surfaced as
   * ctx.request.body and returns the full result including logs and any function error.
   */
  executeFunction(id: string, body?: unknown): Promise<FunctionExecuteResult> {
    return this.request({
      method: "POST",
      path: this.api("functions", id, "execute"),
      body: body ?? {},
      enveloped: true,
    });
  }
  /**
   * Data-plane invocation of an active function by schema + key (the same route the
   * base's gateway proxies /v1/fn/{key} to). Resolves to the function's return value.
   */
  invokeFunction(
    schema: string,
    functionKey: string,
    body?: unknown,
    opts?: FunctionInvokeOptions,
  ): Promise<unknown> {
    return this.dataRequest(schema, {
      method: opts?.method ?? "POST",
      route: functionRoute(functionKey),
      body,
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
    const url = new URL(opts.absolute ? opts.path : this.baseUrl + opts.path);
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

/**
 * The manager's error envelope puts the *opaque platform code* in `error.message`
 * ("AAS-00105" and friends, from core/api/builder.go) and the **real** text in
 * `error.details`. Reading `message` alone is what made every error thrown by a DB
 * function reach its `ctx.functions.invoke` caller as a bare "AAS-00105" with the
 * cause discarded — guards could only be asserted as "it rejected".
 */
const OPAQUE_PLATFORM_CODE = /^AAS-\d+$/;

function buildHttpError(status: number, text: string): LowcodbError {
  let message = text.trim();
  let code: string | number | undefined;
  try {
    const parsed = JSON.parse(text) as { message?: string; error?: APIErrorPayload };
    const envelope = parsed.error;
    const envelopeMessage = envelope?.message?.trim();
    if (envelopeMessage) {
      message = envelopeMessage;
      code = envelope?.code;
      // Prefer the detail text whenever `message` is nothing but the platform code.
      // `code` is left alone (the manager sends the numeric HTTP status there) and the
      // platform code stays recoverable from `body`, so nothing is lost.
      const details = typeof envelope?.details === "string" ? envelope.details.trim() : "";
      if (details && OPAQUE_PLATFORM_CODE.test(envelopeMessage)) {
        message = details;
      }
    } else if (parsed.message) {
      message = parsed.message;
    }
  } catch {
    /* keep raw text */
  }
  if (status === 402) {
    const quota = parseQuotaExceeded(status, message, text);
    if (quota) return quota;
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

// --- Gateway routes --------------------------------------------------------

const seg = (p: string): string => encodeURIComponent(p.replace(/^\/+|\/+$/g, ""));
/** @internal */
export function tableRoute(table: string, ...parts: string[]): string {
  return "/" + ["v1", seg(table), ...parts.map(seg)].join("/");
}
/** @internal */
export function viewRoute(view: string, ...parts: string[]): string {
  return "/" + ["v1", "views", seg(view), ...parts.map(seg)].join("/");
}
/** @internal */
export function functionRoute(key: string): string {
  return "/" + ["v1", "fn", seg(key)].join("/");
}
/** @internal */
export function transactionsRoute(): string {
  return "/v1/transactions";
}

/**
 * A client bound to one base gateway (`client.gateway("/gateway/<hash>")`): the record,
 * view, function and transaction methods without the schema argument, for callers that
 * hold the gateway rather than the base.
 */
export class GatewayClient {
  constructor(
    private readonly client: LowcodbClient,
    /** Absolute prefix: origin + `/gateway/<hash>`. */
    readonly url: string,
  ) {}

  private req<T>(opts: Omit<RequestInternalOptions, "path"> & { route: string }): Promise<T> {
    // Direct call: no schema, nothing to resolve or retry.
    return (this.client as unknown as { request<T>(o: RequestInternalOptions): Promise<T> }).request<T>({
      ...opts,
      path: this.url + opts.route,
      absolute: true,
    });
  }

  createRecord(tableName: string, record: LowcodbRecord): Promise<LowcodbRecord> {
    return this.req({ method: "POST", route: tableRoute(tableName), body: record, enveloped: true });
  }
  getRecord(tableName: string, id: string): Promise<LowcodbRecord> {
    return this.req({ method: "GET", route: tableRoute(tableName, id), enveloped: true });
  }
  updateRecord(tableName: string, id: string, record: LowcodbRecord): Promise<LowcodbRecord> {
    return this.req({ method: "PUT", route: tableRoute(tableName, id), body: record, enveloped: true });
  }
  deleteRecord(tableName: string, id: string): Promise<DeleteCountResponse> {
    return this.req({ method: "DELETE", route: tableRoute(tableName, id), enveloped: true });
  }
  listRecords(tableName: string, params?: ListParams): Promise<LowcodbRecord[]> {
    return this.req({ method: "GET", route: tableRoute(tableName), query: listQueryOf(params), enveloped: true });
  }
  countRecords(tableName: string, params?: ListParams): Promise<CountResponse> {
    return this.req({ method: "GET", route: tableRoute(tableName, "count"), query: listQueryOf(params), enveloped: true });
  }
  async createBulkRecords(tableName: string, records: LowcodbRecord[]): Promise<void> {
    await this.req({ method: "POST", route: tableRoute(tableName, "bulk"), body: records, enveloped: true });
  }
  updateBulkRecords(tableName: string, records: LowcodbRecord[]): Promise<RecordsBulkResult> {
    return this.req({ method: "PUT", route: tableRoute(tableName, "bulk"), body: records, enveloped: true });
  }
  async deleteBulkRecords(tableName: string, body: unknown): Promise<void> {
    await this.req({ method: "DELETE", route: tableRoute(tableName, "bulk"), body, enveloped: true });
  }
  getViewRecord(viewName: string, id: string): Promise<LowcodbRecord> {
    return this.req({ method: "GET", route: viewRoute(viewName, id), enveloped: true });
  }
  listViewRecords(viewName: string, params?: ListParams): Promise<LowcodbRecord[]> {
    return this.req({ method: "GET", route: viewRoute(viewName), query: listQueryOf(params), enveloped: true });
  }
  countViewRecords(viewName: string, params?: ListParams): Promise<CountResponse> {
    return this.req({ method: "GET", route: viewRoute(viewName, "count"), query: listQueryOf(params), enveloped: true });
  }
  invokeFunction(functionKey: string, body?: unknown, opts?: FunctionInvokeOptions): Promise<unknown> {
    return this.req({ method: opts?.method ?? "POST", route: functionRoute(functionKey), body, enveloped: true });
  }
  executeTransaction(operations: TransactionOperation[]): Promise<TransactionResult> {
    return this.req({ method: "POST", route: transactionsRoute(), body: { operations }, enveloped: true });
  }
}

function listQueryOf(params?: ListParams): URLSearchParams | null {
  if (!params) return null;
  const q = new URLSearchParams();
  if (params.pageNo !== undefined) q.set("pageNo", String(params.pageNo));
  if (params.size !== undefined) q.set("size", String(params.size));
  if (params.filter !== undefined) q.set("filter", params.filter);
  if (params.sort !== undefined) q.set("sort", params.sort);
  return q;
}
