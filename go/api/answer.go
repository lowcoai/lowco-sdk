package api

import (
	"context"
	"encoding/json"
	"strings"
)

// Answer is an operation's answer: Data when it finished in the request
// (200), Job when it was accepted as one (202), Bytes when WithAccept asked
// for the output file's own type.
type Answer[T any] struct {
	Status      int
	Data        *T
	Job         *Job
	Bytes       []byte
	ContentType string
	RequestID   string
	// Replayed is true when an Idempotency-Key replayed an earlier submission.
	Replayed bool
	// CreditsUsed is what the call consumed (live, metered calls).
	CreditsUsed string

	raw rawAnswer
	c   *core
}

func (a *Answer[T]) decode(c *core) (*Answer[T], error) {
	a.c = c
	a.Status = a.raw.status
	a.RequestID = a.raw.header.Get("X-Request-Id")
	a.Replayed = a.raw.header.Get("Idempotent-Replayed") == "true"
	a.CreditsUsed = a.raw.header.Get("X-Lowco-Credits-Used")
	switch {
	case !strings.Contains(a.raw.contentType, "json"):
		a.Bytes, a.ContentType = a.raw.body, a.raw.contentType
	case a.raw.status == 202:
		var job Job
		if err := c.data(&a.raw, &job); err != nil {
			return nil, err
		}
		a.Job = &job
	default:
		var data T
		if err := c.data(&a.raw, &data); err != nil {
			return nil, err
		}
		a.Data = &data
	}
	return a, nil
}

// Result returns Data, or waits for the job (honouring Retry-After) and
// decodes its result.
func (a *Answer[T]) Result(ctx context.Context, opts ...WaitOption) (*T, error) {
	if a.Data != nil {
		return a.Data, nil
	}
	if a.Job == nil {
		return nil, errNoResult
	}
	job, err := a.c.waitForJob(ctx, a.Job.JobID, opts)
	if err != nil {
		return nil, err
	}
	b, err := json.Marshal(job.Result)
	if err != nil {
		return nil, err
	}
	var out T
	if err := json.Unmarshal(b, &out); err != nil {
		return nil, &Error{Reason: ReasonInternalError, Message: "decoding the job result: " + err.Error(), cause: err}
	}
	return &out, nil
}
