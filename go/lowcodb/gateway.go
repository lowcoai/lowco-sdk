package lowcodb

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// A base's data — records, views, DB functions, transactions — is served only by the
// base's API gateway (https://api.lowco.ai/gateway/<hash>/v1/...). The manager's own
// data routes are cluster-internal. The record methods keep their (schema, table)
// signatures; the client resolves the schema's gateway behind them.

// GatewayOrigin selects which address of a base's gateway data calls are sent to.
type GatewayOrigin string

const (
	// GatewayOriginPublic is the public address, https://api.lowco.ai/gateway/<hash>.
	GatewayOriginPublic GatewayOrigin = "public"
	// GatewayOriginInternal is the gateway's in-cluster Service, for callers that run
	// inside the platform and should not leave the cluster to reach a base.
	GatewayOriginInternal GatewayOrigin = "internal"
)

// DefaultGatewayCacheTTL is how long a resolved gateway is reused before it is looked
// up again (its access hash can be regenerated in the console).
const DefaultGatewayCacheTTL = 10 * time.Minute

// GatewayRouteTemplates names where each kind of object lives on a base gateway.
type GatewayRouteTemplates struct {
	Tables       string `json:"tables"`
	Views        string `json:"views"`
	Functions    string `json:"functions"`
	Transactions string `json:"transactions,omitempty"`
}

// GatewaySyncInfo is the gateway's route sync state.
type GatewaySyncInfo struct {
	Status     string `json:"status"`
	SyncedAt   string `json:"syncedAt,omitempty"`
	RouteCount int    `json:"routeCount,omitempty"`
	Error      string `json:"error,omitempty"`
}

// GatewayInfo is what GET /v1/lowcodb/bases/{id}/gateway (and
// /bases/gateway-by-schema/{schema}) answers: where a base's data is served.
type GatewayInfo struct {
	GatewayId   string                 `json:"gatewayId"`
	Hash        string                 `json:"hash,omitempty"`
	ContextPath string                 `json:"contextPath,omitempty"`
	URL         string                 `json:"url,omitempty"`
	InternalURL string                 `json:"internalUrl,omitempty"`
	GatewayType string                 `json:"gatewayType,omitempty"`
	Routes      *GatewayRouteTemplates `json:"routes,omitempty"`
	Sync        *GatewaySyncInfo       `json:"sync,omitempty"`
}

// WithGateway pins the gateway of a schema so it is never looked up: pathOrURL is
// either the context path ("/gateway/<hash>", joined to the client's base URL) or a
// full origin + path. Use it for API keys that may call the gateway but not the
// management API, and for in-cluster callers that know the gateway's Service.
func WithGateway(schema, pathOrURL string) Option {
	return func(c *Client) {
		schema, pathOrURL = strings.TrimSpace(schema), strings.TrimSpace(pathOrURL)
		if schema == "" || pathOrURL == "" {
			return
		}
		if c.gateways == nil {
			c.gateways = map[string]string{}
		}
		c.gateways[schema] = pathOrURL
	}
}

// WithGatewayOrigin chooses the public or in-cluster address of resolved gateways.
func WithGatewayOrigin(origin GatewayOrigin) Option {
	return func(c *Client) {
		if origin == GatewayOriginInternal {
			c.gatewayOrigin = GatewayOriginInternal
		} else {
			c.gatewayOrigin = GatewayOriginPublic
		}
	}
}

// WithGatewayCacheTTL overrides how long a resolved gateway is reused.
func WithGatewayCacheTTL(ttl time.Duration) Option {
	return func(c *Client) {
		if ttl > 0 {
			c.gatewayTTL = ttl
		}
	}
}

type cachedGateway struct {
	base    string
	expires time.Time
}

