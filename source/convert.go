//	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"encoding/binary"
	"fmt"
	"io"
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
	// Fast paths for the common shape: raw bytes on one side and a single-byte-
	// per-digit base (base 16, 32, 64, ...) on the other. These skip the per-byte
	// closures and string indexing of the general loop, writing straight into a
	// sized byte buffer through a small lookup table. This is the base64/base16/
	// base32 case, i.e. everything that competes with the system encoders.
	if from.Binary && !to.Binary && to.allOneByte {
		return encodeBytesToDigits(input, to, kOut), nil
	}
	if to.Binary && !from.Binary && from.allOneByte {
		return decodeDigitsToBytes(input, from, kIn)
	}

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

// encodeBytesToDigits is the fast path of convertBitPacked for raw bytes ->
// a single-byte-per-digit power-of-2 base (kOut bits per digit, kOut <= 8).
// It packs bits most-significant-first and appends one output byte per digit
// via a lookup table. A final partial digit is zero-padded in its low bits,
// exactly as the general path does, so the reverse direction cancels it.
func encodeBytesToDigits(input string, to *Base, kOut int) string {
	var table [256]byte // index (0 .. 2^kOut-1) -> the digit's single byte
	n := 1 << kOut
	for i := 0; i < n; i++ {
		table[i] = to.Symbols[i][0]
	}

	out := make([]byte, 0, len(input)*8/kOut+1)
	var acc uint64
	var accBits int
	for i := 0; i < len(input); i++ {
		acc = (acc << 8) | uint64(input[i])
		accBits += 8
		for accBits >= kOut {
			accBits -= kOut
			out = append(out, table[acc>>accBits])
			acc &= (uint64(1) << accBits) - 1
		}
	}
	if accBits > 0 {
		out = append(out, table[acc<<(kOut-accBits)])
	}
	return string(out)
}

// decodeDigitsToBytes is the fast path of convertBitPacked for a single-byte-
// per-digit power-of-2 base -> raw bytes. Each input byte maps to its kIn-bit
// digit value through the base's byteValue table (which already carries the
// case-flipped input aliases), packed most-significant-first into output bytes.
// Any trailing sub-byte bits must be zero, or the input wasn't a byte-aligned
// encoding (e.g. odd-length hex); that mirrors the general path's guard.
func decodeDigitsToBytes(input string, from *Base, kIn int) (string, error) {
	out := make([]byte, 0, len(input)*kIn/8+1)
	var acc uint64
	var accBits int
	for i := 0; i < len(input); i++ {
		v := from.byteValue[input[i]]
		if v < 0 {
			return "", fmt.Errorf("byte %#02x (%q) not in base %q", input[i], string(input[i]), from.Name())
		}
		acc = (acc << kIn) | uint64(v)
		accBits += kIn
		for accBits >= 8 {
			accBits -= 8
			out = append(out, byte(acc>>accBits))
			acc &= (uint64(1) << accBits) - 1
		}
	}
	if accBits > 0 && acc != 0 {
		return "", fmt.Errorf("cannot decode to binary: %d trailing bit(s) are nonzero, so the input didn't come from a binary encoding (e.g. odd-length hex has no byte representation)", accBits)
	}
	return string(out), nil
}

// streamConvert handles the binary bit-packed conversions (raw bytes <-> a
// single-byte-per-digit power-of-2 base, up to 8 bits per digit) by streaming
// straight from r to w, holding neither the whole input nor the whole output in
// memory. It returns handled=false, without writing anything, for any conversion
// it can't stream, so the caller falls back to the buffered Convert. This is the
// base64/base32/base16 hot path; it borrows the streaming + byte-aligned tricks
// the system encoders use (base64's 3-bytes->4-chars, generalized to any k).
func streamConvert(r io.Reader, w io.Writer, from, to *Base) (bool, error) {
	kIn := powerOfTwoBits(len(from.Symbols))
	kOut := powerOfTwoBits(len(to.Symbols))
	if kIn == 0 || kOut == 0 {
		return false, nil
	}
	kBase := kOut
	if to.Binary {
		kBase = kIn
	}
	if kBase > 8 { // the big native bases (2048/32768/65536) keep the buffered path
		return false, nil
	}
	switch {
	case from.Binary && !to.Binary && to.allOneByte:
		return true, streamEncode(r, w, to, kOut)
	case to.Binary && !from.Binary && from.allOneByte:
		// A multi-byte pad symbol can't be matched a byte at a time, so bail.
		if len(from.PadSymbol) > 1 {
			return false, nil
		}
		return true, streamDecode(r, w, from, kIn)
	}
	return false, nil
}

