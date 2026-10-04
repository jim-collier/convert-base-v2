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

func loadConfigText(t *testing.T, text string) error {
	t.Helper()
	path := filepath.Join(t.TempDir(), "convert-base-v2.shcl")
	if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
	r, err := NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	return r.LoadConfig(path)
}

// A field written twice reads back as Multiple, and every accessor answers that
// with a zero value - so the loader would quietly fall back to a default and
// build a base the file does not describe. Each of these was silent before.
// Test ID: Em1008w
func TestConfigRejectsRepeatedField(t *testing.T) {
	cases := map[string]string{
		"symbols":  "base: a\n\tsymbols: ab\n\tsymbols: cd\n",
		"negative": "base: a\n\tsymbols: ab\n\tnegative: X\n\tnegative: Y\n",
		"decimal":  "base: a\n\tsymbols: ab\n\tdecimal: X\n\tdecimal: Y\n",
		"aliases":  "base: a\n\tsymbols: ab\n\taliases: p\n\taliases: q\n",
		"pademit":  "base: a\n\tsymbols: ab\n\tpademit: true\n\tpademit: false\n",
		"apart":    "base: a\n\tsymbols: ab\n\tnegative: X\n\tdecimal: D\n\tnegative: Y\n",
	}
	for name, text := range cases {
		t.Run(name, func(t *testing.T) {
			err := loadConfigText(t, text)
			if err == nil {
				t.Fatalf("repeated %q loaded without error", name)
			}
			if !strings.Contains(err.Error(), "more than once") {
				t.Fatalf("repeated %q: got %v", name, err)
			}
		})
	}
}

// A name needing quotes was invisible to the path enumeration the check used to
// walk, so a quoted typo slipped past the unknown-field guard entirely.
// Test ID: Em1008x
func TestConfigRejectsQuotedUnknownField(t *testing.T) {
	cases := map[string]string{
		"dotted":    "base: a\n\tsymbols: ab\n\t\"weird.field\": 1\n",
		"backslash": "base: a\n\tsymbols: ab\n\t\"back\\\\\": 1\n",
		"toplevel":  "\"odd.name\": 1\nbase: a\n\tsymbols: ab\n",
	}
	for name, text := range cases {
		t.Run(name, func(t *testing.T) {
			err := loadConfigText(t, text)
			if err == nil {
				t.Fatalf("quoted unknown field %q loaded without error", name)
			}
			if !strings.Contains(err.Error(), "unknown") {
				t.Fatalf("quoted unknown field %q: got %v", name, err)
			}
		})
	}
}

// No base field takes fields of its own, so anything indented under one is a
// mistake. The field above it still reads, often as Empty, which disables a
// marker on purpose - so the stray line used to cost a marker without a word.
// Test ID: Erg4X7J
func TestConfigRejectsNestedField(t *testing.T) {
	cases := map[string]string{
		"under empty":  "base: a\n\tsymbols: ab\n\tnegative:\n\t\tdecimal: X\n",
		"under value":  "base: a\n\tsymbols: ab\n\tnegative: N\n\t\tdecimal: X\n",
		"under alias":  "base: a\n\tsymbols: ab\n\taliases: p\n\t\tdecimal: X\n",
		"under symbol": "base: a\n\tsymbols: ab\n\t\tpad: =\n",
		"under bool":   "base: a\n\tsymbols: ab\n\tpademit: false\n\t\tpad: =\n",
		"deeper":       "base: a\n\tsymbols: ab\n\tnegative:\n\t\tdecimal:\n\t\t\tpad: Y\n",
		"dotted":       "base: a\n\tsymbols: ab\n\tnegative.decimal: X\n",
		"quoted":       "base: a\n\tsymbols: ab\n\tnegative:\n\t\t\"odd.x\": X\n",
		"later base":   "base: a\n\tsymbols: ab\n\nbase: b\n\tsymbols: cd\n\tdecimal:\n\t\tnegative: X\n",
		"merged twice": "base: a\n\tsymbols: ab\n\tnegative:\n\t\tdecimal: X\n\tnegative:\n\t\tpad: Y\n",
	}
	for name, text := range cases {
		t.Run(name, func(t *testing.T) {
			err := loadConfigText(t, text)
			if err == nil {
				t.Fatalf("nested field (%s) loaded without error", name)
			}
			if !strings.Contains(err.Error(), "nested under") {
				t.Fatalf("nested field (%s): got %v", name, err)
			}
		})
	}
}

