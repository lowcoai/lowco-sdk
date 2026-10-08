package docs

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strings"
)

// Construction errors returned by NewClient.
var (
	// ErrMissingToken is returned when Config.Token is empty.
	ErrMissingToken = errors.New("token is required")
	// ErrMissingOrgID is returned when Config.OrgID is empty.
	ErrMissingOrgID = errors.New("orgId is required")
)

// Error is returned for any non-2xx response, a network or timeout failure
// (Status 0), a response the SDK could not interpret, and an invalid
// argument such as an empty required value or a "." / ".." path segment
// (Status 0, no request sent).
type Error struct {
	// Status is the HTTP status code, or 0 when no response was received.
	Status int
	// Message is the best message found in the response body.
	Message string
	// Code is the platform error code (e.g. "AAS-00106") of a
	// {"status":0,"error":{"message","code","details"}} body whose message is
	// such a code; empty otherwise.
	Code string
	// Payload is the decoded JSON body, the raw body text when it is not
	// JSON, or nil when there was no body.
	Payload any

	raw   []byte
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

// PreconditionState returns the file's current state when e is the 412 of a
// conditional save (UpdateFileRequest.IfMatch / IfNoneMatch).
func (e *Error) PreconditionState() (*PreconditionState, bool) {
	if e == nil || e.Status != http.StatusPreconditionFailed || len(e.raw) == 0 {
		return nil, false
	}
	var body struct {
		Data *PreconditionState `json:"data"`
	}
	if err := json.Unmarshal(e.raw, &body); err != nil || body.Data == nil {
		return nil, false
	}
	return body.Data, true
}

// newResponseError builds the *Error for a non-2xx response. The service
// answers with either {"status":0,"error":{"message","code","details"}}
// (message is an error code such as AAS-00106 and details the reason) or
// {"message":"..."}.
func newResponseError(status int, raw []byte) *Error {
	e := &Error{Status: status, raw: raw}
	trimmed := strings.TrimSpace(string(raw))
	if trimmed != "" {
		var payload any
		if err := json.Unmarshal(raw, &payload); err == nil {
			e.Payload = payload
			e.Message, e.Code = messageFromPayload(payload)
		} else {
			e.Payload = string(raw)
			if len(trimmed) <= 256 && !strings.HasPrefix(trimmed, "<") {
				e.Message = trimmed
			}
		}
	}
	if e.Message == "" {
		e.Message = fmt.Sprintf("request failed with status %d", status)
	}
	return e
}

func messageFromPayload(payload any) (message, code string) {
	obj, ok := payload.(map[string]any)
	if !ok {
		if s, ok := payload.(string); ok {
			return strings.TrimSpace(s), ""
		}
		return "", ""
	}
	switch errField := obj["error"].(type) {
	case map[string]any:
		errMessage, _ := errField["message"].(string)
		details, _ := errField["details"].(string)
		errMessage, details = strings.TrimSpace(errMessage), strings.TrimSpace(details)
		if platformCode.MatchString(errMessage) {
			code = errMessage
			if details != "" {
				return details, code
			}
			return errMessage, code
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

// platformCode matches platform error codes such as AAS-00106.
var platformCode = regexp.MustCompile(`^[A-Z][A-Z0-9]*-\d+$`)

// transportError wraps a failure to get a response.
func transportError(err error) *Error {
	return &Error{Status: 0, Message: err.Error(), cause: err}
}

// argumentError reports a missing required argument; no request is sent.
func argumentError(name string) *Error {
	return &Error{Status: 0, Message: name + " is required"}
}

// dotSegmentError reports a "." or ".." path segment; no request is sent.
func dotSegmentError(name string) *Error {
	return &Error{Status: 0, Message: name + ` must not contain "." or ".." segments`}
}
