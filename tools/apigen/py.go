package main

import (
	"fmt"
	"strings"
)

var pyKeywords = map[string]bool{"from": true, "in": true, "is": true, "not": true, "and": true, "or": true, "class": true, "def": true, "return": true, "import": true, "global": true, "lambda": true, "pass": true, "with": true, "yield": true, "async": true, "await": true, "None": true, "True": true, "False": true, "del": true, "try": true, "except": true, "raise": true, "finally": true, "while": true, "for": true, "if": true, "else": true, "elif": true, "break": true, "continue": true, "assert": true, "as": true, "nonlocal": true}

// pyCallOptions are the keyword-only arguments every generated method may
// take; a path parameter with one of these names would be a duplicate
// argument (GET /v1/requests/{request_id}), so it gets a trailing underscore.
var pyCallOptions = map[string]bool{"request_id": true, "idempotency_key": true, "mode": true, "accept": true, "timeout": true}

// pyPathName is a path parameter's Python name.
func pyPathName(wire string) string {
	n := pyName(wire)
	if pyCallOptions[n] {
		n += "_"
	}
	return n
}

func pyName(wire string) string {
	n := strings.NewReplacer("[", "_", "]", "", "-", "_", ".", "_").Replace(wire)
	if pyKeywords[n] {
		n += "_"
	}
	return n
}

func pyType(t *Type) string {
	var s string
	switch t.Kind {
	case "ref":
		s = t.Ref
	case "object":
		s = "dict[str, Any]"
		if t.Name != "" {
			s = t.Name
		}
	case "array":
		s = "list[" + pyType(t.Items) + "]"
	case "map":
		s = "dict[str, " + pyType(t.Values) + "]"
	case "string":
		s = "str"
	case "integer":
		s = "int"
	case "number":
		s = "float"
	case "boolean":
		s = "bool"
	case "enum":
		var vs []string
		for _, v := range t.Enum {
			vs = append(vs, fmt.Sprintf("%q", v))
		}
		s = "Literal[" + strings.Join(vs, ", ") + "]"
	case "union":
		var vs []string
		for _, u := range t.Union {
			vs = append(vs, pyType(u))
		}
		s = "Union[" + strings.Join(vs, ", ") + "]"
	case "file":
		s = "FileInput"
	default:
		return "Any"
	}
	if t.Nullable {
		s = "Optional[" + s + "]"
	}
	return s
}

func pyDoc(b *strings.Builder, indent, desc string) {
	desc = strings.TrimSpace(strings.ReplaceAll(desc, `"""`, `'''`))
	if desc == "" {
		return
	}
	fmt.Fprintf(b, "%s\"\"\"%s\"\"\"\n", indent, strings.ReplaceAll(desc, "\\", "\\\\"))
}

