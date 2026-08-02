//	Copyright © 2023-2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"bytes"
	"encoding/hex"
	"math/big"
	"math/rand"
	"strings"
	"testing"
)

// Real unit tests for the conversion core. `make test` used to run only
// benchmarks, so `go test` gated nothing. These pin the number path, the codec
// and native-base vectors (same reference values as test.bash), markers and
// custom symbols, the spec parser, and - most important - that the streaming and
// buffered binary paths agree byte-for-byte, since they are two hand-tuned
// implementations of the same encodings.

func newReg(t testing.TB) *Registry {
	t.Helper()
	reg, err := NewRegistry()
	if err != nil {
		t.Fatalf("NewRegistry: %v", err)
	}
	return reg
}

func base(t testing.TB, reg *Registry, name string) *Base {
	t.Helper()
	b, err := reg.Lookup(name)
	if err != nil {
		t.Fatalf("Lookup(%q): %v", name, err)
	}
	return b
}

func customBase(t testing.TB, reg *Registry, spec string) *Base {
	t.Helper()
	b, err := ResolveBase(reg, "", spec, nil)
	if err != nil {
		t.Fatalf("ResolveBase(%q): %v", spec, err)
	}
	return b
}

// mk builds an Options the way flag parsing would. A nil neg/dec means the flag
// was not given; a string (including "") means it was.
func mk(label string, neg, dec interface{}) *Options {
	o := &Options{Label: label}
	if s, ok := neg.(string); ok {
		o.Negative = &s
	}
	if s, ok := dec.(string); ok {
		o.Decimal = &s
	}
	return o
}

// markerBase builds a custom base and applies marker overrides to it, the same
// way the --from-neg / --from-dec flags do.
func markerBase(t testing.TB, reg *Registry, spec, neg, dec string) *Base {
	t.Helper()
	b := customBase(t, reg, spec)
	b, err := ApplyOptions(b, mk("--from", neg, dec))
	if err != nil {
		t.Fatalf("ApplyOptions(%q, neg %q, dec %q): %v", spec, neg, dec, err)
	}
	return b
}

func mustHex(t testing.TB, h string) string {
	t.Helper()
	raw, err := hex.DecodeString(h)
	if err != nil {
		t.Fatalf("bad hex %q: %v", h, err)
	}
	return string(raw)
}

// runes builds a string from space-separated hex code points, matching the
// nvec() helper in test.bash.
func runes(cps ...rune) string { return string(cps) }

func TestNumberVectors(t *testing.T) {
	reg := newReg(t)
	cases := []struct {
		from, to, in, want string
		prec               int
	}{
		{"10", "16", "255", "FF", 50},
		{"16", "10", "FF", "255", 50},
		{"10", "8", "255", "377", 50},
		{"10", "2", "255", "11111111", 50},
		{"2", "10", "11111111", "255", 50},
		{"10", "16", "-123456", "-1E240", 50},
		{"16", "10", "-1E240", "-123456", 50},
		{"10", "16", "000255", "FF", 50}, // leading zeros dropped
		{"10", "16", "1.5", "1.8", 50},
		{"16", "10", "1.8", "1.5", 50},
		{"10", "3", "1.5", "1.12", 2}, // rounds half-up, not truncates
	}
	for _, c := range cases {
		from, to := base(t, reg, c.from), base(t, reg, c.to)
		got, err := Convert(c.in, from, to, c.prec)
		if err != nil {
			t.Errorf("Convert(%q, %s->%s): %v", c.in, c.from, c.to, err)
			continue
		}
		if got != c.want {
			t.Errorf("Convert(%q, %s->%s) = %q, want %q", c.in, c.from, c.to, got, c.want)
		}
	}
}

