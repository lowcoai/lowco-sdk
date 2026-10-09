package main

import (
	"bytes"
	"fmt"
	"go/format"
	"strings"
)

var goInitialisms = map[string]string{"pdf": "PDF", "ocr": "OCR", "qr": "QR", "docai": "DocAI", "id": "ID", "url": "URL", "upi": "UPI", "irn": "IRN",
	"gstin": "GSTIN", "pan": "PAN", "ifsc": "IFSC", "hsn": "HSN", "html": "HTML", "json": "JSON", "csv": "CSV", "dpi": "DPI", "kb": "KB", "mb": "MB", "mm": "MM",
	"ip": "IP", "ips": "IPs", "api": "API", "ecc": "ECC", "ssid": "SSID", "pdfa": "PDFA", "xlsx": "XLSX", "docx": "DOCX", "hocr": "HOCR", "sha256": "SHA256"}

// goField names a JSON field in Go: snake parts PascalCased with initialisms.
func goField(name string) string {
	var b strings.Builder
	for _, part := range strings.FieldsFunc(name, func(r rune) bool { return r == '_' || r == '-' || r == '[' || r == ']' || r == '.' }) {
		if v, ok := goInitialisms[strings.ToLower(part)]; ok {
			b.WriteString(v)
			continue
		}
		b.WriteString(strings.ToUpper(part[:1]) + part[1:])
	}
	out := b.String()
	if out == "" || out[0] >= '0' && out[0] <= '9' {
		out = "F" + out
	}
	return out
}

func goType(t *Type, optional bool) string {
	var s string
	ptr := optional || t.Nullable
	switch t.Kind {
	case "ref":
		s = t.Ref
	case "object":
		s = "map[string]any"
		ptr = false
		if t.Name != "" {
			s = t.Name
			ptr = optional || t.Nullable
		}
	case "array":
		return "[]" + goType(t.Items, false)
	case "map":
		return "map[string]" + goType(t.Values, false)
	case "string", "enum":
		s = "string"
	case "integer":
		s = "int"
	case "number":
		s = "float64"
	case "boolean":
		s = "bool"
	case "file":
		return "FileInput"
	default:
		return "any"
	}
	if ptr {
		return "*" + s
	}
	return s
}

func goComment(b *strings.Builder, indent, desc string) {
	desc = strings.TrimSpace(desc)
	if desc == "" {
		return
	}
	for _, line := range strings.Split(desc, "\n") {
		fmt.Fprintf(b, "%s// %s\n", indent, line)
	}
}

func enumDoc(t *Type) string {
	if t.Kind == "enum" {
		return "One of: " + strings.Join(t.Enum, ", ") + "."
	}
	if len(t.IntEnum) > 0 {
		var v []string
		for _, n := range t.IntEnum {
			v = append(v, fmt.Sprint(n))
		}
		return "One of: " + strings.Join(v, ", ") + "."
	}
	return ""
}

