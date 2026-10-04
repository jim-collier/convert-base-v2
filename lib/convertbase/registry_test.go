//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// A bare-number alias is a size, so it has to match the symbol count. Only the
// first alias used to be checked, and only before the "b" prefix came off.
// Test ID: ErkSf4Y
func TestRegisterChecksEveryNumericAlias(t *testing.T) {
	for _, aliases := range [][]string{
		{"99"},
		{"three", "99"},
		{"three", "b99"},
		{"3", "base99"},
	} {
		reg := newReg(t)
		err := reg.Register(&Base{Aliases: aliases, Symbols: []string{"x", "y", "z"}})
		if err == nil {
			t.Errorf("aliases %q on a 3-symbol base should be refused", aliases)
		}
	}
	reg := newReg(t)
	if err := reg.Register(&Base{Aliases: []string{"three", "b3"}, Symbols: []string{"x", "y", "z"}}); err != nil {
		t.Errorf("a matching size alias should register: %v", err)
	}
}

// A config base that takes every name of a built-in replaces it. The built-in
// leaves the index, and the listing shows only names that still resolve to
// the row they sit on.
// Test ID: ErkSf4Z
func TestConfigShadowedBuiltinDropsOut(t *testing.T) {
	reg := newReg(t)
	old := base(t, reg, "8")
	before := len(reg.OrderedBases())
	part := base(t, reg, "16")

	cfg := "base: " + old.Aliases[0] + "\n\tsymbols: 0 1 2 3 4 5 6 X\n"
	if len(old.Aliases) > 1 {
		cfg += "\taliases: " + strings.Join(old.Aliases[1:], ", ") + "\n"
	}
	// One name taken from another built-in, which has to stay listed.
	cfg += "\nbase: hexish\n\taliases: " + part.Aliases[len(part.Aliases)-1] + "\n\tsymbols: a b c\n"
	path := filepath.Join(t.TempDir(), "convert-base-v2.shcl")
	if err := os.WriteFile(path, []byte(cfg), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := reg.LoadConfig(path); err != nil {
		t.Fatal(err)
	}

	ordered := reg.OrderedBases()
	if len(ordered) != before+1 {
		t.Errorf("index has %d bases, want %d: one replaced, one added", len(ordered), before+1)
	}
	for _, b := range ordered {
		if b == old {
			t.Error("the replaced built-in is still in the index")
		}
		for _, a := range reg.liveAliases(b) {
			if got, err := reg.Lookup(a); err != nil || got != b {
				t.Errorf("listed alias %q of %s resolves elsewhere", a, b.Name())
			}
		}
	}
	if !containsBase(ordered, part) {
		t.Error("a built-in that lost one alias dropped out of the index")
	}
	var listing bytes.Buffer
	reg.Print(&listing, false)
	for _, line := range strings.Split(listing.String(), "\n") {
		f := strings.Fields(line)
		if len(f) > 1 && f[1] == part.Name() && strings.Contains(line, part.Aliases[len(part.Aliases)-1]) {
			t.Errorf("the listing still shows the stolen alias on %s: %q", part.Name(), line)
		}
	}
}

func containsBase(list []*Base, b *Base) bool {
	for _, x := range list {
		if x == b {
			return true
		}
	}
	return false
}
