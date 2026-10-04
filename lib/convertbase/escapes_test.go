//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"runtime"
	"strings"
	"testing"
)

// Test ID: Elotfax
func TestExpandEscapes(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"", ""},
		{"plain text", "plain text"},
		{"A⊳LFB", "A\nB"},
		{"A⊳lfB", "A\nB"},       // names are case-insensitive
		{"A⊳NEWLINEB", "A\nB"},  // everyday alias
		{"A⊳x0AB", "A\nB"},      // hex form
		{"A⊳X0aB", "A\nB"},      // hex form, other case
		{"⊳TAB⊳HT", "\t\t"},     // alias and canonical name agree
		{"a\tb⊳LFc", "a\tb\nc"}, // raw and escaped, mixed
		{"⊳CR⊳LF", "\r\n"},
		{"⊳NUL⊳DEL⊳ESC", "\x00\x7f\x1b"},
		{"⊳SP", " "},
		{"⊳DQUOTE⊳SQUOTE⊳BACKSLASH", `"'\`},
		{"⊳SOH", "\x01"},   // longest name wins over SO
		{"⊳x0EH", "\x0eH"}, // ... and hex writes SO before an H
		{"⊳LF⊳LF⊳LF", "\n\n\n"},
	}
	for _, c := range cases {
		got, err := ExpandEscapes(c.in, nil)
		if err != nil {
			t.Errorf("ExpandEscapes(%q): %v", c.in, err)
			continue
		}
		if got != c.want {
			t.Errorf("ExpandEscapes(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// Test ID: Elotfay
func TestExpandEscapesErrors(t *testing.T) {
	for _, in := range []string{"⊳", "⊳ZZZ", "⊳x0", "⊳xZZ", "A⊳QQQ⊳LF", "⊳ "} {
		if _, err := ExpandEscapes(in, nil); err == nil {
			t.Errorf("ExpandEscapes(%q): expected an error", in)
		}
	}
}

// A base owning the marker as a digit keeps it. Expanding there would turn its
// own digits into something else.
// Test ID: Elotfaz
func TestExpandEscapesMarkerIsDigit(t *testing.T) {
	b := &Base{Aliases: []string{"marky"}, Symbols: []string{"⊳", "L", "F", "a"}}
	if err := b.Finalize(); err != nil {
		t.Fatal(err)
	}
	const in = "a⊳LF"
	got, err := ExpandEscapes(in, b)
	if err != nil {
		t.Fatal(err)
	}
	if got != in {
		t.Errorf("ExpandEscapes(%q) = %q, want it left alone", in, got)
	}
	if out := EscapeControls("a\nb", b); out != "a\nb" {
		t.Errorf("EscapeControls with a marker-owning base = %q, want it left alone", out)
	}
}

// The round trip is the whole contract, and the place it can break is a control
// character whose name runs into whatever follows it (SO before an H reads as
// SOH). Every control against every ASCII character covers that exhaustively.
// Test ID: Elotfb0
func TestEscapeControlsRoundTrip(t *testing.T) {
	var controls []byte
	for c := 0; c < 0x20; c++ {
		controls = append(controls, byte(c))
	}
	controls = append(controls, 0x7f)

	for _, c := range controls {
		for next := 0x20; next < 0x7f; next++ {
			in := string([]byte{'q', c, byte(next), 'z'})
			esc := EscapeControls(in, nil)
			if strings.ContainsAny(esc, "\x00\n\r\t") {
				t.Fatalf("EscapeControls(%q) left a control in %q", in, esc)
			}
			back, err := ExpandEscapes(esc, nil)
			if err != nil {
				t.Fatalf("ExpandEscapes(%q) from input %q: %v", esc, in, err)
			}
			if back != in {
				t.Fatalf("round trip of %q via %q gave %q", in, esc, back)
			}
		}
		// Two controls in a row, and one at the very end of the string.
		for _, in := range []string{string([]byte{c, c}), string([]byte{'z', c})} {
			back, err := ExpandEscapes(EscapeControls(in, nil), nil)
			if err != nil {
				t.Fatalf("round trip of %q: %v", in, err)
			}
			if back != in {
				t.Fatalf("round trip of %q gave %q", in, back)
			}
		}
	}
}

// Test ID: Elotfb1
func TestEscapeControlsLeavesTextAlone(t *testing.T) {
	const in = "Hello, World! 0123 ⊳ 日本"
	if got := EscapeControls(in, nil); got != in {
		t.Errorf("EscapeControls(%q) = %q", in, got)
	}
}

// End to end through the keyboard base, which is the reason any of this exists.
// Test ID: Elotfb2
func TestKeyboardBaseEscapes(t *testing.T) {
	reg, err := NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	kb, err := reg.Lookup("keyboard")
	if err != nil {
		t.Fatal(err)
	}
	dec, err := reg.Lookup("10")
	if err != nil {
		t.Fatal(err)
	}

	const text = "hi\nthere\tyou\r!"
	num, err := Convert(text, kb, dec, -1)
	if err != nil {
		t.Fatal(err)
	}

	raw, err := Convert(num, dec, kb, -1)
	if err != nil {
		t.Fatal(err)
	}
	if raw != text {
		t.Fatalf("plain round trip gave %q, want %q", raw, text)
	}

	esc := EscapeControls(raw, kb)
	if esc != "hi⊳LFthere⊳HTyou⊳CR!" {
		t.Fatalf("escaped form is %q", esc)
	}
	// The escaped spelling has to convert to exactly the same value as the raw one.
	again, err := Convert(esc, kb, dec, -1)
	if err != nil {
		t.Fatal(err)
	}
	if again != num {
		t.Fatalf("escaped input gave %q, want %q", again, num)
	}
}

// Each name is checked against the text after it. That check once copied the
// whole rest of the value, so escaping a long value was quadratic. Count the
// bytes allocated: linear stays near the input size, quadratic runs to gigabytes.
// Test ID: ErkSf4f
func TestEscapeControlsIsLinear(t *testing.T) {
	in := strings.Repeat("\n", 64*1024)
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	out := EscapeControls(in, nil)
	runtime.ReadMemStats(&after)
	if want := strings.Repeat("⊳LF", len(in)); out != want {
		t.Fatalf("escaped output is wrong, %d bytes", len(out))
	}
	if used := after.TotalAlloc - before.TotalAlloc; used > 64*uint64(len(in)) {
		t.Errorf("escaping %d bytes allocated %d", len(in), used)
	}
}