func emitGo(m *Model) []byte {
	var b strings.Builder
	fmt.Fprintf(&b, "// "+header+"\n\npackage api\n\nimport (\n\t\"context\"\n\t\"net/http\"\n\t\"net/url\"\n)\n\n", m.Version)
	fmt.Fprintf(&b, "// APIVersion is the Lowco API version these types were generated from.\nconst APIVersion = %q\n\n", m.Version)
	b.WriteString("// ErrorReason is the stable error.reason of every Lowco API error (docs.lowco.ai/api/errors).\ntype ErrorReason string\n\n// Every error.reason the API can answer.\nconst (\n")
	for _, r := range m.Reasons {
		fmt.Fprintf(&b, "\t// Reason%s (HTTP %d): %s\n\tReason%s ErrorReason = %q\n", goField(r.Name), r.Status, r.When, goField(r.Name), r.Name)
	}
	b.WriteString(")\n\n// ReasonInfo says when a reason is answered and what to do.\ntype ReasonInfo struct {\n\tStatus int\n\tWhen   string\n\tAction string\n}\n\n")
	b.WriteString("// ErrorReasons describes every reason.\nvar ErrorReasons = map[ErrorReason]ReasonInfo{\n")
	for _, r := range m.Reasons {
		fmt.Fprintf(&b, "\tReason%s: {%d, %q, %q},\n", goField(r.Name), r.Status, r.When, r.Action)
	}
	b.WriteString("}\n\n")

	for _, name := range m.typeNames() {
		t := m.Types[name]
		goComment(&b, "", t.Desc)
		if t.Kind != "object" {
			if t.Desc == "" {
				fmt.Fprintf(&b, "// %s is a Lowco API value.\n", name)
			}
			fmt.Fprintf(&b, "type %s = %s\n\n", name, strings.TrimPrefix(goType(t, false), "*"))
			continue
		}
		if t.Desc == "" {
			fmt.Fprintf(&b, "// %s is a Lowco API object.\n", name)
		}
		fmt.Fprintf(&b, "type %s struct {\n", name)
		for _, f := range t.Fields {
			doc := strings.TrimSpace(strings.TrimSpace(f.Desc) + " " + enumDoc(f.Type))
			goComment(&b, "\t", doc)
			tag := f.Name
			if !f.Required || f.Type.Kind == "file" {
				tag += ",omitempty"
			}
			if f.Type.Kind == "file" || (f.Type.Kind == "array" && f.Type.Items.Kind == "file") {
				tag = "-"
			}
			fmt.Fprintf(&b, "\t%s %s `json:%q`\n", goField(f.Name), goType(f.Type, !f.Required && f.Type.Kind != "array" && f.Type.Kind != "map"), tag)
		}
		b.WriteString("}\n\n")
	}

	for _, svc := range m.services() {
		cls := goField(svc) + "Service"
		fmt.Fprintf(&b, "// %s calls the /v1/%s operations.\ntype %s struct{ c *core }\n\n", cls, svc, cls)
		for _, o := range m.Ops {
			if o.Service != svc {
				continue
			}
			goComment(&b, "", fmt.Sprintf("%s: %s. %s Meter %s; scope %s.", goField(o.Name), o.Summary, modeNote(o), o.Meter, o.Scope))
			fmt.Fprintf(&b, "func (s *%s) %s(ctx context.Context, p %s, opts ...CallOption) (*Answer[%s], error) {\n", cls, goField(o.Name), o.Params.Name, o.Result)
			main := "nil"
			var files string = "nil"
			switch o.Input {
			case "file":
				main = "p.File"
			case "files":
				files = "p.Files"
			}
			extra := "nil"
			if len(o.Extra) > 0 {
				var parts []string
				for _, x := range o.Extra {
					parts = append(parts, fmt.Sprintf("%q: p.%s", x, goField(x)))
				}
				extra = "map[string]FileInput{" + strings.Join(parts, ", ") + "}"
			}
			fmt.Fprintf(&b, "\tvar out Answer[%s]\n\terr := s.c.operation(ctx, %q, %q, %s, %s, %s, p, &out.raw, opts)\n\tif err != nil {\n\t\treturn nil, err\n\t}\n\treturn out.decode(s.c)\n}\n\n", o.Result, o.Path, o.Input, main, files, extra)
		}
	}

	for _, g := range m.groups() {
		cls := goField(g) + "Resource"
		fmt.Fprintf(&b, "// %s: %s.\ntype %s struct{ c *core }\n\n", cls, groupDoc(g), cls)
		for _, e := range m.Endpoints {
			if e.Group != g {
				continue
			}
			var args []string
			args = append(args, "ctx context.Context")
			pathExpr := fmt.Sprintf("%q", e.Path)
			if len(e.PathParams) > 0 {
				var vals []string
				p := e.Path
				for _, pp := range e.PathParams {
					args = append(args, camel(pp)+" string")
					p = strings.Replace(p, "{"+pp+"}", "%s", 1)
					vals = append(vals, "url.PathEscape("+camel(pp)+")")
				}
				pathExpr = fmt.Sprintf("sprintf(%q, %s)", p, strings.Join(vals, ", "))
			}
			result := "struct{}"
			if e.Result != nil {
				result = strings.TrimPrefix(goType(e.Result, false), "*")
			}
			name := goField(snake(e.Method))
			goComment(&b, "", fmt.Sprintf("%s: %s.", name, e.Summary))
			switch {
			case e.Multipart:
				fmt.Fprintf(&b, "func (r *%s) %s(ctx context.Context, file FileInput, opts ...RequestOption) (*%s, error) {\n\tvar out %s\n\treturn &out, r.c.upload(ctx, %s, file, &out, opts)\n}\n\n", cls, name, result, result, pathExpr)
				continue
			case e.Redirect:
				fmt.Fprintf(&b, "func (r *%s) %s(%s, opts ...RequestOption) (string, error) {\n\treturn r.c.redirect(ctx, %s, opts)\n}\n\n", cls, name, strings.Join(args, ", "), pathExpr)
				continue
			}
			body := "nil"
			if e.Body != nil {
				args = append(args, "body "+strings.TrimPrefix(goType(e.Body, false), "*"))
				body = "body"
			}
			query := "nil"
			if e.Query != nil {
				args = append(args, "query *"+e.Query.Name)
				query = "query"
			}
			args = append(args, "opts ...RequestOption")
			method := map[string]string{"GET": "http.MethodGet", "POST": "http.MethodPost", "PATCH": "http.MethodPatch", "DELETE": "http.MethodDelete", "PUT": "http.MethodPut"}[e.HTTP]
			fmt.Fprintf(&b, "func (r *%s) %s(%s) (*%s, error) {\n\tvar out %s\n\tif err := r.c.call(ctx, %s, %s, toQuery(%s), %s, &out, opts); err != nil {\n\t\treturn nil, err\n\t}\n\treturn &out, nil\n}\n\n",
				cls, name, strings.Join(args, ", "), result, result, method, pathExpr, query, body)
			if e.Paged != nil {
				item := strings.TrimPrefix(goType(e.Paged, false), "*")
				var pargs []string
				pargs = append(pargs, "ctx context.Context")
				for _, pp := range e.PathParams {
					pargs = append(pargs, camel(pp)+" string")
				}
				q := "nil"
				if e.Query != nil {
					pargs = append(pargs, "query *"+e.Query.Name)
					q = "query"
				}
				pargs = append(pargs, "opts ...RequestOption")
				goComment(&b, "", fmt.Sprintf("%sAll pages through %s, following next_cursor.", name, name))
				fmt.Fprintf(&b, "func (r *%s) %sAll(%s) *Pager[%s] {\n\treturn newPager[%s](r.c, %s, toQuery(%s), opts)\n}\n\n", cls, name, strings.Join(pargs, ", "), item, item, pathExpr, q)
			}
		}
		switch g {
		case "jobs":
			b.WriteString("// Wait polls the job until it is succeeded, failed or cancelled, honouring the Retry-After the API sends. A failed or cancelled job is a *JobFailedError; the timeout (WithWaitTimeout, default 5 minutes) a *TimeoutError.\nfunc (r *JobsResource) Wait(ctx context.Context, jobID string, opts ...WaitOption) (*Job, error) {\n\treturn r.c.waitForJob(ctx, jobID, opts)\n}\n\n")
		case "files":
			b.WriteString("// Download fetches a file object's signed url (no API key is sent).\nfunc (r *FilesResource) Download(ctx context.Context, signedURL string) ([]byte, error) {\n\treturn r.c.download(ctx, signedURL)\n}\n\n")
		}
	}

	b.WriteString("// services holds every operation and resource group of the Lowco API.\ntype services struct {\n")
	for _, svc := range m.services() {
		fmt.Fprintf(&b, "\t// %s calls the /v1/%s operations.\n\t%s *%sService\n", goField(svc), svc, goField(svc), goField(svc))
	}
	for _, g := range m.groups() {
		fmt.Fprintf(&b, "\t// %s: %s.\n\t%s *%sResource\n", goField(g), groupDoc(g), goField(g), goField(g))
	}
	b.WriteString("}\n\nfunc newServices(c *core) services {\n\treturn services{\n")
	for _, svc := range m.services() {
		fmt.Fprintf(&b, "\t\t%s: &%sService{c},\n", goField(svc), goField(svc))
	}
	for _, g := range m.groups() {
		fmt.Fprintf(&b, "\t\t%s: &%sResource{c},\n", goField(g), goField(g))
	}
	b.WriteString("\t}\n}\n")
	src := []byte(b.String())
	out, err := format.Source(src)
	if err != nil {
		// keep the unformatted source so the compiler shows the problem
		return bytes.Join([][]byte{[]byte("// gofmt: " + err.Error() + "\n"), src}, nil)
	}
	return out
}
