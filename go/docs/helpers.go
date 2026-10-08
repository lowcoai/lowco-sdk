package docs

import (
	"bytes"
	"fmt"
	"io"
	"math"
	"mime"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Bool returns a pointer to v, for optional boolean fields such as
// FolderListParams.Sizes and FolderConfigRequest.Active.
func Bool(v bool) *bool {
	return &v
}

// basePath is the route prefix of every document API route except /health.
const basePath = "/v1/documents"

type partKind int

const (
	partLiteral partKind = iota
	partParam
	partWildcard
)

// pathPart is one element of an API path: a literal segment, a single-segment
// parameter or a wildcard ({path}) parameter.
type pathPart struct {
	kind  partKind
	name  string
	value string
}

func lit(segment string) pathPart { return pathPart{kind: partLiteral, value: segment} }

func param(name, value string) pathPart { return pathPart{kind: partParam, name: name, value: value} }

func wildcard(name, value string) pathPart {
	return pathPart{kind: partWildcard, name: name, value: value}
}

// buildPath joins parts under basePath. Single-segment parameters are fully
// percent-encoded (encodeURIComponent semantics); wildcard parameters lose
// their leading "/" and have each segment encoded with "/" kept. Empty
// parameters and "." or ".." segments fail with an *Error before anything
// is sent.
func buildPath(parts ...pathPart) (string, error) {
	var b strings.Builder
	b.WriteString(basePath)
	for _, part := range parts {
		switch part.kind {
		case partLiteral:
			b.WriteByte('/')
			b.WriteString(part.value)
		case partParam:
			if strings.TrimSpace(part.value) == "" {
				return "", argumentError(part.name)
			}
			if isDotSegment(part.value) {
				return "", dotSegmentError(part.name)
			}
			b.WriteByte('/')
			b.WriteString(encodeComponent(part.value))
		case partWildcard:
			value := strings.TrimLeft(part.value, "/")
			if strings.TrimSpace(value) == "" {
				return "", argumentError(part.name)
			}
			for _, segment := range strings.Split(value, "/") {
				if isDotSegment(segment) {
					return "", dotSegmentError(part.name)
				}
			}
			b.WriteByte('/')
			b.WriteString(encodeWildcard(value))
		}
	}
	return b.String(), nil
}

// isDotSegment reports a "." or ".." segment, which URL normalisation would
// resolve into a different route; such paths are rejected before sending.
func isDotSegment(segment string) bool {
	return segment == "." || segment == ".."
}

// encodeComponent percent-encodes s like JavaScript's encodeURIComponent:
// every byte except A-Z a-z 0-9 - _ . ! ~ * ' ( ) is escaped.
func encodeComponent(s string) string {
	const hex = "0123456789ABCDEF"
	var b strings.Builder
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if isUnreservedComponent(c) {
			b.WriteByte(c)
			continue
		}
		b.WriteByte('%')
		b.WriteByte(hex[c>>4])
		b.WriteByte(hex[c&0x0f])
	}
	return b.String()
}

func isUnreservedComponent(c byte) bool {
	switch {
	case 'a' <= c && c <= 'z', 'A' <= c && c <= 'Z', '0' <= c && c <= '9':
		return true
	}
	switch c {
	case '-', '_', '.', '!', '~', '*', '\'', '(', ')':
		return true
	}
	return false
}

// encodeWildcard encodes each "/"-separated segment of p and keeps the
// separators.
func encodeWildcard(p string) string {
	segments := strings.Split(p, "/")
	for i, segment := range segments {
		segments[i] = encodeComponent(segment)
	}
	return strings.Join(segments, "/")
}

// requireValue fails with an *Error when a required argument is empty.
func requireValue(name, value string) error {
	if strings.TrimSpace(value) == "" {
		return argumentError(name)
	}
	return nil
}

// query collects query parameters, omitting unset values.
type query url.Values

func (q query) str(key, value string) {
	if value != "" {
		url.Values(q).Set(key, value)
	}
}

