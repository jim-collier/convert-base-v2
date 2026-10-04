//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jim-collier/convert-base-v2/lib/shcl"
)

func symbolsOf(t *testing.T, r *Registry, name string) string {
	t.Helper()
	b, err := ResolveBase(r, name, "", nil)
	if err != nil {
		t.Fatal(err)
	}
	return strings.Join(b.Symbols, "|")
}

// A config with no Format line was written for SHCL 1.x, and has to load to
// the bases it did then. Each want is what v3.0.0, the last release on SHCL
// 1.x, gave for that file. The first nine read differently under the current
// rules as written.
// Test ID: ErgDzUX
func TestUpgradeConfigKeepsOldMeaning(t *testing.T) {
	uEscape := `"` + `\` + `u00e9 x"` // in pieces to keep the escape out of the source text
	cases := []struct {
		name      string
		value     string
		want      []string
		respelled bool
	}{
		{"bare tab escape", `x\ty`, []string{"x", "y"}, true},
		{"bare backslash", `\\ x`, []string{" ", "x"}, true},
		{"u escape kept as written", uEscape, []string{`\u00e9`, "x"}, true},
		{"comma escape", `a\, b`, []string{`a\,`, "b"}, true},
		{"hash escape", `a\#b c`, []string{`a\#b`, "c"}, true},
		{"unknown escape in double quotes", `"a\ b"`, []string{"a", " ", "b"}, true},
		{"single quoted tab", `'x\ty'`, []string{"x", "y"}, true},
		{"escaped quote", `a\'b c`, []string{"a'b", "c"}, true},
		{"windows path tab", `C:\temp x`, []string{"C:", "emp", "x"}, true},
		{"space escape reads the same", `a\ b c`, []string{"a b", "c"}, false},
		{"no backslash", `0123`, []string{"0", "1", "2", "3"}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			text := "base: old\n\tsymbols: " + c.value + "\n"
			up, err := UpgradeConfig(text)
			if err != nil {
				t.Fatal(err)
			}
			if up == nil {
				t.Fatal("an unstamped file was taken as current")
			}
			if up.FromFormat != 1 || up.Respelled != c.respelled {
				t.Fatalf("FromFormat %d, Respelled %v; want 1, %v", up.FromFormat, up.Respelled, c.respelled)
			}
			if v, ok := shcl.FormatVersion(up.Text); !ok || v != shcl.FormatMajor {
				t.Fatalf("converted text names format %d, %v", v, ok)
			}
			if again, err := UpgradeConfig(up.Text); again != nil || err != nil {
				t.Fatalf("converted text converts again: %v, %v", again, err)
			}

			want := strings.Join(c.want, "|")
			// The old file through LoadConfig, which converts in memory, and the
			// converted file as written to disk, which is read as it stands.
			for label, body := range map[string]string{"old file": text, "converted file": up.Text} {
				path := filepath.Join(t.TempDir(), "convert-base-v2.shcl")
				if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
					t.Fatal(err)
				}
				r, err := NewRegistry()
				if err != nil {
					t.Fatal(err)
				}
				if err := r.LoadConfig(path); err != nil {
					t.Fatalf("%s: %v", label, err)
				}
				if got := symbolsOf(t, r, "old"); got != want {
					t.Fatalf("%s: symbols %q, want %q", label, got, want)
				}
			}
		})
	}
}

// Test ID: ErgDzUY
func TestUpgradeConfigCurrentIsLeftAlone(t *testing.T) {
	for name, text := range map[string]string{
		"format line":   "base: x\n\tsymbols: ab\n" + shcl.FormatLine + "\n",
		"info block":    "base: x\n\tsymbols: ab\n\n" + shcl.GenBanner,
		"later version": "base: x\n\tsymbols: ab\n" + shcl.FormatLineHead + "9\n",
	} {
		if up, err := UpgradeConfig(text); up != nil || err != nil {
			t.Errorf("%s: got %v, %v; want nil, nil", name, up, err)
		}
	}
}

// Each of these failed to load under the old rules too, or cannot be carried
// over without changing what it says. None may come out of the conversion as
// a file that loads.
// Test ID: ErgDzUZ
func TestUpgradeConfigRefuses(t *testing.T) {
	cases := []struct {
		name string
		text string
		want string
	}{
		// The old parser read this with an error and the old loader refused
		// it. Migrate rewrites it to `symbols: ab` and reports nothing lost.
		{"bracket value", "base: x\n\tsymbols: [ab]\n", "line 2: bracket array syntax"},
		{"bracket header", "base: [x]\n\tsymbols: ab\n", "line 1: bracket array syntax"},
		// Migrate hands this back unchanged and unstamped.
		{"unclosed raw block", "base: x\n\tsymbols: 01\n\ttail:\n\t\t~~~\n\t\tab\n", "did not finish"},
		{"unknown field", "base: x\n\tsybmols: ab\n", `line 2: base "x": unknown field "sybmols"`},
		// The old rules read a newline here, which has no spelling now.
		{"windows path newline", "base: x\n\tsymbols: C:\\new x\n", "line 2: value starts like a Windows path"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			up, err := UpgradeConfig(c.text)
			if err == nil {
				t.Fatalf("converted without error:\n%s", up.Text)
			}
			if !strings.Contains(err.Error(), "written for SHCL format 1") || !strings.Contains(err.Error(), c.want) {
				t.Fatalf("got %v, want it to name format 1 and contain %q", err, c.want)
			}
			if err := loadConfigText(t, c.text); err == nil || !strings.Contains(err.Error(), c.want) {
				t.Fatalf("LoadConfig: got %v, want %q", err, c.want)
			}
		})
	}
}
