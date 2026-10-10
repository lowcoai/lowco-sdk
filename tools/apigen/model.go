package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
	"unicode"
)

type obj = map[string]any

// Type is a schema in the generator's terms.
type Type struct {
	Kind     string // object, array, map, string, integer, number, boolean, any, ref, enum, union
	Name     string // named types (components and inline objects)
	Ref      string // Kind ref: the named type
	Fields   []*Field
	Items    *Type
	Values   *Type
	Enum     []string
	IntEnum  []int
	Union    []*Type
	Nullable bool
	Desc     string
	Format   string
}

// Field is one property of an object.
type Field struct {
	Name     string
	Type     *Type
	Required bool
	Desc     string
}

// Op is one Lowco API operation (POST /v1/{service}/{operation}).
type Op struct {
	Service     string
	Name        string // operation, e.g. to-images
	OperationID string
	Path        string
	Summary     string
	Description string
	Input       string // file, files, none
	Extra       []string
	Params      *Type // the options plus the file inputs, wire names
	Result      string
	DefaultMode string
	Status      string
	Meter       string
	Scope       string
	Binary      []string // media types the single output can be answered as
	Deprecated  bool
}

// Endpoint is one resource route (files, jobs, webhooks, …).
type Endpoint struct {
	Group       string
	Method      string
	OperationID string
	HTTP        string
	Path        string
	PathParams  []string
	Query       *Type
	Body        *Type
	Result      *Type
	Status      string // the success status
	Paged       *Type  // the item type of a page answer
	Summary     string
	Multipart   bool
	Redirect    bool
}

// Reason is one error.reason.
type Reason struct {
	Name   string
	Status int
	When   string
	Action string
}

// Model is everything the emitters need.
type Model struct {
	Version   string
	Types     map[string]*Type
	Order     []string
	Ops       []*Op
	Endpoints []*Endpoint
	Reasons   []Reason
	raw       obj
}

// fileKeys are the main file input's wire fields.
var fileKeys = map[string]bool{"file_id": true, "file_url": true, "file_base64": true, "filename": true, "password": true}

// resourceNames maps operationIds to SDK groups and methods.
var resourceNames = map[string][2]string{
	"files_upload": {"files", "upload"}, "files_get": {"files", "get"}, "files_delete": {"files", "delete"},
	"files_content": {"files", "contentUrl"},
	"jobs_list":     {"jobs", "list"}, "jobs_get": {"jobs", "get"}, "jobs_cancel": {"jobs", "cancel"}, "jobs_events": {"jobs", "events"},
	"requests_get":    {"requests", "get"},
	"webhooks_create": {"webhooks", "create"}, "webhooks_list": {"webhooks", "list"}, "webhooks_get": {"webhooks", "get"},
	"webhooks_update": {"webhooks", "update"}, "webhooks_delete": {"webhooks", "delete"}, "webhooks_ping": {"webhooks", "ping"},
	"webhooks_deliveries": {"webhooks", "listDeliveries"}, "webhooks_retry": {"webhooks", "retryDelivery"}, "webhooks_delivery": {"webhooks", "getDelivery"},
	"webhooks_callback_secret": {"webhooks", "rollCallbackSecret"},
	"render_templates_create":  {"templates", "create"}, "render_templates_list": {"templates", "list"},
	"render_templates_get": {"templates", "get"}, "render_templates_update": {"templates", "update"},
	"render_templates_delete": {"templates", "delete"}, "render_templates_versions": {"templates", "listVersions"},
	"render_templates_pin": {"templates", "pin"}, "render_templates_unpin": {"templates", "unpin"},
	"settings_get": {"settings", "get"}, "settings_update": {"settings", "update"}, "settings_purge": {"settings", "purge"}, "data_handling": {"settings", "dataHandling"},
	"usage_get": {"usage", "get"}, "usage_alerts": {"usage", "alerts"}, "overview": {"usage", "overview"},
	"audit_list": {"audit", "list"}, "verify_audit_list": {"audit", "listVerify"},
	"keys_list": {"keys", "list"}, "keys_validate": {"keys", "validate"}, "keys_sync": {"keys", "sync"},
	"sign_requests_create": {"sign", "create"}, "sign_requests_list": {"sign", "list"}, "sign_requests_get": {"sign", "get"},
	"sign_requests_send": {"sign", "send"}, "sign_requests_remind": {"sign", "remind"}, "sign_requests_void": {"sign", "void"},
	"sign_requests_events": {"sign", "events"}, "sign_requests_audit": {"sign", "audit"},
	"sign_requests_signer_link": {"sign", "signerLink"}, "sign_requests_signer_update": {"sign", "updateSigner"},
	"sign_requests_signed_document": {"sign", "signedDocumentUrl"}, "sign_requests_certificate": {"sign", "certificateUrl"},
	"sign_templates_create": {"signTemplates", "create"}, "sign_templates_list": {"signTemplates", "list"},
	"sign_templates_get": {"signTemplates", "get"}, "sign_templates_update": {"signTemplates", "update"},
	"sign_templates_delete": {"signTemplates", "delete"}, "sign_templates_request": {"signTemplates", "createRequest"},
	"sign_templates_bulk": {"signTemplates", "bulkSend"},
	// The Communication API (COM-01).
	"messages_send": {"messages", "send"}, "messages_batch": {"messages", "sendBatch"}, "messages_list": {"messages", "list"},
	"messages_get": {"messages", "get"}, "messages_cancel": {"messages", "cancel"},
	"message_templates_create": {"messageTemplates", "create"}, "message_templates_list": {"messageTemplates", "list"},
	"message_templates_get": {"messageTemplates", "get"}, "message_templates_update": {"messageTemplates", "update"},
	"message_templates_delete": {"messageTemplates", "delete"},
	"message_senders_create":   {"senders", "create"}, "message_senders_list": {"senders", "list"}, "message_senders_get": {"senders", "get"},
	"message_senders_delete": {"senders", "delete"}, "message_senders_verify": {"senders", "verify"},
	"message_suppressions_create": {"suppressions", "create"}, "message_suppressions_list": {"suppressions", "list"},
	"message_suppressions_delete": {"suppressions", "delete"},
	"otp_send":                    {"otp", "send"}, "otp_verify": {"otp", "verify"}, "otp_resend": {"otp", "resend"},
}

