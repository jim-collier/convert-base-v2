//	Copyright © 2023-2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
//	Licensed under the GPL, Version 2 or later. Full text in ../../../license.md, or:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

// Host-side exerciser for the reactor module. Loads the .wasm under wazero
// (pure Go, so no system runtime is needed), drives every export through the
// documented ABI, and exits nonzero on the first disagreement. A separate
// module on purpose: the library itself stays at zero dependencies.
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
	"github.com/tetratelabs/wazero/imports/wasi_snapshot_preview1"
)

// Mirrors the ABI error codes in reactor/README.md.
const (
	errNone        = 0
	errUnknownBase = 1
	errBadInput    = 5
	errBadArg      = 6
)

type host struct {
	ctx context.Context
	mod api.Module
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: reactor-host MODULE.wasm")
		os.Exit(2)
	}
	wasm, err := os.ReadFile(os.Args[1])
	if err != nil {
		fatal("read module: %v", err)
	}

	ctx := context.Background()
	rt := wazero.NewRuntime(ctx)
	defer func() { _ = rt.Close(ctx) }()
	wasi_snapshot_preview1.MustInstantiate(ctx, rt)

	// A reactor initializes and stays resident; _start would mean the command
	// shape slipped back in.
	mod, err := rt.InstantiateWithConfig(ctx, wasm,
		wazero.NewModuleConfig().WithStartFunctions("_initialize"))
	if err != nil {
		fatal("instantiate: %v", err)
	}
	if mod.ExportedFunction("_start") != nil {
		fatal("module exports _start; it is a command, not a reactor")
	}
	for _, name := range []string{"alloc", "free", "convert", "lookup",
		"base_radix", "base_zero", "symbol_count",
		"last_error_code", "last_error_text", "version", "region_count"} {
		if mod.ExportedFunction(name) == nil {
			fatal("export %q missing", name)
		}
	}

	h := &host{ctx: ctx, mod: mod}
	h.run()
	fmt.Println("reactor-host: all checks passed")
}

func (h *host) run() {
	// Version must be a plausible semver, and module-owned (no free needed).
	ver := h.readPacked(h.call("version"))
	if len(ver) < 5 || ver[0] != 'v' {
		fatal("version: got %q", ver)
	}

	// One-shot conversions against known answers, auto precision.
	for _, c := range []struct{ from, to, in, want string }{
		{"10", "16", "1234567890", "499602D2"},
		{"10", "16", "-255", "-FF"},
		{"16", "10", "ff", "255"},
		{"10", "32w", "0", "2"},
		{"10", "2", "10", "1010"},
		{"10", "16", "0.5", "0.8"},
	} {
		got, code := h.convert(c.from, c.to, c.in, -1)
		if code != errNone || got != c.want {
			fatal("convert %s %s->%s: got %q code %d, want %q", c.in, c.from, c.to, got, code, c.want)
		}
	}

	// Fixed precision.
	if got, code := h.convert("10", "16", "0.1", 4); code != errNone || got != "0.199A" {
		fatal("convert 0.1 with precision 4: got %q code %d", got, code)
	}

	// lookup: aliases resolve, junk does not, and the error text keeps the
	// library's near-match suggestion.
	for _, name := range []string{"16", "hex", "b16", "32w", "bytes"} {
		args := h.str(name)
		code := h.calli32("lookup", args...)
		if code != errNone {
			fatal("lookup %q: code %d (%s)", name, code, h.lastError())
		}
		h.freeAll(args[0])
	}
	args := h.str("hexx")
	if code := h.calli32("lookup", args...); code != errUnknownBase {
		fatal("lookup hexx: code %d, want %d", code, errUnknownBase)
	} else if msg := h.lastError(); msg == "" {
		fatal("lookup hexx: no error text")
	}
	h.freeAll(args[0])

	// Base metadata: radix, and the zero symbol that is not "0" on 32w.
	for _, c := range []struct {
		name string
		rad  int64
		zero string
	}{
		{"16", 16, "0"},
		{"32w", 32, "2"},
		{"64rfc", 64, "A"},
		{"bytes", 256, "\x00"},
	} {
		nameArgs := h.str(c.name)
		if rad := h.calli64("base_radix", nameArgs...); rad != c.rad {
			fatal("base_radix %s: got %d, want %d", c.name, rad, c.rad)
		}
		zero := h.readPackedFree(h.call("base_zero", nameArgs...))
		if zero != c.zero {
			fatal("base_zero %s: got %q, want %q", c.name, zero, c.zero)
		}
		h.freeAll(nameArgs[0])
	}

	// symbol_count counts symbols, not bytes. 128tt digits are multi-byte.
	enc, code := h.convert("10", "128tt", "1234567890", -1)
	if code != errNone {
		fatal("convert to 128tt: code %d", code)
	}
	scArgs := h.str("128tt")
	scArgs = append(scArgs, h.str(enc)...)
	if n := h.calli64("symbol_count", scArgs...); n != 5 {
		fatal("symbol_count 128tt %q: got %d, want 5", enc, n)
	}
	if len(enc) <= 5 {
		fatal("128tt encoding %q is not multi-byte; the check proves nothing", enc)
	}
	h.freeAll(scArgs[0], scArgs[2])

	// Error paths: bad digit, unknown base, stale pointer, double free.
	if _, code := h.convert("10", "16", "12z", -1); code != errBadInput {
		fatal("convert 12z: code %d, want %d", code, errBadInput)
	}
	if _, code := h.convert("nope", "16", "1", -1); code != errUnknownBase {
		fatal("convert from nope: code %d, want %d", code, errUnknownBase)
	}
	if code := h.calli32("lookup", 12345678, 3); code != errBadArg {
		fatal("lookup with wild pointer: code %d, want %d", code, errBadArg)
	}
	p := h.call("alloc", 8)
	if h.calli32("free", p) != errNone {
		fatal("free of fresh region failed")
	}
	if h.calli32("free", p) != errBadArg {
		fatal("double free not detected")
	}

	// Leak check: everything above freed what it took, and a work loop holds
	// region_count at zero. A missing free would step it up every pass.
	if n := h.call("region_count"); n != 0 {
		fatal("region_count %d after checks, want 0", n)
	}
	for i := 0; i < 2000; i++ {
		if _, code := h.convert("10", "62", fmt.Sprint(1000000+i), -1); code != errNone {
			fatal("loop convert %d: code %d", i, code)
		}
	}
	if n := h.call("region_count"); n != 0 {
		fatal("region_count %d after loop, want 0", n)
	}
}