// Every way a config file can be refused cites the line it went wrong on. The
// repeat is the one that needs Lines() rather than Line(), since a path with two
// bindings is exactly what the singular cannot place.
// Test ID: Em2MFrs
func TestConfigErrorsCiteLines(t *testing.T) {
	cases := []struct {
		name string
		text string
		want string
	}{
		{"repeat", "base: a\n\tsymbols: ab\n\tnegative: X\n\tdecimal: D\n\tnegative: Y\n",
			"line 5: base \"a\": negative is given more than once (first at line 3)"},
		{"unknown", "base: a\n\tsymbols: ab\n\tsymbold: X\n", "line 3: base \"a\": unknown field"},
		{"quoted", "base: a\n\tsymbols: ab\n\t\"weird.field\": 1\n", "line 3: base \"a\": unknown field"},
		{"toplevel", "\n\"odd.name\": 1\nbase: a\n\tsymbols: ab\n", "line 2: unknown setting"},
		{"nosymbols", "base: a\n\tsymbols: ab\n\nbase: b\n\tnegative: X\n", "line 4: base \"b\": missing"},
		{"noname", "base: a\n\tsymbols: ab\n\nbase:\n\tsymbols: cd\n", "line 4: a \"base:\" line has no name"},
		{"pademit", "base: a\n\tsymbols: ab\n\tpademit: maybe\n", "line 3: base \"a\": pademit"},
		{"nested", "base: a\n\tsymbols: ab\n\tnegative:\n\t\tdecimal: X\n",
			"line 4: base \"a\": \"decimal\" is nested under negative"},
		{"raw marker", "base: a\n\tsymbols: ab\n\tnegative:\n\t\t~~~\n\t\t~\n\t\t~~~\n",
			"line 3: base \"a\": negative takes a one-line value, not a raw block"},
		{"raw name", "base: a\n\tsymbols: ab\n\nbase:\n\t~~~\n\tb\n\t~~~\n\tsymbols: cd\n",
			"line 4: a \"base:\" name is one line, not a raw block"},
		// Registration knows the base, not the field, so it cites the block.
		{"badsymbols", "base: a\n\tsymbols: ab\n\nbase: b\n\tsymbols: \"c c\"\n",
			"line 4: base \"b\": duplicate symbol"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := loadConfigText(t, c.text)
			if err == nil {
				t.Fatalf("%s loaded without error", c.name)
			}
			if !strings.Contains(err.Error(), c.want) {
				t.Fatalf("%s: want %q, got %v", c.name, c.want, err)
			}
		})
	}
}

// An empty pad: switches padding off, pad: X writes it, and pademit: false
// keeps a pad that is read but never written.
// Test ID: ErkSf4u
func TestConfigPadFields(t *testing.T) {
	const b32 = "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z 2 3 4 5 6 7"
	cfg := "base: nopad\n\tsymbols: " + b32 + "\n\tpad:\n\n" +
		"base: withpad\n\tsymbols: " + b32 + "\n\tpad: =\n\n" +
		"base: readpad\n\tsymbols: " + b32 + "\n\tpad: =\n\tpademit: false\n"
	path := filepath.Join(t.TempDir(), "convert-base-v2.shcl")
	if err := os.WriteFile(path, []byte(cfg), 0o600); err != nil {
		t.Fatal(err)
	}
	reg := newReg(t)
	if err := reg.LoadConfig(path); err != nil {
		t.Fatal(err)
	}
	bin := base(t, reg, "bytes")
	for _, c := range []struct{ name, want string }{
		{"nopad", "IE"}, {"withpad", "IE======"}, {"readpad", "IE"},
	} {
		got, err := Convert("A", bin, base(t, reg, c.name), 0)
		if err != nil || got != c.want {
			t.Errorf("%s: A -> %q, %v; want %q", c.name, got, err, c.want)
		}
	}
	if got, err := Convert("IE======", base(t, reg, "readpad"), bin, 0); err != nil || got != "A" {
		t.Errorf("readpad should still read a padded value: %q, %v", got, err)
	}
}

// The shapes the file is meant to carry still load.
// Test ID: Em1008y
func TestConfigAcceptsValidShapes(t *testing.T) {
	text := "base: myb\n\taliases: mybase, mb\n\tsymbols: \"z y x w\"\n\n" +
		"base: nodec\n\tsymbols: 0123456789\n\tdecimal:\n\n" +
		"base: fruit4\n\tsymbols:\n\t\t* 🍎\n\t\t* 🍊\n\t\t* 🍋\n\t\t* 🍌\n\n" +
		"base: spacey\n\tsymbols: \"a b\", c, d, e\n\n" +
		"base: quoted\n\t\"symbols\": abcd\n"
	if err := loadConfigText(t, text); err != nil {
		t.Fatalf("valid config rejected: %v", err)
	}
}

