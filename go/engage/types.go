package engage

import (
	"net/http"
	"time"
)

// Config configures NewClient.
type Config struct {
	// APIKey is required. An lc_ API key (generated in the admin portal) is
	// sent as the X-Api-Key header; any other value (an OAuth2 access token)
	// as "Authorization: Bearer <APIKey>".
	APIKey string
	// OrgID is required and sent as the X-Org-Id header.
	OrgID string
	// AppID is the engage app to track into, sent as the X-Engage-App-Id
	// header. Optional: when empty, events go to the org's default app.
	AppID string
	// DeviceID is the device_id of events that do not set one. Defaults to a
	// random UUID generated for this client.
	DeviceID string
	// TimeoutMS is the request timeout of the default HTTP client in
	// milliseconds (30s when zero). It is not applied to HTTPClient.
	TimeoutMS int
	// HTTPClient replaces the default HTTP client.
	HTTPClient *http.Client
}

// Metadata holds free-form event properties (event_data). Values must be
// JSON-encodable.
type Metadata = map[string]any

// EventOptions are the per-call event fields. A nil *EventOptions sends none
// of them.
type EventOptions struct {
	// UserID attributes the event to a user. IdentifyUser ignores it and uses
	// its userID argument.
	UserID string
	// DeviceID overrides the client's default device id, e.g. with the
	// browser SDK's lowco_uuid to tie server events to a visitor.
	DeviceID string
	// SessionID, e.g. forwarded from the browser SDK's lowco_session_id.
	SessionID string
	// DeviceInfo describes the client device.
	DeviceInfo *DeviceInfo
	// Location of the client.
	Location *LocationInfo
	// EventTime defaults to now.
	EventTime time.Time
}

// Event is one tracked event as sent to POST /v1/engage/track. Its JSON is
// the shape the browser SDK sends; empty optional fields are left out.
type Event struct {
	ID         string        `json:"id"`
	EventName  string        `json:"event_name"`
	EventData  Metadata      `json:"event_data"`
	UserID     string        `json:"user_id,omitempty"`
	DeviceID   string        `json:"device_id"`
	SessionID  string        `json:"session_id,omitempty"`
	DeviceInfo *DeviceInfo   `json:"device_info,omitempty"`
	Location   *LocationInfo `json:"location,omitempty"`
	// EventTime is ISO-8601 UTC with milliseconds and a Z suffix, like
	// JavaScript's Date.toISOString.
	EventTime string `json:"event_time"`
}

// DeviceInfo describes the client device (the ua-parser-js result in the
// browser SDK).
type DeviceInfo struct {
	Browser *BrowserInfo        `json:"browser,omitempty"`
	OS      *OSInfo             `json:"os,omitempty"`
	Device  *DeviceHardwareInfo `json:"device,omitempty"`
	CPU     *CPUInfo            `json:"cpu,omitempty"`
	Engine  *EngineInfo         `json:"engine,omitempty"`
	UA      string              `json:"ua,omitempty"`
}

// BrowserInfo is device_info.browser.
type BrowserInfo struct {
	Name    string `json:"name,omitempty"`
	Version string `json:"version,omitempty"`
	Major   string `json:"major,omitempty"`
}

// OSInfo is device_info.os.
type OSInfo struct {
	Name    string `json:"name,omitempty"`
	Version string `json:"version,omitempty"`
}

// DeviceHardwareInfo is device_info.device.
type DeviceHardwareInfo struct {
	Model  string `json:"model,omitempty"`
	Type   string `json:"type,omitempty"`
	Vendor string `json:"vendor,omitempty"`
}

// CPUInfo is device_info.cpu.
type CPUInfo struct {
	Architecture string `json:"architecture,omitempty"`
}

// EngineInfo is device_info.engine.
type EngineInfo struct {
	Name    string `json:"name,omitempty"`
	Version string `json:"version,omitempty"`
}

// LocationInfo is the location of the client, with the snake_case keys the
// engage ingest model reads. Coordinates are pointers so that 0 is sent; use
// Float64 to set them. IPAddress is the field a server usually knows.
type LocationInfo struct {
	Latitude         *float64 `json:"latitude,omitempty"`
	Longitude        *float64 `json:"longitude,omitempty"`
	Accuracy         *float64 `json:"accuracy,omitempty"`
	Altitude         *float64 `json:"altitude,omitempty"`
	AltitudeAccuracy *float64 `json:"altitude_accuracy,omitempty"`
	Heading          *float64 `json:"heading,omitempty"`
	Speed            *float64 `json:"speed,omitempty"`
	IPAddress        string   `json:"ip_address,omitempty"`
}

// Float64 returns a pointer to v, for the LocationInfo fields.
func Float64(v float64) *float64 {
	return &v
}
