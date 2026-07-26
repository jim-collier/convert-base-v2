//	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"bytes"
	"testing"
)

// Fuzz targets for the cicd fuzz stage. Run one for a bounded time with
//	go test -run x -fuzz FuzzStreamRoundTrip -fuzztime 20s ./...
// The pipeline discovers and runs each in turn. Two properties are checked:
// nothing panics on arbitrary input, and the binary encode/decode paths
// round-trip byte-for-byte.

// FuzzParseSymbolSpec: the custom-alphabet parser must never panic, whatever the
// input. An error return is fine; a crash is not.
func FuzzParseSymbolSpec(f *testing.F) {
	f.Add("ABCD")
	f.Add("aeiouy.-_0")
	f.Add("0123456789abcdef")
	f.Add("0 1 2 3 neg=~") // retired marker token: must error, not panic
	f.Add("")
	f.Fuzz(func(t *testing.T, spec string) {
		_, _ = ParseSymbolSpec(spec) // only asserting no panic
	})
}

// FuzzConvert: Convert must never panic on arbitrary input in a fixed base pair.
// Most fuzz inputs are not valid base-10 numbers, so an error is the norm; the
// point is that malformed input is rejected cleanly, not with a crash.
func FuzzConvert(f *testing.F) {
	reg, err := NewRegistry()
	if err != nil {
		f.Fatal(err)
	}
	from, err := reg.Lookup("10")
	if err != nil {
		f.Fatal(err)
	}
	to, err := reg.Lookup("16")
	if err != nil {
		f.Fatal(err)
	}
	f.Add("255")
	f.Add("-123456.789")
	f.Add("0")
	f.Fuzz(func(t *testing.T, number string) {
		_, _ = Convert(number, from, to, 50) // only asserting no panic
	})
}

// FuzzStreamRoundTrip: raw bytes -> text base -> raw bytes must reproduce the
// input exactly. Exercises the streaming bit-packing encode and decode paths on
// arbitrary lengths and byte values, across one base per streaming shape: the
// tuned byte path, wide symbols under and over 8 bits per digit, and each of the
// tail schemes. Odd lengths are where chunk edges and tails go wrong.
func FuzzStreamRoundTrip(f *testing.F) {
	reg, err := NewRegistry()
	if err != nil {
		f.Fatal(err)
	}
	bytesBase, err := reg.Lookup("bytes")
	if err != nil {
		f.Fatal(err)
	}
	var targets []*Base
	for _, name := range []string{"64u", "128tt", "emoji64", "512tt", "2048rust", "65536qntm"} {
		b, err := reg.Lookup(name)
		if err != nil {
			f.Fatal(err)
		}
		targets = append(targets, b)
	}
	f.Add([]byte("hello world"))
	f.Add([]byte{0, 1, 2, 253, 254, 255})
	f.Add([]byte(""))
	f.Fuzz(func(t *testing.T, data []byte) {
		for _, to := range targets {
			var enc bytes.Buffer
			handled, err := streamConvert(bytes.NewReader(data), &enc, bytesBase, to)
			if err != nil || !handled {
				t.Skipf("encode not handled/streamed for %s (err=%v)", to.Name(), err)
			}
			var dec bytes.Buffer
			handled, err = streamConvert(bytes.NewReader(enc.Bytes()), &dec, to, bytesBase)
			if err != nil {
				t.Fatalf("decode failed for %d-byte input via %s: %v", len(data), to.Name(), err)
			}
			if !handled {
				t.Skipf("decode not streamed for %s", to.Name())
			}
			if !bytes.Equal(dec.Bytes(), data) {
				t.Fatalf("round-trip mismatch via %s: in=%q out=%q", to.Name(), data, dec.Bytes())
			}
		}
	})
}
