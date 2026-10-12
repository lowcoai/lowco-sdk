package main

import (
	"fmt"
	"strings"
)

var dartReserved = map[string]bool{"assert": true, "break": true, "case": true, "catch": true, "class": true, "const": true, "continue": true, "default": true,
	"do": true, "else": true, "enum": true, "extends": true, "false": true, "final": true, "finally": true, "for": true, "if": true, "in": true, "is": true,
	"new": true, "null": true, "rethrow": true, "return": true, "super": true, "switch": true, "this": true, "throw": true, "true": true, "try": true,
	"var": true, "void": true, "while": true, "with": true, "hashCode": true, "runtimeType": true, "toString": true, "toJson": true}

func dartName(wire string) string {
	n := camel(wire)
	if dartReserved[n] {
		n += "Value"
	}
	return n
}

// dartResolve follows aliases to the underlying type.
func dartResolve(m *Model, t *Type) *Type {
	for i := 0; i < 10 && t != nil && t.Kind == "ref"; i++ {
		target := m.Types[t.Ref]
		if target == nil || target.Kind == "object" {
			return t
		}
		t = target
	}
	return t
}

func dartType(m *Model, t *Type) string {
	switch t.Kind {
	case "ref":
		return t.Ref
	case "object":
		if t.Name != "" {
			return t.Name
		}
		return "Map<String, dynamic>"
	case "array":
		return "List<" + dartType(m, t.Items) + ">"
	case "map":
		return "Map<String, " + dartType(m, t.Values) + ">"
	case "string", "enum":
		return "String"
	case "integer":
		return "int"
	case "number":
		return "num"
	case "boolean":
		return "bool"
	case "file":
		return "FileInput"
	}
	return "Object"
}

// dartDecode is an expression decoding the JSON value v.
func dartDecode(m *Model, t *Type, v string) string {
	r := dartResolve(m, t)
	switch r.Kind {
	case "ref":
		return fmt.Sprintf("%s == null ? null : %s.fromJson(%s as Map<String, dynamic>)", v, r.Ref, v)
	case "object":
		if r.Name != "" {
			return fmt.Sprintf("%s == null ? null : %s.fromJson(%s as Map<String, dynamic>)", v, r.Name, v)
		}
		return fmt.Sprintf("%s as Map<String, dynamic>?", v)
	case "array":
		return fmt.Sprintf("(%s as List?)?.map((e) => (%s)!).toList().cast<%s>()", v, dartDecode(m, r.Items, "e"), dartType(m, r.Items))
	case "map":
		return fmt.Sprintf("(%s as Map?)?.map((k, e) => MapEntry(k as String, (%s)!)).cast<String, %s>()", v, dartDecode(m, r.Values, "e"), dartType(m, r.Values))
	case "string", "enum":
		return v + " as String?"
	case "integer":
		return "(" + v + " as num?)?.toInt()"
	case "number":
		return v + " as num?"
	case "boolean":
		return v + " as bool?"
	}
	return v
}

func dartEncode(m *Model, t *Type, v string) string {
	r := dartResolve(m, t)
	switch r.Kind {
	case "ref":
		return v + ".toJson()"
	case "object":
		if r.Name != "" {
			return v + ".toJson()"
		}
	case "array":
		inner := dartEncode(m, r.Items, "e")
		if inner == "e" {
			return v
		}
		return fmt.Sprintf("%s.map((e) => %s).toList()", v, inner)
	case "map":
		inner := dartEncode(m, r.Values, "e")
		if inner == "e" {
			return v
		}
		return fmt.Sprintf("%s.map((k, e) => MapEntry(k, %s))", v, inner)
	}
	return v
}

func dartDoc(b *strings.Builder, indent, desc string) {
	desc = strings.TrimSpace(desc)
	if desc == "" {
		return
	}
	for _, line := range strings.Split(desc, "\n") {
		fmt.Fprintf(b, "%s/// %s\n", indent, strings.ReplaceAll(line, "[", "\\["))
	}
}