// prec = -1 asks Convert for auto precision: output frac length tracks the
// input's, scaled by base size, so no invented tail. These pin the odd corners.
func TestAutoPrecision(t *testing.T) {
	reg := newReg(t)
	cases := []struct{ from, to, in, want string }{
		{"10", "16", "0.1", "0.1A"},          // 1 dec digit -> 2 hex, honest tail not 50
		{"10", "2", "0.1", "0.00011"},        // widens: 1 dec -> 5 binary
		{"10", "3", "0.1", "0.0022"},         // odd base ratio
		{"10", "2", "0.5", "0.1"},            // terminates, trailing zeros trimmed
		{"16", "10", "FF.8", "255.5"},        // narrows: exact half trims to one digit
		{"10", "16", "1.5", "1.8"},           // exact, integer part carries through
		{"16", "2", "0.8", "0.1"},            // power-of-2 both sides, positional path
		{"10", "10", "3.14", "3.14"},         // identity base ratio, nothing invented
		{"10", "2", "0.9", "0.11101"},        // guard digit forces a round-up at the edge
		{"10", "16", "255", "FF"},            // no fraction -> auto precision is zero
		{"288j1", "10", "0.1", "0.0035"},     // big base -> small base
		{"10", "16", "0.000001", "0.000011"}, // tiny value, still no spurious 0
	}
	for _, c := range cases {
		from, to := base(t, reg, c.from), base(t, reg, c.to)
		got, err := Convert(c.in, from, to, -1)
		if err != nil {
			t.Errorf("Convert(%q, %s->%s, auto): %v", c.in, c.from, c.to, err)
			continue
		}
		if got != c.want {
			t.Errorf("Convert(%q, %s->%s, auto) = %q, want %q", c.in, c.from, c.to, got, c.want)
		}
	}
}

func TestCodecVectors(t *testing.T) {
	reg := newReg(t)
	bytesB := base(t, reg, "bytes")
	cases := []struct{ base, hexIn, want string }{
		{"45", "4142", "BB8"},
		{"45", "6965746621", "QED8WEX0"},
		{"85ps", "737572652e", "F*2M7/c"},
		{"85ps", "00000000", "z"},
		{"85z", "864fd26fb559f75b", "HelloWorld"},
		{"91hk", "74657374", "fPNKd"},
	}
	for _, c := range cases {
		to := base(t, reg, c.base)
		in := mustHex(t, c.hexIn)
		got, err := Convert(in, bytesB, to, 0)
		if err != nil {
			t.Errorf("codec %s encode: %v", c.base, err)
			continue
		}
		if got != c.want {
			t.Errorf("codec %s: encode(%s) = %q, want %q", c.base, c.hexIn, got, c.want)
		}
		// Decode must recover the exact bytes.
		back, err := Convert(got, to, bytesB, 0)
		if err != nil {
			t.Errorf("codec %s decode: %v", c.base, err)
			continue
		}
		if back != in {
			t.Errorf("codec %s: decode round-trip mismatch for %s", c.base, c.hexIn)
		}
	}
}

func TestNativeBaseVectors(t *testing.T) {
	reg := newReg(t)
	bytesB := base(t, reg, "bytes")
	cases := []struct {
		base, hexIn, want string
	}{
		{"65536qntm", "00", runes(0x1500)},
		{"65536qntm", "0102", runes(0x3601)},
		{"65536qntm", "010203", runes(0x3601, 0x1503)},
		{"65536qntm", "ffff", runes(0x285FF)},
		{"65536qntm", "48656c6c6f", runes(0x9A48, 0xA36C, 0x156F)},
		{"32768qntm", "00", runes(0x06BF)},
		{"32768qntm", "0000", runes(0x04A0, 0x025F)},
		{"32768qntm", "000000000000", runes(0x04A0, 0x04A0, 0x04A0, 0x018F)},
		{"2048qntm", "00", runes(0x0046)},
		{"2048qntm", "0000", runes(0x0038, 0x0110)},
		{"2048qntm", "010203", runes(0x0047, 0x01B7, 0x0037)},
		{"2048llfourn", "00", runes(0x00D8)},
		{"2048llfourn", "000000", runes(0x00D8, 0x00D8, 0x0F0D)},
		{"2048llfourn", "010203", runes(0x00C5, 0x0140, 0x0F10)},
	}
	for _, c := range cases {
		to := base(t, reg, c.base)
		in := mustHex(t, c.hexIn)
		got, err := Convert(in, bytesB, to, 0)
		if err != nil {
			t.Errorf("native %s encode(%s): %v", c.base, c.hexIn, err)
			continue
		}
		if got != c.want {
			t.Errorf("native %s: encode(%s) = %x, want %x", c.base, c.hexIn, got, c.want)
		}
		back, err := Convert(got, to, bytesB, 0)
		if err != nil {
			t.Errorf("native %s decode: %v", c.base, err)
			continue
		}
		if back != in {
			t.Errorf("native %s: decode round-trip mismatch for %s (got %x)", c.base, c.hexIn, back)
		}
	}
}