// skipped operationIds: the signed download is a plain URL (Client.download);
// the signer link's routes are the signer page's, not a developer's.
var skipped = map[string]bool{"files_download": true, "sign_session_open": true, "sign_session_state": true, "sign_session_otp": true,
	"sign_session_otp_verify": true, "sign_session_viewed": true, "sign_session_sign": true, "sign_session_decline": true,
	"sign_session_document": true, "sign_session_logo": true, "sign_session_page": true,
	// Carriers and recipients call these, not developers (COM-02).
	"messages_receipts": true, "messages_receipts_challenge": true, "messages_unsubscribe_page": true, "messages_unsubscribe": true}

func load(path string) (*Model, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var raw obj
	if err := json.Unmarshal(b, &raw); err != nil {
		return nil, err
	}
	m := &Model{Types: map[string]*Type{}, raw: raw}
	m.Version = str(raw["info"].(obj)["version"])
	schemas := raw["components"].(obj)["schemas"].(obj)
	for _, name := range sortedKeys(schemas) {
		m.named(name, schemas[name].(obj))
	}
	errSchema := schemas["Error"].(obj)
	reasons := errSchema["x-lowco-reasons"].(obj)
	for _, r := range sortedKeys(reasons) {
		d := reasons[r].(obj)
		m.Reasons = append(m.Reasons, Reason{Name: r, Status: int(d["status"].(float64)), When: str(d["when"]), Action: str(d["action"])})
	}
	paths := raw["paths"].(obj)
	for _, p := range sortedKeys(paths) {
		item := paths[p].(obj)
		for _, method := range sortedKeys(item) {
			op := item[method].(obj)
			id := str(op["operationId"])
			if skipped[id] {
				continue
			}
			if _, isOp := op["x-lowco-test-fixture"]; isOp {
				if p == "/v1/pdf" {
					continue // the deprecated alias is not offered by the SDKs
				}
				o, err := m.operation(p, op)
				if err != nil {
					return nil, err
				}
				m.Ops = append(m.Ops, o)
				continue
			}
			e, err := m.endpoint(strings.ToUpper(method), p, op)
			if err != nil {
				return nil, err
			}
			m.Endpoints = append(m.Endpoints, e)
		}
	}
	m.applyRenames()
	sort.Slice(m.Ops, func(i, j int) bool { return m.Ops[i].Path < m.Ops[j].Path })
	sort.Slice(m.Endpoints, func(i, j int) bool {
		if m.Endpoints[i].Group != m.Endpoints[j].Group {
			return m.Endpoints[i].Group < m.Endpoints[j].Group
		}
		return m.Endpoints[i].Method < m.Endpoints[j].Method
	})
	return m, nil
}

