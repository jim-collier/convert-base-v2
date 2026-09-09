//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GPL, Version 2 or later. Full text in ../../../license.md, or:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

// Host-side exerciser for the reactor module. Loads the .wasm under wazero
// (pure Go, so no system runtime is needed), drives every export through the
// documented ABI, and exits nonzero on the first disagreement. A separate
// module on purpose: the library itself stays at zero dependencies.
//
// Two extra modes let the harness hold the reactor to the command's answers:
// --batch reads one conversion request per stdin line (FROM <tab> TO <tab>
// PRECISION <tab> HEX(VALUE), answering "ok" <tab> HEX(RESULT) or "err", the
// module-driver protocol), and --stream FROM TO [CHUNK] pipes stdin to stdout
// through the streaming ABI.
package main

import (
	"bufio"
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

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

	// Error text of the last failed stream helper call, captured before the
	// input region is freed (free clears the module's last-error state).
	errText string
}

func main() {
	args := os.Args[1:]
	mode := ""
	if len(args) > 0 && strings.HasPrefix(args[0], "--") {
		mode, args = strings.TrimPrefix(args[0], "--"), args[1:]
	}
	usageOK := (mode == "" && len(args) == 1) ||
		(mode == "batch" && len(args) == 1) ||
		(mode == "stream" && (len(args) == 3 || len(args) == 4))
	if !usageOK {
		fmt.Fprintln(os.Stderr, "usage: reactor-host MODULE.wasm\n"+
			"       reactor-host --batch MODULE.wasm\n"+
			"       reactor-host --stream MODULE.wasm FROM TO [CHUNK]")
		os.Exit(2)
	}
	wasm, err := os.ReadFile(args[0])
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

	h := &host{ctx: ctx, mod: mod}
	switch mode {
	case "batch":
		h.batch()
	case "stream":
		chunk := 4096
		if len(args) == 4 {
			if chunk, err = strconv.Atoi(args[3]); err != nil || chunk < 1 {
				fatal("bad chunk size %q", args[3])
			}
		}
		h.stream(args[1], args[2], chunk)
	default:
		if mod.ExportedFunction("_start") != nil {
			fatal("module exports _start; it is a command, not a reactor")
		}
		for _, name := range []string{"alloc", "free", "convert", "lookup",
			"base_radix", "base_zero", "symbol_count",
			"symbol_slice", "fit", "convert_fit",
			"last_error_code", "last_error_text", "version", "region_count",
			"stream_new", "stream_write", "stream_finish", "stream_free",
			"stream_count"} {
			if mod.ExportedFunction(name) == nil {
				fatal("export %q missing", name)
			}
		}
		h.run()
		fmt.Println("reactor-host: all checks passed")
	}
}

// batch answers module-driver protocol requests through the module's one-shot
// convert, one reply line per request line.
func (h *host) batch() {
	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 0, 1<<20), 1<<20)
	out := bufio.NewWriter(os.Stdout)
	for in.Scan() {
		line := in.Text()
		if line == "" {
			continue
		}
		f := strings.Split(line, "\t")
		if len(f) != 4 {
			fatal("batch: bad request line %q", line)
		}
		prec, err := strconv.ParseInt(f[2], 10, 32)
		if err != nil {
			fatal("batch: bad precision %q: %v", f[2], err)
		}
		value, err := hex.DecodeString(f[3])
		if err != nil {
			fatal("batch: bad value hex %q: %v", f[3], err)
		}
		res, code := h.convert(f[0], f[1], string(value), prec)
		if code != errNone {
			fmt.Fprintln(out, "err")
		} else {
			fmt.Fprintf(out, "ok\t%s\n", hex.EncodeToString([]byte(res)))
		}
	}
	if err := in.Err(); err != nil {
		fatal("batch: stdin: %v", err)
	}
	if err := out.Flush(); err != nil {
		fatal("batch: stdout: %v", err)
	}
}