// RFC 4648 vectors: every RFC variant pads to the group boundary in codec mode.
func TestRFCPaddingVectors(t *testing.T) {
	reg := newReg(t)
	bytesB := base(t, reg, "bytes")
	cases := []struct{ base, in, want string }{
		{"64", "f", "Zg=="},
		{"64", "fo", "Zm8="},
		{"64", "foobar", "Zm9vYmFy"},
		{"32", "f", "MY======"},
		{"32", "foobar", "MZXW6YTBOI======"},
		{"64u", "foob", "Zm9vYg=="},
		{"32h", "f", "CO======"},
	}
	for _, c := range cases {
		to := base(t, reg, c.base)
		got, err := Convert(c.in, bytesB, to, 0)
		if err != nil {
			t.Errorf("rfc %s: %v", c.base, err)
			continue
		}
		if got != c.want {
			t.Errorf("rfc %s: encode(%q) = %q, want %q", c.base, c.in, got, c.want)
		}
		// Decode accepts both padded and unpadded input.
		for _, variant := range []string{got, strings.TrimRight(got, "=")} {
			back, err := Convert(variant, to, bytesB, 0)
			if err != nil {
				t.Errorf("rfc %s decode(%q): %v", c.base, variant, err)
				continue
			}
			if back != c.in {
				t.Errorf("rfc %s decode(%q) = %q, want %q", c.base, variant, back, c.in)
			}
		}
	}
	// Number-mode output is never padded.
	got, err := Convert("255", base(t, reg, "10"), base(t, reg, "64u"), 0)
	if err != nil {
		t.Fatalf("number 64u: %v", err)
	}
	if strings.Contains(got, "=") {
		t.Errorf("number-mode 64u output should not be padded, got %q", got)
	}
}

// Crockford base32 decodes O as 0 and I/L as 1 (case-insensitive) but only ever
// emits the strict alphabet.
func TestCrockfordAsymmetric(t *testing.T) {
	reg := newReg(t)
	b32c := base(t, reg, "32c")
	dec10 := base(t, reg, "10")
	dec := map[string]string{"O1": "1", "o1": "1", "I1": "33", "L1": "33", "l1": "33", "LO": "32"}
	for in, want := range dec {
		got, err := Convert(in, b32c, dec10, 0)
		if err != nil {
			t.Errorf("32c decode %q: %v", in, err)
			continue
		}
		if got != want {
			t.Errorf("32c decode %q = %q, want %q", in, got, want)
		}
	}
	// Encoding never produces O, I, or L.
	for n := 0; n < 32; n++ {
		got, err := Convert(itoa(n), dec10, b32c, 0)
		if err != nil {
			t.Fatalf("encode %d: %v", n, err)
		}
		if strings.ContainsAny(got, "OIL") {
			t.Errorf("32c encode(%d) = %q contains a decode-only alias", n, got)
		}
	}
}

func TestCustomSymbolsAndMarkers(t *testing.T) {
	reg := newReg(t)
	dec10 := base(t, reg, "10")
	// Multi-char digits and a fractional value.
	from := customBase(t, reg, "ABCD")
	got, err := Convert("CBBA.B", from, dec10, 50)
	if err != nil {
		t.Fatalf("custom multichar: %v", err)
	}
	if got != "148.25" {
		t.Errorf("custom ABCD CBBA.B -> 10 = %q, want 148.25", got)
	}
	// Round-trip a signed fraction through a custom negative/decimal marker base.
	rt := markerBase(t, reg, "0123456789", "~", "/")
	enc, err := Convert("~12/5", rt, dec10, 50)
	if err != nil {
		t.Fatalf("marker decode: %v", err)
	}
	if enc != "-12.5" {
		t.Errorf("marker base ~12/5 -> 10 = %q, want -12.5", enc)
	}
	back, err := Convert("-12.5", dec10, rt, 50)
	if err != nil {
		t.Fatalf("marker encode: %v", err)
	}
	if back != "~12/5" {
		t.Errorf("marker base 10 -12.5 -> custom = %q, want ~12/5", back)
	}
}

func TestSpecParser(t *testing.T) {
	reg := newReg(t)
	// Multi-token comma split: "0,1 2 3" is four digits.
	b := customBase(t, reg, "0,1 2 3")
	if len(b.Symbols) != 4 {
		t.Errorf("spec '0,1 2 3' = %d symbols, want 4", len(b.Symbols))
	}
	// Escaped space is a literal-space digit.
	b = customBase(t, reg, `a\ b`)
	if len(b.Symbols) != 3 {
		t.Errorf(`spec 'a\ b' = %d symbols, want 3`, len(b.Symbols))
	}
	// A one-symbol spec is rejected.
	if _, err := ResolveBase(reg, "", "A", nil); err == nil {
		t.Error("one-symbol spec should error")
	}
}