func dartStr(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `'`, `\'`)
	s = strings.ReplaceAll(s, `$`, `\$`)
	return "'" + s + "'"
}

func emitDart(m *Model) []byte {
	var b strings.Builder
	fmt.Fprintf(&b, "// "+header+"\n// ignore_for_file: public_member_api_docs, lines_longer_than_80_chars, prefer_single_quotes, unnecessary_cast, unnecessary_null_comparison, unintended_html_in_doc_comment\n\n", m.Version)
	b.WriteString("import 'core.dart';\n\n")
	fmt.Fprintf(&b, "/// The Lowco API version these types were generated from.\nconst apiVersion = %s;\n\n", dartStr(m.Version))
	b.WriteString("/// Every error.reason the API can answer (docs.lowco.ai/api/errors).\nabstract final class ErrorReason {\n")
	for _, r := range m.Reasons {
		fmt.Fprintf(&b, "  /// HTTP %d: %s\n  static const %s = %s;\n", r.Status, strings.ReplaceAll(r.When, "[", "\\["), dartName(r.Name), dartStr(r.Name))
	}
	b.WriteString("}\n\n/// Each reason's HTTP status, when it is answered and what to do.\nconst errorReasons = <String, ({int status, String when, String action})>{\n")
	for _, r := range m.Reasons {
		fmt.Fprintf(&b, "  %s: (status: %d, when: %s, action: %s),\n", dartStr(r.Name), r.Status, dartStr(r.When), dartStr(r.Action))
	}
	b.WriteString("};\n\n")

	params := map[string]bool{}
	for _, o := range m.Ops {
		params[o.Params.Name] = true
	}
	for _, name := range m.typeNames() {
		t := m.Types[name]
		dartDoc(&b, "", t.Desc)
		if t.Kind != "object" {
			fmt.Fprintf(&b, "typedef %s = %s;\n\n", name, dartType(m, t))
			continue
		}
		fmt.Fprintf(&b, "class %s {\n", name)
		// constructor
		if len(t.Fields) == 0 {
			fmt.Fprintf(&b, "  const %s();\n\n  // ignore: avoid_unused_constructor_parameters\n  factory %s.fromJson(Map<String, dynamic> json) => const %s();\n\n  Map<String, dynamic> toJson() => {};\n}\n\n", name, name, name)
			continue
		}
		fmt.Fprintf(&b, "  const %s({\n", name)
		for _, f := range t.Fields {
			req := ""
			if f.Type.Kind == "file" && f.Required {
				req = "required "
			}
			if f.Type.Kind == "array" && f.Type.Items.Kind == "file" && f.Required {
				req = "required "
			}
			fmt.Fprintf(&b, "    %sthis.%s,\n", req, dartName(f.Name))
		}
		b.WriteString("  });\n\n")
		if !params[name] {
			fmt.Fprintf(&b, "  factory %s.fromJson(Map<String, dynamic> json) => %s(\n", name, name)
			for _, f := range t.Fields {
				fmt.Fprintf(&b, "        %s: %s,\n", dartName(f.Name), dartDecode(m, f.Type, fmt.Sprintf("json[%s]", dartStr(f.Name))))
			}
			b.WriteString("      );\n\n")
		}
		for _, f := range t.Fields {
			dartDoc(&b, "  ", f.Desc)
			typ := dartType(m, f.Type)
			if f.Type.Kind == "file" && f.Required || (f.Type.Kind == "array" && f.Type.Items.Kind == "file" && f.Required) {
				fmt.Fprintf(&b, "  final %s %s;\n\n", typ, dartName(f.Name))
				continue
			}
			fmt.Fprintf(&b, "  final %s? %s;\n\n", typ, dartName(f.Name))
		}
		b.WriteString("  /// The wire form; null fields are left out (file inputs are sent separately).\n  Map<String, dynamic> toJson() => {\n")
		for _, f := range t.Fields {
			if f.Type.Kind == "file" || (f.Type.Kind == "array" && f.Type.Items.Kind == "file") {
				continue
			}
			n := dartName(f.Name)
			fmt.Fprintf(&b, "        if (%s != null) %s: %s,\n", n, dartStr(f.Name), dartEncode(m, f.Type, n+"!"))
		}
		b.WriteString("      };\n")
		// file inputs accessor for params
		var fileFields []string
		for _, f := range t.Fields {
			if f.Type.Kind == "file" {
				fileFields = append(fileFields, fmt.Sprintf("%s: %s", dartStr(f.Name), dartName(f.Name)))
			}
		}
		hasMany := false
		for _, f := range t.Fields {
			if f.Type.Kind == "array" && f.Type.Items.Kind == "file" {
				hasMany = true
			}
		}
		if len(fileFields) > 0 || hasMany {
			fmt.Fprintf(&b, "\n  /// The named file inputs.\n  Map<String, FileInput?> get fileInputs => {%s};\n", strings.Join(fileFields, ", "))
			if hasMany {
				b.WriteString("\n  /// The files, in order.\n  List<FileInput> get manyFiles => files;\n")
			} else {
				b.WriteString("\n  /// The files, in order.\n  List<FileInput>? get manyFiles => null;\n")
			}
		}
		b.WriteString("}\n\n")
	}

	for _, svc := range m.services() {
		cls := pascal(svc) + "Operations"
		fmt.Fprintf(&b, "/// /v1/%s operations.\nclass %s {\n  %s(this._core);\n  final Core _core;\n\n", svc, cls, cls)
		for _, o := range m.Ops {
			if o.Service != svc {
				continue
			}
			dartDoc(&b, "  ", o.Summary+". "+modeNote(o)+" Meter "+o.Meter+"; scope "+o.Scope+".")
			many := "null"
			if o.Input == "files" {
				many = "params.manyFiles"
			}
			named := "const {}"
			if o.Input == "file" || len(o.Extra) > 0 {
				named = "params.fileInputs"
			}
			fmt.Fprintf(&b, "  Future<Answer<%s>> %s(%s params, [CallOptions? options]) => _core.operation(%s, params.toJson(), %s, %s, %s.fromJson, options);\n\n",
				o.Result, dartName(o.Name), o.Params.Name, dartStr(o.Path), named, many, dartResolveName(m, o.Result))
		}
		b.WriteString("}\n\n")
	}

	for _, g := range m.groups() {
		cls := pascal(g) + "Resource"
		fmt.Fprintf(&b, "/// %s.\nclass %s {\n  %s(this._core);\n  final Core _core;\n\n", groupDoc(g), cls, cls)
		for _, e := range m.Endpoints {
			if e.Group != g {
				continue
			}
			var args []string
			path := e.Path
			for _, p := range e.PathParams {
				args = append(args, "String "+dartName(p))
				path = strings.Replace(path, "{"+p+"}", "${Uri.encodeComponent("+dartName(p)+")}", 1)
			}
			pathExpr := "'" + path + "'"
			result := "Object?"
			decode := "(j) => j"
			if e.Result != nil {
				rt := dartResolve(m, e.Result)
				result = dartType(m, e.Result)
				if rt.Kind == "ref" || (rt.Kind == "object" && rt.Name != "") {
					decode = "(j) => " + dartResolveName(m, result) + ".fromJson(j as Map<String, dynamic>)"
				}
			}
			dartDoc(&b, "  ", e.Summary+".")
			switch {
			case e.Multipart:
				fmt.Fprintf(&b, "  Future<%s> %s(FileInput file, [RequestOptions? options]) => _core.upload(%s, file, %s, options);\n\n", result, dartName(e.Method), pathExpr, decode)
				continue
			case e.Redirect:
				fmt.Fprintf(&b, "  Future<String> %s(%s, [RequestOptions? options]) => _core.redirect(%s, options);\n\n", dartName(e.Method), strings.Join(args, ", "), pathExpr)
				continue
			}
			body := "null"
			if e.Body != nil {
				args = append(args, dartType(m, e.Body)+" body")
				body = dartEncode(m, e.Body, "body")
			}
			query := "null"
			if e.Query != nil {
				if hasRequired(e.Query) {
					args = append(args, e.Query.Name+" query")
					query = "query.toJson()"
				} else {
					args = append(args, e.Query.Name+"? query")
					query = "query?.toJson()"
				}
			}
			fmt.Fprintf(&b, "  Future<%s> %s(%s[RequestOptions? options]) => _core.call(%s, %s, query: %s, body: %s, decode: %s, options: options);\n\n",
				result, dartName(e.Method), joinArgs(args), dartStr(e.HTTP), pathExpr, query, body, decode)
			if e.Paged != nil {
				item := dartType(m, e.Paged)
				var pargs []string
				for _, p := range e.PathParams {
					pargs = append(pargs, "String "+dartName(p))
				}
				q := "null"
				if e.Query != nil {
					pargs = append(pargs, e.Query.Name+"? query")
					q = "query?.toJson()"
				}
				dartDoc(&b, "  ", "Every item of "+dartName(e.Method)+", page after page (follows next_cursor).")
				fmt.Fprintf(&b, "  Stream<%s> %sAll(%s[RequestOptions? options]) => _core.paginate(%s, %s, (j) => %s.fromJson(j as Map<String, dynamic>), options);\n\n",
					item, dartName(e.Method), joinArgs(pargs), pathExpr, q, dartResolveName(m, item))
			}
		}
		switch g {
		case "jobs":
			b.WriteString("  /// Waits until the job is succeeded, failed or cancelled, polling with the Retry-After the API sends; throws [LowcoJobError] when it failed or was cancelled, [LowcoTimeoutError] at the timeout.\n")
			b.WriteString("  Future<Job> wait(String jobId, {Duration timeout = const Duration(minutes: 5), Duration maxInterval = const Duration(seconds: 10)}) =>\n      _core.waitForJob(jobId, timeout: timeout, maxInterval: maxInterval);\n\n")
		case "files":
			b.WriteString("  /// Downloads a file object's signed url (no API key is sent).\n  Future<List<int>> download(String url) => _core.download(url);\n\n")
		}
		b.WriteString("}\n\n")
	}

	b.WriteString("/// Every operation and resource of the Lowco API.\nclass GeneratedClient {\n  GeneratedClient(Core core)\n      : ")
	var inits []string
	for _, svc := range m.services() {
		inits = append(inits, fmt.Sprintf("%s = %sOperations(core)", dartName(svc), pascal(svc)))
	}
	for _, g := range m.groups() {
		inits = append(inits, fmt.Sprintf("%s = %sResource(core)", dartName(g), pascal(g)))
	}
	b.WriteString(strings.Join(inits, ",\n        ") + ";\n\n")
	for _, svc := range m.services() {
		fmt.Fprintf(&b, "  /// /v1/%s operations.\n  final %sOperations %s;\n\n", svc, pascal(svc), dartName(svc))
	}
	for _, g := range m.groups() {
		fmt.Fprintf(&b, "  /// %s.\n  final %sResource %s;\n\n", groupDoc(g), pascal(g), dartName(g))
	}
	b.WriteString("}\n")
	return []byte(b.String())
}

// dartResolveName names the class an alias stands for.
func dartResolveName(m *Model, name string) string {
	for i := 0; i < 10; i++ {
		t := m.Types[name]
		if t == nil || t.Kind != "ref" {
			return name
		}
		name = t.Ref
	}
	return name
}

func joinArgs(args []string) string {
	if len(args) == 0 {
		return ""
	}
	return strings.Join(args, ", ") + ", "
}
