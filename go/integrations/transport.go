package integrations

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
	timeout      time.Duration
	extraHeaders map[string]string
	httpClient   *http.Client
}

func newHTTPClient(config Config) (*httpClient, error) {
	if strings.TrimSpace(config.Token) == "" {
		return nil, fmt.Errorf("token is required")
	}

	timeout := 30 * time.Second
	if config.TimeoutMS > 0 {
		timeout = time.Duration(config.TimeoutMS) * time.Millisecond
	}

	client := config.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: timeout}
	}

	return &httpClient{
		baseURL:      DefaultBaseURL,
		token:        config.Token,
		orgID:        config.OrgID,
		timeout:      timeout,
		extraHeaders: cloneHeaders(config.Headers),
		httpClient:   client,
	}, nil
}

func (c *httpClient) Request(ctx context.Context, method, path string, body any, options *RequestOptions, out any) error {
	reqURL, err := c.buildURL(path, options)
	if err != nil {
		return err
	}

	var bodyReader io.Reader
	if body != nil {
		payload, marshalErr := json.Marshal(body)
		if marshalErr != nil {
			return marshalErr
		}
		bodyReader = bytes.NewReader(payload)
	}

	req, err := http.NewRequestWithContext(ctx, method, reqURL, bodyReader)
	if err != nil {
		return err
	}

	for key, value := range c.extraHeaders {
		req.Header.Set(key, value)
	}
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if req.Header.Get("Authorization") == "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	if c.orgID != "" && req.Header.Get(HeaderOrgID) == "" {
		req.Header.Set(HeaderOrgID, c.orgID)
	}
	if options != nil {
		for key, value := range options.Headers {
			req.Header.Set(key, value)
		}
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return &Error{
			Status:  0,
			Message: err.Error(),
			Payload: nil,
		}
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	var payload any
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &payload); err != nil {
			return err
		}
	}

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return &Error{
			Status:  resp.StatusCode,
			Message: fmt.Sprintf("request failed with status %d", resp.StatusCode),
			Payload: payload,
		}
	}

	if out == nil || len(raw) == 0 {
		return nil
	}

	unwrap, ok := payload.(map[string]any)
	if ok {
		data, hasData := unwrap["data"]
		if hasData {
			dataBytes, marshalErr := json.Marshal(data)
			if marshalErr != nil {
				return marshalErr
			}
			return json.Unmarshal(dataBytes, out)
		}
	}

	return json.Unmarshal(raw, out)
}

func (c *httpClient) buildURL(path string, options *RequestOptions) (string, error) {
	normalized := path
	if !strings.HasPrefix(path, "/") {
		normalized = "/" + path
	}

	u, err := url.Parse(c.baseURL + normalized)
	if err != nil {
		return "", err
	}

	if options == nil || len(options.Query) == 0 {
		return u.String(), nil
	}

	q := u.Query()
	for key, value := range options.Query {
		if value == nil {
			continue
		}
		switch v := value.(type) {
		case string:
			if v == "" {
				continue
			}
			q.Set(key, v)
		case bool:
			if v {
				q.Set(key, "true")
			} else {
				q.Set(key, "false")
			}
		case int, int8, int16, int32, int64:
			q.Set(key, fmt.Sprintf("%d", v))
		case uint, uint8, uint16, uint32, uint64:
			q.Set(key, fmt.Sprintf("%d", v))
		case float32, float64:
			q.Set(key, fmt.Sprintf("%v", v))
		default:
			b, err := json.Marshal(v)
			if err != nil {
				return "", err
			}
			q.Set(key, string(b))
		}
	}
	u.RawQuery = q.Encode()
	return u.String(), nil
}

func cloneHeaders(input map[string]string) map[string]string {
	if len(input) == 0 {
		return map[string]string{}
	}
	result := make(map[string]string, len(input))
	for key, value := range input {
		result[key] = value
	}
	return result
}
