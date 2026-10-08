package agentx

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

// DefaultBaseURL is the fixed API host every request is sent to. All three
// agentx services (manager, kb, executor) live behind this host.
const DefaultBaseURL = "https://api.lowco.ai"

// Default API base paths registered by each agentx service.
const (
	DefaultManagerAPIBasePath  = "/v1/agentx/manager"
	DefaultKBAPIBasePath       = "/v1/agentx/kb"
	DefaultExecutorAPIBasePath = "/v1/agentx/executors"
)

// Option configures a Client at construction time.
type Option func(*Client)

// Client is the unified agentx client. It exposes three sub-clients –
// Manager, KB and Executor – that share HTTP transport and tenancy headers.
type Client struct {
	httpClient *http.Client
	headers    http.Header

	managerURL      *url.URL
	managerBasePath string

	kbURL      *url.URL
	kbBasePath string

	executorURL      *url.URL
	executorBasePath string

	// Manager exposes the agent-manager service routes.
	Manager *ManagerClient
	// KB exposes the agent-kb (knowledge-base) service routes.
	KB *KBClient
	// Executor exposes the agent-executor service routes.
	Executor *ExecutorClient
}

// NewClient returns a Client targeting DefaultBaseURL. token is required –
// it may hold a user token or an API key and is sent as
// "Authorization: Bearer <token>" on every request.
func NewClient(token string, opts ...Option) (*Client, error) {
	if strings.TrimSpace(token) == "" {
		return nil, fmt.Errorf("agentx: token is required")
	}

	u, err := url.Parse(DefaultBaseURL)
	if err != nil {
		return nil, fmt.Errorf("agentx: parse base URL: %w", err)
	}

	c := &Client{
		httpClient:       &http.Client{Timeout: 30 * time.Second},
		headers:          make(http.Header),
		managerURL:       u,
		kbURL:            u,
		executorURL:      u,
		managerBasePath:  DefaultManagerAPIBasePath,
		kbBasePath:       DefaultKBAPIBasePath,
		executorBasePath: DefaultExecutorAPIBasePath,
	}
	c.headers.Set("Authorization", "Bearer "+token)

	for _, opt := range opts {
		opt(c)
	}

	c.Manager = &ManagerClient{c: c}
	c.KB = &KBClient{c: c}
	c.Executor = &ExecutorClient{c: c}
	return c, nil
}

// WithHTTPClient overrides the default http.Client (30s timeout). Note that
// the executor's streaming call needs a long-lived connection – use a client
// without a timeout (or rely on context for cancellation) for streaming.
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

// WithManagerAPIBasePath overrides the default "/v1/agentx/manager" route prefix.
func WithManagerAPIBasePath(p string) Option {
	return func(c *Client) {
		if s := normalizePrefix(p); s != "" {
			c.managerBasePath = s
		}
	}
}

// WithKBAPIBasePath overrides the default "/v1/agentx/kb" route prefix.
func WithKBAPIBasePath(p string) Option {
	return func(c *Client) {
		if s := normalizePrefix(p); s != "" {
			c.kbBasePath = s
		}
	}
}

// WithExecutorAPIBasePath overrides the default "/v1/agentx/executors" route prefix.
func WithExecutorAPIBasePath(p string) Option {
	return func(c *Client) {
		if s := normalizePrefix(p); s != "" {
			c.executorBasePath = s
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

// SetHeader sets or removes (when value=="") an arbitrary default header.
func (c *Client) SetHeader(key, value string) {
	if strings.TrimSpace(value) == "" {
		c.headers.Del(key)
		return
	}
	c.headers.Set(key, value)
}

// --- shared transport ----------------------------------------------------

func normalizePrefix(p string) string {
	p = strings.TrimSpace(p)
	if p == "" {
		return ""
	}
	return "/" + strings.Trim(p, "/")
}

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

func joinPath(basePath string, parts ...string) string {
	segs := []string{strings.Trim(basePath, "/")}
	for _, part := range parts {
		segs = append(segs, strings.Trim(part, "/"))
	}
	return "/" + strings.Join(segs, "/")
}

func (c *Client) do(
	ctx context.Context,
	base *url.URL,
	method, endpoint string,
	query url.Values,
	body, out any,
	enveloped bool,
) error {
	respBody, status, err := c.doRaw(ctx, base, method, endpoint, query, body, "application/json")
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
		return fmt.Errorf("agentx: decode response: %w", err)
	}
	return nil
}

func (c *Client) doRaw(
	ctx context.Context,
	base *url.URL,
	method, endpoint string,
	query url.Values,
	body any,
	accept string,
) ([]byte, int, error) {
	resp, err := c.sendRequest(ctx, base, method, endpoint, query, body, accept)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, resp.StatusCode, fmt.Errorf("agentx: read response: %w", err)
	}
	if resp.StatusCode >= 400 {
		return nil, resp.StatusCode, parseRequestError(resp.StatusCode, respBody)
	}
	return respBody, resp.StatusCode, nil
}

func (c *Client) sendRequest(
	ctx context.Context,
	base *url.URL,
	method, endpoint string,
	query url.Values,
	body any,
	accept string,
) (*http.Response, error) {
	var requestBody io.Reader
	if body != nil {
		payload, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("agentx: marshal request: %w", err)
		}
		requestBody = bytes.NewReader(payload)
	}

	reqURL := *base
	rel, err := url.Parse(endpoint)
	if err != nil {
		return nil, fmt.Errorf("agentx: parse endpoint: %w", err)
	}
	reqURL = *reqURL.ResolveReference(rel)
	if len(query) > 0 {
		reqURL.RawQuery = query.Encode()
	}

	req, err := http.NewRequestWithContext(ctx, method, reqURL.String(), requestBody)
	if err != nil {
		return nil, fmt.Errorf("agentx: build request: %w", err)
	}
	if accept != "" {
		req.Header.Set("Accept", accept)
	}
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
		return nil, fmt.Errorf("agentx: perform request: %w", err)
	}
	return resp, nil
}

func decodeEnvelope(body []byte, out any) error {
	var env struct {
		Success bool            `json:"success"`
		Data    json.RawMessage `json:"data"`
		Message string          `json:"message"`
		Error   *APIError       `json:"error"`
	}
	if err := json.Unmarshal(body, &env); err != nil {
		return json.Unmarshal(body, out)
	}
	data := bytes.TrimSpace(env.Data)
	if len(data) == 0 || string(data) == "null" {
		return nil
	}
	if err := json.Unmarshal(data, out); err != nil {
		return fmt.Errorf("agentx: decode envelope data: %w", err)
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
