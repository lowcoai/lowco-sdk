package api

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"net/url"
	"strconv"
	"strings"
	"time"
)

var sprintf = fmt.Sprintf

type core struct {
	key     string
	base    string
	http    *http.Client
	retries int
}

type rawAnswer struct {
	status      int
	header      http.Header
	body        []byte
	contentType string
}

type envelope struct {
	Status int             `json:"status"`
	Data   json.RawMessage `json:"data"`
	Error  *struct {
		Code      int           `json:"code"`
		Reason    ErrorReason   `json:"reason"`
		Message   string        `json:"message"`
		Param     string        `json:"param"`
		Details   []ErrorDetail `json:"details"`
		RequestID string        `json:"request_id"`
		DocURL    string        `json:"doc_url"`
		Retryable *bool         `json:"retryable"`
	} `json:"error"`
}

func (c *core) url(path string, q url.Values) string {
	u := path
	if !strings.HasPrefix(path, "http") {
		u = c.base + path
	}
	if len(q) > 0 {
		sep := "?"
		if strings.Contains(u, "?") {
			sep = "&"
		}
		u += sep + q.Encode()
	}
	return u
}

func collect(opts []Option) callOptions {
	var o callOptions
	for _, f := range opts {
		if f != nil {
			f(&o)
		}
	}
	return o
}

type sendInput struct {
	method      string
	url         string
	body        func() (io.Reader, string, error) // rebuilt on every attempt
	auth        bool
	noRedirect  bool
	accept      string
	retrySafe   bool
	callOptions callOptions
}

func (c *core) send(ctx context.Context, in sendInput) (*rawAnswer, error) {
	safe := in.retrySafe || in.callOptions.idempotencyKey != ""
	for attempt := 0; ; attempt++ {
		var body io.Reader
		ctype := ""
		if in.body != nil {
			b, t, err := in.body()
			if err != nil {
				return nil, &Error{Reason: ReasonInvalidParam, Message: err.Error(), cause: err}
			}
			body, ctype = b, t
		}
		req, err := http.NewRequestWithContext(ctx, in.method, in.url, body)
		if err != nil {
			return nil, &Error{Reason: ReasonInvalidParam, Message: err.Error(), cause: err}
		}
		req.Header.Set("X-Client-User-Agent", "lowcoai-api-go/"+SDKVersion)
		if ctype != "" {
			req.Header.Set("Content-Type", ctype)
		}
		if in.accept != "" {
			req.Header.Set("Accept", in.accept)
		} else {
			req.Header.Set("Accept", "application/json")
		}
		if in.auth {
			req.Header.Set("Authorization", "Bearer "+c.key)
		}
		if id := in.callOptions.requestID; id != "" {
			req.Header.Set("X-Request-Id", id)
		}
		if k := in.callOptions.idempotencyKey; k != "" {
			req.Header.Set("Idempotency-Key", k)
		}
		client := c.http
		if in.noRedirect {
			cp := *c.http
			cp.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
			client = &cp
		}
		resp, err := client.Do(req)
		if err != nil {
			if ctx.Err() != nil {
				return nil, &Error{Reason: ReasonTimeout, Message: ctx.Err().Error(), cause: err}
			}
			if safe && attempt < c.retries {
				if err := pause(ctx, time.Duration(500<<attempt)*time.Millisecond); err != nil {
					return nil, err
				}
				continue
			}
			return nil, &Error{Reason: ReasonServiceUnavailable, Message: "network error: " + err.Error(), cause: err, Retryable: Bool(true)}
		}
		data, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			return nil, &Error{Status: resp.StatusCode, Reason: ReasonServiceUnavailable, Message: err.Error(), cause: err}
		}
		raw := &rawAnswer{status: resp.StatusCode, header: resp.Header, body: data, contentType: resp.Header.Get("Content-Type")}
		if resp.StatusCode >= 400 {
			apiErr := c.error(raw)
			if safe && attempt < c.retries && (resp.StatusCode == 429 || resp.StatusCode == 503) {
				wait := apiErr.RetryAfter
				if wait == 0 && raw.header.Get("Retry-After") == "" {
					wait = time.Second
				}
				if err := pause(ctx, min(wait, 30*time.Second)); err != nil {
					return nil, err
				}
				continue
			}
			return nil, apiErr
		}
		return raw, nil
	}
}

