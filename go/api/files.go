package api

import (
	"io"
	"mime"
	"os"
	"path/filepath"
)

// FileInput is one file input: build it with FilePath, FileBytes,
// FileReader, FileURL, FileID or FileBase64. Local inputs (path, bytes,
// reader) are sent as multipart parts; remote ones by reference.
type FileInput interface{ ref() *fileRef }

type fileRef struct {
	kind     string // path, bytes, reader, url, id, base64
	path     string
	data     []byte
	reader   io.Reader
	value    string
	filename string
	mimeType string
	password string
}

func (f *fileRef) ref() *fileRef { return f }

func (f *fileRef) local() bool { return f.kind == "path" || f.kind == "bytes" || f.kind == "reader" }

// FileOption sets a file input's name, type or PDF password.
type FileOption func(*fileRef)

// WithFilename names the stored input.
func WithFilename(name string) FileOption { return func(f *fileRef) { f.filename = name } }

// WithMimeType sets the part's content type.
func WithMimeType(t string) FileOption { return func(f *fileRef) { f.mimeType = t } }

// WithPassword opens a protected PDF (never stored or logged).
func WithPassword(p string) FileOption { return func(f *fileRef) { f.password = p } }

func build(f *fileRef, opts []FileOption) FileInput {
	for _, o := range opts {
		o(f)
	}
	return f
}

// FilePath is a local file, read when the call is made.
func FilePath(path string, opts ...FileOption) FileInput {
	return build(&fileRef{kind: "path", path: path}, opts)
}

// FileBytes is a file in memory.
func FileBytes(data []byte, opts ...FileOption) FileInput {
	return build(&fileRef{kind: "bytes", data: data}, opts)
}

// FileReader is read to the end when the call is made.
func FileReader(r io.Reader, opts ...FileOption) FileInput {
	return build(&fileRef{kind: "reader", reader: r}, opts)
}

// FileURL is a public https URL the API fetches (file_url).
func FileURL(u string, opts ...FileOption) FileInput {
	return build(&fileRef{kind: "url", value: u}, opts)
}

// FileID is a stored file (file_id from Files.Upload or an earlier output).
func FileID(id string, opts ...FileOption) FileInput {
	return build(&fileRef{kind: "id", value: id}, opts)
}

// FileBase64 is base64 or a data: URL (up to 5 MB decoded).
func FileBase64(b64 string, opts ...FileOption) FileInput {
	return build(&fileRef{kind: "base64", value: b64}, opts)
}

// read returns a local input's name, type and bytes.
func (f *fileRef) read() (string, string, []byte, error) {
	var data []byte
	name := f.filename
	switch f.kind {
	case "path":
		b, err := os.ReadFile(f.path)
		if err != nil {
			return "", "", nil, err
		}
		data = b
		if name == "" {
			name = filepath.Base(f.path)
		}
	case "bytes":
		data = f.data
	case "reader":
		b, err := io.ReadAll(f.reader)
		if err != nil {
			return "", "", nil, err
		}
		data = b
	}
	if name == "" {
		name = "file"
	}
	mt := f.mimeType
	if mt == "" {
		mt = mime.TypeByExtension(filepath.Ext(name))
	}
	if mt == "" {
		mt = "application/octet-stream"
	}
	return name, mt, data, nil
}

// reference is a remote input's JSON fields.
func (f *fileRef) reference() map[string]any {
	out := map[string]any{}
	switch f.kind {
	case "url":
		out["file_url"] = f.value
	case "id":
		out["file_id"] = f.value
	case "base64":
		out["file_base64"] = f.value
		if f.filename != "" {
			out["filename"] = f.filename
		}
	}
	if f.password != "" {
		out["password"] = f.password
	}
	return out
}
