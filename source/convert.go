//	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"encoding/binary"
	"fmt"
	"math/big"
	"strings"
	"unicode/utf8"
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
		// The non-binary side's bit width decides the tail handling. Up to 8
		// bits per digit, the plain bit-packed path already round-trips every
		// length and matches the standard encodings, so it is left alone. Above
		// 8 bits (base 2048, 32768, 65536) a zero-padded tail can add a whole
		// byte the decoder can't distinguish from data, so those use a
		// length-prefixed scheme that stays lossless at any length.
		kBase := kOut
		if to.Binary {
			kBase = kIn
		}
		if kBase <= 8 {
			// RFC base32/base64: strip padding on decode (lenient input), and
			// emit it on encode for the strict variants that require it.
			if to.Binary && from.PadSymbol != "" {
				input = strings.TrimRight(input, from.PadSymbol)
			}
			out, err := convertBitPacked(input, from, to, kIn, kOut)
			if err != nil {
				return "", err
			}
			if from.Binary && to.PadEmit {
				out = rfcPad(out, to)
			}
			return out, nil
		}
		// Above 8 bits per digit. If the non-binary base carries a published
		// native scheme (2048, 32768, 65536), match it byte-for-byte using its
		// secondary tail repertoire. Otherwise fall back to the generic
		// length-prefixed packing, which round-trips any power-of-2 base.
		big := to
		if to.Binary {
			big = from
		}
		if big.BinaryScheme != "" {
			if from.Binary {
				return encodeBigBaseNative(input, big), nil
			}
			return decodeBigBaseNative(input, big)
		}
		if from.Binary {
			return encodeBinaryPrefixed(input, to, kOut), nil
		}
		return decodeBinaryPrefixed(input, from, kIn)
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

	// Integer part -> big.Int (Horner's method).
	intVal := new(big.Int)
	tmp := new(big.Int)
	for _, d := range intDigits {
		intVal.Mul(intVal, fromRadix)
		intVal.Add(intVal, tmp.SetInt64(int64(from.value[d])))
	}

	// Fractional part -> num/den.
	fracNum := new(big.Int)
	fracDen := big.NewInt(1)
	for _, d := range fracDigits {
		fracNum.Mul(fracNum, fromRadix)
		fracNum.Add(fracNum, tmp.SetInt64(int64(from.value[d])))
		fracDen.Mul(fracDen, fromRadix)
	}

	// Integer part -> output base (repeated division).
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

	// Fractional part -> output base (repeated multiplication).
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
	if accBits > 0 {
		if to.Binary {
			// We're about to drop accBits worth of trailing bits. This is only
			// safe when they're padding (all zero). That's what the encoder
			// adds when a binary source doesn't align to kIn. If any trailing
			// bit is set, the source wasn't a padded encoding of a binary
			// blob, and discarding would corrupt data.
			if acc != 0 {
				return "", fmt.Errorf("cannot decode to binary: %d trailing bit(s) are nonzero, so the input didn't come from a binary encoding (e.g. odd-length hex has no byte representation)", accBits)
			}
		} else {
			// Pad LSB with zeros to make one more full output digit.
			sb.WriteString(to.Symbols[int(acc<<(kOut-accBits))])
		}
	}

	if to.Binary {
		return string(out), nil
	}
	return sb.String(), nil
}