func pause(ctx context.Context, d time.Duration) error {
	if d <= 0 {
		return nil
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return &Error{Reason: ReasonTimeout, Message: ctx.Err().Error(), cause: ctx.Err()}
	case <-t.C:
		return nil
	}
}

func (c *core) error(raw *rawAnswer) *Error {
	e := &Error{Status: raw.status, Body: raw.body, RequestID: raw.header.Get("X-Request-Id")}
	if ra := raw.header.Get("Retry-After"); ra != "" {
		if n, err := strconv.Atoi(ra); err == nil {
			e.RetryAfter = time.Duration(n) * time.Second
		}
	}
	var env envelope
	if strings.Contains(raw.contentType, "json") && json.Unmarshal(raw.body, &env) == nil && env.Error != nil {
		e.Reason, e.Message, e.Param, e.Details = env.Error.Reason, env.Error.Message, env.Error.Param, env.Error.Details
		e.DocURL, e.Retryable = env.Error.DocURL, env.Error.Retryable
		if env.Error.RequestID != "" {
			e.RequestID = env.Error.RequestID
		}
		return e
	}
	e.Message = strings.TrimSpace(string(raw.body))
	if e.Message == "" {
		e.Message = sprintf("request failed with status %d", raw.status)
	}
	e.Reason = ReasonInvalidParam
	if raw.status >= 500 {
		e.Reason = ReasonInternalError
	}
	return e
}

func (c *core) data(raw *rawAnswer, out any) error {
	var env envelope
	if err := json.Unmarshal(raw.body, &env); err != nil || env.Status != 1 {
		return &Error{Status: raw.status, Reason: ReasonInternalError, Message: "the API answered without a success envelope", Body: raw.body}
	}
	if out == nil {
		return nil
	}
	if err := json.Unmarshal(env.Data, out); err != nil {
		return &Error{Status: raw.status, Reason: ReasonInternalError, Message: "decoding the answer: " + err.Error(), Body: raw.body, cause: err}
	}
	return nil
}

func jsonBody(v any) func() (io.Reader, string, error) {
	return func() (io.Reader, string, error) {
		b, err := json.Marshal(v)
		return bytes.NewReader(b), "application/json", err
	}
}

func (c *core) call(ctx context.Context, method, path string, q url.Values, body any, out any, opts []Option) error {
	in := sendInput{method: method, url: c.url(path, q), auth: true, retrySafe: method == http.MethodGet, callOptions: collect(opts)}
	if body != nil {
		in.body = jsonBody(body)
	}
	raw, err := c.send(ctx, in)
	if err != nil {
		return err
	}
	return c.data(raw, out)
}

type part struct {
	field, filename, mimeType string
	data                      []byte
}

func multipartBody(fields [][2]string, parts []part) func() (io.Reader, string, error) {
	return func() (io.Reader, string, error) {
		var buf bytes.Buffer
		w := multipart.NewWriter(&buf)
		for _, p := range parts {
			h := make(textproto.MIMEHeader)
			h.Set("Content-Disposition", sprintf(`form-data; name=%q; filename=%q`, p.field, p.filename))
			h.Set("Content-Type", p.mimeType)
			pw, err := w.CreatePart(h)
			if err != nil {
				return nil, "", err
			}
			if _, err := pw.Write(p.data); err != nil {
				return nil, "", err
			}
		}
		for _, f := range fields {
			if err := w.WriteField(f[0], f[1]); err != nil {
				return nil, "", err
			}
		}
		if err := w.Close(); err != nil {
			return nil, "", err
		}
		return &buf, w.FormDataContentType(), nil
	}
}

