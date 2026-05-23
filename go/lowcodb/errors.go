package lowcodb

import "fmt"

// RequestError is returned for any non-2xx response from the manager.
// It always carries StatusCode and the raw response Body; Message and Code
// are populated when the manager returned a JSON error envelope.
type RequestError struct {
	StatusCode int
	Message    string
	Code       string
	Body       string
}

func (e *RequestError) Error() string {
	if e.Message != "" {
		return fmt.Sprintf("lowcodb: status=%d %s", e.StatusCode, e.Message)
	}
	return fmt.Sprintf("lowcodb: status=%d", e.StatusCode)
}