func emitPython(m *Model) []byte {
	var b strings.Builder
	fmt.Fprintf(&b, "# "+header+"\n# fmt: off\n# ruff: noqa\n\n", m.Version)
	b.WriteString("from __future__ import annotations\n\nimport sys\nfrom typing import TYPE_CHECKING, Any, Dict, Iterator, List, Literal, Optional, Union\n\n")
	b.WriteString("if sys.version_info >= (3, 11):\n    from typing import NotRequired, TypedDict\nelse:  # pragma: no cover\n    from typing_extensions import NotRequired, TypedDict\n\n")
	b.WriteString("if TYPE_CHECKING:\n    from ._core import Answer, Core, FileInput\n\n")
	fmt.Fprintf(&b, "API_VERSION = %q\n\"\"\"The Lowco API version these types were generated from.\"\"\"\n\n", m.Version)
	b.WriteString("ErrorReason = Literal[\n")
	for _, r := range m.Reasons {
		fmt.Fprintf(&b, "    %q,\n", r.Name)
	}
	b.WriteString("]\n\"\"\"Every error.reason the API can answer (docs.lowco.ai/api/errors).\"\"\"\n\n")
	b.WriteString("ERROR_REASONS: Dict[str, Dict[str, Any]] = {\n")
	for _, r := range m.Reasons {
		fmt.Fprintf(&b, "    %q: {\"status\": %d, \"when\": %q, \"action\": %q},\n", r.Name, r.Status, r.When, r.Action)
	}
	b.WriteString("}\n\"\"\"Each reason's HTTP status, when it is answered and what to do.\"\"\"\n\n")

	for _, name := range m.typeNames() {
		t := m.Types[name]
		if t.Kind != "object" {
			continue
		}
		functional := false
		for _, f := range t.Fields {
			if pyName(f.Name) != f.Name {
				functional = true
			}
		}
		if functional {
			// a wire name that is not an identifier (from): the functional form keeps it
			var fields []string
			for _, f := range t.Fields {
				typ := pyType(f.Type)
				if !f.Required {
					typ = "NotRequired[" + typ + "]"
				}
				fields = append(fields, fmt.Sprintf("%q: %q", f.Name, typ))
			}
			fmt.Fprintf(&b, "\n%s = TypedDict(%q, {%s})\n", name, name, strings.Join(fields, ", "))
			pyDoc(&b, "", t.Desc)
			continue
		}
		fmt.Fprintf(&b, "\nclass %s(TypedDict):\n", name)
		pyDoc(&b, "    ", t.Desc)
		if len(t.Fields) == 0 {
			b.WriteString("    pass\n")
		}
		for _, f := range t.Fields {
			typ := pyType(f.Type)
			if !f.Required {
				typ = "NotRequired[" + typ + "]"
			}
			fmt.Fprintf(&b, "    %s: %s\n", f.Name, typ)
			pyDoc(&b, "    ", f.Desc)
		}
	}
	// Aliases after the TypedDicts (whose annotations are lazy), each after
	// the aliases it refers to.
	b.WriteString("\n\n")
	for _, name := range aliasOrder(m) {
		t := m.Types[name]
		fmt.Fprintf(&b, "%s = %s\n", name, pyType(t))
		pyDoc(&b, "", t.Desc)
	}
	b.WriteString("\n\n")

	for _, svc := range m.services() {
		fmt.Fprintf(&b, "class %sOperations:\n    \"\"\"/v1/%s operations.\"\"\"\n\n    def __init__(self, core: Core) -> None:\n        self._core = core\n\n", pascal(svc), svc)
		for _, o := range m.Ops {
			if o.Service != svc {
				continue
			}
			var args, wire []string
			for _, f := range o.Params.Fields {
				def := ""
				if !f.Required {
					def = " = None"
				}
				typ := pyType(f.Type)
				if !f.Required && !strings.HasPrefix(typ, "Optional[") {
					typ = "Optional[" + typ + "]"
				}
				args = append(args, fmt.Sprintf("%s: %s%s", pyName(f.Name), typ, def))
				wire = append(wire, fmt.Sprintf("%q: %s", f.Name, pyName(f.Name)))
			}
			extra := "[]"
			if len(o.Extra) > 0 {
				var q []string
				for _, x := range o.Extra {
					q = append(q, fmt.Sprintf("%q", x))
				}
				extra = "[" + strings.Join(q, ", ") + "]"
			}
			fmt.Fprintf(&b, "    def %s(\n        self,\n        *,\n", pyName(snake(camel(o.Name))))
			for _, a := range args {
				fmt.Fprintf(&b, "        %s,\n", a)
			}
			b.WriteString("        mode: Optional[Literal[\"sync\", \"async\"]] = None,\n        idempotency_key: Optional[str] = None,\n        accept: Optional[str] = None,\n        request_id: Optional[str] = None,\n        timeout: Optional[float] = None,\n")
			fmt.Fprintf(&b, "    ) -> Answer[%s]:\n", o.Result)
			pyDoc(&b, "        ", o.Summary+". "+modeNote(o)+" Meter "+o.Meter+"; scope "+o.Scope+".")
			fmt.Fprintf(&b, "        params = {%s}\n", strings.Join(wire, ", "))
			fmt.Fprintf(&b, "        return self._core.operation(%q, params, input_kind=%q, extra=%s, mode=mode, idempotency_key=idempotency_key, accept=accept, request_id=request_id, timeout=timeout)\n\n", o.Path, o.Input, extra)
		}
		b.WriteString("\n")
	}

	for _, g := range m.groups() {
		fmt.Fprintf(&b, "class %sResource:\n    \"\"\"%s.\"\"\"\n\n    def __init__(self, core: Core) -> None:\n        self._core = core\n\n", pascal(g), groupDoc(g))
		for _, e := range m.Endpoints {
			if e.Group != g {
				continue
			}
			name := pyName(snake(e.Method))
			pathExpr := e.Path
			var pos []string
			for _, p := range e.PathParams {
				pos = append(pos, pyPathName(p)+": str")
				pathExpr = strings.Replace(pathExpr, "{"+p+"}", "{_seg("+pyPathName(p)+")}", 1)
			}
			pathExpr = "f\"" + pathExpr + "\""
			result := "Any"
			if e.Result != nil {
				result = pyType(e.Result)
			}
			switch {
			case e.Multipart:
				fmt.Fprintf(&b, "    def %s(self, file: FileInput, *, request_id: Optional[str] = None) -> %s:\n", name, result)
				pyDoc(&b, "        ", e.Summary+".")
				fmt.Fprintf(&b, "        return self._core.upload(%s, file, request_id=request_id)\n\n", pathExpr)
				continue
			case e.Redirect:
				fmt.Fprintf(&b, "    def %s(self, %s, *, request_id: Optional[str] = None) -> str:\n", name, strings.Join(pos, ", "))
				pyDoc(&b, "        ", e.Summary+".")
				fmt.Fprintf(&b, "        return self._core.redirect(%s, request_id=request_id)\n\n", pathExpr)
				continue
			}
			var kw, bodyWire, queryWire []string
			if e.Body != nil {
				bt := e.Body
				if bt.Kind == "ref" {
					bt = m.Types[bt.Ref]
				}
				for _, f := range bt.Fields {
					def := ""
					typ := pyType(f.Type)
					if !f.Required {
						def = " = None"
						if !strings.HasPrefix(typ, "Optional[") {
							typ = "Optional[" + typ + "]"
						}
					}
					kw = append(kw, fmt.Sprintf("%s: %s%s", pyName(f.Name), typ, def))
					bodyWire = append(bodyWire, fmt.Sprintf("%q: %s", f.Name, pyName(f.Name)))
				}
			}
			if e.Query != nil {
				for _, f := range e.Query.Fields {
					def := ""
					typ := pyType(f.Type)
					if !f.Required {
						def = " = None"
						if !strings.HasPrefix(typ, "Optional[") {
							typ = "Optional[" + typ + "]"
						}
					}
					kw = append(kw, fmt.Sprintf("%s: %s%s", pyName(f.Name), typ, def))
					queryWire = append(queryWire, fmt.Sprintf("%q: %s", f.Name, pyName(f.Name)))
				}
			}
			sort2(kw)
			kw = append(kw, "idempotency_key: Optional[str] = None", "request_id: Optional[str] = None")
			sig := append(append([]string{"self"}, pos...), "*")
			sig = append(sig, kw...)
			fmt.Fprintf(&b, "    def %s(%s) -> %s:\n", name, strings.Join(sig, ", "), result)
			pyDoc(&b, "        ", e.Summary+".")
			body := "None"
			if e.Body != nil {
				body = "_drop_none({" + strings.Join(bodyWire, ", ") + "})"
			}
			query := "None"
			if e.Query != nil {
				query = "{" + strings.Join(queryWire, ", ") + "}"
			}
			fmt.Fprintf(&b, "        return self._core.call(%q, %s, query=%s, json=%s, idempotency_key=idempotency_key, request_id=request_id)\n\n", e.HTTP, pathExpr, query, body)
			if e.Paged != nil {
				var pkw, pq []string
				if e.Query != nil {
					for _, f := range e.Query.Fields {
						if f.Name == "cursor" {
							continue
						}
						typ := pyType(f.Type)
						if !strings.HasPrefix(typ, "Optional[") {
							typ = "Optional[" + typ + "]"
						}
						pkw = append(pkw, fmt.Sprintf("%s: %s = None", pyName(f.Name), typ))
						pq = append(pq, fmt.Sprintf("%q: %s", f.Name, pyName(f.Name)))
					}
				}
				psig := append(append([]string{"self"}, pos...), "*")
				psig = append(psig, pkw...)
				psig = append(psig, "request_id: Optional[str] = None")
				fmt.Fprintf(&b, "    def %s_all(%s) -> Iterator[%s]:\n", name, strings.Join(psig, ", "), pyType(e.Paged))
				pyDoc(&b, "        ", "Every item of "+name+", page after page (follows next_cursor).")
				fmt.Fprintf(&b, "        return self._core.paginate(%s, {%s}, request_id=request_id)\n\n", pathExpr, strings.Join(pq, ", "))
			}
		}
		switch g {
		case "jobs":
			b.WriteString("    def wait(self, job_id: str, *, timeout: float = 300.0, max_interval: float = 10.0) -> Job:\n")
			b.WriteString("        \"\"\"Waits until the job is succeeded, failed or cancelled, polling with the Retry-After the API sends; raises LowcoJobError when it failed or was cancelled, LowcoTimeoutError at the timeout.\"\"\"\n")
			b.WriteString("        return self._core.wait_for_job(job_id, timeout=timeout, max_interval=max_interval)\n\n")
		case "files":
			b.WriteString("    def download(self, url: str) -> bytes:\n        \"\"\"Downloads a file object's signed url (no API key is sent).\"\"\"\n        return self._core.download(url)\n\n")
		}
		b.WriteString("\n")
	}
	b.WriteString("def _seg(value: str) -> str:\n    from urllib.parse import quote\n\n    return quote(value, safe=\"\")\n\n\n")
	b.WriteString("def _drop_none(d: Dict[str, Any]) -> Dict[str, Any]:\n    return {k: v for k, v in d.items() if v is not None}\n\n\n")
	b.WriteString("class GeneratedClient:\n    \"\"\"Every operation and resource of the Lowco API.\"\"\"\n\n    def __init__(self, core: Core) -> None:\n        self._core = core\n")
	for _, svc := range m.services() {
		fmt.Fprintf(&b, "        self.%s = %sOperations(core)\n        \"\"\"/v1/%s operations.\"\"\"\n", pyName(svc), pascal(svc), svc)
	}
	for _, g := range m.groups() {
		fmt.Fprintf(&b, "        self.%s = %sResource(core)\n        \"\"\"%s.\"\"\"\n", pyName(g), pascal(g), groupDoc(g))
	}
	return []byte(b.String())
}

