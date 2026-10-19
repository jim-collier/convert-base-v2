//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// Messages say "can't", not "cannot". Comments and identifiers aren't checked.
var longNegation = regexp.MustCompile(`(?i)\b(cannot|can not|is not|are not|does not|do not|did not|was not|were not|will not|would not|could not|should not|has not|have not|had not|must not|need not)\b`)

// Test ID: Et9kwvY
func TestMessagesUseContractions(t *testing.T) {
	dirs := []string{".", "../../convertbase", "../../internal/errcode", "../../reactor", "../../wasm"}
	fset := token.NewFileSet()
	files := 0
	for _, dir := range dirs {
		paths, err := filepath.Glob(filepath.Join(dir, "*.go"))
		if err != nil {
			t.Fatal(err)
		}
		for _, p := range paths {
			if strings.HasSuffix(p, "_test.go") {
				continue
			}
			f, err := parser.ParseFile(fset, p, nil, parser.SkipObjectResolution)
			if err != nil {
				t.Fatal(err)
			}
			files++
			ast.Inspect(f, func(n ast.Node) bool {
				lit, ok := n.(*ast.BasicLit)
				if !ok || lit.Kind != token.STRING {
					return true
				}
				s, err := strconv.Unquote(lit.Value)
				if err != nil {
					s = lit.Value
				}
				if m := longNegation.FindString(s); m != "" {
					t.Errorf("%s: %q in a string", fset.Position(lit.Pos()), m)
				}
				return true
			})
		}
	}
	// Under 20 means a moved dir left this checking next to nothing.
	if files < 20 {
		t.Fatalf("only %d Go files scanned", files)
	}

	// Outside the module, so absent from a module download.
	for _, p := range []string{"../../../install.bash", "../../../install.ps1", "../../../web/index.html"} {
		text, err := os.ReadFile(p)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			t.Fatal(err)
		}
		for i, line := range strings.Split(string(text), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "#") || strings.HasPrefix(line, "//") {
				continue
			}
			for _, cut := range []string{" # ", " // "} {
				if j := strings.Index(line, cut); j >= 0 {
					line = line[:j]
				}
			}
			if m := longNegation.FindString(line); m != "" {
				t.Errorf("%s:%d: %q", p, i+1, m)
			}
		}
	}
}