func (q query) int(key string, value int) {
	if value != 0 {
		url.Values(q).Set(key, strconv.Itoa(value))
	}
}

func (q query) optBool(key string, value *bool) {
	if value != nil {
		url.Values(q).Set(key, strconv.FormatBool(*value))
	}
}

// flag sets key=1 when value is true.
func (q query) flag(key string, value bool) {
	if value {
		url.Values(q).Set(key, "1")
	}
}

// multipartForm builds a multipart/form-data body in memory.
type multipartForm struct {
	buf    bytes.Buffer
	writer *multipart.Writer
	err    error
}

func newMultipartForm() *multipartForm {
	m := &multipartForm{}
	m.writer = multipart.NewWriter(&m.buf)
	return m
}

var quoteEscaper = strings.NewReplacer("\\", "\\\\", `"`, "\\\"")

// file adds a file part under field.
func (m *multipartForm) file(field string, f UploadFile) {
	if m.err != nil {
		return
	}
	if strings.TrimSpace(f.FileName) == "" {
		m.err = argumentError("file name")
		return
	}
	contentType := f.ContentType
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	header := make(textproto.MIMEHeader)
	header.Set("Content-Disposition", fmt.Sprintf(`form-data; name="%s"; filename="%s"`,
		quoteEscaper.Replace(field), quoteEscaper.Replace(f.FileName)))
	header.Set("Content-Type", contentType)
	part, err := m.writer.CreatePart(header)
	if err != nil {
		m.err = err
		return
	}
	_, m.err = part.Write(f.Data)
}

// field adds a text field; empty values are omitted.
func (m *multipartForm) field(name, value string) {
	if m.err != nil || value == "" {
		return
	}
	m.err = m.writer.WriteField(name, value)
}

// finish closes the form and returns its body and content type.
func (m *multipartForm) finish() (io.Reader, string, error) {
	if m.err != nil {
		return nil, "", m.err
	}
	if err := m.writer.Close(); err != nil {
		return nil, "", err
	}
	return bytes.NewReader(m.buf.Bytes()), m.writer.FormDataContentType(), nil
}

// binaryFrom builds a Binary from a response and its body.
func binaryFrom(resp *http.Response, data []byte) Binary {
	return Binary{
		Data:        data,
		ContentType: resp.Header.Get("Content-Type"),
		FileName:    fileNameFrom(resp.Header),
	}
}

// fileNameFrom reads X-File-Name, else the Content-Disposition filename.
func fileNameFrom(h http.Header) string {
	if name := strings.TrimSpace(h.Get("X-File-Name")); name != "" {
		return name
	}
	disposition := h.Get("Content-Disposition")
	if disposition == "" {
		return ""
	}
	if _, params, err := mime.ParseMediaType(disposition); err == nil {
		if name := params["filename"]; name != "" {
			return name
		}
	}
	// Lenient fallback for headers mime rejects.
	const marker = `filename="`
	if i := strings.Index(disposition, marker); i >= 0 {
		rest := disposition[i+len(marker):]
		if j := strings.IndexByte(rest, '"'); j >= 0 {
			return rest[:j]
		}
	}
	return ""
}

// parseRetryAfter reads a Retry-After header given in seconds or as an HTTP
// date; it returns 0 when absent or invalid.
func parseRetryAfter(value string) int {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0
	}
	if seconds, err := strconv.Atoi(value); err == nil {
		if seconds < 0 {
			return 0
		}
		return seconds
	}
	if at, err := http.ParseTime(value); err == nil {
		if d := time.Until(at); d > 0 {
			return int(math.Ceil(d.Seconds()))
		}
	}
	return 0
}

func isRedirect(status int) bool {
	switch status {
	case http.StatusMovedPermanently, http.StatusFound, http.StatusSeeOther,
		http.StatusTemporaryRedirect, http.StatusPermanentRedirect:
		return true
	}
	return false
}

func isSuccess(status int) bool {
	return status >= http.StatusOK && status < http.StatusMultipleChoices
}