// A backslash in a symbols value can belong to one of two layers. SHCL reads
// escapes only inside double quotes, and the one string form then goes through
// ParseSymbolSpec, which has escapes of its own. These pin which layer reads
// which backslash, so a parser change that would quietly change an alphabet
// fails here first.
// Test ID: Erg0gZ2
func TestConfigBackslashLayers(t *testing.T) {
	uEscape := `"` + `\` + `u00e9 x"` // spelled in pieces to keep the escape out of the source text
	cases := []struct {
		name  string
		value string
		want  []string // nil means the load must fail
	}{
		{"bare space escape", `a\ b c`, []string{"a b", "c"}},
		{"double quoted, doubled", `"a\\ b c"`, []string{"a b", "c"}},
		{"single quoted is literal", `'a\ b c'`, []string{"a b", "c"}},
		{"bare tab escape", `x\ty`, []string{"x", "\t", "y"}},
		{"bare backslash digit", `\\ x`, []string{`\`, "x"}},
		{"double quoted backslash digit", `"\\\\ x"`, []string{`\`, "x"}},
		// SHCL turns this one into a real tab, which the spec then splits on.
		{"double quoted tab separates", `"x\ty"`, []string{"x", "y"}},
		{"double quoted u escape", uEscape, []string{"é", "x"}},
		// The list form skips ParseSymbolSpec, so a backslash there is a digit.
		{"list element is literal", `a\ b, c`, []string{`a\ b`, "c"}},
		// \, and \# protected the next character before shcl 3.0. Now the comma
		// splits and the # starts a comment.
		{"comma no longer protected", `a\, b`, []string{`a\`, "b"}},
		{"hash no longer protected", `a\#b c`, []string{"a", `\`}},
		{"unknown escape in double quotes", `"a\ b"`, nil},
		{"bracket text", `[ab]`, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "convert-base-v2.shcl")
			// Stamped, since these pin the current rules. An unstamped file is
			// read the old way; TestUpgradeConfigKeepsOldMeaning pins that.
			text := "base: bs\n\tsymbols: " + c.value + "\n" + shcl.FormatLine + "\n"
			if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
				t.Fatal(err)
			}
			r, err := NewRegistry()
			if err != nil {
				t.Fatal(err)
			}
			err = r.LoadConfig(path)
			if c.want == nil {
				if err == nil {
					t.Fatalf("%s loaded without error", c.value)
				}
				if !strings.Contains(err.Error(), "line 2") {
					t.Fatalf("%s: error does not cite line 2: %v", c.value, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("%s: %v", c.value, err)
			}
			b, err := ResolveBase(r, "bs", "", nil)
			if err != nil {
				t.Fatal(err)
			}
			if strings.Join(b.Symbols, "|") != strings.Join(c.want, "|") {
				t.Fatalf("%s: symbols %q, want %q", c.value, b.Symbols, c.want)
			}
		})
	}
}

// No field takes a raw block. One used to be dropped, as an alias or a tail was,
// or read with its line breaks kept, as a marker was. Under symbols it could mean
// two different alphabets, one digit per row or one per character.
// Test ID: Erg6SWX
func TestConfigRejectsRawBlockValue(t *testing.T) {
	block := "\n\t\t~~~\n\t\tx\n\t\t~~~\n"
	cases := map[string]string{
		"symbols":  "base: a\n\tsymbols:" + block,
		"rows":     "base: a\n\tsymbols:\n\t\t~~~\n\t\tABCD\n\t\tEFGH\n\t\t~~~\n",
		"tail":     "base: a\n\tsymbols: ab\n\ttail:" + block,
		"aliases":  "base: a\n\tsymbols: ab\n\taliases:" + block,
		"negative": "base: a\n\tsymbols: ab\n\tnegative:" + block,
		"two-line": "base: a\n\tsymbols: ab\n\tnegative:\n\t\t~~~\n\t\tx\n\t\ty\n\t\t~~~\n",
		"decimal":  "base: a\n\tsymbols: ab\n\tdecimal:" + block,
		"pad":      "base: a\n\tsymbols: ab\n\tpad:" + block,
		"pademit":  "base: a\n\tsymbols: ab\n\tpad: =\n\tpademit:\n\t\t~~~\n\t\ttrue\n\t\t~~~\n",
		"name":     "base:\n\t~~~\n\tnm\n\t~~~\n\tsymbols: ab\n",
	}
	for name, text := range cases {
		t.Run(name, func(t *testing.T) {
			err := loadConfigText(t, text)
			if err == nil {
				t.Fatalf("raw block as %s loaded without error", name)
			}
			if !strings.Contains(err.Error(), "not a raw block") || !strings.Contains(err.Error(), "line ") {
				t.Fatalf("raw block as %s: got %v", name, err)
			}
		})
	}
}
