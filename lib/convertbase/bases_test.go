//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"strings"
	"testing"
	"unicode/utf8"
)

// ascending reports the first digit that is not one code point above the one
// before it, or -1. Order is what 2048tt got wrong, and nothing else would see
// it: an out-of-order alphabet still round-trips.
func ascending(syms []string) int {
	prev := rune(-1)
	for i, s := range syms {
		r, n := utf8.DecodeRuneInString(s)
		if n != len(s) || r <= prev {
			return i
		}
		prev = r
	}
	return -1
}

// The tt and tz families are prefixes of two ordered alphabets that agree for
// their first 384 symbols. Below 512 a tt and a tz name are one base.
// Test ID: ErkSf4W
func TestTTFamilyOrdered(t *testing.T) {
	tt, tz := strings.Fields(base_534tt), strings.Fields(base_2048tz)
	if i := ascending(tt); i >= 0 {
		t.Errorf("534tt digit %d %q is out of code point order", i, tt[i])
	}
	if i := ascending(tz); i >= 0 {
		t.Errorf("2048tz digit %d %q is out of code point order", i, tz[i])
	}
	if len(tt) < 512 || len(tz) < 2048 {
		t.Fatalf("alphabets too short: tt %d, tz %d", len(tt), len(tz))
	}
	for i := 0; i < 384; i++ {
		if tt[i] != tz[i] {
			t.Fatalf("tt and tz differ at digit %d: %q vs %q", i, tt[i], tz[i])
		}
	}

	reg := newReg(t)
	for _, c := range []struct {
		name string
		from []string
	}{
		{"64tt", tt}, {"128tt", tt}, {"256tt", tt}, {"512tt", tt},
		{"512tz", tz}, {"1024tz", tz}, {"2048tz", tz},
	} {
		b := base(t, reg, c.name)
		if strings.Join(b.Symbols, " ") != strings.Join(c.from[:len(b.Symbols)], " ") {
			t.Errorf("%s is not the first %d digits of its family", c.name, len(b.Symbols))
		}
	}
	for _, n := range []string{"64", "128", "256"} {
		if base(t, reg, n+"tt") != base(t, reg, n+"tz") {
			t.Errorf("%stt and %stz should be one base", n, n)
		}
	}
	if _, err := reg.Lookup("2048tt"); err == nil {
		t.Error("2048tt was retired and should not resolve")
	}
	if b := base(t, reg, "10blocks"); ascending(b.Symbols) >= 0 {
		t.Errorf("10blocks is out of code point order: %q", b.Symbols)
	}
}

// Emoji digits are single code points that draw in color on their own: no
// presentation selector, no skin tone, and none of the four text-presentation
// ones 69emoji used to carry. Both bases are in code point order.
// Test ID: ErkSf4X
func TestEmojiDigits(t *testing.T) {
	reg := newReg(t)
	textStyle := map[rune]bool{0x2702: true, 0x2764: true, 0x2934: true, 0x1F6CF: true}
	for _, name := range []string{"64emoji", "69emoji"} {
		b := base(t, reg, name)
		for i, s := range b.Symbols {
			r, n := utf8.DecodeRuneInString(s)
			switch {
			case n != len(s):
				t.Errorf("%s digit %d %q is more than one code point", name, i, s)
			case r >= 0x1F3FB && r <= 0x1F3FF:
				t.Errorf("%s digit %d is a skin tone modifier", name, i)
			case textStyle[r]:
				t.Errorf("%s digit %d U+%04X draws as text by default", name, i, r)
			}
		}
		if i := ascending(b.Symbols); i >= 0 {
			t.Errorf("%s digit %d %q is out of code point order", name, i, b.Symbols[i])
		}
	}
}
