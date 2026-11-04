package engage

import (
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
)

// Argument errors. No request is sent when one is returned.
var (
	// ErrMissingAPIKey is returned by NewClient when Config.APIKey is empty.
	ErrMissingAPIKey = errors.New("engage: apiKey is required")
	// ErrMissingOrgID is returned by NewClient when Config.OrgID is empty.
	ErrMissingOrgID = errors.New("engage: orgId is required")
	// ErrMissingEventName is returned by Track for an empty event name.
	ErrMissingEventName = errors.New("engage: eventName is required")
	// ErrMissingUserID is returned by IdentifyUser for an empty user id.
	ErrMissingUserID = errors.New("engage: userID is required")
)

// Error is returned for a non-2xx response and for a network or timeout
// failure (Status 0).
type Error struct {
	// Status is the HTTP status code, or 0 when no response was received.
	Status int
	// Message is the best message found in the response body: the
	// envelope's error.details when error.message is an opaque platform code
	// such as "AAS-00400", otherwise error.message or message, otherwise the
	// raw text.
	Message string
	// Code is that platform code (e.g. "AAS-00400"); empty otherwise.
	Code string
	// Body is the raw response body.
	Body string

	cause error
}

// Error returns Message.
func (e *Error) Error() string {
	return e.Message
}

// Unwrap returns the underlying transport error, if any, so errors.Is works
// with context.Canceled and context.DeadlineExceeded.
func (e *Error) Unwrap() error {
	return e.cause
}

// platformCode matches platform error codes such as AAS-00106.
var platformCode = regexp.MustCompile(`^[A-Z][A-Z0-9]*-\d+$`)

// newResponseError builds the *Error for a non-2xx response. The service
// answers with {"status":0,"error":{"message","code","details"}}; the gateway
// may answer with {"message":"..."} or plain text.
func newResponseError(status int, raw []byte) *Error {
	e := &Error{Status: status, Body: string(raw)}
	trimmed := strings.TrimSpace(string(raw))
	var payload map[string]any
	if err := json.Unmarshal(raw, &payload); err == nil {
		e.Message, e.Code = messageFromPayload(payload)
	} else if trimmed != "" && len(trimmed) <= 256 && !strings.HasPrefix(trimmed, "<") {
		e.Message = trimmed
	}
	if e.Message == "" {
		e.Message = fmt.Sprintf("engage: status=%d", status)
	}
	return e
}

func messageFromPayload(obj map[string]any) (message, code string) {
	switch errField := obj["error"].(type) {
	case map[string]any:
		errMessage, _ := errField["message"].(string)
		details, _ := errField["details"].(string)
		errMessage, details = strings.TrimSpace(errMessage), strings.TrimSpace(details)
		if platformCode.MatchString(errMessage) {
			if details != "" {
				return details, errMessage
			}
			return errMessage, errMessage
		}
		if errMessage != "" {
			return errMessage, ""
		}
		if details != "" {
			return details, ""
		}
	case string:
		if strings.TrimSpace(errField) != "" {
			return errField, ""
		}
	}
	if m, _ := obj["message"].(string); strings.TrimSpace(m) != "" {
		return m, ""
	}
	return "", ""
}

// transportError wraps a failure to get a response.
func transportError(err error) *Error {
	return &Error{Status: 0, Message: err.Error(), cause: err}
}
