//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"fmt"
	"strings"
)

// SymbolSlice returns the part of s covering symbols [start, start+count),
// counting symbols rather than bytes. A negative start counts from the right
// end (-3 = the last three symbols); count < 0 means through the end. Both are
// clamped to what s actually holds, so asking past either edge yields what is
// there rather than an error. Digits only, like Tokenize: a sign or decimal
// marker in s is an error. The result is in canonical symbol form - an input
// that reached here through a decode alias or a case flip comes back as the
// base would have emitted it.
func (b *Base) SymbolSlice(s string, start, count int) (string, error) {
	digits, err := b.Tokenize(s)
	if err != nil {
		return "", err
	}
	if start < 0 {
		start = max(len(digits)+start, 0)
	}
	start = min(start, len(digits))
	// Compare against what is left rather than start+count, which overflows for
	// a count near the integer maximum and would clamp the wrong way.
	if count < 0 || count > len(digits)-start {
		count = len(digits) - start
	}
	return strings.Join(digits[start:start+count], ""), nil
}

// Fit right-aligns s to exactly width symbols: left-filled with the base's
// zero symbol (Symbols[0]) when s is short, cut to the rightmost width symbols
// when s is long. This is the whole pad-or-truncate policy for fixed-width
// columnar or sortable output in one place, so callers cannot drift on the
// half of it they implement themselves - and Symbols[0] is not always "0"
// (the word-safe base 32 starts at "2").
func (b *Base) Fit(s string, width int) (string, error) {
	if width < 0 {
		return "", fmt.Errorf("base %q: fit width must not be negative", b.Name())
	}
	digits, err := b.Tokenize(s)
	if err != nil {
		return "", err
	}
	if len(digits) >= width {
		return strings.Join(digits[len(digits)-width:], ""), nil
	}
	return strings.Repeat(b.Symbols[0], width-len(digits)) + strings.Join(digits, ""), nil
}