func (c *core) upload(ctx context.Context, path string, file FileInput, out any, opts []Option) error {
	if file == nil || !file.ref().local() {
		return &Error{Reason: ReasonInvalidParam, Param: "file", Message: "Upload takes a local file (FilePath, FileBytes or FileReader)"}
	}
	f := file.ref()
	name, mt, data, err := f.read()
	if err != nil {
		return &Error{Reason: ReasonInvalidParam, Param: "file", Message: err.Error(), cause: err}
	}
	var fields [][2]string
	if f.password != "" {
		fields = append(fields, [2]string{"password", f.password})
	}
	raw, err := c.send(ctx, sendInput{method: http.MethodPost, url: c.url(path, nil), auth: true, body: multipartBody(fields, []part{{"file", name, mt, data}}), callOptions: collect(opts)})
	if err != nil {
		return err
	}
	return c.data(raw, out)
}

func (c *core) redirect(ctx context.Context, path string, opts []Option) (string, error) {
	raw, err := c.send(ctx, sendInput{method: http.MethodGet, url: c.url(path, nil), auth: true, noRedirect: true, retrySafe: true, callOptions: collect(opts)})
	if err != nil {
		return "", err
	}
	loc := raw.header.Get("Location")
	if loc == "" {
		return "", &Error{Status: raw.status, Reason: ReasonInternalError, Message: "the API answered without a Location"}
	}
	return loc, nil
}

func (c *core) download(ctx context.Context, signedURL string) ([]byte, error) {
	raw, err := c.send(ctx, sendInput{method: http.MethodGet, url: signedURL, accept: "*/*", retrySafe: true})
	if err != nil {
		return nil, err
	}
	return raw.body, nil
}

// operation sends an operation call: multipart when every file input is
// local, JSON references when none is, and an upload of the local ones first
// when they are mixed.
func (c *core) operation(ctx context.Context, path, inputKind string, main FileInput, files []FileInput, extra map[string]FileInput, params any, raw *rawAnswer, opts []Option) error {
	o := collect(opts)
	pb, err := json.Marshal(params)
	if err != nil {
		return &Error{Reason: ReasonInvalidParam, Message: err.Error(), cause: err}
	}
	options := map[string]any{}
	if err := json.Unmarshal(pb, &options); err != nil {
		return &Error{Reason: ReasonInvalidParam, Message: err.Error(), cause: err}
	}
	type named struct {
		field string
		ref   *fileRef
	}
	var refs []named
	if inputKind == "file" {
		if main == nil {
			return &Error{Reason: ReasonMissingParam, Param: "file", Message: "File is required"}
		}
		refs = append(refs, named{"file", main.ref()})
	}
	var many []*fileRef
	if inputKind == "files" {
		if len(files) == 0 {
			return &Error{Reason: ReasonMissingParam, Param: "files", Message: "Files is required"}
		}
		for _, f := range files {
			many = append(many, f.ref())
		}
	}
	for _, k := range sortedFileFields(extra) {
		if extra[k] != nil {
			refs = append(refs, named{k, extra[k].ref()})
		}
	}
	total, local := len(refs)+len(many), 0
	for _, n := range refs {
		if n.ref.local() {
			local++
		}
	}
	for _, f := range many {
		if f.local() {
			local++
		}
	}
	if local > 0 && local < total {
		up := func(f *fileRef) (*fileRef, error) {
			if !f.local() {
				return f, nil
			}
			var stored StoredFile
			if err := c.upload(ctx, "/v1/files", f, &stored, nil); err != nil {
				return nil, err
			}
			return &fileRef{kind: "id", value: stored.FileID, password: f.password}, nil
		}
		for i := range refs {
			if refs[i].ref, err = up(refs[i].ref); err != nil {
				return err
			}
		}
		for i := range many {
			if many[i], err = up(many[i]); err != nil {
				return err
			}
		}
	}
	var body func() (io.Reader, string, error)
	if local > 0 && local == total {
		var fields [][2]string
		var parts []part
		for _, n := range refs {
			name, mt, data, err := n.ref.read()
			if err != nil {
				return &Error{Reason: ReasonInvalidParam, Param: n.field, Message: err.Error(), cause: err}
			}
			parts = append(parts, part{n.field, name, mt, data})
			if n.field == "file" && n.ref.password != "" {
				fields = append(fields, [2]string{"password", n.ref.password})
			}
		}
		for _, f := range many {
			name, mt, data, err := f.read()
			if err != nil {
				return &Error{Reason: ReasonInvalidParam, Param: "files", Message: err.Error(), cause: err}
			}
			parts = append(parts, part{"files[]", name, mt, data})
		}
		if cb, ok := options["callback_url"].(string); ok {
			fields = append(fields, [2]string{"callback_url", cb})
			delete(options, "callback_url")
		}
		ob, _ := json.Marshal(options)
		fields = append(fields, [2]string{"options", string(ob)})
		body = multipartBody(fields, parts)
	} else {
		payload := options
		for _, n := range refs {
			if n.field == "file" {
				for k, v := range n.ref.reference() {
					payload[k] = v
				}
			} else {
				payload[n.field] = n.ref.reference()
			}
		}
		if many != nil {
			list := make([]map[string]any, len(many))
			for i, f := range many {
				list[i] = f.reference()
			}
			payload["files"] = list
		}
		body = jsonBody(payload)
	}
	q := url.Values{}
	if o.mode != "" {
		q.Set("mode", o.mode)
	}
	r, err := c.send(ctx, sendInput{method: http.MethodPost, url: c.url(path, q), auth: true, body: body, accept: o.accept, callOptions: o})
	if err != nil {
		return err
	}
	*raw = *r
	return nil
}