// encodeBinaryPrefixed encodes raw bytes into a power-of-2 base with more than
// 8 bits per digit (2048, 32768, 65536). For those bases a zero-padded tail can
// add a whole byte the decoder can't tell from real data, so the byte length is
// written as a leading varint and the whole payload is bit-packed. The decoder
// reads the length back and returns exactly that many bytes, so the final
// padding is harmless. Lossless at any input length. Matching the published
// third-party tail schemes for these bases is a separate, later step; this is
// the internal, always-correct default.
func encodeBinaryPrefixed(data string, to *Base, k int) string {
	payload := binary.AppendUvarint(make([]byte, 0, len(data)+4), uint64(len(data)))
	payload = append(payload, data...)

	var sb strings.Builder
	sb.Grow(len(payload) * 8 / k)
	var acc uint64
	var accBits int
	for i := 0; i < len(payload); i++ {
		acc = (acc << 8) | uint64(payload[i])
		accBits += 8
		for accBits >= k {
			accBits -= k
			sb.WriteString(to.Symbols[int(acc>>accBits)])
			acc &= (uint64(1) << accBits) - 1
		}
	}
	if accBits > 0 {
		sb.WriteString(to.Symbols[int(acc<<(k-accBits))])
	}
	return sb.String()
}

// decodeBinaryPrefixed reverses encodeBinaryPrefixed: unpack the digits back to
// bytes, read the leading varint length, and return exactly that many bytes.
// Trailing zero-pad bytes past the counted length are ignored.
func decodeBinaryPrefixed(input string, from *Base, k int) (string, error) {
	digits, err := from.Tokenize(input)
	if err != nil {
		return "", err
	}
	buf := make([]byte, 0, len(digits)*k/8)
	var acc uint64
	var accBits int
	for _, d := range digits {
		acc = (acc << k) | uint64(from.value[d])
		accBits += k
		for accBits >= 8 {
			accBits -= 8
			buf = append(buf, byte(acc>>accBits))
			acc &= (uint64(1) << accBits) - 1
		}
	}
	// Any remaining sub-byte bits are zero padding from the encoder; ignore them.
	n, m := binary.Uvarint(buf)
	if m <= 0 || n > uint64(len(buf)-m) {
		return "", fmt.Errorf("cannot decode to binary: input is not a valid %s binary encoding", from.Name())
	}
	return string(buf[m : m+int(n)]), nil
}

// rfcPad appends the base's padding character to bring the encoded output up to
// the encoding's group boundary (4 characters for base64, 8 for base32), as
// RFC 4648 requires. Called only for bases that emit padding.
func rfcPad(s string, to *Base) string {
	k := powerOfTwoBits(len(to.Symbols))
	group := 8 / gcd(8, k) // characters per whole-byte group
	rem := utf8.RuneCountInString(s) % group
	if rem == 0 {
		return s
	}
	return s + strings.Repeat(to.PadSymbol, group-rem)
}

func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}

// swap16 exchanges the two bytes of a 16-bit value. Base65536 indexes its
// repertoire by the byte-swapped (little-endian) pair, so the raw big-endian
// accumulator and the code-point index differ by this swap in both directions.
func swap16(x int) int { return 256*(x&0xff) + (x >> 8) }

// encodeBigBaseNative encodes raw bytes into one of the published big bases
// (2048, 32768, 65536) exactly as the reference implementations do, so the
// output interoperates with them. Bits are consumed most-significant-first.
// Full chunks map to the primary repertoire; a final partial chunk maps to the
// smaller tail repertoire (or a padded primary char), per the base's scheme.
func encodeBigBaseNative(data string, big *Base) string {
	kPrimary := powerOfTwoBits(len(big.Symbols))
	kTail := powerOfTwoBits(len(big.TailSymbols))

	var sb strings.Builder
	sb.Grow(len(data) * 8 / kPrimary)

	emitPrimary := func(idx int) {
		if big.BinaryScheme == "qntm65536" {
			idx = swap16(idx)
		}
		sb.WriteString(big.Symbols[idx])
	}

	var acc uint64
	var accBits int
	for i := 0; i < len(data); i++ {
		acc = (acc << 8) | uint64(data[i])
		accBits += 8
		for accBits >= kPrimary {
			accBits -= kPrimary
			emitPrimary(int(acc >> accBits))
			acc &= (uint64(1) << accBits) - 1
		}
	}
	if accBits == 0 {
		return sb.String()
	}

	// Final partial chunk.
	if big.BinaryScheme == "rust2048" {
		// The Rust crate right-justifies the leftover value with zero high bits;
		// no padding bits are added.
		if accBits <= kTail {
			sb.WriteString(big.TailSymbols[int(acc)])
		} else {
			emitPrimary(int(acc))
		}
		return sb.String()
	}

	// qntm bases: left-justify the data and pad the low bits with 1s up to the
	// next available repertoire width (tail if it fits, else primary).
	if accBits <= kTail {
		idx := int(acc<<(kTail-accBits)) | (1<<(kTail-accBits) - 1)
		sb.WriteString(big.TailSymbols[idx])
	} else {
		idx := int(acc<<(kPrimary-accBits)) | (1<<(kPrimary-accBits) - 1)
		emitPrimary(idx)
	}
	return sb.String()
}

