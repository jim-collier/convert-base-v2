//	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import "testing"

// Throughput benchmarks for the streaming binary path. Run one direction with
//	go test -run x -bench BenchmarkEncode64 -benchmem ./...
// and profile with
//	go test -run x -bench BenchmarkEncode64 -cpuprofile cpu.out ./...
// SetBytes reports MB/s over the raw-byte side, so the numbers line up with the
// system encoders (base64/basenc).

// benchBytes is a deterministic 1 MiB blob (no rand, so runs are comparable).
func benchBytes() string {
	b := make([]byte, 1<<20)
	for i := range b {
		b[i] = byte(i*31 + 7)
	}
	return string(b)
}

func benchConvert(b *testing.B, fromName, toName, input string) {
	reg, err := NewRegistry()
	if err != nil {
		b.Fatal(err)
	}
	from, err := reg.Lookup(fromName)
	if err != nil {
		b.Fatal(err)
	}
	to, err := reg.Lookup(toName)
	if err != nil {
		b.Fatal(err)
	}
	// Bytes moved is measured on whichever side is the raw binary.
	raw := len(input)
	if toName == "binary" {
		if out, err := Convert(input, from, to, 0); err == nil {
			raw = len(out)
		}
	}
	b.SetBytes(int64(raw))
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, err := Convert(input, from, to, 0); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkEncode16(b *testing.B) { benchConvert(b, "binary", "16", benchBytes()) }
func BenchmarkEncode64(b *testing.B) { benchConvert(b, "binary", "64u", benchBytes()) }
func BenchmarkEncode32(b *testing.B) { benchConvert(b, "binary", "32", benchBytes()) }

func BenchmarkDecode16(b *testing.B) {
	reg, _ := NewRegistry()
	from, _ := reg.Lookup("binary")
	to, _ := reg.Lookup("16")
	enc, _ := Convert(benchBytes(), from, to, 0)
	benchConvert(b, "16", "binary", enc)
}

func BenchmarkDecode64(b *testing.B) {
	reg, _ := NewRegistry()
	from, _ := reg.Lookup("binary")
	to, _ := reg.Lookup("64u")
	enc, _ := Convert(benchBytes(), from, to, 0)
	benchConvert(b, "64u", "binary", enc)
}

// The big native base goes through a separate encoder (multi-byte symbols).
func BenchmarkEncode65536(b *testing.B) { benchConvert(b, "binary", "65536", benchBytes()) }
