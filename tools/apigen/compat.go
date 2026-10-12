package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
)

// Breaking-change rules between two OpenAPI documents (DX-03 AC4). A
// client built from old must keep working against new:
//
//   - every old route (path and method) still exists;
//   - request bodies: no property removed (the API refuses unknown
//     options), no new required property, no type change, no enum value
//     removed;
//   - query parameters: none removed, no new required one, no type change;
//   - success responses: no property removed, no type change, nothing
//     required becoming optional or nullable;
//   - every error.reason still exists.
//
// Additions (routes, optional properties, response properties, enum
// values, reasons) are reported but do not fail.

type spec struct {
	raw     obj
	schemas obj
}

func loadSpec(path string) (*spec, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var raw obj
	if err := json.Unmarshal(b, &raw); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return &spec{raw: raw, schemas: raw["components"].(obj)["schemas"].(obj)}, nil
}

func (s *spec) deref(n obj) obj {
	for i := 0; i < 20 && n != nil; i++ {
		r, ok := n["$ref"].(string)
		if !ok {
			if all, ok := n["allOf"].([]any); ok && len(all) == 1 && n["properties"] == nil {
				inner := all[0].(obj)
				nullable := n["nullable"]
				n = obj{}
				for k, v := range inner {
					n[k] = v
				}
				if nullable != nil {
					n["nullable"] = nullable
				}
				continue
			}
			return n
		}
		next, _ := s.schemas[refName(r)].(obj)
		n = next
	}
	return n
}

func typeName(n obj) string {
	if n == nil {
		return "any"
	}
	if t, ok := n["type"].(string); ok {
		return t
	}
	if n["properties"] != nil {
		return "object"
	}
	if n["oneOf"] != nil {
		return "oneOf"
	}
	return "any"
}

func enumSet(n obj) map[string]bool {
	out := map[string]bool{}
	for _, v := range asList(n["enum"]) {
		out[fmt.Sprint(v)] = true
	}
	return out
}

func asList(v any) []any { l, _ := v.([]any); return l }

func reqSet(n obj) map[string]bool {
	out := map[string]bool{}
	for _, v := range asList(n["required"]) {
		out[v.(string)] = true
	}
	return out
}

type compat struct {
	old, new           *spec
	breaking, additive []string
	seen               map[string]bool
}

func (c *compat) br(f string, a ...any)  { c.breaking = append(c.breaking, fmt.Sprintf(f, a...)) }
func (c *compat) add(f string, a ...any) { c.additive = append(c.additive, fmt.Sprintf(f, a...)) }

// schema compares a schema; request says which direction is breaking.
func (c *compat) schema(where string, o, n obj, request bool, depth int) {
	o, n = c.old.deref(o), c.new.deref(n)
	if o == nil || n == nil || depth > 8 {
		return
	}
	key := fmt.Sprintf("%s|%v", where, request)
	if c.seen[key] {
		return
	}
	c.seen[key] = true
	ot, nt := typeName(o), typeName(n)
	if ot != nt && ot != "any" && nt != "any" && !(ot == "integer" && nt == "number" && request) && !(ot == "number" && nt == "integer" && !request) {
		c.br("%s: type %s became %s", where, ot, nt)
		return
	}
	if oe, ne := enumSet(o), enumSet(n); len(oe) > 0 {
		for v := range oe {
			if len(ne) > 0 && !ne[v] && request {
				c.br("%s: enum value %q removed", where, v)
			}
		}
		for v := range ne {
			if !oe[v] {
				c.add("%s: enum value %q added", where, v)
			}
		}
	}
	if !request {
		if on, _ := o["nullable"].(bool); !on {
			if nn, _ := n["nullable"].(bool); nn {
				c.br("%s: may now be null", where)
			}
		}
	}
	op, _ := o["properties"].(obj)
	np, _ := n["properties"].(obj)
	oreq, nreq := reqSet(o), reqSet(n)
	for _, k := range sortedKeys(op) {
		w := where + "." + k
		nv, ok := np[k]
		if !ok {
			c.br("%s: removed", w)
			continue
		}
		if !request && oreq[k] && !nreq[k] {
			c.br("%s: no longer always present", w)
		}
		c.schema(w, op[k].(obj), nv.(obj), request, depth+1)
	}
	for _, k := range sortedKeys(np) {
		if _, ok := op[k]; ok {
			if request && nreq[k] && !oreq[k] {
				c.br("%s.%s: now required", where, k)
			}
			continue
		}
		if request && nreq[k] {
			c.br("%s.%s: new required property", where, k)
		} else {
			c.add("%s.%s: added", where, k)
		}
	}
	if oi, ok := o["items"].(obj); ok {
		if ni, ok := n["items"].(obj); ok {
			c.schema(where+"[]", oi, ni, request, depth+1)
		}
	}
	if oa, ok := o["additionalProperties"].(obj); ok {
		if na, ok := n["additionalProperties"].(obj); ok {
			c.schema(where+"{}", oa, na, request, depth+1)
		}
	}
}