// The retired marker tokens must be an error, never a digit symbol. Accepting
// them as digits would silently shift a whole alphabet.
func TestRetiredMarkerTokensRejected(t *testing.T) {
	for _, spec := range []string{
		"0123456789 neg=~",
		"0 1 2 3 dec=,",
		"0123456789abcdef pad==",
		"neg=",
	} {
		if _, err := ParseSymbolSpec(spec); err == nil {
			t.Errorf("spec %q: retired marker token should be rejected", spec)
		}
	}
	// A token that merely starts with the same letters is still a normal digit.
	syms, err := ParseSymbolSpec("negative decisive padding")
	if err != nil {
		t.Fatalf("non-marker tokens should parse: %v", err)
	}
	if len(syms) != 3 {
		t.Errorf("got %d symbols, want 3", len(syms))
	}
}

// Marker flags apply to any base, and must not disturb the shared registry copy.
func TestApplyMarkers(t *testing.T) {
	reg := newReg(t)
	dec10 := base(t, reg, "10")
	hex := base(t, reg, "hex")

	// Override the negative marker on a named base.
	tilde, err := ApplyOptions(hex, mk("--from", "~", nil))
	if err != nil {
		t.Fatalf("applyMarkers on hex: %v", err)
	}
	got, err := Convert("~ff", tilde, dec10, 0)
	if err != nil {
		t.Fatalf("convert with overridden marker: %v", err)
	}
	if got != "-255" {
		t.Errorf("~ff hex -> 10 = %q, want -255", got)
	}
	// The registry's own hex must be untouched, since bases are shared pointers.
	if hex.NegSym() != "-" {
		t.Errorf("registry hex negative marker = %q, want \"-\"; applyMarkers mutated a shared base", hex.NegSym())
	}
	if _, err := Convert("~ff", hex, dec10, 0); err == nil {
		t.Error("unmodified hex should still reject \"~ff\"")
	}

	// An empty value disables the marker.
	off, err := ApplyOptions(hex, mk("--from", "", nil))
	if err != nil {
		t.Fatalf("applyMarkers disable: %v", err)
	}
	if off.NegSym() != "" {
		t.Errorf("disabled negative marker = %q, want empty", off.NegSym())
	}
	if _, err := Convert("-ff", off, dec10, 0); err == nil {
		t.Error("negatives should be rejected once the marker is disabled")
	}

	// No flags set returns the base itself, not a copy.
	same, err := ApplyOptions(hex, mk("--from", nil, nil))
	if err != nil {
		t.Fatalf("applyMarkers no-op: %v", err)
	}
	if same != hex {
		t.Error("applyMarkers with no flags should return the original base")
	}

	// A marker that collides with a digit is caught by Finalize().
	if _, err := ApplyOptions(hex, mk("--from", "a", nil)); err == nil {
		t.Error("a negative marker that is also a hex digit should be rejected")
	}

	// Markers are meaningless for raw bytes.
	if _, err := ApplyOptions(base(t, reg, "bytes"), mk("--from", "~", nil)); err == nil {
		t.Error("marker overrides should be rejected for the bytes base")
	}
}

// Padding is only ever applied on the bit-packed path, one character at a time.
// A definition that can never take effect must be rejected where it is written,
// not accepted and then quietly ignored.
func TestPadRejections(t *testing.T) {
	reg := newReg(t)
	pad := func(name, p string) error {
		b, err := reg.Lookup(name)
		if err != nil {
			t.Fatalf("Lookup(%q): %v", name, err)
		}
		copied := *b
		copied.PadSymbol = p
		copied.PadEmit = true
		return copied.Finalize()
	}
	// Multi-character pad: encode would overshoot the group boundary.
	if err := pad("64", "=="); err == nil {
		t.Error("a multi-character pad should be rejected")
	}
	// Above 8 bits per digit the bit-packed path is never taken, so a pad there
	// would silently do nothing.
	if err := pad("512tt", "="); err == nil {
		t.Error("a pad on a base above 8 bits per digit should be rejected")
	}
	// Same for a base that is not a power of two at all.
	if err := pad("45", "="); err == nil {
		t.Error("a pad on a non-power-of-2 base should be rejected")
	}
	// A single character is fine, including a multi-byte one.
	if err := pad("64", "="); err != nil {
		t.Errorf("single-character pad rejected: %v", err)
	}
	if err := pad("64", "§"); err != nil {
		t.Errorf("single-rune multi-byte pad rejected: %v", err)
	}
	// The padded builtins must still Finalize as defined.
	for _, name := range []string{"64", "64u", "64h", "32", "32h"} {
		b, err := reg.Lookup(name)
		if err != nil {
			t.Fatalf("Lookup(%q): %v", name, err)
		}
		if b.PadSymbol == "" {
			t.Errorf("builtin %q lost its padding symbol", name)
		}
	}
}