// stream pipes stdin to stdout through the streaming ABI, in fixed chunks.
func (h *host) stream(from, to string, chunk int) {
	hd := h.streamNew(from, to)
	buf := make([]byte, chunk)
	out := bufio.NewWriter(os.Stdout)
	for {
		n, rerr := os.Stdin.Read(buf)
		if n > 0 {
			part, code := h.streamWrite(hd, buf[:n])
			if code != errNone {
				fatal("stream: %s", h.errText)
			}
			_, _ = out.WriteString(part)
		}
		if rerr != nil {
			if errors.Is(rerr, io.EOF) {
				break
			}
			fatal("stream: stdin: %v", rerr)
		}
	}
	tail, code := h.streamFinish(hd)
	if code != errNone {
		fatal("stream: %s", h.errText)
	}
	_, _ = out.WriteString(tail)
	h.streamFree(hd)
	if err := out.Flush(); err != nil {
		fatal("stream: stdout: %v", err)
	}
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

	// symbol_slice and fit, on single-byte digits and on the multi-byte 128tt
	// encoding from above, where a byte slice would cut a digit in half.
	for _, c := range []struct {
		base, s      string
		start, count int64
		want         string
	}{
		{"16", "ABCDEF", 0, 3, "ABC"},
		{"16", "ABCDEF", -3, -1, "DEF"},
		{"16", "ABCDEF", 4, 99, "EF"},
		{"128tt", enc, -2, -1, ""}, // filled in below: last two multi-byte symbols
	} {
		want := c.want
		if want == "" {
			one, code := h.symbolSlice(c.base, c.s, -2, 1)
			two, code2 := h.symbolSlice(c.base, c.s, -1, 1)
			if code != errNone || code2 != errNone {
				fatal("symbol_slice 128tt singles: codes %d %d", code, code2)
			}
			want = one + two
		}
		got, code := h.symbolSlice(c.base, c.s, c.start, c.count)
		if code != errNone || got != want {
			fatal("symbol_slice %s %q [%d,%d): got %q code %d, want %q", c.base, c.s, c.start, c.count, got, code, want)
		}
	}
	// A slice past the end is a legal empty result: packed length 0, code 0.
	if got, code := h.symbolSlice("16", "AB", 5, 3); code != errNone || got != "" {
		fatal("symbol_slice past end: got %q code %d, want empty success", got, code)
	}
	for _, c := range []struct {
		base, s string
		width   int64
		want    string
	}{
		{"16", "FF", 4, "00FF"},
		{"16", "ABCDEF", 4, "CDEF"},
		{"32w", "X", 4, "222X"}, // the zero symbol is "2", not "0"
	} {
		got, code := h.fit(c.base, c.s, c.width)
		if code != errNone || got != c.want {
			fatal("fit %s %q %d: got %q code %d, want %q", c.base, c.s, c.width, got, code, c.want)
		}
	}
	fitted, code := h.fit("128tt", enc, 3)
	directSlice, code2 := h.symbolSlice("128tt", enc, -3, -1)
	if code != errNone || code2 != errNone || fitted != directSlice {
		fatal("fit 128tt truncation disagrees with symbol_slice: %q vs %q", fitted, directSlice)
	}
	if got, code := h.fit("16", "12z", 4); code != errBadInput || got != "" {
		fatal("fit on bad digit: got %q code %d, want %d", got, code, errBadInput)
	}
	// A wild width has to come back as an error. Padding to it allocates that
	// many symbols, and running the module out of memory is not recoverable.
	if got, code := h.fit("16", "FF", 0xFFFFFFFF); code != errBadArg || got != "" {
		fatal("fit at maximum width: got %d bytes code %d, want %d", len(got), code, errBadArg)
	}
	if _, code := h.convertFit("10", "16", "255", 0xFFFFFFFF); code != errBadArg {
		fatal("convert_fit at maximum width: code %d, want %d", code, errBadArg)
	}
	// convert_fit equals convert then fit.
	if got, code := h.convertFit("10", "16", "255", 6); code != errNone || got != "0000FF" {
		fatal("convert_fit 255->16 width 6: got %q code %d", got, code)
	}
	if got, code := h.convertFit("16", "32w", "0", 5); code != errNone || got != "22222" {
		fatal("convert_fit 0->32w width 5: got %q code %d", got, code)
	}
	if _, code := h.convertFit("10", "16", "-255", 4); code != errBadInput {
		fatal("convert_fit on a signed value: code %d, want %d", code, errBadInput)
	}

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

	h.runStreams()
}

