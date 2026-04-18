//	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"fmt"
	"math/big"
	"strings"
)

// Convert converts a number string from 'from' base to 'to' base.
// Supports arbitrary-precision integers, fractional parts, and negative numbers.
// 'precision' is the maximum number of fractional digits emitted in the output.
//
// The negative and decimal markers are taken from each base's definition.
// The input is validated:
//   - the negative marker, if present, must be at position 0 and occur exactly once;
//   - the decimal marker, if present, must occur at most once.
func Convert(input string, from, to *Base, precision int) (string, error) {
	// Binary mode: use bit-packing, which is O(N) and preserves leading zero
	// bytes naturally (padding lives in the low bits, not as digit-position
	// leading zeros). Falling through to the big.Int path would be correct
	// but quadratic - unusable on real files.
	if from.Binary || to.Binary {
		kIn := powerOfTwoBits(len(from.Symbols))
		kOut := powerOfTwoBits(len(to.Symbols))
		if kIn == 0 || kOut == 0 {
			other := from
			if from.Binary {
				other = to
			}
			return "", fmt.Errorf("binary mode requires a power-of-2 counterpart (2, 4, 8, 16, 32, 64, 128, 256); base %q has %d digits", other.Name(), len(other.Symbols))
		}
		return convertBitPacked(input, from, to, kIn, kOut)
	}

	if input == "" {
		return "", fmt.Errorf("empty input")
	}
	negMark := from.NegSym()
	decMark := from.DecSym()

	// Validate negative marker usage.
	negative := false
	s := input
	if negMark != "" {
		firstAt := strings.Index(s, negMark)
		if firstAt == 0 {
			negative = true
			s = s[len(negMark):]
			if strings.Contains(s, negMark) {
				return "", fmt.Errorf("input has more than one occurrence of negative marker %q", negMark)
			}
		} else if firstAt > 0 {
			return "", fmt.Errorf("negative marker %q appears inside input, not at the start", negMark)
		}
	}

	// Split at decimal marker (validate only one).
	intPart, fracPart := s, ""
	if decMark != "" {
		first := strings.Index(s, decMark)
		if first >= 0 {
			rest := s[first+len(decMark):]
			if strings.Contains(rest, decMark) {
				return "", fmt.Errorf("input has more than one decimal marker %q", decMark)
			}
			intPart = s[:first]
			fracPart = rest
		}
	}
	if intPart == "" {
		// Treat ".5" as "0.5" by using the first digit symbol as zero.
		intPart = from.Symbols[0]
	}

	if s == "" {
		return "", fmt.Errorf("no digits in input")
	}

	// Tokenize the two parts separately.
	intDigits, err := from.Tokenize(intPart)
	if err != nil {
		return "", fmt.Errorf("integer part: %w", err)
	}
	fracDigits, err := from.Tokenize(fracPart)
	if err != nil {
		return "", fmt.Errorf("fractional part: %w", err)
	}

	fromRadix := big.NewInt(int64(len(from.Symbols)))
	toRadix := big.NewInt(int64(len(to.Symbols)))

	// Integer part → big.Int (Horner's method).
	intVal := new(big.Int)
	tmp := new(big.Int)
	for _, d := range intDigits {
		intVal.Mul(intVal, fromRadix)
		intVal.Add(intVal, tmp.SetInt64(int64(from.value[d])))
	}

	// Fractional part → num/den.
	fracNum := new(big.Int)
	fracDen := big.NewInt(1)
	for _, d := range fracDigits {
		fracNum.Mul(fracNum, fromRadix)
		fracNum.Add(fracNum, tmp.SetInt64(int64(from.value[d])))
		fracDen.Mul(fracDen, fromRadix)
	}

	// Integer part → output base (repeated division).
	var intOut []string
	if intVal.Sign() == 0 {
		intOut = []string{to.Symbols[0]}
	} else {
		n := new(big.Int).Set(intVal)
		mod := new(big.Int)
		for n.Sign() > 0 {
			n.DivMod(n, toRadix, mod)
			intOut = append([]string{to.Symbols[mod.Int64()]}, intOut...)
		}
	}

	// Fractional part → output base (repeated multiplication).
	var fracOut []string
	if fracNum.Sign() > 0 {
		digit := new(big.Int)
		for i := 0; i < precision && fracNum.Sign() > 0; i++ {
			fracNum.Mul(fracNum, toRadix)
			digit.QuoRem(fracNum, fracDen, fracNum)
			fracOut = append(fracOut, to.Symbols[digit.Int64()])
		}
	}

	// Assemble, using the OUTPUT base's markers.
	isZero := intVal.Sign() == 0 && len(fracOut) == 0
	if negative && !isZero {
		if to.NegSym() == "" {
			return "", fmt.Errorf("output base %q has no negative marker; set one (e.g. --to-symbols \"... neg=X\")", to.Name())
		}
	}
	if len(fracOut) > 0 && to.DecSym() == "" {
		return "", fmt.Errorf("output base %q has no decimal marker; set one (e.g. --to-symbols \"... dec=Y\")", to.Name())
	}

	var sb strings.Builder
	if negative && !isZero {
		sb.WriteString(to.NegSym())
	}
	for _, d := range intOut {
		sb.WriteString(d)
	}
	if len(fracOut) > 0 {
		sb.WriteString(to.DecSym())
		for _, d := range fracOut {
			sb.WriteString(d)
		}
	}
	return sb.String(), nil
}

