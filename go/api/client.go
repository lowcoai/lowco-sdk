package api

import (
	"errors"
	"net/http"
	"os"
	"strings"
	"time"
)

// DefaultBaseURL is the API host every request goes to unless Config.BaseURL
// or LOWCO_API_BASE_URL says otherwise.
const DefaultBaseURL = "https://api.lowco.ai"

// SDKVersion is this SDK's version; its major and minor follow the API
// document it was generated from.
const SDKVersion = "1.1.0"

// ErrMissingAPIKey is returned by NewClient when no key is configured.
var ErrMissingAPIKey = errors.New("lowco api: an API key is required (lc_live_… or lc_test_…): set Config.APIKey or LOWCO_API_KEY")

// Config configures a Client.
type Config struct {
	// APIKey is lc_live_… or lc_test_…; the key picks the environment.
	// Defaults to the LOWCO_API_KEY environment variable.
	APIKey string
	// BaseURL defaults to LOWCO_API_BASE_URL, else DefaultBaseURL.
	BaseURL string
	// HTTPClient defaults to a client with Timeout.
	HTTPClient *http.Client
	// Timeout is the per-request timeout (default 60 s).
	Timeout time.Duration
	// MaxRetries retries 429, 503 and network failures for requests that are
	// safe to repeat: GETs and calls with an Idempotency-Key (default 2;
	// negative disables).
	MaxRetries int
}

// Client is the Lowco API client. Its fields are the operation services
// (PDF, Render, OCR, DocAI, QR, Barcode) and the resources (Files, Jobs,
// Webhooks, Templates, Settings, Usage, Audit).
type Client struct {
	services
	c *core
}

// NewClient builds a Client.
func NewClient(cfg Config) (*Client, error) {
	if cfg.APIKey == "" {
		cfg.APIKey = os.Getenv("LOWCO_API_KEY")
	}
	if cfg.APIKey == "" {
		return nil, ErrMissingAPIKey
	}
	if cfg.BaseURL == "" {
		cfg.BaseURL = os.Getenv("LOWCO_API_BASE_URL")
	}
	if cfg.BaseURL == "" {
		cfg.BaseURL = DefaultBaseURL
	}
	if cfg.Timeout == 0 {
		cfg.Timeout = 60 * time.Second
	}
	if cfg.HTTPClient == nil {
		cfg.HTTPClient = &http.Client{Timeout: cfg.Timeout}
	}
	if cfg.MaxRetries == 0 {
		cfg.MaxRetries = 2
	}
	if cfg.MaxRetries < 0 {
		cfg.MaxRetries = 0
	}
	c := &core{key: cfg.APIKey, base: strings.TrimRight(cfg.BaseURL, "/"), http: cfg.HTTPClient, retries: cfg.MaxRetries}
	return &Client{services: newServices(c), c: c}, nil
}

// Option adjusts one call: WithRequestID, WithIdempotencyKey, WithMode,
// WithAccept.
type Option func(*callOptions)

// RequestOption is an Option for a resource call.
type RequestOption = Option

// CallOption is an Option for an operation call.
type CallOption = Option

type callOptions struct {
	requestID      string
	idempotencyKey string
	mode           string
	accept         string
}

// WithRequestID sends your own request id (echoed in X-Request-Id).
func WithRequestID(id string) Option { return func(o *callOptions) { o.requestID = id } }

// WithIdempotencyKey makes a submission safe to retry for 24 hours (see
// NewIdempotencyKey).
func WithIdempotencyKey(key string) Option { return func(o *callOptions) { o.idempotencyKey = key } }

// WithMode is "sync" or "async"; async always answers 202 with a job.
func WithMode(mode string) Option { return func(o *callOptions) { o.mode = mode } }

// WithAccept asks for the single output file itself in Answer.Bytes
// (application/pdf, image/png, image/svg+xml).
func WithAccept(mediaType string) Option { return func(o *callOptions) { o.accept = mediaType } }

// WaitOption adjusts Jobs.Wait and Answer.Result.
type WaitOption func(*waitOptions)

type waitOptions struct {
	timeout     time.Duration
	maxInterval time.Duration
}

// WithWaitTimeout gives up after d (default 5 minutes).
func WithWaitTimeout(d time.Duration) WaitOption { return func(o *waitOptions) { o.timeout = d } }

// WithMaxInterval caps the pause between polls (default 10 s).
func WithMaxInterval(d time.Duration) WaitOption { return func(o *waitOptions) { o.maxInterval = d } }

// String, Int, Float and Bool return pointers for optional parameters.
func String(v string) *string { return &v }

// Int returns a pointer to v.
func Int(v int) *int { return &v }

// Float returns a pointer to v.
func Float(v float64) *float64 { return &v }

// Bool returns a pointer to v.
func Bool(v bool) *bool { return &v }
