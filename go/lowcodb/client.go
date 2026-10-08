package lowcodb

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// DefaultBaseURL is the fixed API host every request is sent to.
const DefaultBaseURL = "https://api.lowco.ai"

const defaultAPIBasePath = "/v1/lowcodb"

// Option configures a Client at construction time.
type Option func(*Client)

// Client is a thread-safe HTTP client for the lowcodb manager.
type Client struct {
	baseURL     *url.URL
	apiBasePath string
	httpClient  *http.Client
	headers     http.Header
}

// NewClient returns a Client targeting DefaultBaseURL. token is required –
// it may hold a user token or an API key and is sent as
// "Authorization: Bearer <token>" on every request. Use the With* options to
// configure tenancy headers, a custom HTTP client, or a non-default API base
// path.
func NewClient(token string, opts ...Option) (*Client, error) {
	if strings.TrimSpace(token) == "" {
		return nil, fmt.Errorf("token is required")
	}
	u, err := url.Parse(DefaultBaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse base URL: %w", err)
	}
	c := &Client{
		baseURL:     u,
		apiBasePath: defaultAPIBasePath,
		httpClient:  &http.Client{Timeout: 30 * time.Second},
		headers:     make(http.Header),
	}
	c.headers.Set("Authorization", "Bearer "+token)
	for _, opt := range opts {
		opt(c)
	}
	return c, nil
}

// WithHTTPClient overrides the default http.Client (30s timeout).
func WithHTTPClient(httpClient *http.Client) Option {
	return func(c *Client) {
		if httpClient != nil {
			c.httpClient = httpClient
		}
	}
}

// WithOrgID sets the X-Org-Id header for every request.
func WithOrgID(orgID string) Option {
	return func(c *Client) {
		if strings.TrimSpace(orgID) != "" {
			c.headers.Set(HeaderOrgID, orgID)
		}
	}
}

// WithDefaultHeader adds an arbitrary header to every request.
func WithDefaultHeader(key, value string) Option {
	return func(c *Client) {
		if strings.TrimSpace(key) != "" {
			c.headers.Set(key, value)
		}
	}
}

// WithAPIBasePath overrides the default "/v1/lowcodb" route prefix.
func WithAPIBasePath(apiBasePath string) Option {
	return func(c *Client) {
		if strings.TrimSpace(apiBasePath) != "" {
			c.apiBasePath = "/" + strings.Trim(strings.TrimSpace(apiBasePath), "/")
		}
	}
}

// SetOrgID updates the X-Org-Id header at runtime. Pass "" to clear it.
func (c *Client) SetOrgID(orgID string) {
	if strings.TrimSpace(orgID) == "" {
		c.headers.Del(HeaderOrgID)
		return
	}
	c.headers.Set(HeaderOrgID, orgID)
}

// Health pings the manager's /health endpoint.
func (c *Client) Health(ctx context.Context) error {
	return c.do(ctx, http.MethodGet, "/health", nil, nil, nil, false)
}

// --- Bases ---------------------------------------------------------------