// powerOfTwoBits returns k if n == 2^k (for some k >= 1), else 0.
func powerOfTwoBits(n int) int {
	if n < 2 {
		return 0
	}
	for k := 1; k <= 16; k++ {
		if 1<<k == n {
			return k
		}
	}
	return 0
}

// convertBitPacked converts between two power-of-2 bases, one of which is
// the binary mode (Base.Binary=true). It streams bits through an accumulator
// with no big.Int allocations and is therefore O(N).
//
// Roundtrip semantics: each input digit contributes exactly kIn bits (MSB-first)
// to the stream; output digits are read from the stream in kOut-bit groups.
// If the total bit count isn't a multiple of kOut, one extra output digit is
// emitted whose low bits are zero-padded. On the reverse direction, any
// trailing sub-byte bits (on the binary side) are discarded - which cancels
// out the original padding exactly, giving bit-perfect roundtrip.
func convertBitPacked(input string, from, to *Base, kIn, kOut int) (string, error) {
	var out []byte
	var sb strings.Builder
	if !to.Binary {
		// Rough pre-size: len(input) input-digits * kIn / kOut output-digits,
		// times avg symbol bytes (for binary-in, 8 bits per input byte).
		sb.Grow(len(input) * kIn / kOut)
	}

	var acc uint64
	var accBits int
	mask := func(nBits int) uint64 { return (uint64(1) << nBits) - 1 }

	emit := func() {
		if to.Binary {
			for accBits >= 8 {
				accBits -= 8
				out = append(out, byte(acc>>accBits))
				acc &= mask(accBits)
			}
		} else {
			for accBits >= kOut {
				accBits -= kOut
				sb.WriteString(to.Symbols[int(acc>>accBits)])
				acc &= mask(accBits)
			}
		}
	}

	feed := func(v int) {
		acc = (acc << kIn) | uint64(v)
		accBits += kIn
		emit()
	}

	switch {
	case from.Binary:
		for i := 0; i < len(input); i++ {
			feed(int(input[i]))
		}
	case from.allOneByte:
		for i := 0; i < len(input); i++ {
			v := from.byteValue[input[i]]
			if v < 0 {
				return "", fmt.Errorf("byte %#02x (%q) not in base %q", input[i], string(input[i]), from.Name())
			}
			feed(v)
		}
	default:
		digits, err := from.Tokenize(input)
		if err != nil {
			return "", err
		}
		for _, d := range digits {
			feed(from.value[d])
		}
	}

	// Leftover bits at end.
	if accBits > 0 && !to.Binary {
		// Pad LSB with zeros to make one more full output digit.
		sb.WriteString(to.Symbols[int(acc<<(kOut-accBits))])
	}
	// If to.Binary, any leftover < 8 bits are discarded - they're the LSB
	// padding that the encoding side introduced.

	if to.Binary {
		return string(out), nil
	}
	return sb.String(), nil
}
