//	Copyright © 2023-2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import "testing"

func sliceBase(t *testing.T, name string) *Base {
	t.Helper()
	reg, err := NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	b, err := reg.Lookup(name)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestSymbolSlice(t *testing.T) {
	hex := sliceBase(t, "16")
	tt := sliceBase(t, "128tt") // multi-byte digits: byte offsets would slice wrongly
	enc, err := Convert("1234567890", sliceBase(t, "10"), tt, -1)
	if err != nil {
		t.Fatal(err)
	}
	encDigits, err := tt.Tokenize(enc)
	if err != nil {
		t.Fatal(err)
	}
	if len(encDigits) != 5 || len(enc) <= 5 {
		t.Fatalf("128tt fixture %q: want 5 multi-byte symbols", enc)
	}

	cases := []struct {
		base         *Base
		s            string
		start, count int
		want         string
	}{
		{hex, "ABCDEF", 0, 3, "ABC"},
		{hex, "ABCDEF", 2, 2, "CD"},
		{hex, "ABCDEF", -3, -1, "DEF"},
		{hex, "ABCDEF", -2, 1, "E"},
		{hex, "ABCDEF", 0, -1, "ABCDEF"},
		{hex, "ABCDEF", 4, 99, "EF"},  // count clamps to the end
		{hex, "ABCDEF", 99, 2, ""},    // start clamps to the end
		{hex, "ABCDEF", -99, 2, "AB"}, // negative start clamps to the front
		{hex, "abcdef", 0, 2, "AB"},   // canonical form out
		{hex, "", 0, 5, ""},
		{tt, enc, -2, -1, encDigits[3] + encDigits[4]},
		{tt, enc, 1, 2, encDigits[1] + encDigits[2]},
	}
	for _, c := range cases {
		got, err := c.base.SymbolSlice(c.s, c.start, c.count)
		if err != nil {
			t.Errorf("SymbolSlice(%q, %d, %d): %v", c.s, c.start, c.count, err)
			continue
		}
		if got != c.want {
			t.Errorf("SymbolSlice(%q, %d, %d) = %q, want %q", c.s, c.start, c.count, got, c.want)
		}
	}

	if _, err := hex.SymbolSlice("12z", 0, 1); err == nil {
		t.Error("SymbolSlice on a bad digit: want error")
	}
	if _, err := hex.SymbolSlice("-FF", 0, 1); err == nil {
		t.Error("SymbolSlice on a signed value: want error")
	}
}

func TestFit(t *testing.T) {
	hex := sliceBase(t, "16")
	w32 := sliceBase(t, "32w") // zero symbol is "2", not "0"
	tt := sliceBase(t, "128tt")
	enc, err := Convert("1234567890", sliceBase(t, "10"), tt, -1)
	if err != nil {
		t.Fatal(err)
	}
	encDigits, err := tt.Tokenize(enc)
	if err != nil {
		t.Fatal(err)
	}

	cases := []struct {
		base  *Base
		s     string
		width int
		want  string
	}{
		{hex, "FF", 4, "00FF"},
		{hex, "ABCDEF", 4, "CDEF"}, // rightmost symbols survive
		{hex, "ABCD", 4, "ABCD"},
		{hex, "ABCD", 0, ""},
		{hex, "", 3, "000"},
		{w32, "X", 4, "222X"},
		{tt, enc, 3, encDigits[2] + encDigits[3] + encDigits[4]},
		{tt, enc, 7, tt.Symbols[0] + tt.Symbols[0] + enc},
	}
	for _, c := range cases {
		got, err := c.base.Fit(c.s, c.width)
		if err != nil {
			t.Errorf("Fit(%q, %d): %v", c.s, c.width, err)
			continue
		}
		if got != c.want {
			t.Errorf("Fit(%q, %d) = %q, want %q", c.s, c.width, got, c.want)
		}
	}

	if _, err := hex.Fit("FF", -1); err == nil {
		t.Error("Fit with negative width: want error")
	}
	if _, err := hex.Fit("12z", 4); err == nil {
		t.Error("Fit on a bad digit: want error")
	}
}
