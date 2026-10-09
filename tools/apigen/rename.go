package main

import "sort"

// renames avoid clashes with built-in types (DOM and Dart File, Error).
var renames = map[string]string{"File": "StoredFile", "Error": "ErrorBody"}

func sortStrings(s []string) { sort.Strings(s) }

// applyRenames renames types and every reference to them.
func (m *Model) applyRenames() {
	for from, to := range renames {
		if t, ok := m.Types[from]; ok {
			delete(m.Types, from)
			t.Name = to
			m.Types[to] = t
			for i, n := range m.Order {
				if n == from {
					m.Order[i] = to
				}
			}
		}
	}
	var walk func(t *Type)
	seen := map[*Type]bool{}
	walk = func(t *Type) {
		if t == nil || seen[t] {
			return
		}
		seen[t] = true
		if to, ok := renames[t.Ref]; ok {
			t.Ref = to
		}
		for _, f := range t.Fields {
			walk(f.Type)
		}
		walk(t.Items)
		walk(t.Values)
		for _, u := range t.Union {
			walk(u)
		}
	}
	for _, t := range m.Types {
		walk(t)
	}
	for _, e := range m.Endpoints {
		walk(e.Query)
		walk(e.Body)
		walk(e.Result)
		walk(e.Paged)
	}
}