// Bad base definitions must be rejected by Finalize(), not silently accepted.
func TestFinalizeRejections(t *testing.T) {
	reg := newReg(t)
	bad := []string{
		"10 11 1", // "1" is a prefix of "10"/"11": not prefix-free
		"a a.b",   // decimal marker "." inside a digit "a.b"
		"aa a",    // "a" is a prefix of "aa"
	}
	for _, spec := range bad {
		if _, err := ResolveBase(reg, "", spec, nil); err == nil {
			t.Errorf("spec %q should be rejected by Finalize()", spec)
		}
	}
}

// Wrapped encoder output must decode back to the original, on both paths and at
// wrap widths that fall inside a multi-byte digit. Line breaks have to be dropped
// before the bytes are read as runes, or a split digit looks like bad UTF-8.
func TestWrappedBinaryDecode(t *testing.T) {
	reg := newReg(t)
	bytesB := base(t, reg, "bytes")
	rng := rand.New(rand.NewSource(0xf01d))
	blob := make([]byte, 300)
	rng.Read(blob)

	for _, name := range []string{"64", "64ws_compat_v1b", "64emoji", "128tt", "512tt", "2048llfourn", "65536qntm"} {
		to := base(t, reg, name)
		enc, err := Convert(string(blob), bytesB, to, 0)
		if err != nil {
			t.Fatalf("encode %s: %v", name, err)
		}
		for _, width := range []int{7, 13, 40} {
			wrapped := wrapBytes(enc, width)
			got, err := Convert(wrapped, to, bytesB, 0)
			if err != nil {
				t.Errorf("buffered decode %s wrap %d: %v", name, width, err)
			} else if got != string(blob) {
				t.Errorf("buffered decode %s wrap %d did not recover the blob", name, width)
			}
			var streamed bytes.Buffer
			ok, err := StreamConvert(strings.NewReader(wrapped), &streamed, to, bytesB)
			if err != nil {
				t.Errorf("stream decode %s wrap %d: %v", name, width, err)
				continue
			}
			if ok && streamed.String() != string(blob) {
				t.Errorf("stream decode %s wrap %d did not recover the blob", name, width)
			}
		}
	}
}

// wrapBytes inserts a newline every n bytes, ignoring rune boundaries the way a
// byte-counting wrapper would.
func wrapBytes(s string, n int) string {
	var sb strings.Builder
	for i := 0; i < len(s); i += n {
		end := i + n
		if end > len(s) {
			end = len(s)
		}
		sb.WriteString(s[i:end])
		sb.WriteByte('\n')
	}
	return sb.String()
}

// cjkSymbols returns n distinct one-rune symbols from the CJK block, for building
// a big custom base in tests.
func cjkSymbols(n int) []string {
	syms := make([]string, n)
	for i := range syms {
		syms[i] = string(rune(0x4E00 + i))
	}
	return syms
}

// tailSymbols returns n one-rune symbols from a block well clear of cjkSymbols,
// so a tail built from it never collides with the digits.
func tailSymbols(n int) []string {
	syms := make([]string, n)
	for i := range syms {
		syms[i] = string(rune(0xA000 + i))
	}
	return syms
}