func sort2(s []string) {
	// required keyword arguments (no default) first, then the rest, each sorted
	var req, opt []string
	for _, a := range s {
		if strings.Contains(a, " = ") {
			opt = append(opt, a)
		} else {
			req = append(req, a)
		}
	}
	sortStrings(req)
	sortStrings(opt)
	copy(s, append(req, opt...))
}

// aliasOrder lists the non-object named types so each comes after the
// aliases its definition refers to.
func aliasOrder(m *Model) []string {
	var names []string
	for _, n := range m.typeNames() {
		if m.Types[n].Kind != "object" {
			names = append(names, n)
		}
	}
	isAlias := map[string]bool{}
	for _, n := range names {
		isAlias[n] = true
	}
	var refs func(t *Type, out map[string]bool)
	refs = func(t *Type, out map[string]bool) {
		if t == nil {
			return
		}
		if t.Kind == "ref" && isAlias[t.Ref] {
			out[t.Ref] = true
		}
		refs(t.Items, out)
		refs(t.Values, out)
		for _, u := range t.Union {
			refs(u, out)
		}
	}
	done := map[string]bool{}
	var order []string
	var visit func(n string)
	visit = func(n string) {
		if done[n] {
			return
		}
		done[n] = true
		deps := map[string]bool{}
		refs(m.Types[n], deps)
		for _, d := range sortedSet(deps) {
			visit(d)
		}
		order = append(order, n)
	}
	for _, n := range names {
		visit(n)
	}
	return order
}

func sortedSet(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sortStrings(out)
	return out
}
