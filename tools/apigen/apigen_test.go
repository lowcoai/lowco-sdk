package main

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The committed SDK sources are what the vendored document generates.
func TestGeneratedFilesAreCurrent(t *testing.T) {
	m, err := load("../../specs/lowco-api.json")
	if err != nil {
		t.Fatal(err)
	}
	for rel, b := range map[string][]byte{
		"npm/api/src/generated.ts":                 emitTS(m),
		"python/api/src/lowcoai/api/_generated.py": emitPython(m),
		"go/api/zz_generated.go":                   emitGo(m),
		"flutter/api/lib/src/generated.dart":       emitDart(m),
	} {
		cur, err := os.ReadFile(filepath.Join("../..", rel))
		if err != nil || !bytes.Equal(cur, b) {
			t.Errorf("%s is stale; run make api-gen", rel)
		}
	}
	if len(m.Ops) != 54 || len(m.Reasons) != 56 {
		t.Fatalf("%d operations, %d reasons", len(m.Ops), len(m.Reasons))
	}
}

func mutate(t *testing.T, f func(doc map[string]any)) string {
	t.Helper()
	b, err := os.ReadFile("../../specs/lowco-api.json")
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	if err := json.Unmarshal(b, &doc); err != nil {
		t.Fatal(err)
	}
	f(doc)
	out, _ := json.Marshal(doc)
	p := filepath.Join(t.TempDir(), "new.json")
	if err := os.WriteFile(p, out, 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func schemas(doc map[string]any) map[string]any {
	return doc["components"].(map[string]any)["schemas"].(map[string]any)
}

func props(doc map[string]any, name string) map[string]any {
	return schemas(doc)[name].(map[string]any)["properties"].(map[string]any)
}

func compatOutput(t *testing.T, newPath string) (int, string) {
	t.Helper()
	cmd := exec.Command("go", "run", ".", "-compat", "../../specs/lowco-api.json", newPath)
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	err := cmd.Run()
	code := 0
	if ee, ok := err.(*exec.ExitError); ok {
		code = ee.ExitCode()
	} else if err != nil {
		t.Fatal(err)
	}
	return code, out.String()
}

// DX-03 AC4: a breaking change to the document fails the gate, naming it;
// additive changes pass.
func TestCompatFailsOnBreakingChanges(t *testing.T) {
	cases := []struct {
		name, want string
		f          func(doc map[string]any)
	}{
		{"route removed", "BREAKING: POST /v1/pdf/rotate: route removed", func(d map[string]any) { delete(d["paths"].(map[string]any), "/v1/pdf/rotate") }},
		{"response field removed", "BREAKING: POST /v1/pdf/merge 200.data.files_merged: removed", func(d map[string]any) {
			delete(props(d, "PdfMergeResult"), "files_merged")
		}},
		{"new required option", "BREAKING: POST /v1/pdf/merge body.dpi: new required property", func(d map[string]any) {
			props(d, "PdfMergeRequest")["dpi"] = map[string]any{"type": "integer"}
			s := schemas(d)["PdfMergeRequest"].(map[string]any)
			s["required"] = append(s["required"].([]any), "dpi")
		}},
		{"option removed", "BREAKING: POST /v1/pdf/merge body.bookmarks: removed", func(d map[string]any) { delete(props(d, "PdfMergeRequest"), "bookmarks") }},
		{"enum value removed", `BREAKING: POST /v1/pdf/to-images body.format: enum value "jpeg" removed`, func(d map[string]any) {
			props(d, "PdfToImagesRequest")["format"].(map[string]any)["enum"] = []any{"png", "webp"}
		}},
		{"type change", "BREAKING: POST /v1/pdf/rotate body.angle: type integer became string", func(d map[string]any) {
			props(d, "PdfRotateRequest")["angle"] = map[string]any{"type": "string"}
		}},
		{"query parameter removed", "BREAKING: GET /v1/jobs: query parameter status removed", func(d map[string]any) {
			op := d["paths"].(map[string]any)["/v1/jobs"].(map[string]any)["get"].(map[string]any)
			var keep []any
			for _, p := range op["parameters"].([]any) {
				if pm, ok := p.(map[string]any); ok && pm["name"] == "status" {
					continue
				}
				keep = append(keep, p)
			}
			op["parameters"] = keep
		}},
		{"reason removed", `BREAKING: error.reason "file_corrupt" removed`, func(d map[string]any) {
			r := schemas(d)["Error"].(map[string]any)["properties"].(map[string]any)["reason"].(map[string]any)
			var keep []any
			for _, v := range r["enum"].([]any) {
				if v != "file_corrupt" {
					keep = append(keep, v)
				}
			}
			r["enum"] = keep
		}},
		{"response becomes nullable", "BREAKING: POST /v1/pdf/merge 200.data.pages: may now be null", func(d map[string]any) {
			props(d, "PdfMergeResult")["pages"].(map[string]any)["nullable"] = true
		}},
	}
	for _, tc := range cases {
		code, out := compatOutput(t, mutate(t, tc.f))
		if code != 1 || !strings.Contains(out, tc.want) {
			t.Errorf("%s: exit %d, want %q in:\n%s", tc.name, code, tc.want, out)
		}
	}
	code, out := compatOutput(t, mutate(t, func(d map[string]any) {
		props(d, "PdfMergeRequest")["title"] = map[string]any{"type": "string"}
		props(d, "PdfMergeResult")["bytes_saved"] = map[string]any{"type": "integer"}
		d["paths"].(map[string]any)["/v1/pdf/repair"] = d["paths"].(map[string]any)["/v1/pdf/unlock"]
	}))
	if code != 0 || !strings.Contains(out, "additive: POST /v1/pdf/repair: route added") || !strings.Contains(out, "body.title: added") || strings.Contains(out, "BREAKING") {
		t.Fatalf("additive changes: exit %d\n%s", code, out)
	}
}

// A path parameter named like a per-call option (request_id) must not
// become a duplicate Python argument.
func TestPythonPathParamsDoNotShadowCallOptions(t *testing.T) {
	for in, want := range map[string]string{"request_id": "request_id_", "id": "id", "key_id": "key_id", "delivery_id": "delivery_id", "timeout": "timeout_"} {
		if got := pyPathName(in); got != want {
			t.Errorf("%s: %s, want %s", in, got, want)
		}
	}
}