// A user-defined base above 8 bits streams only once it declares a tail; without
// one it falls back to the length-prefixed packing, which can't stream-encode.
// Both layouts must still round-trip at every awkward length.
func TestUserDefinedTail(t *testing.T) {
	reg := newReg(t)
	bytesB := base(t, reg, "bytes")
	rng := rand.New(rand.NewSource(0x7a11))

	withTail := &Base{
		Aliases:      []string{"custom512"},
		Symbols:      cjkSymbols(512),
		TailSymbols:  []string{"⸐", "⸑"},
		BinaryScheme: "qntm",
	}
	noTail := &Base{Aliases: []string{"custom512nt"}, Symbols: cjkSymbols(512)}
	for _, b := range []*Base{withTail, noTail} {
		if err := b.Finalize(); err != nil {
			t.Fatalf("Finalize %s: %v", b.Name(), err)
		}
	}

	if !streamableWide(withTail) {
		t.Error("a custom base with a tail should stream")
	}
	if streamableWide(noTail) {
		t.Error("a custom base without a tail cannot stream; it has no way to write the length prefix")
	}

	for _, n := range []int{0, 1, 2, 3, 7, 8, 9, 15, 16, 17, 63, 64, 65, 1000} {
		blob := make([]byte, n)
		rng.Read(blob)
		for _, b := range []*Base{withTail, noTail} {
			enc, err := Convert(string(blob), bytesB, b, 0)
			if err != nil {
				t.Fatalf("%s encode %d bytes: %v", b.Name(), n, err)
			}
			got, err := Convert(enc, b, bytesB, 0)
			if err != nil {
				t.Fatalf("%s decode %d bytes: %v", b.Name(), n, err)
			}
			if got != string(blob) {
				t.Errorf("%s round-trip lost %d bytes", b.Name(), n)
			}
		}
		// The streaming path has to agree with the buffered one it replaces.
		enc, err := Convert(string(blob), bytesB, withTail, 0)
		if err != nil {
			t.Fatal(err)
		}
		var se, sd bytes.Buffer
		if ok, err := StreamConvert(bytes.NewReader(blob), &se, bytesB, withTail); err != nil || !ok {
			t.Fatalf("stream encode %d bytes: ok=%v err=%v", n, ok, err)
		}
		if se.String() != enc {
			t.Errorf("stream encode differs from buffered at %d bytes", n)
		}
		if ok, err := StreamConvert(strings.NewReader(enc), &sd, withTail, bytesB); err != nil || !ok {
			t.Fatalf("stream decode %d bytes: ok=%v err=%v", n, ok, err)
		}
		if sd.String() != string(blob) {
			t.Errorf("stream decode lost %d bytes", n)
		}
	}
}

// A codec name and a tail layout share Base.BinaryScheme, so clearing a tail
// must leave a codec alone. Otherwise --to-tail "" would quietly stop base45
// and friends doing binary at all.
func TestEmptyTailSparesCodecs(t *testing.T) {
	reg := newReg(t)
	for _, name := range []string{"45", "85ps", "85z", "91hk"} {
		b := base(t, reg, name)
		scheme := b.BinaryScheme
		if scheme == "" {
			t.Fatalf("%s should carry a codec scheme", name)
		}
		clone := *b
		empty := ""
		if err := (&Options{Label: "--to", Tail: &empty}).apply(&clone); err != nil {
			t.Fatal(err)
		}
		if clone.BinaryScheme != scheme {
			t.Errorf("%s: empty tail cleared codec scheme %q", name, scheme)
		}
		if !clone.RawCodec() {
			t.Errorf("%s: empty tail stopped it being a raw codec", name)
		}
	}

	// A real tail layout, on the other hand, is what the empty value clears.
	b := base(t, reg, "512tt")
	clone := *b
	empty := ""
	if err := (&Options{Label: "--to", Tail: &empty}).apply(&clone); err != nil {
		t.Fatal(err)
	}
	if clone.BinaryScheme != "" || len(clone.TailSymbols) != 0 {
		t.Errorf("empty tail should have cleared 512tt's tail layout")
	}
}

// A tail that could never work is rejected where it is declared, not silently
// ignored at conversion time.
func TestTailValidation(t *testing.T) {
	cases := []struct {
		name    string
		symbols []string
		tail    []string
		want    string
	}{
		{"too few for the base", cjkSymbols(2048), tailSymbols(4), "must be between 8"},
		{"not a power of 2", cjkSymbols(512), []string{"⸐", "⸑", "⸒"}, "power of 2"},
		{"wider than a byte", cjkSymbols(512), tailSymbols(512), "must be between"},
		{"base is only 8 bits", cjkSymbols(256), []string{"⸐", "⸑"}, "above 256 symbols"},
		{"base is not a power of 2", cjkSymbols(300), []string{"⸐", "⸑"}, "above 256 symbols"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			b := &Base{Aliases: []string{"t"}, Symbols: tc.symbols, TailSymbols: tc.tail, BinaryScheme: "qntm"}
			err := b.Finalize()
			if err == nil {
				t.Fatalf("accepted a tail that cannot work")
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Errorf("error %q does not mention %q", err, tc.want)
			}
		})
	}

	// A tail symbol that is also a digit could never be reached, since decode
	// looks the primary repertoire up first.
	syms := cjkSymbols(512)
	b := &Base{Aliases: []string{"t"}, Symbols: syms, TailSymbols: []string{syms[0], "⸑"}, BinaryScheme: "qntm"}
	if err := b.Finalize(); err == nil || !strings.Contains(err.Error(), "also a digit") {
		t.Errorf("a tail symbol that is also a digit should be rejected, got %v", err)
	}
}

