//	Copyright © 2023-2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
//	Licensed under the Apache License, Version 2.0. Full text in
//	../convertbase/LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

//go:build wasip1

// Reactor entry point: a WebAssembly library module any host runtime can load
// and call, built with -buildmode=c-shared for GOOS=wasip1. Like the browser
// module this is a build target of the same library the command uses, not a
// second implementation. The ABI is documented in README.md beside this file;
// the design is design_docs/20260801_wasm_reactor.md.
//
// Apache-2.0 rather than the command's GPL, for the same reason as the browser
// module: it links into somebody else's program.
//
// Only numbers cross a wasmexport boundary, so strings travel as a pointer
// into linear memory plus a length. The host allocates a region with alloc(),
// writes its input there, and passes offsets. String results come back packed
// into one uint64 as (pointer << 32) | length, because an export gets a single
// result. A zero return means failure; last_error_code/last_error_text say why.
//
// The regions map is what keeps handed-out memory alive: Go's collector would
// otherwise reclaim a buffer the host still holds a pointer to. It also makes
// a double free detectable instead of silently corrupting. No locking anywhere
// on purpose - a wasm instance runs the host's calls one at a time.
package main

import (
	"errors"
	"unsafe"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
)

// Stable numeric error codes, part of the ABI contract. Add at the end only;
// hosts map these to their own handling and a renumber would break them.
const (
	errNone          = 0
	errUnknownBase   = 1 // base name or alias resolves to nothing
	errMissingMarker = 2 // output base lacks a sign or decimal marker the value needs
	errMarkerDefault = 3 // default marker collides with a digit
	errRetiredToken  = 4 // symbol spec carried a retired neg=/dec=/pad= token
	errBadInput      = 5 // any other conversion or parse failure
	errBadArg        = 6 // bad pointer, length, size, or precision from the host
	errInternal      = 7 // registry failed to initialize
)

// Fractional digits cost quadratic time and the module runs synchronously
// inside the host's call, so precision is bounded the same way the browser
// module bounds it.
const maxPrecision = 100000

var (
	reg    *convertbase.Registry
	regErr error

	// Handed-out memory, keyed by its linear-memory address.
	regions = map[uint32][]byte{}

	// Module-owned, not freed by the host: the text is stable only until the
	// next call, so a host copies it out before calling anything else.
	lastCode int32
	lastText []byte

	versionBuf = []byte(convertbase.Version)
)

// Runs during _initialize, so the registry exists before the first export call.
func init() { reg, regErr = convertbase.NewRegistry() }

// Never called under -buildmode=c-shared; the compiler requires it anyway.
func main() {}

func clearErr() { lastCode = errNone; lastText = lastText[:0] }

func setErr(code int32, msg string) {
	lastCode = code
	lastText = append(lastText[:0], msg...)
}

// classify maps the library's typed errors onto the ABI codes.
func classify(err error) int32 {
	var ub *convertbase.UnknownBaseError
	var mm *convertbase.MissingMarkerError
	var md *convertbase.MarkerDefaultError
	var rt *convertbase.RetiredTokenError
	switch {
	case errors.As(err, &ub):
		return errUnknownBase
	case errors.As(err, &mm):
		return errMissingMarker
	case errors.As(err, &md):
		return errMarkerDefault
	case errors.As(err, &rt):
		return errRetiredToken
	}
	return errBadInput
}

func ready() bool {
	if regErr != nil {
		setErr(errInternal, "registry: "+regErr.Error())
		return false
	}
	return true
}

func pack(b []byte) uint64 {
	p := uint32(uintptr(unsafe.Pointer(unsafe.SliceData(b))))
	return uint64(p)<<32 | uint64(uint32(len(b)))
}

// packRegion copies s into a fresh region the host must free. Capacity is
// never zero so an empty result still has a real, nonzero address.
func packRegion(s string) uint64 {
	buf := make([]byte, len(s), max(len(s), 1))
	copy(buf, s)
	p := uint32(uintptr(unsafe.Pointer(unsafe.SliceData(buf))))
	regions[p] = buf
	return pack(buf)
}