func sortedFileFields(m map[string]FileInput) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	for i := 1; i < len(out); i++ {
		for j := i; j > 0 && out[j] < out[j-1]; j-- {
			out[j], out[j-1] = out[j-1], out[j]
		}
	}
	return out
}

// toQuery encodes a query struct (its JSON fields) as URL values.
func toQuery(q any) url.Values {
	if q == nil {
		return nil
	}
	b, err := json.Marshal(q)
	if err != nil || string(b) == "null" {
		return nil
	}
	var m map[string]any
	if json.Unmarshal(b, &m) != nil {
		return nil
	}
	out := url.Values{}
	for k, v := range m {
		switch x := v.(type) {
		case nil:
		case string:
			out.Set(k, x)
		case float64:
			out.Set(k, strconv.FormatFloat(x, 'f', -1, 64))
		case bool:
			out.Set(k, strconv.FormatBool(x))
		default:
			jb, _ := json.Marshal(x)
			out.Set(k, string(jb))
		}
	}
	return out
}

func (c *core) waitForJob(ctx context.Context, jobID string, opts []WaitOption) (*Job, error) {
	w := waitOptions{timeout: 5 * time.Minute, maxInterval: 10 * time.Second}
	for _, o := range opts {
		o(&w)
	}
	deadline := time.Now().Add(w.timeout)
	for {
		raw, err := c.send(ctx, sendInput{method: http.MethodGet, url: c.url("/v1/jobs/"+url.PathEscape(jobID), nil), auth: true, retrySafe: true})
		if err != nil {
			return nil, err
		}
		var job Job
		if err := c.data(raw, &job); err != nil {
			return nil, err
		}
		switch job.Status {
		case "succeeded":
			return &job, nil
		case "failed", "cancelled":
			ae := &Error{Status: 409, Reason: ReasonInvalidState, Message: sprintf("job %s was %s", jobID, job.Status)}
			if e := job.Error; e != nil {
				ae.Status, ae.Reason, ae.Message, ae.Param, ae.Details, ae.DocURL, ae.Retryable = e.Code, ErrorReason(e.Reason), e.Message, deref(e.Param), e.Details, e.DocURL, e.Retryable
			}
			ae.RequestID = raw.header.Get("X-Request-Id")
			return nil, &JobFailedError{Err: ae, Job: &job}
		}
		interval := 2 * time.Second
		if n, err := strconv.ParseFloat(raw.header.Get("Retry-After"), 64); err == nil {
			interval = time.Duration(n * float64(time.Second))
		}
		left := time.Until(deadline)
		if left <= 0 {
			return nil, &TimeoutError{JobID: jobID, Timeout: w.timeout}
		}
		if err := pause(ctx, min(interval, w.maxInterval, left)); err != nil {
			return nil, err
		}
	}
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// NewIdempotencyKey returns a random key: store it with your record before
// calling, and reuse it on retries.
func NewIdempotencyKey() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

var errNoResult = errors.New("lowco api: the answer carries bytes, not a result")
