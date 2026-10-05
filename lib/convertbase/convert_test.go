//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"bytes"
	"io"
	"math"
	"math/big"
	"testing"
	"time"
)

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

// benchDigits is a deterministic run of n nonzero decimal digits.
func benchDigits(n int) string {
	d := make([]byte, n)
	for i := range d {
		d[i] = byte('1' + (i*7+3)%9)
	}
	return string(d)
}

// Positional-path benchmarks: neither base is a power of 2, so these take the
// big.Int route. Run at several lengths on purpose - the cost grows with the
// square of the digit count, so a single length says nothing about the curve.
//
//	go test -run x -bench Positional -benchmem ./convertbase
func benchPositional(b *testing.B, digits int) {
	reg, err := NewRegistry()
	if err != nil {
		b.Fatal(err)
	}
	from, err := reg.Lookup("10")
	if err != nil {
		b.Fatal(err)
	}
	to, err := reg.Lookup("36")
	if err != nil {
		b.Fatal(err)
	}
	input := benchDigits(digits)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, err := Convert(input, from, to, 0); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkPositional1K(b *testing.B)  { benchPositional(b, 1000) }
func BenchmarkPositional4K(b *testing.B)  { benchPositional(b, 4000) }
func BenchmarkPositional16K(b *testing.B) { benchPositional(b, 16000) }
func BenchmarkPositional64K(b *testing.B) { benchPositional(b, 64000) }

// The tokenizer already knows each digit's value, so the number path must not
// look it up again by symbol. A one-byte base reads input through its byte
// table alone, so with the symbol map gone a second lookup reads every digit
// as zero.
// Test ID: ErmUk2J
func TestNumberPathUsesTokenValues(t *testing.T) {
	reg := newReg(t)
	dec10 := base(t, reg, "10")
	to := base(t, reg, "36")
	b := &Base{Aliases: []string{"nomap10"}, Symbols: dec10.Symbols}
	if err := b.Finalize(); err != nil {
		t.Fatal(err)
	}
	b.value = nil
	for _, in := range []string{"7", "-98765432109876543210", "123.456", benchDigits(2000)} {
		want, err := Convert(in, dec10, to, 8)
		if err != nil {
			t.Fatal(err)
		}
		got, err := Convert(in, b, to, 8)
		if err != nil {
			t.Fatalf("%d digits: %v", len(in), err)
		}
		if got != want {
			t.Errorf("%d digits: got %.40q, want %.40q", len(in), got, want)
		}
	}
}

// The number path does the same divide and conquer as math/big's SetString
// and Text, so their time is a yardstick that moves with the machine. Ours sat
// near 1.9 times theirs at 1K digits while each digit was looked up twice, and
// near 1.2 after. The two take turns, one call each, so both see the same load,
// and each side's fastest call is compared. Timing all of ours and then all of
// theirs let a load change in between read as a slowdown. Many short rounds
// give a busy box enough quiet moments for both minimums.
// Test ID: ErmULlt
func TestPositionalNearMathBig(t *testing.T) {
	reg := newReg(t)
	from, to := base(t, reg, "10"), base(t, reg, "36")
	input := benchDigits(1000)
	ours := func() {
		if _, err := Convert(input, from, to, 0); err != nil {
			t.Fatal(err)
		}
	}
	ref := func() {
		v, ok := new(big.Int).SetString(input, 10)
		if !ok {
			t.Fatal("math/big refused the input")
		}
		_ = v.Text(36)
	}
	timed := func(f func()) time.Duration {
		start := time.Now()
		f()
		return time.Since(start)
	}
	ours()
	ref()
	bestOurs, bestRef := time.Duration(math.MaxInt64), time.Duration(math.MaxInt64)
	for round := 0; round < 1201; round++ {
		if round%2 == 0 {
			bestOurs = min(bestOurs, timed(ours))
			bestRef = min(bestRef, timed(ref))
		} else {
			bestRef = min(bestRef, timed(ref))
			bestOurs = min(bestOurs, timed(ours))
		}
	}
	const limit = 1.5
	if ratio := float64(bestOurs) / float64(bestRef); ratio > limit {
		t.Errorf("1K digits base 10 -> 36 took %.2f times math/big's own conversion, limit %.1f (%v vs %v)", ratio, limit, bestOurs, bestRef)
	}
}

func benchBases(b *testing.B, fromName, toName string) (*Base, *Base) {
	b.Helper()
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
	return from, to
}

// benchEncoded is the benchmark payload in the named base, for the decoders.
func benchEncoded(b *testing.B, toName string) string {
	b.Helper()
	from, to := benchBases(b, "bytes", toName)
	enc, err := Convert(benchBytes(), from, to, 0)
	if err != nil {
		b.Fatal(err)
	}
	return enc
}

func benchConvert(b *testing.B, fromName, toName, input string) {
	from, to := benchBases(b, fromName, toName)
	// Bytes moved is measured on whichever side is the raw binary.
	raw := len(input)
	if toName == "bytes" {
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

func BenchmarkEncode16(b *testing.B) { benchConvert(b, "bytes", "16", benchBytes()) }
func BenchmarkEncode64(b *testing.B) { benchConvert(b, "bytes", "64u", benchBytes()) }
func BenchmarkEncode32(b *testing.B) { benchConvert(b, "bytes", "32", benchBytes()) }

func BenchmarkDecode16(b *testing.B) {
	enc := benchEncoded(b, "16")
	benchConvert(b, "16", "bytes", enc)
}

func BenchmarkDecode64(b *testing.B) {
	enc := benchEncoded(b, "64u")
	benchConvert(b, "64u", "bytes", enc)
}

// The big native base goes through a separate encoder (multi-byte symbols).
func BenchmarkEncode65536(b *testing.B) { benchConvert(b, "bytes", "65536qntm", benchBytes()) }

// Typed input, the browser page and the reactor all decode a big base buffered.
func BenchmarkDecode65536(b *testing.B) {
	enc := benchEncoded(b, "65536qntm")
	benchConvert(b, "65536qntm", "bytes", enc)
}

func BenchmarkDecode2048(b *testing.B) {
	enc := benchEncoded(b, "2048qntm")
	benchConvert(b, "2048qntm", "bytes", enc)
}

// The buffered big-base decoder once made a string per character to look it
// up, about one allocation per digit. Its cost must not grow with the input.
// Test ID: Erm5wyD
func TestBigBaseDecodeAllocs(t *testing.T) {
	reg := newReg(t)
	bytesB := base(t, reg, "bytes")
	blob := benchBytes()[:1<<16]
	for _, name := range []string{"65536qntm", "32768qntm", "2048qntm", "2048llfourn", "512tt"} {
		big := base(t, reg, name)
		enc, err := Convert(blob, bytesB, big, 0)
		if err != nil {
			t.Fatal(err)
		}
		allocs := testing.AllocsPerRun(5, func() {
			if _, err := Convert(enc, big, bytesB, 0); err != nil {
				t.Fatal(err)
			}
		})
		if allocs > 8 {
			t.Errorf("%s: decoding 64 KiB took %.0f allocations, want at most 8", name, allocs)
		}
	}
}

// Streaming benchmarks exercise the CLI's actual pipe path (StreamConvert) with
// no real I/O: a bytes.Reader in, io.Discard out. This is what a `cat file | ...`
// invocation runs.
func benchStream(b *testing.B, fromName, toName, input string) {
	from, to := benchBases(b, fromName, toName)
	b.SetBytes(int64(len(benchBytes()))) // report over the raw-byte side
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if ok, err := StreamConvert(bytes.NewReader([]byte(input)), io.Discard, from, to); !ok || err != nil {
			b.Fatalf("StreamConvert ok=%v err=%v", ok, err)
		}
	}
}

func BenchmarkStreamEncode64(b *testing.B) { benchStream(b, "bytes", "64u", benchBytes()) }
func BenchmarkStreamEncode16(b *testing.B) { benchStream(b, "bytes", "16", benchBytes()) }
func BenchmarkStreamEncode32(b *testing.B) { benchStream(b, "bytes", "32", benchBytes()) }

func BenchmarkStreamDecode64(b *testing.B) {
	enc := benchEncoded(b, "64u")
	benchStream(b, "64u", "bytes", enc)
}