// runStreams drives the push-streaming half of the ABI: known vectors, chunk
// boundaries, agreement with one-shot convert, error paths, the leak counters,
// and a linear-memory ceiling that catches a stream quietly buffering.
func (h *host) runStreams() {
	// Known answers, written in awkward chunk sizes so partial groups cross
	// write boundaries. hex->64rfc runs the two-stage bytes route.
	for _, c := range []struct {
		from, to, in, want string
		chunk              int
	}{
		{"bytes", "64rfc", "Hello, world!", "SGVsbG8sIHdvcmxkIQ==", 5},
		{"64rfc", "bytes", "SGVsbG8sIHdvcmxkIQ==", "Hello, world!", 7},
		{"bytes", "16", "\x00\xff\x10", "00FF10", 1},
		{"16", "64rfc", "48656c6c6f", "SGVsbG8=", 3},
	} {
		got, code := h.streamRun(c.from, c.to, []byte(c.in), c.chunk)
		if code != errNone || got != c.want {
			fatal("stream %s->%s: got %q code %d, want %q", c.from, c.to, got, code, c.want)
		}
	}

	// Every plumbing shape must agree with the module's own one-shot convert:
	// the byte path, the wide tail path, the buffered codec fallback, and z85
	// with its alignment rule. 61 bytes lands partial groups everywhere.
	payload := make([]byte, 61)
	for i := range payload {
		payload[i] = byte(i*7 + 13)
	}
	for _, to := range []string{"64rfc", "32rfc", "8", "2048qntm", "65536qntm", "128tt", "ascii85", "45", "91"} {
		want, code := h.convert("bytes", to, string(payload), -1)
		if code != errNone {
			fatal("one-shot bytes->%s: code %d", to, code)
		}
		got, code := h.streamRun("bytes", to, payload, 7)
		if code != errNone || got != want {
			fatal("stream bytes->%s disagrees with one-shot: got %q code %d, want %q", to, got, code, want)
		}
		back, code := h.streamRun(to, "bytes", []byte(got), 11)
		if code != errNone || back != string(payload) {
			fatal("stream %s->bytes round-trip: code %d, %d bytes back", to, code, len(back))
		}
	}
	aligned := payload[:60]
	want, code := h.convert("bytes", "z85", string(aligned), -1)
	if code != errNone {
		fatal("one-shot bytes->z85: code %d", code)
	}
	if got, code := h.streamRun("bytes", "z85", aligned, 7); code != errNone || got != want {
		fatal("stream bytes->z85: got %q code %d, want %q", got, code, want)
	}

	// An empty stream is legal and empty; finish must report success.
	hd := h.streamNew("bytes", "64rfc")
	if out, code := h.streamFinish(hd); code != errNone || out != "" {
		fatal("empty stream finish: out %q code %d", out, code)
	}
	h.streamFree(hd)

	// Error paths. A base with no raw-byte mapping is refused at stream_new.
	args := h.str("bytes")
	args = append(args, h.str("10")...)
	if res := int64(h.call("stream_new", args...)); res != -errBadInput {
		fatal("stream_new to base 10: got %d, want %d", res, -errBadInput)
	} else if h.lastError() == "" {
		fatal("stream_new to base 10: no error text")
	}
	h.freeAll(args[0], args[2])

	// A bad digit fails the stream; the write or the finish reports it, and
	// afterward the stream is dead to writes but still frees.
	hd = h.streamNew("16", "bytes")
	_, wcode := h.streamWrite(hd, []byte("zz"))
	_, fcode := h.streamFinish(hd)
	if wcode != errBadInput && fcode != errBadInput {
		fatal("bad digit in stream: write code %d finish code %d, want %d in one", wcode, fcode, errBadInput)
	}
	if _, code := h.streamWrite(hd, []byte("00")); code != errBadArg {
		fatal("write after failed finish: code %d, want %d", code, errBadArg)
	}
	h.streamFree(hd)

	// Handle misuse: wild handle, double free, abandon without finish.
	h.call("stream_write", 99999, 0, 0)
	if code := h.calli32("last_error_code"); code != errBadArg {
		fatal("stream_write on wild handle: code %d, want %d", code, errBadArg)
	}
	if code := h.calli32("stream_free", 99999); code != errBadArg {
		fatal("stream_free on wild handle: code %d, want %d", code, errBadArg)
	}
	hd = h.streamNew("bytes", "64rfc")
	if _, code := h.streamWrite(hd, []byte("abc")); code != errNone {
		fatal("write before abandon: code %d", code)
	}
	h.streamFree(hd)
	if code := h.calli32("stream_free", uint64(hd)); code != errBadArg {
		fatal("double stream_free: code %d, want %d", code, errBadArg)
	}

	// Leak check: a work loop of whole streams leaves both counters at zero.
	for i := 0; i < 300; i++ {
		if _, code := h.streamRun("bytes", "64rfc", []byte(fmt.Sprint(1000000+i)), 3); code != errNone {
			fatal("stream loop %d: code %d", i, code)
		}
	}
	if n := h.call("stream_count"); n != 0 {
		fatal("stream_count %d after loop, want 0", n)
	}
	if n := h.call("region_count"); n != 0 {
		fatal("region_count %d after stream loop, want 0", n)
	}

	// Constant memory. Correctness cannot catch a stream that quietly buffers,
	// so the ceiling does: linear memory only ever grows, and streaming 24 MiB
	// through the byte path and 4 MiB through the wide path must not grow it
	// by anything near the payload size. Buffering would add input plus output.
	baseline := h.memSize()
	big := make([]byte, 24<<20)
	for i := range big {
		big[i] = byte(i*31 + 7)
	}
	if _, code := h.streamDrain("bytes", "64rfc", big, 64<<10); code != errNone {
		fatal("big byte-path stream: code %d", code)
	}
	if _, code := h.streamDrain("bytes", "2048qntm", big[:4<<20], 64<<10); code != errNone {
		fatal("big wide-path stream: code %d", code)
	}
	if grew := h.memSize() - baseline; grew > 16<<20 {
		fatal("streaming grew module memory by %d MiB; it is buffering", grew>>20)
	}
}