func (c *Client) GetBase(ctx context.Context, id string) (*Base, error) {
	var out Base
	if err := c.do(ctx, http.MethodGet, c.apiPath("bases", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) CreateBase(ctx context.Context, base Base) (*Base, error) {
	var out Base
	if err := c.do(ctx, http.MethodPost, c.apiPath("bases"), nil, base, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) UpdateBase(ctx context.Context, id string, base Base) (*Base, error) {
	var out Base
	if err := c.do(ctx, http.MethodPut, c.apiPath("bases", id), nil, base, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) DeleteBase(ctx context.Context, id string) error {
	return c.do(ctx, http.MethodDelete, c.apiPath("bases", id), nil, nil, nil, true)
}

func (c *Client) ListBases(ctx context.Context, params *ListParams) ([]Base, error) {
	var out []Base
	if err := c.do(ctx, http.MethodGet, c.apiPath("bases"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

// ExportBaseCollection downloads a Postman collection for a base as raw bytes.
func (c *Client) ExportBaseCollection(ctx context.Context, id string) ([]byte, error) {
	body, _, err := c.doRaw(ctx, http.MethodGet, c.apiPath("bases", id, "export"), nil, nil)
	return body, err
}

// SyncBaseTables reconciles external-DB metadata for the base.
func (c *Client) SyncBaseTables(ctx context.Context, id string) (*SyncTablesResult, error) {
	var out SyncTablesResult
	if err := c.do(ctx, http.MethodPost, c.apiPath("bases", id, "sync-tables"), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

// --- Tables --------------------------------------------------------------

func (c *Client) GetTable(ctx context.Context, id string) (*TableWithColumns, error) {
	var out TableWithColumns
	if err := c.do(ctx, http.MethodGet, c.apiPath("tables", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) CreateTable(ctx context.Context, table Table) (*TableWithColumns, error) {
	var out TableWithColumns
	if err := c.do(ctx, http.MethodPost, c.apiPath("tables"), nil, table, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) UpdateTable(ctx context.Context, id string, table Table) (*TableWithColumns, error) {
	var out TableWithColumns
	if err := c.do(ctx, http.MethodPut, c.apiPath("tables", id), nil, table, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) DeleteTable(ctx context.Context, id string) error {
	return c.do(ctx, http.MethodDelete, c.apiPath("tables", id), nil, nil, nil, true)
}

func (c *Client) ListTables(ctx context.Context, params *ListParams) ([]Table, error) {
	var out []Table
	if err := c.do(ctx, http.MethodGet, c.apiPath("tables"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

// --- Columns -------------------------------------------------------------

func (c *Client) GetColumn(ctx context.Context, tableID, id string) (*Column, error) {
	var out Column
	if err := c.do(ctx, http.MethodGet, c.apiPath("tables", tableID, "columns", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) CreateColumn(ctx context.Context, tableID string, column Column) (*Column, error) {
	var out Column
	if err := c.do(ctx, http.MethodPost, c.apiPath("tables", tableID, "columns"), nil, column, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) BulkCreateColumns(ctx context.Context, tableID string, columns []Column) (*ColumnsBulkResult, error) {
	var out ColumnsBulkResult
	if err := c.do(ctx, http.MethodPost, c.apiPath("tables", tableID, "columns", "bulk"), nil, columns, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) UpdateColumn(ctx context.Context, tableID, id string, column Column) (*Column, error) {
	var out Column
	if err := c.do(ctx, http.MethodPut, c.apiPath("tables", tableID, "columns", id), nil, column, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) BulkUpdateColumns(ctx context.Context, tableID string, columns []Column) (map[string]any, error) {
	var out map[string]any
	if err := c.do(ctx, http.MethodPut, c.apiPath("tables", tableID, "columns", "bulk"), nil, columns, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

func (c *Client) DeleteColumn(ctx context.Context, tableID, id string) error {
	return c.do(ctx, http.MethodDelete, c.apiPath("tables", tableID, "columns", id), nil, nil, nil, true)
}

func (c *Client) ListColumns(ctx context.Context, tableID string, params *ListParams) ([]Column, error) {
	var out []Column
	if err := c.do(ctx, http.MethodGet, c.apiPath("tables", tableID, "columns"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

// ValidateField runs the manager's field validator without persisting anything.
func (c *Client) ValidateField(ctx context.Context, field Field) (*ValidationResponse, error) {
	var out ValidationResponse
	if err := c.do(ctx, http.MethodPost, c.apiPath("validate"), nil, field, &out, false); err != nil {
		return nil, err
	}
	return &out, nil
}

// --- Table indexes -------------------------------------------------------

func (c *Client) GetTableIndex(ctx context.Context, tableID, id string) (*TableIndex, error) {
	var out TableIndex
	if err := c.do(ctx, http.MethodGet, c.apiPath("tables", tableID, "index", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) CreateTableIndex(ctx context.Context, tableID string, index TableIndex) (*TableIndex, error) {
	var out TableIndex
	if err := c.do(ctx, http.MethodPost, c.apiPath("tables", tableID, "index"), nil, index, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) UpdateTableIndex(ctx context.Context, tableID, id string, index TableIndexUpdateInput) (*TableIndex, error) {
	var out TableIndex
	if err := c.do(ctx, http.MethodPut, c.apiPath("tables", tableID, "index", id), nil, index, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) ListTableIndexes(ctx context.Context, tableID string, params *ListParams) ([]TableIndex, error) {
	var out []TableIndex
	if err := c.do(ctx, http.MethodGet, c.apiPath("tables", tableID, "indexes"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

func (c *Client) DeleteTableIndex(ctx context.Context, tableID, id string) error {
	return c.do(ctx, http.MethodDelete, c.apiPath("tables", tableID, "index", id), nil, nil, nil, true)
}

// --- Records -------------------------------------------------------------

func (c *Client) CreateRecord(ctx context.Context, schema, tableName string, record Record) (*Record, error) {
	var out Record
	if err := c.do(ctx, http.MethodPost, c.dataPath(schema, "tables", tableName, "records"), nil, record, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) GetRecord(ctx context.Context, schema, tableName, id string) (*Record, error) {
	var out Record
	if err := c.do(ctx, http.MethodGet, c.dataPath(schema, "tables", tableName, "records", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) UpdateRecord(ctx context.Context, schema, tableName, id string, record Record) (*Record, error) {
	var out Record
	if err := c.do(ctx, http.MethodPut, c.dataPath(schema, "tables", tableName, "records", id), nil, record, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) DeleteRecord(ctx context.Context, schema, tableName, id string) (*DeleteCountResponse, error) {
	var out DeleteCountResponse
	if err := c.do(ctx, http.MethodDelete, c.dataPath(schema, "tables", tableName, "records", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) ListRecords(ctx context.Context, schema, tableName string, params *ListParams) ([]Record, error) {
	var out []Record
	if err := c.do(ctx, http.MethodGet, c.dataPath(schema, "tables", tableName, "records"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

func (c *Client) CountRecords(ctx context.Context, schema, tableName string, params *ListParams) (*CountResponse, error) {
	var out CountResponse
	if err := c.do(ctx, http.MethodGet, c.dataPath(schema, "tables", tableName, "records", "count"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) CreateBulkRecords(ctx context.Context, schema, tableName string, records []Record) error {
	return c.do(ctx, http.MethodPost, c.dataPath(schema, "tables", tableName, "records", "bulk"), nil, records, nil, true)
}

func (c *Client) UpdateBulkRecords(ctx context.Context, schema, tableName string, records []Record) (*RecordsBulkResult, error) {
	var out RecordsBulkResult
	if err := c.do(ctx, http.MethodPut, c.dataPath(schema, "tables", tableName, "records", "bulk"), nil, records, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

// DeleteBulkRecords accepts any JSON-marshalable body (typically an array of
// ids or filter clauses) – the manager treats it as the deletion criterion.
func (c *Client) DeleteBulkRecords(ctx context.Context, schema, tableName string, body any) error {
	return c.do(ctx, http.MethodDelete, c.dataPath(schema, "tables", tableName, "records", "bulk"), nil, body, nil, true)
}

// --- View data -----------------------------------------------------------

func (c *Client) GetViewRecord(ctx context.Context, schema, viewName, id string) (*Record, error) {
	var out Record
	if err := c.do(ctx, http.MethodGet, c.dataPath(schema, "views", viewName, "records", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) ListViewRecords(ctx context.Context, schema, viewName string, params *ListParams) ([]Record, error) {
	var out []Record
	if err := c.do(ctx, http.MethodGet, c.dataPath(schema, "views", viewName, "records"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

func (c *Client) CountViewRecords(ctx context.Context, schema, viewName string, params *ListParams) (*CountResponse, error) {
	var out CountResponse
	if err := c.do(ctx, http.MethodGet, c.dataPath(schema, "views", viewName, "records", "count"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

// --- Overview / validate / metrics --------------------------------------

func (c *Client) GetOverviewCounts(ctx context.Context) (*OverviewCounts, error) {
	var out OverviewCounts
	if err := c.do(ctx, http.MethodGet, c.apiPath("overview", "counts"), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

// MetricsDashboardParams are the supported query knobs for GetMetricsDashboard.
// Set Range (a Go duration, e.g. "5m") OR explicit From/To (RFC3339).
type MetricsDashboardParams struct {
	Range  string
	From   *time.Time
	To     *time.Time
	BaseID string
}

func (c *Client) GetMetricsDashboard(ctx context.Context, params *MetricsDashboardParams) (DashboardResponse, error) {
	q := url.Values{}
	if params != nil {
		if params.Range != "" {
			q.Set("range", params.Range)
		}
		if params.From != nil {
			q.Set("from", params.From.UTC().Format(time.RFC3339))
		}
		if params.To != nil {
			q.Set("to", params.To.UTC().Format(time.RFC3339))
		}
		if params.BaseID != "" {
			q.Set("baseId", params.BaseID)
		}
	}
	var out DashboardResponse
	if err := c.do(ctx, http.MethodGet, c.apiPath("metrics", "dashboard"), q, nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

// DashboardOverviewParams matches /v1/lowcodb/dashboard/overview.
type DashboardOverviewParams struct {
	BaseID    string
	TableID   string
	StartDate *time.Time
	EndDate   *time.Time
}

func (c *Client) GetDashboardOverview(ctx context.Context, params *DashboardOverviewParams) (DashboardResponse, error) {
	q := url.Values{}
	if params != nil {
		if params.BaseID != "" {
			q.Set("baseId", params.BaseID)
		}
		if params.TableID != "" {
			q.Set("tableId", params.TableID)
		}
		if params.StartDate != nil {
			q.Set("startDate", params.StartDate.UTC().Format(time.RFC3339))
		}
		if params.EndDate != nil {
			q.Set("endDate", params.EndDate.UTC().Format(time.RFC3339))
		}
	}
	var out DashboardResponse
	if err := c.do(ctx, http.MethodGet, c.apiPath("dashboard", "overview"), q, nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

// --- Triggers ------------------------------------------------------------

func (c *Client) GetTrigger(ctx context.Context, id string) (*TableTrigger, error) {
	var out TableTrigger
	if err := c.do(ctx, http.MethodGet, c.apiPath("triggers", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) CreateTrigger(ctx context.Context, trigger TableTrigger) (*TableTrigger, error) {
	var out TableTrigger
	if err := c.do(ctx, http.MethodPost, c.apiPath("triggers"), nil, trigger, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) UpdateTrigger(ctx context.Context, id string, trigger TableTrigger) (*TableTrigger, error) {
	var out TableTrigger
	if err := c.do(ctx, http.MethodPut, c.apiPath("triggers", id), nil, trigger, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) DeleteTrigger(ctx context.Context, id string) error {
	return c.do(ctx, http.MethodDelete, c.apiPath("triggers", id), nil, nil, nil, false)
}

func (c *Client) ListTriggers(ctx context.Context, params *ListParams) ([]TableTrigger, error) {
	var out []TableTrigger
	if err := c.do(ctx, http.MethodGet, c.apiPath("triggers"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

// --- Webhooks ------------------------------------------------------------

func (c *Client) GetWebhook(ctx context.Context, id string) (*TableWebhook, error) {
	var out TableWebhook
	if err := c.do(ctx, http.MethodGet, c.apiPath("webhooks", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) CreateWebhook(ctx context.Context, webhook TableWebhook) (*TableWebhook, error) {
	var out TableWebhook
	if err := c.do(ctx, http.MethodPost, c.apiPath("webhooks"), nil, webhook, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) UpdateWebhook(ctx context.Context, id string, webhook TableWebhook) (*TableWebhook, error) {
	var out TableWebhook
	if err := c.do(ctx, http.MethodPut, c.apiPath("webhooks", id), nil, webhook, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) DeleteWebhook(ctx context.Context, id string) error {
	return c.do(ctx, http.MethodDelete, c.apiPath("webhooks", id), nil, nil, nil, false)
}

func (c *Client) ListWebhooks(ctx context.Context, params *ListParams) ([]TableWebhook, error) {
	var out []TableWebhook
	if err := c.do(ctx, http.MethodGet, c.apiPath("webhooks"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

// --- Query ---------------------------------------------------------------

func (c *Client) ExecuteQuery(ctx context.Context, req RunQueryRequest) (*RowsResponse, error) {
	var out RowsResponse
	if err := c.do(ctx, http.MethodPost, c.apiPath("query", "execute"), nil, req, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) GetQuerySuggestions(ctx context.Context, query, baseID string) (*SuggestionsResponse, error) {
	q := url.Values{}
	q.Set("query", query)
	if baseID != "" {
		q.Set("baseId", baseID)
	}
	var out SuggestionsResponse
	if err := c.do(ctx, http.MethodGet, c.apiPath("query", "suggestions"), q, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

// --- Views (metadata) ----------------------------------------------------

func (c *Client) ListViews(ctx context.Context, params *ListParams) ([]TableView, error) {
	var out []TableView
	if err := c.do(ctx, http.MethodGet, c.apiPath("views"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

func (c *Client) CreateView(ctx context.Context, view TableView) (*TableView, error) {
	var out TableView
	if err := c.do(ctx, http.MethodPost, c.apiPath("views"), nil, view, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) GetView(ctx context.Context, id string) (*TableView, error) {
	var out TableView
	if err := c.do(ctx, http.MethodGet, c.apiPath("views", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) UpdateView(ctx context.Context, id string, view TableView) (*TableView, error) {
	var out TableView
	if err := c.do(ctx, http.MethodPut, c.apiPath("views", id), nil, view, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) DeleteView(ctx context.Context, id string) error {
	return c.do(ctx, http.MethodDelete, c.apiPath("views", id), nil, nil, nil, true)
}

func (c *Client) RefreshView(ctx context.Context, id string, req ViewRefreshRequest) (*ViewRefreshResponse, error) {
	var out ViewRefreshResponse
	if err := c.do(ctx, http.MethodPost, c.apiPath("views", id, "refresh"), nil, req, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

// --- internals -----------------------------------------------------------

func (p *ListParams) values() url.Values {
	if p == nil {
		return nil
	}
	v := url.Values{}
	if p.PageNo > 0 {
		v.Set("pageNo", strconv.Itoa(p.PageNo))
	}
	if p.Size != 0 {
		v.Set("size", strconv.Itoa(p.Size))
	}
	if p.Filter != "" {
		v.Set("filter", p.Filter)
	}
	if p.Sort != "" {
		v.Set("sort", p.Sort)
	}
	return v
}

func (c *Client) apiPath(parts ...string) string {
	pathParts := []string{strings.Trim(c.apiBasePath, "/")}
	for _, part := range parts {
		pathParts = append(pathParts, strings.Trim(part, "/"))
	}
	return "/" + strings.Join(pathParts, "/")
}

func (c *Client) dataPath(schema, objectType, objectName string, parts ...string) string {
	pathParts := []string{
		strings.Trim(c.apiBasePath, "/"),
		"data",
		strings.Trim(schema, "/"),
		objectType,
		strings.Trim(objectName, "/"),
	}
	for _, part := range parts {
		pathParts = append(pathParts, strings.Trim(part, "/"))
	}
	return "/" + strings.Join(pathParts, "/")
}

func (c *Client) do(ctx context.Context, method, endpoint string, query url.Values, body, out any, enveloped bool) error {
	respBody, status, err := c.doRaw(ctx, method, endpoint, query, body)
	if err != nil {
		return err
	}
	if status == http.StatusNoContent || len(bytes.TrimSpace(respBody)) == 0 || out == nil {
		return nil
	}
	if enveloped {
		return decodeEnvelope(respBody, out)
	}
	if err := json.Unmarshal(respBody, out); err != nil {
		return fmt.Errorf("decode response: %w", err)
	}
	return nil
}

func (c *Client) doRaw(ctx context.Context, method, endpoint string, query url.Values, body any) ([]byte, int, error) {
	var requestBody io.Reader
	if body != nil {
		payload, err := json.Marshal(body)
		if err != nil {
			return nil, 0, fmt.Errorf("marshal request: %w", err)
		}
		requestBody = bytes.NewReader(payload)
	}

	reqURL := *c.baseURL
	rel, err := url.Parse(endpoint)
	if err != nil {
		return nil, 0, fmt.Errorf("parse endpoint: %w", err)
	}
	reqURL = *reqURL.ResolveReference(rel)
	if len(query) > 0 {
		reqURL.RawQuery = query.Encode()
	}

	req, err := http.NewRequestWithContext(ctx, method, reqURL.String(), requestBody)
	if err != nil {
		return nil, 0, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	for k, values := range c.headers {
		for _, v := range values {
			req.Header.Add(k, v)
		}
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("perform request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, resp.StatusCode, fmt.Errorf("read response: %w", err)
	}
	if resp.StatusCode >= 400 {
		return nil, resp.StatusCode, parseRequestError(resp.StatusCode, respBody)
	}
	return respBody, resp.StatusCode, nil
}

func decodeEnvelope(body []byte, out any) error {
	var env struct {
		Success bool            `json:"success"`
		Data    json.RawMessage `json:"data"`
		Message string          `json:"message"`
		Error   *APIError       `json:"error"`
	}
	if err := json.Unmarshal(body, &env); err != nil {
		// Some endpoints (e.g. validate) return un-enveloped JSON; try a direct decode.
		return json.Unmarshal(body, out)
	}
	data := bytes.TrimSpace(env.Data)
	if len(data) == 0 || string(data) == "null" {
		return nil
	}
	if err := json.Unmarshal(data, out); err != nil {
		return fmt.Errorf("decode envelope data: %w", err)
	}
	return nil
}

func parseRequestError(status int, body []byte) error {
	var env struct {
		Message string    `json:"message"`
		Error   *APIError `json:"error"`
	}
	message := strings.TrimSpace(string(body))
	code := ""
	if err := json.Unmarshal(body, &env); err == nil {
		switch {
		case env.Error != nil && strings.TrimSpace(env.Error.Message) != "":
			message = env.Error.Message
			code = env.Error.Code
		case env.Message != "":
			message = env.Message
		}
	}
	return &RequestError{
		StatusCode: status,
		Message:    message,
		Code:       code,
		Body:       string(body),
	}
}
