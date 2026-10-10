// Command apigen generates the Lowco API SDKs (npm/api, python/api, go/api,
// flutter/api) from the vendored OpenAPI document, checks that the
// generated code is current (-check), and reports breaking changes between
// two documents (-compat old.json new.json), which gates every publish
// (DX-03).
package main

import (
	"bytes"
	"flag"
	"fmt"
	"os"
	"path/filepath"
)

func main() {
	spec := flag.String("spec", "specs/lowco-api.json", "the OpenAPI document")
	root := flag.String("root", ".", "the lowco-sdk checkout")
	check := flag.Bool("check", false, "fail when the generated files differ instead of writing them")
	compat := flag.Bool("compat", false, "compare two documents: apigen -compat old.json new.json")
	flag.Parse()
	if *compat {
		if flag.NArg() != 2 {
			fmt.Fprintln(os.Stderr, "usage: apigen -compat old.json new.json")
			os.Exit(2)
		}
		os.Exit(runCompat(flag.Arg(0), flag.Arg(1)))
	}
	m, err := load(*spec)
	if err != nil {
		fmt.Fprintln(os.Stderr, "apigen:", err)
		os.Exit(1)
	}
	files := map[string][]byte{
		"npm/api/src/generated.ts":                 emitTS(m),
		"python/api/src/lowcoai/api/_generated.py": emitPython(m),
		"go/api/zz_generated.go":                   emitGo(m),
		"flutter/api/lib/src/generated.dart":       emitDart(m),
	}
	stale := 0
	for _, rel := range sortedFileKeys(files) {
		path := filepath.Join(*root, rel)
		if *check {
			cur, err := os.ReadFile(path)
			if err != nil || !bytes.Equal(cur, files[rel]) {
				fmt.Fprintf(os.Stderr, "apigen: %s is stale; run go run ./tools/apigen\n", rel)
				stale++
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if err := os.WriteFile(path, files[rel], 0o644); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
	if stale > 0 {
		os.Exit(1)
	}
	verb := "wrote"
	if *check {
		verb = "checked"
	}
	fmt.Printf("apigen: %s 4 SDK sources from API %s (%d operations, %d resource methods, %d types, %d error reasons)\n",
		verb, m.Version, len(m.Ops), len(m.Endpoints), len(m.typeNames()), len(m.Reasons))
}

func sortedFileKeys(m map[string][]byte) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sortStrings(out)
	return out
}