// The crown-jewel test: the streaming and buffered binary paths must produce
// identical output, for both encode and decode, across power-of-2 bases and many
// lengths (the two are otherwise only ever tested against themselves).
func TestStreamBufferedEquivalence(t *testing.T) {
	reg := newReg(t)
	bytesB := base(t, reg, "bytes")
	rng := rand.New(rand.NewSource(0x5eed))
	// Every base that can carry raw bytes through a power-of-2 packing: the
	// single-byte ones on the tuned path, the rest on the wide path. Taken from
	// the registry rather than listed here, so a base that is added or renamed
	// is covered without touching this test.
	var targets []string
	for _, b := range reg.OrderedBases() {
		if b.Binary || PowerOfTwoBits(len(b.Symbols)) == 0 {
			continue
		}
		targets = append(targets, b.Name())
	}
	if len(targets) < 20 {
		t.Fatalf("only %d power-of-2 bases found; the registry scan is wrong", len(targets))
	}
	lengths := []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 15, 16, 17, 31, 63, 64, 100, 255, 256, 257, 1000, 4096, 65537}

	streamed := 0
	for _, name := range targets {
		to := base(t, reg, name)
		perBase := 0
		for _, n := range lengths {
			blob := make([]byte, n)
			rng.Read(blob)
			in := string(blob)

			bufEnc, err := Convert(in, bytesB, to, 0)
			if err != nil {
				t.Fatalf("buffered encode %s len %d: %v", name, n, err)
			}
			var streamEnc bytes.Buffer
			ok, err := StreamConvert(bytes.NewReader(blob), &streamEnc, bytesB, to)
			if err != nil {
				t.Fatalf("stream encode %s len %d: %v", name, n, err)
			}
			if !ok {
				// This base isn't served by the streaming path; buffered-only.
				continue
			}
			streamed++
			perBase++
			if streamEnc.String() != bufEnc {
				t.Errorf("ENCODE mismatch %s len %d:\n buffered=%q\n stream  =%q", name, n, bufEnc, streamEnc.String())
				continue
			}

			// Decode the buffered encoding both ways; both must recover the blob.
			bufDec, err := Convert(bufEnc, to, bytesB, 0)
			if err != nil {
				t.Fatalf("buffered decode %s len %d: %v", name, n, err)
			}
			var streamDec bytes.Buffer
			ok, err = StreamConvert(strings.NewReader(bufEnc), &streamDec, to, bytesB)
			if err != nil {
				t.Fatalf("stream decode %s len %d: %v", name, n, err)
			}
			if ok && streamDec.String() != bufDec {
				t.Errorf("DECODE mismatch %s len %d", name, n)
			}
			if bufDec != in {
				t.Errorf("decode did not recover blob %s len %d", name, n)
			}
		}
		// Every target here is meant to stream. Declining one silently would
		// leave it buffered-only with the comparison quietly skipped.
		if perBase == 0 {
			t.Errorf("%s never took the streaming path", name)
		}
	}
	if streamed == 0 {
		t.Fatal("streaming path never engaged; equivalence was tested against nothing")
	}
	t.Logf("compared %d streamed/buffered encodings", streamed)
}

// Random values round-trip through a spread of bases (number path).
func TestRoundTripNumber(t *testing.T) {
	reg := newReg(t)
	dec10 := base(t, reg, "10")
	rng := rand.New(rand.NewSource(1))
	targets := []string{"2", "8", "16", "36", "62", "64u", "85z", "288_compat_v1"}
	for _, name := range targets {
		to := base(t, reg, name)
		for i := 0; i < 50; i++ {
			// A random non-negative integer of up to ~40 digits.
			var sb strings.Builder
			sb.WriteByte(byte('1' + rng.Intn(9)))
			for j := 0; j < rng.Intn(40); j++ {
				sb.WriteByte(byte('0' + rng.Intn(10)))
			}
			want := sb.String()
			enc, err := Convert(want, dec10, to, 0)
			if err != nil {
				t.Fatalf("encode %s of %q: %v", name, want, err)
			}
			back, err := Convert(enc, to, dec10, 0)
			if err != nil {
				t.Fatalf("decode %s of %q: %v", name, enc, err)
			}
			if back != want {
				t.Errorf("round-trip %s: %q -> %q -> %q", name, want, enc, back)
			}
		}
	}
}