func str(v any) string { s, _ := v.(string); return s }

func sortedKeys(m obj) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// named registers a component schema (or an inline object) as a named type.
func (m *Model) named(name string, s obj) *Type {
	if t, ok := m.Types[name]; ok {
		return t
	}
	t := &Type{Name: name}
	m.Types[name] = t
	m.Order = append(m.Order, name)
	parsed := m.parse(s, name)
	*t = *parsed
	t.Name = name
	return t
}

// parse turns a schema into a Type; inline objects get names from hint.
func (m *Model) parse(s obj, hint string) *Type {
	if s == nil {
		return &Type{Kind: "any"}
	}
	desc := str(s["description"])
	nullable, _ := s["nullable"].(bool)
	if r, ok := s["$ref"].(string); ok {
		return &Type{Kind: "ref", Ref: refName(r), Desc: desc}
	}
	if all, ok := s["allOf"].([]any); ok && len(all) == 1 {
		t := m.parse(all[0].(obj), hint)
		t.Nullable = t.Nullable || nullable
		if desc != "" {
			t.Desc = desc
		}
		return t
	}
	if one, ok := s["oneOf"].([]any); ok && s["type"] == nil && s["properties"] == nil {
		u := &Type{Kind: "union", Nullable: nullable, Desc: desc}
		for i, b := range one {
			u.Union = append(u.Union, m.parse(b.(obj), fmt.Sprintf("%sOption%d", hint, i+1)))
		}
		return u
	}
	typ := str(s["type"])
	switch {
	case typ == "object" || s["properties"] != nil:
		props, _ := s["properties"].(obj)
		if len(props) == 0 {
			if ap, ok := s["additionalProperties"].(obj); ok {
				return &Type{Kind: "map", Values: m.parse(ap, hint+"Value"), Nullable: nullable, Desc: desc}
			}
			return &Type{Kind: "map", Values: &Type{Kind: "any"}, Nullable: nullable, Desc: desc}
		}
		req := map[string]bool{}
		if rl, ok := s["required"].([]any); ok {
			for _, r := range rl {
				req[r.(string)] = true
			}
		}
		t := &Type{Kind: "object", Nullable: nullable, Desc: desc}
		for _, k := range sortedKeys(props) {
			p := props[k].(obj)
			ft := m.parse(p, hint+pascal(k))
			if ft.Kind == "object" && ft.Name == "" {
				name := hint + pascal(k)
				m.Types[name] = ft
				m.Order = append(m.Order, name)
				ft.Name = name
				ft = &Type{Kind: "ref", Ref: name, Nullable: ft.Nullable}
			}
			if ft.Kind == "array" && ft.Items.Kind == "object" && ft.Items.Name == "" {
				name := hint + pascal(singular(k))
				it := ft.Items
				it.Name = name
				m.Types[name] = it
				m.Order = append(m.Order, name)
				ft.Items = &Type{Kind: "ref", Ref: name}
			}
			t.Fields = append(t.Fields, &Field{Name: k, Type: ft, Required: req[k], Desc: str(p["description"])})
		}
		return t
	case typ == "array":
		items, _ := s["items"].(obj)
		return &Type{Kind: "array", Items: m.parse(items, hint+"Item"), Nullable: nullable, Desc: desc}
	case s["enum"] != nil && typ == "string":
		t := &Type{Kind: "enum", Nullable: nullable, Desc: desc}
		for _, v := range s["enum"].([]any) {
			t.Enum = append(t.Enum, v.(string))
		}
		return t
	case s["enum"] != nil && typ == "integer":
		t := &Type{Kind: "integer", Nullable: nullable, Desc: desc}
		for _, v := range s["enum"].([]any) {
			t.IntEnum = append(t.IntEnum, int(v.(float64)))
		}
		return t
	case typ == "string" || typ == "integer" || typ == "number" || typ == "boolean":
		return &Type{Kind: typ, Nullable: nullable, Desc: desc, Format: str(s["format"])}
	}
	return &Type{Kind: "any", Nullable: true, Desc: desc}
}

