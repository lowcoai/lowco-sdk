package api

import (
	"fmt"
	"time"
)

// Error is every failed call: an error envelope, a network failure, a
// timeout or invalid input. Branch on Reason, not on Message.
type Error struct {
	// Status is the HTTP status, or 0 when no response was received.
	Status int
	// Reason is the stable error code (ErrorReasons describes each).
	Reason ErrorReason
	// Message is for people.
	Message string
	// Param is the parameter at fault.
	Param string
	// Details lists each failing item of a validation error.
	Details []ErrorDetail
	// RequestID is what support needs.
	RequestID string
	// DocURL is the reason's entry on docs.lowco.ai/api/errors.
	DocURL string
	// Retryable says whether the same request may succeed later, when known.
	Retryable *bool
	// RetryAfter is the API's Retry-After, when it sent one.
	RetryAfter time.Duration
	// Body is the raw error body.
	Body  []byte
	cause error
}

func (e *Error) Error() string {
	if e.RequestID != "" {
		return fmt.Sprintf("lowco api: %s (%d): %s [request %s]", e.Reason, e.Status, e.Message, e.RequestID)
	}
	return fmt.Sprintf("lowco api: %s (%d): %s", e.Reason, e.Status, e.Message)
}

// Unwrap returns the transport error, if any.
func (e *Error) Unwrap() error { return e.cause }

// JobFailedError is returned by Jobs.Wait and Answer.Result when the job
// failed or was cancelled. Err has the job's reason; Job is its last state.
// errors.As finds both *JobFailedError and *Error.
type JobFailedError struct {
	Err *Error
	Job *Job
}

func (e *JobFailedError) Error() string { return e.Err.Error() }

// Unwrap returns the job's *Error.
func (e *JobFailedError) Unwrap() error { return e.Err }

// TimeoutError is returned by Jobs.Wait when the job is still running at the
// timeout.
type TimeoutError struct {
	JobID   string
	Timeout time.Duration
}

func (e *TimeoutError) Error() string {
	return fmt.Sprintf("lowco api: job %s did not finish within %s", e.JobID, e.Timeout)
}