// naiveConvert is the obvious algorithm - one multiply-add per input digit, one
// divide per output digit - kept here as a reference for the packed one. Integers
// only, and slow enough that it is no use for anything but a comparison.
func naiveConvert(t *testing.T, input string, from, to *Base) string {
	t.Helper()
	digits, err := from.Tokenize(input)
	if err != nil {
		t.Fatalf("tokenize %q: %v", input, err)
	}
	fromRadix := big.NewInt(int64(len(from.Symbols)))
	toRadix := big.NewInt(int64(len(to.Symbols)))
	val := new(big.Int)
	tmp := new(big.Int)
	for _, d := range digits {
		val.Mul(val, fromRadix)
		val.Add(val, tmp.SetInt64(int64(from.value[d])))
	}
	if val.Sign() == 0 {
		return to.Symbols[0]
	}
	var out []string
	mod := new(big.Int)
	for val.Sign() > 0 {
		val.DivMod(val, toRadix, mod)
		out = append([]string{to.Symbols[mod.Int64()]}, out...)
	}
	return strings.Join(out, "")
}

// Digits are packed a machine word at a time on the way in and out, so the one
// place that can go wrong is the leftover chunk at the end - it must keep its
// leading zero digits when more digits follow, and drop them when it is the most
// significant one. Only lengths either side of a chunk boundary show it, and a
// wrong answer still looks like a plausible number, so pin it against the plain
// one-digit-at-a-time version.
func TestDigitChunkBoundaries(t *testing.T) {
	reg := newReg(t)
	dec10 := base(t, reg, "10")
	rng := rand.New(rand.NewSource(7))
	// Chunk widths differ per base: 63 digits per word for base 2, 19 for base
	// 10, 12 for 36, 10 for 62, 5 for 2048, 3 for 65536.
	targets := []string{"2", "10", "16", "36", "62", "2048qntm", "65536qntm"}
	lengths := []int{1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 18, 19, 20, 21, 24, 25, 37, 38, 39, 62, 63, 64, 65, 126, 127, 128}
	for _, name := range targets {
		to := base(t, reg, name)
		for _, n := range lengths {
			var sb strings.Builder
			sb.WriteByte(byte('1' + rng.Intn(9)))
			for j := 1; j < n; j++ {
				sb.WriteByte(byte('0' + rng.Intn(10)))
			}
			in := sb.String()
			got, err := Convert(in, dec10, to, 0)
			if err != nil {
				t.Fatalf("convert %d digits to %s: %v", n, name, err)
			}
			if want := naiveConvert(t, in, dec10, to); got != want {
				t.Errorf("%d digits to %s: got %q, want %q (input %q)", n, name, got, want, in)
			}
		}
	}
}

// Same boundaries on the fractional side. A fraction converted to its own base
// has to come back unchanged, whatever the length, which is an exact check the
// integer comparison above cannot give for fractions.
func TestFractionChunkBoundaries(t *testing.T) {
	reg := newReg(t)
	rng := rand.New(rand.NewSource(11))
	for _, name := range []string{"2", "10", "16", "36", "62"} {
		b := base(t, reg, name)
		for _, n := range []int{1, 2, 3, 9, 10, 11, 12, 13, 18, 19, 20, 21, 38, 39, 62, 63, 64, 65} {
			var sb strings.Builder
			sb.WriteString(b.Symbols[0])
			sb.WriteString(b.DecSym())
			for j := 0; j < n-1; j++ {
				sb.WriteString(b.Symbols[rng.Intn(len(b.Symbols))])
			}
			// A trailing zero digit would be trimmed, so end on a nonzero one.
			sb.WriteString(b.Symbols[1+rng.Intn(len(b.Symbols)-1)])
			want := sb.String()
			got, err := Convert(want, b, b, n)
			if err != nil {
				t.Fatalf("convert %d fraction digits in %s: %v", n, name, err)
			}
			if got != want {
				t.Errorf("%d fraction digits in %s: got %q, want %q", n, name, got, want)
			}
		}
	}
}

// itoa is a tiny local helper so the tests don't pull in strconv just for this.
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}