// hostBytes resolves a host-supplied pointer and length against the handed-out
// regions. Requiring the range to sit inside a region catches a stale or
// misplaced pointer at the call instead of reading whatever the Go heap holds
// there. A zero length is a legal empty string.
func hostBytes(ptr, n uint32) ([]byte, bool) {
	if n == 0 {
		return nil, true
	}
	for base, buf := range regions {
		if ptr >= base && uint64(ptr)+uint64(n) <= uint64(base)+uint64(len(buf)) {
			off := ptr - base
			return buf[off : off+n], true
		}
	}
	setErr(errBadArg, "pointer and length do not fall inside an allocated region")
	return nil, false
}

// namedBase resolves a base name the same way the command does, so every
// alias, prefix form, and near-match suggestion behaves identically here.
func namedBase(ptr, n uint32) (*convertbase.Base, bool) {
	name, ok := hostBytes(ptr, n)
	if !ok {
		return nil, false
	}
	b, err := convertbase.ResolveBase(reg, string(name), "", nil)
	if err != nil {
		setErr(classify(err), err.Error())
		return nil, false
	}
	return b, true
}

//go:wasmexport alloc
func alloc(size uint32) uint32 {
	clearErr()
	if size == 0 {
		setErr(errBadArg, "alloc: size must be positive")
		return 0
	}
	buf := make([]byte, size)
	p := uint32(uintptr(unsafe.Pointer(unsafe.SliceData(buf))))
	regions[p] = buf
	return p
}

//go:wasmexport free
func free(ptr uint32) int32 {
	clearErr()
	if _, ok := regions[ptr]; !ok {
		setErr(errBadArg, "free: not an allocated region")
		return errBadArg
	}
	delete(regions, ptr)
	return errNone
}

// convert is the one-shot conversion: value in fromName's base out as toName's.
// A negative precision means automatic, same as the command's default. Returns
// a packed region the host frees, or zero on error.
//
//go:wasmexport convert
func convert(fromPtr, fromLen, toPtr, toLen, valPtr, valLen uint32, precision int32) uint64 {
	clearErr()
	if !ready() {
		return 0
	}
	if precision > maxPrecision {
		setErr(errBadArg, "precision must be at most 100000")
		return 0
	}
	if precision < 0 {
		precision = -1
	}
	from, ok := namedBase(fromPtr, fromLen)
	if !ok {
		return 0
	}
	to, ok := namedBase(toPtr, toLen)
	if !ok {
		return 0
	}
	value, ok := hostBytes(valPtr, valLen)
	if !ok {
		return 0
	}
	out, err := convertbase.Convert(string(value), from, to, int(precision))
	if err != nil {
		setErr(classify(err), err.Error())
		return 0
	}
	return packRegion(out)
}

// lookup validates a base name or alias without converting anything.
//
//go:wasmexport lookup
func lookup(namePtr, nameLen uint32) int32 {
	clearErr()
	if !ready() {
		return errInternal
	}
	if _, ok := namedBase(namePtr, nameLen); !ok {
		return lastCode
	}
	return errNone
}

// base_radix returns the base's symbol count, or the negated error code.
//
//go:wasmexport base_radix
func baseRadix(namePtr, nameLen uint32) int64 {
	clearErr()
	if !ready() {
		return -errInternal
	}
	b, ok := namedBase(namePtr, nameLen)
	if !ok {
		return -int64(lastCode)
	}
	return int64(len(b.Symbols))
}

// base_zero returns the base's first symbol as a packed region the host frees,
// or zero on error. This is the padding symbol for fixed-width output: the
// word-safe base 32 starts at "2", so assuming "0" would be silently wrong.
//
//go:wasmexport base_zero
func baseZero(namePtr, nameLen uint32) uint64 {
	clearErr()
	if !ready() {
		return 0
	}
	b, ok := namedBase(namePtr, nameLen)
	if !ok {
		return 0
	}
	return packRegion(b.Symbols[0])
}