func params(s *spec, op obj) map[string]obj {
	out := map[string]obj{}
	for _, p := range asList(op["parameters"]) {
		pm := p.(obj)
		if r, ok := pm["$ref"].(string); ok {
			pm = s.raw["components"].(obj)["parameters"].(obj)[refName(r)].(obj)
		}
		if pm["in"] == "query" {
			out[str(pm["name"])] = pm
		}
	}
	return out
}

func runCompat(oldPath, newPath string) int {
	o, err := loadSpec(oldPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "apigen:", err)
		return 2
	}
	n, err := loadSpec(newPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "apigen:", err)
		return 2
	}
	c := &compat{old: o, new: n, seen: map[string]bool{}}
	op, np := o.raw["paths"].(obj), n.raw["paths"].(obj)
	for _, p := range sortedKeys(op) {
		for _, m := range sortedKeys(op[p].(obj)) {
			where := strings.ToUpper(m) + " " + p
			oop := op[p].(obj)[m].(obj)
			nitem, ok := np[p].(obj)
			if !ok {
				c.br("%s: route removed", where)
				continue
			}
			nop, ok := nitem[m].(obj)
			if !ok {
				c.br("%s: method removed", where)
				continue
			}
			oq, nq := params(o, oop), params(n, nop)
			for name, prm := range oq {
				nprm, ok := nq[name]
				if !ok {
					c.br("%s: query parameter %s removed", where, name)
					continue
				}
				c.schema(where+" ?"+name, prm["schema"].(obj), nprm["schema"].(obj), true, 0)
			}
			for name, prm := range nq {
				if _, ok := oq[name]; !ok {
					if req, _ := prm["required"].(bool); req {
						c.br("%s: new required query parameter %s", where, name)
					} else {
						c.add("%s: query parameter %s added", where, name)
					}
				}
			}
			if orb, ok := oop["requestBody"].(obj); ok {
				if nrb, ok := nop["requestBody"].(obj); ok {
					for mt, media := range orb["content"].(obj) {
						nmedia, ok := nrb["content"].(obj)[mt].(obj)
						if !ok {
							c.br("%s: request media type %s removed", where, mt)
							continue
						}
						if oschema, ok := media.(obj)["schema"].(obj); ok {
							w := where + " body"
							if mt != "application/json" {
								w += " (" + mt + ")"
							}
							c.schema(w, oschema, nmedia["schema"].(obj), true, 0)
						}
					}
				} else {
					c.br("%s: request body removed", where)
				}
			}
			for _, code := range []string{"200", "201", "202"} {
				or, ok := oop["responses"].(obj)[code].(obj)
				if !ok {
					continue
				}
				nr, ok := nop["responses"].(obj)[code].(obj)
				if !ok {
					c.br("%s: response %s removed", where, code)
					continue
				}
				oc, _ := or["content"].(obj)
				nc, _ := nr["content"].(obj)
				for mt, media := range oc {
					nmedia, ok := nc[mt].(obj)
					if !ok {
						c.br("%s: response %s media type %s removed", where, code, mt)
						continue
					}
					if oschema, ok := media.(obj)["schema"].(obj); ok {
						if ns, ok := nmedia["schema"].(obj); ok {
							w := fmt.Sprintf("%s %s", where, code)
							if mt != "application/json" {
								w += " (" + mt + ")"
							}
							c.schema(w, oschema, ns, false, 0)
						}
					}
				}
			}
		}
	}
	for _, p := range sortedKeys(np) {
		for _, m := range sortedKeys(np[p].(obj)) {
			if oi, ok := op[p].(obj); !ok || oi[m] == nil {
				c.add("%s %s: route added", strings.ToUpper(m), p)
			}
		}
	}
	oldReasons := enumSet(o.schemas["Error"].(obj)["properties"].(obj)["reason"].(obj))
	newReasons := enumSet(n.schemas["Error"].(obj)["properties"].(obj)["reason"].(obj))
	for r := range oldReasons {
		if !newReasons[r] {
			c.br("error.reason %q removed", r)
		}
	}
	sort.Strings(c.breaking)
	sort.Strings(c.additive)
	c.breaking, c.additive = uniq(c.breaking), uniq(c.additive)
	for _, a := range c.additive {
		fmt.Println("additive: " + a)
	}
	for _, b := range c.breaking {
		fmt.Fprintln(os.Stderr, "BREAKING: "+b)
	}
	fmt.Printf("apigen: %d breaking, %d additive change(s) from %s to %s\n", len(c.breaking), len(c.additive), oldPath, newPath)
	if len(c.breaking) > 0 {
		return 1
	}
	return 0
}

func uniq(s []string) []string {
	var out []string
	for i, v := range s {
		if i == 0 || v != s[i-1] {
			out = append(out, v)
		}
	}
	return out
}
