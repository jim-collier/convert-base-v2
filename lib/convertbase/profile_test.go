//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"io"
	"strings"
	"testing"
)

// Profiler workload for the cicd stage. One iteration exercises both hot
// subsystems back to back: the arbitrary-precision math/big path (O(N^2), the
// real CPU sink) and the O(N) streaming bit-packing path. Run it under a CPU
// sampler with
//	go test -run x -bench BenchmarkProfile -cpuprofile cpu.prof ./...
// and the pipeline turns cpu.prof into a flamegraph.

// bigDecimal is a large but deterministic base-10 number: repeating digits so a
// run is comparable across builds, sized so a single convert is a real workload.
func bigDecimal(digits int) string {
	var b strings.Builder
	b.Grow(digits)
	const cycle = "1234567890"
	b.WriteByte('9') // no leading zero
	for i := 1; i < digits; i++ {
		b.WriteByte(cycle[i%len(cycle)])
	}
	return b.String()
}

func BenchmarkProfile(b *testing.B) {
	reg, err := NewRegistry()
	if err != nil {
		b.Fatal(err)
	}
	base10, err := reg.Lookup("10")
	if err != nil {
		b.Fatal(err)
	}
	baseBig, err := reg.Lookup("62") // non-power-of-2 -> forces the math/big path
	if err != nil {
		b.Fatal(err)
	}
	bytesBase, err := reg.Lookup("bytes")
	if err != nil {
		b.Fatal(err)
	}
	base64u, err := reg.Lookup("64u")
	if err != nil {
		b.Fatal(err)
	}

	number := bigDecimal(4000) // ~4k digits: the quadratic path dominates
	blob := benchBytes()       // 1 MiB deterministic blob for the streaming side

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		// Stage 1: big-int slow path (leading zeros dropped; value path).
		if _, err := Convert(number, base10, baseBig, 0); err != nil {
			b.Fatal(err)
		}
		// Stage 2: streaming codec throughput (raw bytes -> base64url).
		if _, err := StreamConvert(strings.NewReader(blob), io.Discard, bytesBase, base64u); err != nil {
			b.Fatal(err)
		}
	}
}