// symbol_count returns how many of the base's digit symbols make up the
// string, or the negated error code. Counts symbols rather than bytes, which
// is what fixed-width padding needs when digits are multi-byte. Digits only:
// a sign or decimal marker in the string is an error here.
//
//go:wasmexport symbol_count
func symbolCount(namePtr, nameLen, strPtr, strLen uint32) int64 {
	clearErr()
	if !ready() {
		return -errInternal
	}
	b, ok := namedBase(namePtr, nameLen)
	if !ok {
		return -int64(lastCode)
	}
	s, ok := hostBytes(strPtr, strLen)
	if !ok {
		return -int64(lastCode)
	}
	digits, err := b.Tokenize(string(s))
	if err != nil {
		setErr(classify(err), err.Error())
		return -int64(lastCode)
	}
	return int64(len(digits))
}

// symbol_slice returns the part of the string covering symbols
// [start, start+count), counting symbols rather than bytes. Negative start
// counts from the right end; count < 0 means through the end; both clamp
// rather than error. Packed region the host frees, or zero on error - and a
// zero-length result with last_error_code 0 is a legal empty answer.
//
//go:wasmexport symbol_slice
func symbolSlice(namePtr, nameLen, strPtr, strLen uint32, start, count int32) uint64 {
	clearErr()
	if !ready() {
		return 0
	}
	b, ok := namedBase(namePtr, nameLen)
	if !ok {
		return 0
	}
	s, ok := hostBytes(strPtr, strLen)
	if !ok {
		return 0
	}
	out, err := b.SymbolSlice(string(s), int(start), int(count))
	if err != nil {
		setErr(classify(err), err.Error())
		return 0
	}
	return packRegion(out)
}

// fit right-aligns the string to exactly width symbols in the base: left-fills
// with the base's zero symbol when short, keeps the rightmost width symbols
// when long. Packed region the host frees, or zero on error.
//
//go:wasmexport fit
func fit(namePtr, nameLen, strPtr, strLen, width uint32) uint64 {
	clearErr()
	if !ready() {
		return 0
	}
	b, ok := namedBase(namePtr, nameLen)
	if !ok {
		return 0
	}
	s, ok := hostBytes(strPtr, strLen)
	if !ok {
		return 0
	}
	out, err := b.Fit(string(s), int(width))
	if err != nil {
		setErr(classify(err), err.Error())
		return 0
	}
	return packRegion(out)
}

// convert_fit is convert followed by fit in the destination base, one call and
// one region instead of two round trips. Auto precision only: the fixed-width
// fields this exists for are integers, and a caller that wants a fraction has
// the two-step path.
//
//go:wasmexport convert_fit
func convertFit(fromPtr, fromLen, toPtr, toLen, valPtr, valLen, width uint32) uint64 {
	clearErr()
	if !ready() {
		return 0
	}
	from, ok := namedBase(fromPtr, fromLen)
	if !ok {
		return 0
	}
	to, ok := namedBase(toPtr, toLen)
	if !ok {
		return 0
	}
	value, ok := hostBytes(valPtr, valLen)
	if !ok {
		return 0
	}
	out, err := convertbase.Convert(string(value), from, to, -1)
	if err != nil {
		setErr(classify(err), err.Error())
		return 0
	}
	out, err = to.Fit(out, int(width))
	if err != nil {
		setErr(classify(err), err.Error())
		return 0
	}
	return packRegion(out)
}

//go:wasmexport last_error_code
func lastErrorCode() int32 { return lastCode }

// last_error_text returns the current error message, packed. Module-owned: do
// not free it, and copy it out before the next call overwrites it. Zero when
// there is no error.
//
//go:wasmexport last_error_text
func lastErrorText() uint64 {
	if len(lastText) == 0 {
		return 0
	}
	return pack(lastText)
}

// version returns the library version, packed. Module-owned, never freed.
//
//go:wasmexport version
func version() uint64 { return pack(versionBuf) }

// region_count reports how many allocated regions are outstanding, so a host
// or a test can assert it freed everything.
//
//go:wasmexport region_count
func regionCount() uint32 { return uint32(len(regions)) }
