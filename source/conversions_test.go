//	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"bytes"
	"encoding/hex"
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
	b, err := resolveBase(reg, "", spec)
	if err != nil {
		t.Fatalf("resolveBase(%q): %v", spec, err)
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
		{"2048twitter", "00", runes(0x0046)},
		{"2048twitter", "0000", runes(0x0038, 0x0110)},
		{"2048twitter", "010203", runes(0x0047, 0x01B7, 0x0037)},
		{"2048rust", "00", runes(0x00D8)},
		{"2048rust", "000000", runes(0x00D8, 0x00D8, 0x0F0D)},
		{"2048rust", "010203", runes(0x00C5, 0x0140, 0x0F10)},
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
	rt := customBase(t, reg, "0123456789 neg=~ dec=/")
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
	if _, err := resolveBase(reg, "", "A"); err == nil {
		t.Error("one-symbol spec should error")
	}
}

// Bad base definitions must be rejected by finalize(), not silently accepted.
func TestFinalizeRejections(t *testing.T) {
	reg := newReg(t)
	bad := []string{
		"10 11 1", // "1" is a prefix of "10"/"11": not prefix-free
		"a a.b",   // decimal marker "." inside a digit "a.b"
		"aa a",    // "a" is a prefix of "aa"
	}
	for _, spec := range bad {
		if _, err := resolveBase(reg, "", spec); err == nil {
			t.Errorf("spec %q should be rejected by finalize()", spec)
		}
	}
}

// The crown-jewel test: the streaming and buffered binary paths must produce
// identical output, for both encode and decode, across power-of-2 bases and many
// lengths (the two are otherwise only ever tested against themselves).
func TestStreamBufferedEquivalence(t *testing.T) {
	reg := newReg(t)
	bytesB := base(t, reg, "bytes")
	rng := rand.New(rand.NewSource(0x5eed))
	targets := []string{"2", "4", "8", "16", "32", "64", "64u", "64h", "32h", "128jc1", "256jc1"}
	lengths := []int{0, 1, 2, 3, 4, 5, 7, 8, 15, 16, 17, 31, 63, 64, 100, 255, 256, 257, 1000}

	streamed := 0
	for _, name := range targets {
		to := base(t, reg, name)
		for _, n := range lengths {
			blob := make([]byte, n)
			rng.Read(blob)
			in := string(blob)

			bufEnc, err := Convert(in, bytesB, to, 0)
			if err != nil {
				t.Fatalf("buffered encode %s len %d: %v", name, n, err)
			}
			var streamEnc bytes.Buffer
			ok, err := streamConvert(bytes.NewReader(blob), &streamEnc, bytesB, to)
			if err != nil {
				t.Fatalf("stream encode %s len %d: %v", name, n, err)
			}
			if !ok {
				// This base isn't served by the streaming path; buffered-only.
				continue
			}
			streamed++
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
			ok, err = streamConvert(strings.NewReader(bufEnc), &streamDec, to, bytesB)
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
	targets := []string{"2", "8", "16", "36", "62", "64u", "85z", "288jc1"}
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