// streamNew opens a stream and fatals on refusal; refusal cases call the
// export directly.
func (h *host) streamNew(from, to string) uint32 {
	args := h.str(from)
	args = append(args, h.str(to)...)
	res := int64(h.call("stream_new", args...))
	if res <= 0 {
		fatal("stream_new %s->%s: %d (%s)", from, to, res, h.lastError())
	}
	h.freeAll(args[0], args[2])
	return uint32(res)
}

// streamWrite pushes one chunk and returns the drained output with the error
// code. The returned chunk is module-owned, so it is copied here, not freed.
func (h *host) streamWrite(hd uint32, data []byte) (string, int32) {
	args := []uint64{uint64(hd)}
	args = append(args, h.str(string(data))...)
	packed := h.call("stream_write", args...)
	code := h.calli32("last_error_code")
	if code != errNone {
		h.errText = h.lastError()
	}
	out := h.readPacked(packed)
	h.freeAll(args[1])
	return out, code
}

func (h *host) streamFinish(hd uint32) (string, int32) {
	packed := h.call("stream_finish", uint64(hd))
	code := h.calli32("last_error_code")
	if code != errNone {
		h.errText = h.lastError()
	}
	return h.readPacked(packed), code
}

func (h *host) streamFree(hd uint32) {
	if code := h.calli32("stream_free", uint64(hd)); code != errNone {
		fatal("stream_free %d: code %d (%s)", hd, code, h.lastError())
	}
}

// streamRun pushes a whole payload through one stream in fixed chunks and
// returns the collected output.
func (h *host) streamRun(from, to string, payload []byte, chunk int) (string, int32) {
	hd := h.streamNew(from, to)
	var out []byte
	for off := 0; off < len(payload); off += chunk {
		end := min(off+chunk, len(payload))
		part, code := h.streamWrite(hd, payload[off:end])
		if code != errNone {
			h.streamFree(hd)
			return "", code
		}
		out = append(out, part...)
	}
	tail, code := h.streamFinish(hd)
	if code != errNone {
		h.streamFree(hd)
		return "", code
	}
	out = append(out, tail...)
	h.streamFree(hd)
	return string(out), errNone
}

// streamDrain is streamRun without keeping the output, for the big payloads
// the memory ceiling pushes through; holding their output host-side is fine,
// but pointless allocation.
func (h *host) streamDrain(from, to string, payload []byte, chunk int) (int, int32) {
	hd := h.streamNew(from, to)
	total := 0
	for off := 0; off < len(payload); off += chunk {
		end := min(off+chunk, len(payload))
		part, code := h.streamWrite(hd, payload[off:end])
		if code != errNone {
			h.streamFree(hd)
			return 0, code
		}
		total += len(part)
	}
	tail, code := h.streamFinish(hd)
	if code != errNone {
		h.streamFree(hd)
		return 0, code
	}
	total += len(tail)
	h.streamFree(hd)
	return total, errNone
}

func (h *host) memSize() uint64 { return uint64(h.mod.Memory().Size()) }

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

// symbolSlice runs one symbol_slice call, freeing what it allocates.
func (h *host) symbolSlice(base, s string, start, count int64) (string, int32) {
	args := h.str(base)
	args = append(args, h.str(s)...)
	args = append(args, api.EncodeI32(int32(start)), api.EncodeI32(int32(count)))
	packed := h.call("symbol_slice", args...)
	code := h.calli32("last_error_code")
	out := ""
	if packed != 0 {
		out = h.readPackedFree(packed)
	}
	h.freeAll(args[0], args[2])
	return out, code
}

// fit runs one fit call, freeing what it allocates.
func (h *host) fit(base, s string, width int64) (string, int32) {
	args := h.str(base)
	args = append(args, h.str(s)...)
	args = append(args, uint64(width))
	packed := h.call("fit", args...)
	code := h.calli32("last_error_code")
	out := ""
	if packed != 0 {
		out = h.readPackedFree(packed)
	}
	h.freeAll(args[0], args[2])
	return out, code
}

// convertFit runs one convert_fit call, freeing what it allocates.
func (h *host) convertFit(from, to, value string, width int64) (string, int32) {
	args := h.str(from)
	args = append(args, h.str(to)...)
	args = append(args, h.str(value)...)
	args = append(args, uint64(width))
	packed := h.call("convert_fit", args...)
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