// decodeBigBaseNative reverses encodeBigBaseNative for the published big bases.
// Each character is looked up in the primary or the tail repertoire; a tail
// character is only legal as the last one. qntm bases verify the trailing pad
// is all-ones; the Rust base reconstructs the exact bit count from position.
func decodeBigBaseNative(input string, big *Base) (string, error) {
	kPrimary := powerOfTwoBits(len(big.Symbols))
	kTail := powerOfTwoBits(len(big.TailSymbols))
	runes := []rune(input)
	rust := big.BinaryScheme == "rust2048"

	var out []byte
	var acc uint64
	var accBits int
	flush := func() {
		for accBits >= 8 {
			accBits -= 8
			out = append(out, byte(acc>>accBits))
			acc &= (uint64(1) << accBits) - 1
		}
	}

	for i, r := range runes {
		last := i == len(runes)-1
		s := string(r)

		if idx, ok := big.value[s]; ok {
			bits := kPrimary
			if rust && last {
				bits = rustFinalBits(len(runes), kPrimary) // 4..kPrimary
			}
			if big.BinaryScheme == "qntm65536" {
				idx = swap16(idx)
			}
			if idx >= (1 << bits) {
				return "", fmt.Errorf("cannot decode from %s: final digit carries more bits than the input length allows", big.Name())
			}
			acc = (acc << bits) | uint64(idx)
			accBits += bits
			flush()
			continue
		}

		idx, ok := big.tailValue[s]
		if !ok {
			return "", fmt.Errorf("cannot decode from %s: symbol %q is not in the base", big.Name(), s)
		}
		if !last {
			return "", fmt.Errorf("cannot decode from %s: tail symbol %q appears before the end", big.Name(), s)
		}
		bits := kTail
		if rust {
			bits = 8 - (accBits % 8) // exact bits needed to finish the last byte
			if bits == 0 || bits > kTail {
				return "", fmt.Errorf("cannot decode from %s: misplaced tail symbol %q", big.Name(), s)
			}
		}
		if idx >= (1 << bits) {
			return "", fmt.Errorf("cannot decode from %s: tail digit out of range", big.Name())
		}
		acc = (acc << bits) | uint64(idx)
		accBits += bits
		flush()
	}

	if rust {
		if accBits != 0 {
			return "", fmt.Errorf("cannot decode from %s: input is not a whole number of bytes", big.Name())
		}
	} else if acc != (uint64(1)<<accBits)-1 {
		// qntm pads the tail with 1-bits; anything else is not a valid encoding.
		return "", fmt.Errorf("cannot decode from %s: bad trailing padding", big.Name())
	}
	return string(out), nil
}

// rustFinalBits returns how many bits the last character of a rust-base2048
// string carries when that character comes from the primary repertoire. The
// first n-1 characters carry kPrimary bits each; the last carries whatever is
// needed to land on a whole number of bytes (kPrimary for an exact fit).
func rustFinalBits(n, kPrimary int) int {
	remainder := (kPrimary * (n - 1)) % 8
	need := (8 - remainder) % 8 // 0..7
	switch {
	case need == 0:
		return 8
	case need <= 3:
		return need + 8 // 9..kPrimary
	default:
		return need // 4..7
	}
}