func refName(r string) string { return r[strings.LastIndex(r, "/")+1:] }

func singular(s string) string {
	switch {
	case strings.HasSuffix(s, "ies"):
		return s[:len(s)-3] + "y"
	case strings.HasSuffix(s, "ses"):
		return s[:len(s)-2]
	case strings.HasSuffix(s, "s") && !strings.HasSuffix(s, "ss"):
		return s[:len(s)-1]
	}
	return s + "Item"
}

// pascal turns snake, kebab or dotted words into PascalCase.
func pascal(s string) string {
	var b strings.Builder
	up := true
	for _, r := range s {
		if r == '_' || r == '-' || r == '.' || r == '/' || r == ' ' || r == '[' || r == ']' {
			up = true
			continue
		}
		if up {
			b.WriteRune(unicode.ToUpper(r))
			up = false
		} else {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func camel(s string) string {
	p := pascal(s)
	if p == "" {
		return p
	}
	return strings.ToLower(p[:1]) + p[1:]
}

func snake(s string) string {
	var b strings.Builder
	for i, r := range s {
		switch {
		case r == '-' || r == '.' || r == ' ':
			b.WriteByte('_')
		case unicode.IsUpper(r):
			if i > 0 {
				b.WriteByte('_')
			}
			b.WriteRune(unicode.ToLower(r))
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

func (m *Model) schema(ref string) obj {
	return m.raw["components"].(obj)["schemas"].(obj)[refName(ref)].(obj)
}

func (m *Model) operation(path string, op obj) (*Op, error) {
	parts := strings.Split(strings.TrimPrefix(path, "/v1/"), "/")
	o := &Op{
		Service: parts[0], Name: parts[1], OperationID: str(op["operationId"]), Path: path,
		Summary: str(op["summary"]), Description: str(op["description"]),
		Input: str(op["x-lowco-input"]), DefaultMode: str(op["x-lowco-default-mode"]), Status: str(op["x-lowco-status"]),
		Scope: str(op["x-lowco-scope"]),
	}
	if meter, ok := op["x-lowco-meter"].(obj); ok {
		o.Meter = str(meter["name"])
	}
	if ef, ok := op["x-lowco-extra-files"].([]any); ok {
		for _, e := range ef {
			o.Extra = append(o.Extra, e.(string))
		}
	}
	reqRef := str(op["requestBody"].(obj)["content"].(obj)["application/json"].(obj)["schema"].(obj)["$ref"])
	req := m.schema(reqRef)
	params := &Type{Kind: "object", Name: pascal(o.OperationID) + "Params", Desc: str(req["description"])}
	required := map[string]bool{}
	if rl, ok := req["required"].([]any); ok {
		for _, r := range rl {
			required[r.(string)] = true
		}
	}
	switch o.Input {
	case "file":
		params.Fields = append(params.Fields, &Field{Name: "file", Type: &Type{Kind: "file"}, Required: true, Desc: "The file: a path, bytes, a stream, a URL or a stored file id (see the file helpers)"})
	case "files":
		params.Fields = append(params.Fields, &Field{Name: "files", Type: &Type{Kind: "array", Items: &Type{Kind: "file"}}, Required: true, Desc: "The files, in order"})
	}
	extra := map[string]bool{}
	for _, x := range o.Extra {
		extra[x] = true
		params.Fields = append(params.Fields, &Field{Name: x, Type: &Type{Kind: "file"}, Desc: "An extra file input (" + x + ")"})
	}
	props := req["properties"].(obj)
	for _, k := range sortedKeys(props) {
		if k == "files" || extra[k] || (o.Input != "none" && fileKeys[k]) {
			continue
		}
		p := props[k].(obj)
		params.Fields = append(params.Fields, &Field{Name: k, Type: m.parse(p, params.Name+pascal(k)), Required: required[k], Desc: str(p["description"])})
	}
	sort.SliceStable(params.Fields, func(i, j int) bool { return params.Fields[i].Required && !params.Fields[j].Required })
	m.Types[params.Name] = params
	m.Order = append(m.Order, params.Name)
	o.Params = params
	responses := op["responses"].(obj)
	if ok200, has := responses["200"].(obj); has {
		content := ok200["content"].(obj)
		for mt := range content {
			if mt != "application/json" {
				o.Binary = append(o.Binary, mt)
			}
		}
		sort.Strings(o.Binary)
	}
	resultName := pascal(o.OperationID) + "Result"
	if _, ok := m.Types[resultName]; !ok {
		return nil, fmt.Errorf("%s: no %s schema", path, resultName)
	}
	o.Result = resultName
	return o, nil
}

func (m *Model) endpoint(method, path string, op obj) (*Endpoint, error) {
	id := str(op["operationId"])
	names, ok := resourceNames[id]
	if !ok {
		return nil, fmt.Errorf("apigen: %s %s (%s) has no SDK name; add it to resourceNames", method, path, id)
	}
	e := &Endpoint{Group: names[0], Method: names[1], OperationID: id, HTTP: method, Path: path, Summary: str(op["summary"])}
	q := &Type{Kind: "object", Name: pascal(names[0]) + pascal(names[1]) + "Query"}
	if params, ok := op["parameters"].([]any); ok {
		for _, pv := range params {
			p := pv.(obj)
			if r, isRef := p["$ref"].(string); isRef {
				p = m.raw["components"].(obj)["parameters"].(obj)[refName(r)].(obj)
			}
			switch str(p["in"]) {
			case "path":
				e.PathParams = append(e.PathParams, str(p["name"]))
			case "query":
				req, _ := p["required"].(bool)
				q.Fields = append(q.Fields, &Field{Name: str(p["name"]), Type: m.parse(p["schema"].(obj), q.Name+pascal(str(p["name"]))), Required: req, Desc: str(p["description"])})
			}
		}
	}
	if len(q.Fields) > 0 {
		m.Types[q.Name] = q
		m.Order = append(m.Order, q.Name)
		e.Query = q
	}
	if rb, ok := op["requestBody"].(obj); ok {
		content := rb["content"].(obj)
		if js, ok := content["application/json"].(obj); ok {
			e.Body = m.parse(js["schema"].(obj), pascal(names[0])+pascal(names[1])+"Body")
		} else {
			e.Multipart = true
		}
	}
	responses := op["responses"].(obj)
	for _, code := range []string{"200", "201", "202", "307"} {
		r, ok := responses[code].(obj)
		if !ok {
			continue
		}
		e.Status = code
		if code == "307" {
			e.Redirect = true
			break
		}
		content, _ := r["content"].(obj)
		js, _ := content["application/json"].(obj)
		if js == nil {
			break
		}
		env := js["schema"].(obj)
		data := env["properties"].(obj)["data"].(obj)
		e.Result = m.parse(data, pascal(names[0])+pascal(names[1])+"Data")
		if e.Result.Kind == "object" && e.Result.Name == "" {
			name := pascal(names[0]) + pascal(names[1]) + "Data"
			m.Types[name] = e.Result
			m.Order = append(m.Order, name)
			e.Result.Name = name
			res := e.Result
			e.Result = &Type{Kind: "ref", Ref: name}
			if items := fieldOf(res, "items"); items != nil && fieldOf(res, "next_cursor") != nil && items.Type.Kind == "array" && len(res.Fields) == 2 {
				e.Paged = items.Type.Items
			}
		} else if e.Result.Kind == "ref" {
			if t := m.Types[e.Result.Ref]; t != nil {
				if items := fieldOf(t, "items"); items != nil && fieldOf(t, "next_cursor") != nil && len(t.Fields) == 2 {
					e.Paged = items.Type.Items
				}
			}
		}
		break
	}
	return e, nil
}

func fieldOf(t *Type, name string) *Field {
	for _, f := range t.Fields {
		if f.Name == name {
			return f
		}
	}
	return nil
}

// groups lists the resource groups in order.
func (m *Model) groups() []string {
	seen := map[string]bool{}
	var out []string
	for _, e := range m.Endpoints {
		if !seen[e.Group] {
			seen[e.Group] = true
			out = append(out, e.Group)
		}
	}
	return out
}

// services lists the operation services in order.
func (m *Model) services() []string {
	seen := map[string]bool{}
	var out []string
	for _, o := range m.Ops {
		if !seen[o.Service] {
			seen[o.Service] = true
			out = append(out, o.Service)
		}
	}
	return out
}

// typeNames returns the named types in a stable order.
func (m *Model) typeNames() []string {
	out := append([]string(nil), m.Order...)
	sort.Strings(out)
	var dedup []string
	for i, n := range out {
		if i == 0 || n != out[i-1] {
			dedup = append(dedup, n)
		}
	}
	return dedup
}
