package docs

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type httpClient struct {
	baseURL      string
	token        string
	orgID        string
	extraHeaders map[string]string
	client       *http.Client
	// noRedirect is a shallow copy of client that returns 3xx responses
	// instead of following them, so the caller's client is never mutated.
	noRedirect *http.Client
}

func newHTTPClient(config Config) (*httpClient, error) {
	if strings.TrimSpace(config.Token) == "" {
		return nil, ErrMissingToken
	}
	if strings.TrimSpace(config.OrgID) == "" {
		return nil, ErrMissingOrgID
	}

	timeout := 30 * time.Second
	if config.TimeoutMS > 0 {
		timeout = time.Duration(config.TimeoutMS) * time.Millisecond
	}

	client := config.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: timeout}
	}
	noRedirect := *client
	noRedirect.CheckRedirect = func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}

	return &httpClient{
		baseURL:      DefaultBaseURL,
		token:        config.Token,
		orgID:        config.OrgID,
		extraHeaders: cloneHeaders(config.Headers),
		client:       client,
		noRedirect:   &noRedirect,
	}, nil
}

// request describes one HTTP call. path is already escaped.
type request struct {
	method      string
	path        string
	query       query
	body        io.Reader
	contentType string
	accept      string
	noRedirect  bool
}

// send performs r and returns the response with its fully read body.
func (c *httpClient) send(ctx context.Context, r request) (*http.Response, []byte, error) {
	reqURL := c.baseURL + r.path
	if encoded := url.Values(r.query).Encode(); encoded != "" {
		reqURL += "?" + encoded
	}

	req, err := http.NewRequestWithContext(ctx, r.method, reqURL, r.body)
	if err != nil {
		return nil, nil, err
	}

	for key, value := range c.extraHeaders {
		req.Header.Set(key, value)
	}
	accept := r.accept
	if accept == "" {
		accept = "application/json"
	}
	req.Header.Set("Accept", accept)
	if r.contentType != "" {
		req.Header.Set("Content-Type", r.contentType)
	}
	if req.Header.Get("Authorization") == "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	if req.Header.Get(HeaderOrgID) == "" {
		req.Header.Set(HeaderOrgID, c.orgID)
	}

	client := c.client
	if r.noRedirect {
		client = c.noRedirect
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, nil, transportError(err)
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, nil, transportError(err)
	}
	if resp.Request == nil {
		resp.Request = req
	}
	return resp, raw, nil
}

// doJSON sends an optional JSON body and decodes the unwrapped envelope data
// into a T.
func doJSON[T any](ctx context.Context, c *httpClient, method string, q query, body any, parts ...pathPart) (T, error) {
	var out T
	path, err := buildPath(parts...)
	if err != nil {
		return out, err
	}
	r := request{method: method, path: path, query: q}
	if body != nil {
		payload, err := json.Marshal(body)
		if err != nil {
			return out, err
		}
		r.body = bytes.NewReader(payload)
		r.contentType = "application/json"
	}
	err = c.sendJSON(ctx, r, &out)
	return out, err
}

// doMultipart sends form and decodes the unwrapped envelope data into a T.
func doMultipart[T any](ctx context.Context, c *httpClient, form *multipartForm, parts ...pathPart) (T, error) {
	var out T
	path, err := buildPath(parts...)
	if err != nil {
		return out, err
	}
	body, contentType, err := form.finish()
	if err != nil {
		return out, err
	}
	err = c.sendJSON(ctx, request{method: http.MethodPost, path: path, body: body, contentType: contentType}, &out)
	return out, err
}

func (c *httpClient) sendJSON(ctx context.Context, r request, out any) error {
	resp, raw, err := c.send(ctx, r)
	if err != nil {
		return err
	}
	if !isSuccess(resp.StatusCode) {
		return newResponseError(resp.StatusCode, raw)
	}
	return decodeData(resp.StatusCode, raw, out)
}

// decodeData unwraps {"status": 1, "data": <payload>} into out. A body that
// is not an envelope is decoded as is.
func decodeData(status int, raw []byte, out any) error {
	if out == nil || len(bytes.TrimSpace(raw)) == 0 {
		return nil
	}
	target := raw
	var envelope map[string]json.RawMessage
	if err := json.Unmarshal(raw, &envelope); err == nil {
		if data, ok := envelope["data"]; ok {
			target = data
		}
	}
	if err := json.Unmarshal(target, out); err != nil {
		e := newResponseError(status, raw)
		e.Message = fmt.Sprintf("could not decode response: %v", err)
		e.cause = err
		return e
	}
	return nil
}

