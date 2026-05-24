package agentx

import "fmt"

// RequestError is returned for any non-2xx response from any agentx service.
// It always carries StatusCode and the raw response Body; Message and Code
// are populated when the service returned a JSON error envelope.
type RequestError struct {
	StatusCode int
	Message    string
	Code       string
	Body       string
}

func (e *RequestError) Error() string {
	if e.Message != "" {
		return fmt.Sprintf("agentx: status=%d %s", e.StatusCode, e.Message)
	}
	return fmt.Sprintf("agentx: status=%d", e.StatusCode)
}

// APIError is the structured error payload returned inside the response envelope.
type APIError struct {
	Code    string         `json:"code,omitempty"`
	Message string         `json:"message,omitempty"`
	Details map[string]any `json:"details,omitempty"`
}