// streamEncode packs raw bytes from r into single-byte digits on w. It works a
// whole group at a time: groupBytes input bytes carry exactly groupChars output
// digits (3->4 for base64, 5->8 for base32, 1->2 for hex, ...), so within a group
// there is no bit-by-bit accumulator, just shifts and table lookups. The two hot
// widths (base64, hex) get a hand-unrolled constant-shift inner loop, the way the
// system encoders do; the rest use the general group loop. Output is written in
// big batches (no per-byte calls). A final partial group zero-pads its last
// digit, and RFC padding, if the base emits it, tops the output up to the group
// boundary - matching the buffered path byte-for-byte.
func streamEncode(r io.Reader, w io.Writer, to *Base, kOut int) error {
	var table [256]byte
	for i, n := 0, 1<<kOut; i < n; i++ {
		table[i] = to.Symbols[i][0]
	}
	mask := uint64(1)<<kOut - 1
	g := gcd(8, kOut)
	groupBytes := kOut / g // == lcm(8,kOut)/8
	groupChars := 8 / g    // == lcm(8,kOut)/kOut
	bits := groupBytes * 8

	const groupsPerBuf = 1 << 15
	inbuf := make([]byte, groupBytes*groupsPerBuf)
	out := make([]byte, groupChars*groupsPerBuf)

	totalChars := 0
	carry := 0
	for {
		nn, err := io.ReadFull(r, inbuf[carry:])
		total := carry + nn
		groups := total / groupBytes
		o, p := 0, 0
		switch kOut {
		case 6: // base64: 3 bytes -> 4 chars
			for gi := 0; gi < groups; gi++ {
				b0, b1, b2 := inbuf[p], inbuf[p+1], inbuf[p+2]
				p += 3
				out[o] = table[b0>>2]
				out[o+1] = table[(b0&0x03)<<4|(b1>>4)]
				out[o+2] = table[(b1&0x0f)<<2|(b2>>6)]
				out[o+3] = table[b2&0x3f]
				o += 4
			}
		case 4: // hex: 1 byte -> 2 chars
			for gi := 0; gi < groups; gi++ {
				b := inbuf[p]
				p++
				out[o] = table[b>>4]
				out[o+1] = table[b&0x0f]
				o += 2
			}
		case 5: // base32: 5 bytes -> 8 chars
			for gi := 0; gi < groups; gi++ {
				b0, b1, b2, b3, b4 := inbuf[p], inbuf[p+1], inbuf[p+2], inbuf[p+3], inbuf[p+4]
				p += 5
				out[o] = table[b0>>3]
				out[o+1] = table[(b0&0x07)<<2|(b1>>6)]
				out[o+2] = table[(b1>>1)&0x1f]
				out[o+3] = table[(b1&0x01)<<4|(b2>>4)]
				out[o+4] = table[(b2&0x0f)<<1|(b3>>7)]
				out[o+5] = table[(b3>>2)&0x1f]
				out[o+6] = table[(b3&0x03)<<3|(b4>>5)]
				out[o+7] = table[b4&0x1f]
				o += 8
			}
		default:
			for gi := 0; gi < groups; gi++ {
				var acc uint64
				for b := 0; b < groupBytes; b++ {
					acc = acc<<8 | uint64(inbuf[p])
					p++
				}
				for j := 0; j < groupChars; j++ {
					out[o] = table[(acc>>(bits-(j+1)*kOut))&mask]
					o++
				}
			}
		}
		if o > 0 {
			if _, werr := w.Write(out[:o]); werr != nil {
				return werr
			}
			totalChars += o
		}
		carry = total - groups*groupBytes
		if carry > 0 {
			copy(inbuf[:carry], inbuf[groups*groupBytes:total])
		}
		if err != nil { // io.EOF / io.ErrUnexpectedEOF: end of stream
			break
		}
	}
	// Final partial group + any RFC padding, assembled and written in one go.
	if carry > 0 || (to.PadEmit && to.PadSymbol != "") {
		var tail []byte
		acc := uint64(0)
		accBits := 0
		for b := 0; b < carry; b++ {
			acc = acc<<8 | uint64(inbuf[b])
			accBits += 8
			for accBits >= kOut {
				accBits -= kOut
				tail = append(tail, table[(acc>>accBits)&mask])
				acc &= uint64(1)<<accBits - 1
				totalChars++
			}
		}
		if accBits > 0 {
			tail = append(tail, table[(acc<<(kOut-accBits))&mask])
			totalChars++
		}
		if to.PadEmit && to.PadSymbol != "" {
			if rem := totalChars % groupChars; rem != 0 {
				for i := 0; i < groupChars-rem; i++ {
					tail = append(tail, to.PadSymbol...)
				}
			}
		}
		if len(tail) > 0 {
			if _, err := w.Write(tail); err != nil {
				return err
			}
		}
	}
	return nil
}

