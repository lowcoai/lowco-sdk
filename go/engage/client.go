package engage

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// DefaultBaseURL is the fixed API host every event is sent to.
const DefaultBaseURL = "https://api.lowco.ai"

// TrackPath is the event ingestion endpoint.
const TrackPath = "/v1/engage/track"

// Request headers.
const (
	// HeaderAPIKey carries an lc_ API key; other credentials travel as
	// "Authorization: Bearer".
	HeaderAPIKey = "X-Api-Key"
	// HeaderOrgID carries the organization id.
	HeaderOrgID = "X-Org-Id"
	// HeaderAppID selects the engage app; without it the service uses the
	// org's default app.
	HeaderAppID = "X-Engage-App-Id"
)

// Event names sent by Page and IdentifyUser.
const (
	PageViewEvent = "page_view"
	IdentifyEvent = "_lowco_identify"
)

// maxErrorBody caps how much of an error response is read.
const maxErrorBody = 64 << 10

// IsAPIKey reports whether apiKey is a Lowco API key (lc_…) rather than an
// access token.
func IsAPIKey(apiKey string) bool {
	return strings.HasPrefix(strings.TrimSpace(apiKey), "lc_")
}

// Client sends events to the engage track API. Create one and share it: it
// holds no per-user state and is safe for concurrent use.
type Client struct {
	trackURL string
	headers  http.Header
	appID    string
	deviceID string
	http     *http.Client
	now      func() time.Time
}

// NewClient constructs a Client targeting DefaultBaseURL. Config.APIKey and
// Config.OrgID are required: it returns ErrMissingAPIKey or ErrMissingOrgID
// when either is empty. Config.AppID is optional.
func NewClient(config Config) (*Client, error) {
	apiKey := strings.TrimSpace(config.APIKey)
	if apiKey == "" {
		return nil, ErrMissingAPIKey
	}
	if strings.TrimSpace(config.OrgID) == "" {
		return nil, ErrMissingOrgID
	}

	headers := make(http.Header)
	headers.Set("Content-Type", "application/json")
	if IsAPIKey(apiKey) {
		headers.Set(HeaderAPIKey, apiKey)
	} else {
		headers.Set("Authorization", "Bearer "+apiKey)
	}
	headers.Set(HeaderOrgID, config.OrgID)
	appID := strings.TrimSpace(config.AppID)
	if appID != "" {
		headers.Set(HeaderAppID, appID)
	}

	deviceID := strings.TrimSpace(config.DeviceID)
	if deviceID == "" {
		var err error
		if deviceID, err = newUUID(); err != nil {
			return nil, fmt.Errorf("engage: generate device id: %w", err)
		}
	}

	client := config.HTTPClient
	if client == nil {
		timeout := 30 * time.Second
		if config.TimeoutMS > 0 {
			timeout = time.Duration(config.TimeoutMS) * time.Millisecond
		}
		client = &http.Client{Timeout: timeout}
	}

	return &Client{
		trackURL: DefaultBaseURL + TrackPath,
		headers:  headers,
		appID:    appID,
		deviceID: deviceID,
		http:     client,
		now:      time.Now,
	}, nil
}

// DeviceID returns the device_id of events that do not set one.
func (c *Client) DeviceID() string {
	return c.deviceID
}

// AppID returns the engage app events go to, or "" for the org's default app.
func (c *Client) AppID() string {
	return c.appID
}

// Track sends a custom event. properties become event_data.
func (c *Client) Track(ctx context.Context, eventName string, properties Metadata, opts *EventOptions) error {
	if strings.TrimSpace(eventName) == "" {
		return ErrMissingEventName
	}
	return c.send(ctx, c.buildEvent(eventName, properties, opts, ""))
}

// Page sends a page_view event; put path, url, title, referrer and search in
// properties like the browser SDK does.
func (c *Client) Page(ctx context.Context, properties Metadata, opts *EventOptions) error {
	return c.send(ctx, c.buildEvent(PageViewEvent, properties, opts, ""))
}

// IdentifyUser sends an _lowco_identify event linking userID to the device
// id. The user is not remembered for later calls: pass EventOptions.UserID on
// each event that should be attributed to them.
func (c *Client) IdentifyUser(ctx context.Context, userID string, properties Metadata, opts *EventOptions) error {
	if strings.TrimSpace(userID) == "" {
		return ErrMissingUserID
	}
	return c.send(ctx, c.buildEvent(IdentifyEvent, properties, opts, userID))
}

// buildEvent assembles the wire event; userID, when set, wins over opts.
func (c *Client) buildEvent(name string, properties Metadata, opts *EventOptions, userID string) Event {
	if opts == nil {
		opts = &EventOptions{}
	}
	if userID == "" {
		userID = opts.UserID
	}
	deviceID := opts.DeviceID
	if deviceID == "" {
		deviceID = c.deviceID
	}
	eventTime := opts.EventTime
	if eventTime.IsZero() {
		eventTime = c.now()
	}
	data := Metadata{}
	for k, v := range properties {
		data[k] = v
	}
	return Event{
		ID:         "",
		EventName:  name,
		EventData:  data,
		UserID:     userID,
		DeviceID:   deviceID,
		SessionID:  opts.SessionID,
		DeviceInfo: opts.DeviceInfo,
		Location:   opts.Location,
		EventTime:  isoTime(eventTime),
	}
}

func (c *Client) send(ctx context.Context, event Event) error {
	body, err := encodeEvent(event)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.trackURL, bytes.NewReader(body))
	if err != nil {
		return transportError(err)
	}
	req.Header = c.headers.Clone()
	resp, err := c.http.Do(req)
	if err != nil {
		return transportError(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		_, _ = io.Copy(io.Discard, resp.Body)
		return nil
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, maxErrorBody))
	if err != nil {
		return transportError(err)
	}
	return newResponseError(resp.StatusCode, raw)
}

// encodeEvent marshals compact UTF-8 JSON like JSON.stringify (no HTML
// escaping). Unsupported values such as NaN fail here, before any request.
func encodeEvent(event Event) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(event); err != nil {
		return nil, fmt.Errorf("engage: encode event: %w", err)
	}
	return bytes.TrimSuffix(buf.Bytes(), []byte("\n")), nil
}

// isoTime formats t like JavaScript's Date.toISOString: UTC, milliseconds
// (truncated), Z suffix.
func isoTime(t time.Time) string {
	return t.UTC().Format("2006-01-02T15:04:05.000Z")
}

// newUUID returns a random (version 4) UUID.
func newUUID() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16]), nil
}
