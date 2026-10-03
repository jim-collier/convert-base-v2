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

// The shapes the file is meant to carry still load.
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
			if err := os.WriteFile(path, []byte("base: bs\n\tsymbols: "+c.value+"\n"), 0o600); err != nil {
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

// A raw block under symbols or tail is the one string spelling over several
// lines. Before, an array read of a block came back BadType with no value, so
// symbols reported as missing and a tail was dropped without a word.
func TestConfigRawBlockSymbols(t *testing.T) {
	cases := []struct {
		name string
		body string // the lines of the block, already indented
		want []string
	}{
		{"several lines", "\t\t~~~\n\t\tA B\n\t\tC D\n\t\t~~~\n", []string{"A", "B", "C", "D"}},
		{"one word splits per rune", "\t\t~~~\n\t\tABCD\n\t\t~~~\n", []string{"A", "B", "C", "D"}},
		{"fence on the field line", " ~~~\n\t\tw x\n\t\ty z\n\t\t~~~\n", []string{"w", "x", "y", "z"}},
		{"label ignored", "\t\t~~~text\n\t\tp q\n\t\t~~~\n", []string{"p", "q"}},
		// SHCL leaves a block's text alone, so # and quotes are digits.
		{"no comments or quotes", "\t\t```\n\t\t# \" '\n\t\t```\n", []string{"#", `"`, "'"}},
		{"spec escapes still apply", "\t\t~~~\n\t\ta\\ b c\n\t\t~~~\n", []string{"a b", "c"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "convert-base-v2.shcl")
			if err := os.WriteFile(path, []byte("base: rb\n\tsymbols:"+c.body), 0o600); err != nil {
				t.Fatal(err)
			}
			r, err := NewRegistry()
			if err != nil {
				t.Fatal(err)
			}
			if err := r.LoadConfig(path); err != nil {
				t.Fatalf("%v", err)
			}
			b, err := ResolveBase(r, "rb", "", nil)
			if err != nil {
				t.Fatal(err)
			}
			if strings.Join(b.Symbols, "|") != strings.Join(c.want, "|") {
				t.Fatalf("symbols %q, want %q", b.Symbols, c.want)
			}
		})
	}

	t.Run("big alphabet with a tail", func(t *testing.T) {
		var text strings.Builder
		text.WriteString("base: cjk512\n\tsymbols:\n\t\t~~~\n")
		for row := 0; row < 16; row++ {
			text.WriteString("\t\t")
			for col := 0; col < 32; col++ {
				text.WriteRune(rune(0x4E00 + row*32 + col))
				text.WriteByte(' ')
			}
			text.WriteByte('\n')
		}
		text.WriteString("\t\t~~~\n\ttail:\n\t\t~~~\n\t\t\u2E10 \u2E11\n\t\t~~~\n")
		path := filepath.Join(t.TempDir(), "convert-base-v2.shcl")
		if err := os.WriteFile(path, []byte(text.String()), 0o600); err != nil {
			t.Fatal(err)
		}
		r, err := NewRegistry()
		if err != nil {
			t.Fatal(err)
		}
		if err := r.LoadConfig(path); err != nil {
			t.Fatal(err)
		}
		b, err := ResolveBase(r, "cjk512", "", nil)
		if err != nil {
			t.Fatal(err)
		}
		if len(b.Symbols) != 512 || len(b.TailSymbols) != 2 {
			t.Fatalf("got %d symbols and %d tail symbols, want 512 and 2", len(b.Symbols), len(b.TailSymbols))
		}
	})

	t.Run("empty block is no symbols", func(t *testing.T) {
		err := loadConfigText(t, "base: rb\n\tsymbols:\n\t\t~~~\n\t\t~~~\n")
		if err == nil || !strings.Contains(err.Error(), "missing 'symbols'") {
			t.Fatalf("got %v", err)
		}
	})
}

// Every other field is one short value. A block there used to be dropped, as an
// alias was, or read with its line breaks kept, as a marker was. So it is refused.
func TestConfigRejectsRawBlockValue(t *testing.T) {
	block := "\n\t\t~~~\n\t\tx\n\t\t~~~\n"
	cases := map[string]string{
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