// doBinary downloads a file.
func (c *httpClient) doBinary(ctx context.Context, parts ...pathPart) (Binary, error) {
	path, err := buildPath(parts...)
	if err != nil {
		return Binary{}, err
	}
	resp, raw, err := c.send(ctx, request{method: http.MethodGet, path: path, accept: "*/*"})
	if err != nil {
		return Binary{}, err
	}
	if !isSuccess(resp.StatusCode) {
		return Binary{}, newResponseError(resp.StatusCode, raw)
	}
	return binaryFrom(resp, raw), nil
}

// doRedirect sends a GET without following redirects and returns the
// Location URL of the 3xx answer.
func (c *httpClient) doRedirect(ctx context.Context, q query, parts ...pathPart) (string, error) {
	path, err := buildPath(parts...)
	if err != nil {
		return "", err
	}
	resp, raw, err := c.send(ctx, request{method: http.MethodGet, path: path, query: q, accept: "*/*", noRedirect: true})
	if err != nil {
		return "", err
	}
	if isRedirect(resp.StatusCode) {
		return locationOf(resp, raw)
	}
	if !isSuccess(resp.StatusCode) {
		return "", newResponseError(resp.StatusCode, raw)
	}
	e := newResponseError(resp.StatusCode, raw)
	e.Message = fmt.Sprintf("expected a redirect, got status %d", resp.StatusCode)
	return "", e
}

// doNodeFile serves Nodes.Resolve and Nodes.Content: 3xx yields the URL, 202
// the restore state and any other 2xx the file's bytes.
func (c *httpClient) doNodeFile(ctx context.Context, q query, parts ...pathPart) (NodeFileResult, error) {
	path, err := buildPath(parts...)
	if err != nil {
		return NodeFileResult{}, err
	}
	resp, raw, err := c.send(ctx, request{method: http.MethodGet, path: path, query: q, accept: "*/*", noRedirect: true})
	if err != nil {
		return NodeFileResult{}, err
	}
	switch {
	case isRedirect(resp.StatusCode):
		location, err := locationOf(resp, raw)
		if err != nil {
			return NodeFileResult{}, err
		}
		return NodeFileResult{URL: location}, nil
	case resp.StatusCode == http.StatusAccepted:
		var restoring ArchiveRestoring
		if err := decodeData(resp.StatusCode, raw, &restoring); err != nil {
			return NodeFileResult{}, err
		}
		retryAfter := parseRetryAfter(resp.Header.Get("Retry-After"))
		if retryAfter == 0 {
			retryAfter = restoring.RetryAfterSeconds
		}
		return NodeFileResult{Restoring: &restoring, RetryAfter: retryAfter}, nil
	case isSuccess(resp.StatusCode):
		content := binaryFrom(resp, raw)
		return NodeFileResult{Content: &content}, nil
	default:
		return NodeFileResult{}, newResponseError(resp.StatusCode, raw)
	}
}

// doText sends a GET to an absolute path (outside basePath) and returns the
// body as text.
func (c *httpClient) doText(ctx context.Context, path string) (string, error) {
	resp, raw, err := c.send(ctx, request{method: http.MethodGet, path: path, accept: "text/plain"})
	if err != nil {
		return "", err
	}
	if !isSuccess(resp.StatusCode) {
		return "", newResponseError(resp.StatusCode, raw)
	}
	return strings.TrimSpace(string(raw)), nil
}

// locationOf returns the Location header of a redirect. An absolute URL is
// returned verbatim (signed URLs must not be re-encoded); a relative one is
// resolved against the request URL.
func locationOf(resp *http.Response, raw []byte) (string, error) {
	location := strings.TrimSpace(resp.Header.Get("Location"))
	if location == "" {
		e := newResponseError(resp.StatusCode, raw)
		e.Message = fmt.Sprintf("redirect response (status %d) has no Location header", resp.StatusCode)
		return "", e
	}
	parsed, err := url.Parse(location)
	if err != nil || parsed.IsAbs() || resp.Request == nil || resp.Request.URL == nil {
		return location, nil
	}
	return resp.Request.URL.ResolveReference(parsed).String(), nil
}

func cloneHeaders(input map[string]string) map[string]string {
	result := make(map[string]string, len(input))
	for key, value := range input {
		result[key] = value
	}
	return result
}
