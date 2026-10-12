package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
)

// OperationInput is what Client.Operation sends: the file inputs and the
// options of any operation, by wire name. It is for tools that build calls
// from the API document (lowco-cli); applications use the typed services.
type OperationInput struct {
	// File is the input of an operation that takes one file.
	File FileInput
	// Files are the inputs of an operation that takes files[], in order.
	Files []FileInput
	// Extra are the named extra file inputs, e.g. "image" for pdf/watermark.
	Extra map[string]FileInput
	// Params are the options.
	Params map[string]any
}

// Operation calls any operation by its path (POST /v1/{service}/{operation})
// with the same file handling, retries and errors as the typed services; the
// answer's Data is the operation's result as raw JSON, and Result waits for a
// job the same way.
func (c *Client) Operation(ctx context.Context, path string, in OperationInput, opts ...CallOption) (*Answer[json.RawMessage], error) {
	kind := "none"
	switch {
	case in.File != nil && len(in.Files) > 0:
		return nil, &Error{Reason: ReasonInvalidParam, Param: "files", Message: "Pass File or Files, not both"}
	case in.File != nil:
		kind = "file"
	case len(in.Files) > 0:
		kind = "files"
	}
	params := in.Params
	if params == nil {
		params = map[string]any{}
	}
	var out Answer[json.RawMessage]
	if err := c.c.operation(ctx, path, kind, in.File, in.Files, in.Extra, params, &out.raw, opts); err != nil {
		return nil, err
	}
	return out.decode(c.c)
}

// Request calls any resource route (GET /v1/jobs, PATCH /v1/settings, …) and
// returns the envelope's data as raw JSON. body is sent as JSON when not nil.
// GETs are retried like the typed resources.
func (c *Client) Request(ctx context.Context, method, path string, query url.Values, body any, opts ...RequestOption) (json.RawMessage, error) {
	var out json.RawMessage
	if err := c.c.call(ctx, method, path, query, body, &out, opts); err != nil {
		return nil, err
	}
	return out, nil
}

// RequestRaw is Request for a route answered in another media type (usage
// and the audit log as text/csv with format=csv): it returns the body and
// its Content-Type unparsed. Errors are still the typed *Error.
func (c *Client) RequestRaw(ctx context.Context, method, path string, query url.Values, accept string, opts ...RequestOption) ([]byte, string, error) {
	raw, err := c.c.send(ctx, sendInput{method: method, url: c.c.url(path, query), auth: true, accept: accept, retrySafe: method == http.MethodGet, callOptions: collect(opts)})
	if err != nil {
		return nil, "", err
	}
	return raw.body, raw.contentType, nil
}
