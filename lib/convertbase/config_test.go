//	Copyright © 2023-2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
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
