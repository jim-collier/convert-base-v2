//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"
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

// Built-ins are parsed and checked on first use, so a bad alphabet in bases.go
// no longer stops NewRegistry. This builds every one of them instead.
// Test ID: ErmQ6z6
func TestEveryBuiltinBuilds(t *testing.T) {
	reg := newReg(t)
	if len(reg.ordered) != len(predefinedBases()) {
		t.Fatalf("registry has %d bases, bases.go defines %d", len(reg.ordered), len(predefinedBases()))
	}
	for _, b := range reg.ordered {
		if err := b.ready(); err != nil {
			t.Errorf("%v", err)
			continue
		}
		for _, a := range b.Aliases {
			if got, err := reg.Lookup(a); err != nil || got != b {
				t.Errorf("alias %q of %s does not resolve to it: %v", a, b.Name(), err)
			}
		}
	}
}

// built reports which bases have been parsed and finalized so far.
func built(reg *Registry) []string {
	var names []string
	for _, b := range reg.ordered {
		if b.value != nil {
			names = append(names, b.Name())
		}
	}
	return names
}

func containsName(names []string, want string) bool {
	for _, n := range names {
		if n == want {
			return true
		}
	}
	return false
}

// A lookup builds the base it finds and nothing else. A miss builds nothing,
// though it walks every alias for suggestions.
// Test ID: ErmQ6zb
func TestLookupBuildsOnlyItsBase(t *testing.T) {
	reg := newReg(t)
	if got := built(reg); len(got) != 0 {
		t.Fatalf("a new registry has built %q", got)
	}
	if _, err := reg.Lookup("hexx"); err == nil {
		t.Fatal("hexx should not resolve")
	}
	if got := built(reg); len(got) != 0 {
		t.Errorf("an unknown name built %q", got)
	}
	hex := base(t, reg, "Base-Hex")
	big := base(t, reg, "65536utf32")
	got := built(reg)
	if len(got) != 2 || !containsName(got, hex.Name()) || !containsName(got, big.Name()) {
		t.Errorf("two lookups built %q, want only %s and %s", got, hex.Name(), big.Name())
	}
	if len(big.Symbols) != 65536 {
		t.Errorf("%s has %d symbols", big.Name(), len(big.Symbols))
	}
}

// Library callers may share one registry across goroutines. Each built-in is
// built once, however many lookups race for it. Run under -race to see a
// missing guard.
// Test ID: ErmQ706
func TestConcurrentLookup(t *testing.T) {
	reg := newReg(t)
	names := []string{"65536qntm", "32768qntm", "hex", "85ps", "bytes", "keyboard"}
	got := make([][]*Base, 8)
	var wg sync.WaitGroup
	for g := range got {
		wg.Add(1)
		go func(g int) {
			defer wg.Done()
			if g%2 == 1 {
				reg.OrderedBases()
			}
			for _, n := range names {
				b, err := reg.Lookup(n)
				if err != nil {
					t.Errorf("Lookup(%q): %v", n, err)
					return
				}
				got[g] = append(got[g], b)
			}
		}(g)
	}
	wg.Wait()
	for g := 1; g < len(got); g++ {
		for i := range got[g] {
			if got[g][i] != got[0][i] {
				t.Errorf("goroutine %d got a different %s", g, names[i])
			}
		}
	}
	bytesB := base(t, reg, "bytes")
	for _, b := range got[0] {
		if b.Binary || !b.RawCodec() {
			continue
		}
		enc, err := Convert("\x00\x01\xfe\xff", bytesB, b, 0)
		if err != nil {
			t.Fatalf("%s: %v", b.Name(), err)
		}
		if back, err := Convert(enc, b, bytesB, 0); err != nil || back != "\x00\x01\xfe\xff" {
			t.Errorf("%s round trip: %q, %v", b.Name(), back, err)
		}
	}
}

// Every run of the command builds a registry. Building all the built-ins took
// about 50 ms and 29 MB; deferring each to first use takes well under 1 ms.
// Test ID: ErmQ70b
func TestNewRegistryCost(t *testing.T) {
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	if _, err := NewRegistry(); err != nil {
		t.Fatal(err)
	}
	runtime.ReadMemStats(&after)
	if n := after.TotalAlloc - before.TotalAlloc; n > 2<<20 {
		t.Errorf("NewRegistry allocated %d bytes, want at most 2 MiB", n)
	}
	fastest := time.Hour
	for i := 0; i < 5; i++ {
		start := time.Now()
		if _, err := NewRegistry(); err != nil {
			t.Fatal(err)
		}
		fastest = min(fastest, time.Since(start))
	}
	if fastest > 10*time.Millisecond {
		t.Errorf("NewRegistry took %v at best, want at most 10ms", fastest)
	}
}

func BenchmarkNewRegistry(b *testing.B) {
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		if _, err := NewRegistry(); err != nil {
			b.Fatal(err)
		}
	}
}