// streamDecode unpacks single-byte digits from r into raw bytes on w. It reads
// each digit through the base's byteValue table (which carries the case-flipped
// input aliases), tolerates line breaks the way standard decoders do (so it reads
// wrapped base64/base32), and strips a trailing run of the pad symbol. Output is
// batched per input chunk. Any leftover sub-byte bits at the end must be zero,
// matching the buffered guard against non-byte-aligned input (odd-length hex).
//
// The hot widths (base64, base32, hex) get an unrolled group path: whenever the
// accumulator is group-aligned and the next whole group of digits is all valid,
// the group is decoded with constant shifts and no accumulator bookkeeping. A
// line break, pad, or chunk edge drops back to the per-byte path, which realigns
// the accumulator and lets the group path resume - so wrapped input still flies.
func streamDecode(r io.Reader, w io.Writer, from *Base, kIn int) error {
	var padByte byte
	hasPad := from.PadSymbol != ""
	if hasPad {
		padByte = from.PadSymbol[0]
	}
	dec := &from.byteValue
	const bufSize = 1 << 16
	inbuf := make([]byte, bufSize)
	out := make([]byte, 0, bufSize*kIn/8+1)

	var acc uint64
	var accBits int
	for {
		nn, err := r.Read(inbuf)
		out = out[:0]
		i := 0
		for i < nn {
			// Unrolled group path, only while byte-aligned (accBits == 0).
			if accBits == 0 {
				switch kIn {
				case 6: // base64: 4 digits -> 3 bytes
					for i+4 <= nn {
						v0, v1, v2, v3 := dec[inbuf[i]], dec[inbuf[i+1]], dec[inbuf[i+2]], dec[inbuf[i+3]]
						if v0|v1|v2|v3 < 0 {
							break
						}
						out = append(out, byte(v0<<2|v1>>4), byte(v1<<4|v2>>2), byte(v2<<6|v3))
						i += 4
					}
				case 4: // hex: 2 digits -> 1 byte
					for i+2 <= nn {
						v0, v1 := dec[inbuf[i]], dec[inbuf[i+1]]
						if v0|v1 < 0 {
							break
						}
						out = append(out, byte(v0<<4|v1))
						i += 2
					}
				case 5: // base32: 8 digits -> 5 bytes
					for i+8 <= nn {
						v0, v1, v2, v3 := dec[inbuf[i]], dec[inbuf[i+1]], dec[inbuf[i+2]], dec[inbuf[i+3]]
						v4, v5, v6, v7 := dec[inbuf[i+4]], dec[inbuf[i+5]], dec[inbuf[i+6]], dec[inbuf[i+7]]
						if v0|v1|v2|v3|v4|v5|v6|v7 < 0 {
							break
						}
						out = append(out,
							byte(v0<<3|v1>>2),
							byte(v1<<6|v2<<1|v3>>4),
							byte(v3<<4|v4>>1),
							byte(v4<<7|v5<<2|v6>>3),
							byte(v6<<5|v7))
						i += 8
					}
				}
			}
			if i >= nn {
				break
			}
			// Per-byte path: one digit, or a skipped line break / pad, or an error.
			c := inbuf[i]
			i++
			v := dec[c]
			if v >= 0 {
				acc = acc<<kIn | uint64(v)
				accBits += kIn
				if accBits >= 8 {
					accBits -= 8
					out = append(out, byte(acc>>accBits))
					acc &= uint64(1)<<accBits - 1
				}
				continue
			}
			if c == '\n' || c == '\r' || (hasPad && c == padByte) {
				continue
			}
			return fmt.Errorf("byte %#02x (%q) not in base %q", c, string(c), from.Name())
		}
		if len(out) > 0 {
			if _, werr := w.Write(out); werr != nil {
				return werr
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
	}
	if accBits > 0 && acc != 0 {
		return fmt.Errorf("cannot decode to binary: %d trailing bit(s) are nonzero, so the input didn't come from a binary encoding (e.g. odd-length hex has no byte representation)", accBits)
	}
	return nil
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