// GetGateway answers where a base's data is served, by schema.
func (c *Client) GetGateway(ctx context.Context, schema string) (*GatewayInfo, error) {
	var out GatewayInfo
	if err := c.do(ctx, http.MethodGet, c.apiPath("bases", "gateway-by-schema", schema), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

// GetGatewayByBaseID answers where a base's data is served, by base id.
func (c *Client) GetGatewayByBaseID(ctx context.Context, baseID string) (*GatewayInfo, error) {
	var out GatewayInfo
	if err := c.do(ctx, http.MethodGet, c.apiPath("bases", baseID, "gateway"), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

// gatewayBase is the absolute prefix (origin + context path) of schema's gateway.
// Pinned gateways win; otherwise the manager is asked and the answer cached.
func (c *Client) gatewayBase(ctx context.Context, schema string) (base string, pinned bool, err error) {
	schema = strings.TrimSpace(schema)
	if schema == "" {
		return "", false, errors.New("lowcodb: schema is required")
	}
	if p, ok := c.gateways[schema]; ok {
		return c.absoluteGateway(p), true, nil
	}
	c.gatewayMu.Lock()
	if entry, ok := c.gatewayCache[schema]; ok && time.Now().Before(entry.expires) {
		c.gatewayMu.Unlock()
		return entry.base, false, nil
	}
	c.gatewayMu.Unlock()

	info, err := c.GetGateway(ctx, schema)
	if err != nil {
		return "", false, err
	}
	base = c.pickGatewayBase(info)
	if base == "" {
		return "", false, &RequestError{StatusCode: http.StatusNotFound, Message: "lowcodb: base " + schema + " has no usable gateway yet"}
	}
	c.gatewayMu.Lock()
	if c.gatewayCache == nil {
		c.gatewayCache = map[string]cachedGateway{}
	}
	c.gatewayCache[schema] = cachedGateway{base: base, expires: time.Now().Add(c.gatewayTTLOrDefault())}
	c.gatewayMu.Unlock()
	return base, false, nil
}

func (c *Client) gatewayTTLOrDefault() time.Duration {
	if c.gatewayTTL > 0 {
		return c.gatewayTTL
	}
	return DefaultGatewayCacheTTL
}

func (c *Client) forgetGateway(schema string) {
	c.gatewayMu.Lock()
	delete(c.gatewayCache, schema)
	c.gatewayMu.Unlock()
}

// pickGatewayBase chooses the address to call from a discovery answer.
func (c *Client) pickGatewayBase(info *GatewayInfo) string {
	if info == nil {
		return ""
	}
	if c.gatewayOrigin == GatewayOriginInternal && strings.TrimSpace(info.InternalURL) != "" {
		return strings.TrimRight(strings.TrimSpace(info.InternalURL), "/")
	}
	if u := strings.TrimSpace(info.URL); u != "" {
		return strings.TrimRight(u, "/")
	}
	if p := strings.TrimSpace(info.ContextPath); p != "" {
		return c.absoluteGateway(p)
	}
	return ""
}

// absoluteGateway turns a context path into an absolute prefix on the client's base
// URL; a full URL is used as given.
func (c *Client) absoluteGateway(pathOrURL string) string {
	pathOrURL = strings.TrimRight(strings.TrimSpace(pathOrURL), "/")
	if strings.HasPrefix(pathOrURL, "http://") || strings.HasPrefix(pathOrURL, "https://") {
		return pathOrURL
	}
	return strings.TrimRight(c.baseURL.String(), "/") + "/" + strings.TrimLeft(pathOrURL, "/")
}

// Routes the gateway serves under its context path.
func tableRoute(table string, parts ...string) string {
	return joinRoute(append([]string{"v1", table}, parts...)...)
}
func viewRoute(view string, parts ...string) string {
	return joinRoute(append([]string{"v1", "views", view}, parts...)...)
}
func functionRoute(key string) string { return joinRoute("v1", "fn", key) }
func transactionsRoute() string       { return "/v1/transactions" }

func joinRoute(parts ...string) string {
	segs := make([]string, 0, len(parts))
	for _, p := range parts {
		segs = append(segs, url.PathEscape(strings.Trim(p, "/")))
	}
	return "/" + strings.Join(segs, "/")
}

// dataDo sends one data-plane call for schema through its gateway. A 404 from a
// gateway that was looked up is retried once after a fresh lookup: the base's access
// hash may have been regenerated since it was cached.
func (c *Client) dataDo(ctx context.Context, schema, method, route string, query url.Values, body, out any) error {
	base, pinned, err := c.gatewayBase(ctx, schema)
	if err != nil {
		return err
	}
	err = c.do(ctx, method, base+route, query, body, out, true)
	var reqErr *RequestError
	if err == nil || pinned || !errors.As(err, &reqErr) || reqErr.StatusCode != http.StatusNotFound {
		return err
	}
	c.forgetGateway(schema)
	fresh, _, rerr := c.gatewayBase(ctx, schema)
	if rerr != nil || fresh == base {
		return err
	}
	return c.do(ctx, method, fresh+route, query, body, out, true)
}

// InvokeFunction calls an active DB function of a base by key through its gateway;
// method defaults to POST. The function's return value is decoded into out when out
// is non-nil.
func (c *Client) InvokeFunction(ctx context.Context, schema, functionKey string, body any, out any, method ...string) error {
	m := http.MethodPost
	if len(method) > 0 && strings.TrimSpace(method[0]) != "" {
		m = strings.ToUpper(strings.TrimSpace(method[0]))
	}
	return c.dataDo(ctx, schema, m, functionRoute(functionKey), nil, body, out)
}

// ExecuteTransaction applies ordered record writes of a base in one database
// transaction — all succeed or none apply. Internal bases only.
func (c *Client) ExecuteTransaction(ctx context.Context, schema string, operations []TransactionOperation) (*TransactionResult, error) {
	var out TransactionResult
	if err := c.dataDo(ctx, schema, http.MethodPost, transactionsRoute(), nil, map[string]any{"operations": operations}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// GatewayClient addresses one base's gateway directly, for callers that hold the
// gateway's URL or context path rather than the base's schema (an API key scoped to
// the gateway, a mobile app, a partner). Its methods mirror the Client's record, view,
// function and transaction methods without the schema argument.
type GatewayClient struct {
	c    *Client
	base string
}

// Gateway returns a client bound to the gateway at pathOrURL ("/gateway/<hash>" on the
// client's base URL, or a full origin + path).
func (c *Client) Gateway(pathOrURL string) *GatewayClient {
	return &GatewayClient{c: c, base: c.absoluteGateway(pathOrURL)}
}

// URL is the gateway's absolute prefix.
func (g *GatewayClient) URL() string { return g.base }

func (g *GatewayClient) do(ctx context.Context, method, route string, query url.Values, body, out any) error {
	return g.c.do(ctx, method, g.base+route, query, body, out, true)
}

func (g *GatewayClient) CreateRecord(ctx context.Context, tableName string, record Record) (*Record, error) {
	var out Record
	if err := g.do(ctx, http.MethodPost, tableRoute(tableName), nil, record, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (g *GatewayClient) GetRecord(ctx context.Context, tableName, id string) (*Record, error) {
	var out Record
	if err := g.do(ctx, http.MethodGet, tableRoute(tableName, id), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (g *GatewayClient) UpdateRecord(ctx context.Context, tableName, id string, record Record) (*Record, error) {
	var out Record
	if err := g.do(ctx, http.MethodPut, tableRoute(tableName, id), nil, record, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (g *GatewayClient) DeleteRecord(ctx context.Context, tableName, id string) (*DeleteCountResponse, error) {
	var out DeleteCountResponse
	if err := g.do(ctx, http.MethodDelete, tableRoute(tableName, id), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (g *GatewayClient) ListRecords(ctx context.Context, tableName string, params *ListParams) ([]Record, error) {
	var out []Record
	if err := g.do(ctx, http.MethodGet, tableRoute(tableName), params.values(), nil, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func (g *GatewayClient) CountRecords(ctx context.Context, tableName string, params *ListParams) (*CountResponse, error) {
	var out CountResponse
	if err := g.do(ctx, http.MethodGet, tableRoute(tableName, "count"), params.values(), nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (g *GatewayClient) CreateBulkRecords(ctx context.Context, tableName string, records []Record) error {
	return g.do(ctx, http.MethodPost, tableRoute(tableName, "bulk"), nil, records, nil)
}

func (g *GatewayClient) UpdateBulkRecords(ctx context.Context, tableName string, records []Record) (*RecordsBulkResult, error) {
	var out RecordsBulkResult
	if err := g.do(ctx, http.MethodPut, tableRoute(tableName, "bulk"), nil, records, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (g *GatewayClient) DeleteBulkRecords(ctx context.Context, tableName string, body any) error {
	return g.do(ctx, http.MethodDelete, tableRoute(tableName, "bulk"), nil, body, nil)
}

func (g *GatewayClient) GetViewRecord(ctx context.Context, viewName, id string) (*Record, error) {
	var out Record
	if err := g.do(ctx, http.MethodGet, viewRoute(viewName, id), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (g *GatewayClient) ListViewRecords(ctx context.Context, viewName string, params *ListParams) ([]Record, error) {
	var out []Record
	if err := g.do(ctx, http.MethodGet, viewRoute(viewName), params.values(), nil, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func (g *GatewayClient) CountViewRecords(ctx context.Context, viewName string, params *ListParams) (*CountResponse, error) {
	var out CountResponse
	if err := g.do(ctx, http.MethodGet, viewRoute(viewName, "count"), params.values(), nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// InvokeFunction calls an active DB function by key; method defaults to POST. The
// function's return value is decoded into out when out is non-nil.
func (g *GatewayClient) InvokeFunction(ctx context.Context, functionKey string, body any, out any, method ...string) error {
	m := http.MethodPost
	if len(method) > 0 && strings.TrimSpace(method[0]) != "" {
		m = strings.ToUpper(strings.TrimSpace(method[0]))
	}
	return g.do(ctx, m, functionRoute(functionKey), nil, body, out)
}

// ExecuteTransaction applies ordered record writes in one database transaction —
// all succeed or none apply. Internal bases only.
func (g *GatewayClient) ExecuteTransaction(ctx context.Context, operations []TransactionOperation) (*TransactionResult, error) {
	var out TransactionResult
	if err := g.do(ctx, http.MethodPost, transactionsRoute(), nil, map[string]any{"operations": operations}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// gatewayState is the per-client resolver state embedded in Client.
type gatewayState struct {
	gateways      map[string]string
	gatewayOrigin GatewayOrigin
	gatewayTTL    time.Duration
	gatewayMu     sync.Mutex
	gatewayCache  map[string]cachedGateway
}