// convert runs one conversion through the module, freeing everything it
// allocates, and returns the result with the error code.
func (h *host) convert(from, to, value string, precision int64) (string, int32) {
	args := h.str(from)
	args = append(args, h.str(to)...)
	args = append(args, h.str(value)...)
	args = append(args, api.EncodeI32(int32(precision)))
	packed := h.call("convert", args...)
	code := h.calli32("last_error_code")
	out := ""
	if packed != 0 {
		out = h.readPackedFree(packed)
	}
	h.freeAll(args[0], args[2], args[4])
	return out, code
}

// str copies s into module memory and returns its (ptr, len) argument pair.
func (h *host) str(s string) []uint64 {
	if s == "" {
		return []uint64{0, 0}
	}
	p := h.call("alloc", uint64(len(s)))
	if p == 0 {
		fatal("alloc %d failed: %s", len(s), h.lastError())
	}
	if !h.mod.Memory().Write(uint32(p), []byte(s)) {
		fatal("memory write at %d failed", p)
	}
	return []uint64{p, uint64(len(s))}
}

func (h *host) freeAll(ptrs ...uint64) {
	for _, p := range ptrs {
		if p == 0 {
			continue
		}
		if h.calli32("free", p) != errNone {
			fatal("free %d failed: %s", p, h.lastError())
		}
	}
}

// readPacked reads a (ptr << 32 | len) string without freeing (module-owned).
func (h *host) readPacked(packed uint64) string {
	if packed == 0 {
		return ""
	}
	ptr, n := uint32(packed>>32), uint32(packed)
	b, ok := h.mod.Memory().Read(ptr, n)
	if !ok {
		fatal("memory read %d+%d failed", ptr, n)
	}
	return string(b)
}

// readPackedFree reads a packed string the module allocated, then frees it.
func (h *host) readPackedFree(packed uint64) string {
	if packed == 0 {
		fatal("expected a result, got 0: %s", h.lastError())
	}
	s := h.readPacked(packed)
	h.freeAll(uint64(uint32(packed >> 32)))
	return s
}

func (h *host) lastError() string {
	return h.readPacked(h.call("last_error_text"))
}

func (h *host) call(name string, args ...uint64) uint64 {
	res, err := h.mod.ExportedFunction(name).Call(h.ctx, args...)
	if err != nil {
		fatal("%s: %v", name, err)
	}
	if len(res) == 0 {
		return 0
	}
	return res[0]
}

func (h *host) calli32(name string, args ...uint64) int32 {
	return api.DecodeI32(h.call(name, args...))
}

func (h *host) calli64(name string, args ...uint64) int64 {
	return int64(h.call(name, args...))
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "reactor-host: FAIL: "+format+"\n", args...)
	os.Exit(1)
}
