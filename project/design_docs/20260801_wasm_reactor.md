<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Design 20260801: WebAssembly, and a callable reactor module

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Status](#status)
- [Introduction](#introduction)
- [What exists now](#what-exists-now)
- [What is missing](#what-is-missing)
- [End goals](#end-goals)
- [The first consumer: zuid](#the-first-consumer-zuid)
- [What a reactor module is](#what-a-reactor-module-is)
- [What was verified](#what-was-verified)
- [Passing data across the boundary](#passing-data-across-the-boundary)
- [Streaming options](#streaming-options)
- [Where the code would live](#where-the-code-would-live)
- [Costs and benefits](#costs-and-benefits)
- [Licensing](#licensing)
- [Touch points](#touch-points)
- [Testing](#testing)

<!-- /TOC -->

## Status

The one-shot surface shipped: `make reactor` builds `dist/convert-base-reactor.wasm` from `lib/reactor/`, covering everything zuid asked for - conversion, lookup, radix and padding-symbol metadata, symbol counting, the allocator pair, the numeric error codes, and the last-error text accessor. The contract lives in `lib/reactor/README.md`, and a host-side exerciser under `cicd/utility/reactor-host/` drives all of it each test run.

Streaming shipped as well, in the push shape proposed below: `stream_new`/`stream_write`/`stream_finish`/`stream_free`, plus a `stream_count` leak counter. The streams feed the library's own streaming code through an in-module pipe, so the constant-memory paths are the same ones the command uses; pairs the library cannot stream (the codecs) buffer internally and emit at finish, matching the command's behavior for the same conversions. The exerciser holds the streams to the one-shot results, drives the error and abandon paths, and asserts a linear-memory ceiling over a payload large enough that quiet buffering would blow it. This closes the design.

One practical note from the build-out: linters do not yet treat `//go:wasmexport` as a root, so every export reads as unused code under a `wasip1` lint run. The reactor package stays out of lint scope the way the vendored parser does; vet runs on it cross-compiled and comes back clean.

Split out of `20260731_linkable_library.md`, which treated WebAssembly as the replacement for a C library. That conclusion still holds for reach. It skipped one thing: neither build that exists is callable as a library from another program.

## Introduction

WebAssembly is how this project reaches languages other than Go without writing a binding for each one. Most languages have a WebAssembly runtime, so one artifact serves all of them.

The catch is that "runs under WebAssembly" and "can be called as a library" are different things. The builds that exist are programs. A caller runs them. A caller cannot call a function in them.

## What exists now

- `make wasm` builds the whole command for `GOOS=wasip1`, into `dist/convert-base-v2.wasm`.
	- WASI hands it real standard input and output, so streaming works with no adapter.
	- It runs under Wasmtime, Wazero, Node, and the WebAssembly edge platforms.
	- One file runs on every architecture.
	- It is the command, so it is GPL.

- `make web` builds a browser module from `lib/wasm/`, into `web/convert-base.wasm`, plus the loader Go requires.
	- It exposes `convertBase.convert()`, `convertBase.bases()` and `convertBase.version` on `window`.
	- It returns a result object rather than throwing, because a bad base name is ordinary input on a page.
	- `main` must not return, or the callbacks are torn down. That is what the `select {}` is for.
	- It is Apache-2.0, like the library, because it compiles into someone else's page.

- Both artifacts are gitignored and rebuilt by `.github/workflows/pages.yml`, which publishes `web/` to GitHub Pages.

## What is missing

Neither build is a library.

- The WASI build has a `main` that parses argv and reads stdin. Embedding it in another program means setting up argv and pipes, running `_start`, and reading the output back. That is running a program in process, not calling a function. It also does not survive being run twice in the same instance.

- The browser module only exists for JavaScript on a page. It uses `syscall/js`, which has no meaning outside a browser.

So a C, Python, or Rust program that wants in-process conversion has no WebAssembly answer today, only the option of running the command.

## End goals

- One WebAssembly artifact that any host language can load and call directly.

- Conversion available as a function call, not as a process run.

- Streaming available, not just one-shot conversion.

- No change to the command, the library, or the existing two builds.

- No new dependencies, and no rise in the `go.mod` floor.

## The first consumer: zuid

zuid is a sibling project that generates sortable identifiers. Its Go half imports `convertbase` directly and already passes against the shared test vectors with no changes to the package. Its Zig half wants to reach the same conversions through this reactor module, hosted by Wasmtime, and is blocked until the module exists. Its requirements arrived 20260802 and are recorded here so the first cut can be scoped against a real caller.

What zuid needs is small, and streaming is not part of it. Its input is a millisecond timestamp, around thirteen decimal digits. The one-shot surface alone fully unblocks it, which fits the phasing here anyway: the push API stays the right long-term answer, and can follow separately.

The acceptance bar is parity with the four calls zuid already makes natively:

- Registry setup, once. This can happen inside `_initialize` and never be exposed.
- Name lookup, to validate a base name or alias.
- One-shot convert: decimal string in, target base out, automatic precision.
- Symbol count of a converted string, what `Tokenize` gives a native caller.

Plus two pieces of base metadata, and these are load-bearing rather than cosmetic. zuid pads identifiers to a fixed width so they sort chronologically as plain text, so it needs the base's radix, and its zero symbol (the first in the alphabet) to pad with. The padding symbol must come from the library: for the word-safe base 32 the alphabet starts at `2`, so anything that assumes `0` is silently wrong. And padding has to count symbols, not bytes, because a chosen base may have multi-byte digits.

Two asks on errors, both reasonable and both cheap once the surface exists:

- A stable, documented numeric error code set, since the host has to map codes to its own handling and codes that shift between versions would break it.
- A way to read the error text, something like a last-error accessor returning a pointer and length. The library's messages carry near-match suggestions for a mistyped base name, and a host should not have to throw that away.

The error text work elsewhere in the module design pays off here: the library's messages are now stated neutrally, so the text a host reads never mentions command-line flags.

zuid suggested an export shape (per-call functions for radix, padding symbol and symbol count, or one call returning a small serialized blob) but is explicit that the ABI is this project's call. Priority order from their side: one-shot convert plus the allocator pair, then base metadata, then the error codes and message accessor, then streaming whenever it suits.

## What a reactor module is

WebAssembly modules come in two shapes:

| Shape | Entry point | Behavior
|---|---|---
| Command | `_start` | Runs once, top to bottom, then exits. This is what both current builds are.
| Reactor | `_initialize` | Initializes, then stays alive. The host calls exported functions as many times as it wants.

A reactor is the shape a library needs. Go builds one with `-buildmode=c-shared` for `GOOS=wasip1`, and marks the functions to expose with `//go:wasmexport`.

The name `c-shared` is misleading here. It does not produce a C library and there is no C involved. It is the flag Go reuses to mean "build a reactor, not a command".

## What was verified

These were checked by building, not assumed:

- A `wasip1` reactor with `//go:wasmexport` functions builds with the installed toolchain.

- The exported names really appear in the module's export section, alongside `_initialize` and `memory`. The export section was parsed directly, because the function names also appear in the debug section and would look present either way.

- `_start` is not exported. The module is a reactor, not a command.

- The build works with `go 1.21` in `go.mod`. The directive is a language version, and it does not gate this.
	- The **toolchain** doing the build has to be 1.24 or newer, because that is when `//go:wasmexport` and `wasip1` reactor support landed.
	- This matters, because the low `go.mod` floor was kept on purpose for distro packagers. Adding this target does not raise it. Only whoever builds this particular artifact needs the newer toolchain, and that is a release-time concern, not a build-from-source concern.

- `//go:wasmexport` rejects `string` as a parameter or result type. The compiler says so directly.

## Passing data across the boundary

Only numeric types and pointers can cross a `wasmexport` boundary. Strings and slices cannot.

So data crosses as a pointer into the module's linear memory, plus a length. The pattern is:

- The module exports an allocator. The host calls it to get a region inside the module's memory.

- The host writes the input bytes into that region, through the exported `memory`.

- The host calls the conversion function with the pointer and the length.

- The function returns a pointer and length for the result, or an error code.

- The host reads the result out of memory, then calls an exported free.

One detail needs care. Go has a garbage collector, so a region handed to the host must be kept reachable from Go, or it can be collected while the host still holds the pointer. The usual fix is a map from pointer to the backing slice, cleared by the free function. That map is also what makes double-free detectable.

## Streaming options

Streaming is half of why this library is worth having, so the reactor should not drop it.

The three routes sketched for a C boundary in `20260731_linkable_library.md` all have a WebAssembly form:

| Route | How it works here | Pros | Cons
|---|---|---
| Push API | `stream_new`, `stream_write`, `stream_finish`, over linear memory | No host imports needed. Works in every runtime the same way. Matches how zlib is used, so it is familiar. | The module holds state between calls, so the host has to free it.
| File descriptors | Host preopens a descriptor, module wraps it with `os.NewFile` | Reuses the existing streaming function unchanged. | Only works on hosts that grant WASI descriptors. Not available on a page.
| Host callbacks | Module imports `read` and `write` functions from the host | Natural for a host that already has its own I/O. | The host must supply imports at instantiation, which complicates loading and differs per runtime.

The push API is the best fit. It needs nothing from the host beyond memory, so a caller can load the module and use it with no setup. The other two can be added later without breaking it.

Note that the existing push pattern is already in the codebase. `streamBytesRoute` joins two conversion stages through an `io.Pipe`, which is the same shape.

## Where the code would live

A new package under `lib/`, built only for `wasip1` and only when asked.

- It needs a build tag so a native `./...` never sees it, the same way `lib/wasm/` is tagged `js && wasm` today.

- It can stay in the same module. Nothing forces a separate one, since the `go.mod` floor does not have to move.

- It should be a thin adapter over `convertbase`, the same as the browser module is. No conversion logic belongs in it.

- The browser module and the reactor do similar jobs for different hosts. If they start to duplicate argument handling, that shared part can move to a small internal package. It is not worth doing before there is duplication to remove.

## Costs and benefits

Against the WASI command build that already exists:

| | WASI command (exists) | Reactor library (proposed)
|---|---|---
| How the host uses it | Sets up argv and pipes, runs it | Calls a function
| Repeat calls | New instance each time | Same instance, many calls
| Streaming | Free, through real stdin and stdout | Has to be designed, see above
| Host work to adopt | Low, if the host can already run a WASI program | Moderate, memory handling and a small protocol
| License | GPL, it is the command | Apache-2.0, it would wrap the library
| Exists today | Yes | No

Against a native C library, which is covered in `20260801_c_bindings.md`:

- The reactor needs no cgo, no C toolchain per target, and no per-platform artifact. One file runs everywhere.

- The reactor costs the host a WebAssembly runtime, which is measured in megabytes. A native library costs the host nothing at runtime.

- The reactor runs slower than native. For a tool whose number path is already O(N^2), that gap matters more on large inputs than on small ones, and has not been measured.

## Licensing

The reactor would wrap the library, not the command, so it would be Apache-2.0. That is the same reasoning as the browser module. A caller compiles it into their own program, and GPL there would defeat the point of publishing it.

The WASI command build stays GPL. That split already exists and does not change.

## Touch points

- `lib/wasmlib/` or similar - new package, build-tagged for `wasip1`.

- `lib/Makefile` - a new target next to `wasm` and `web`.

- `cicd/tool-versions.env` - the toolchain floor for this target is 1.24, and the pipeline should say so rather than fail with a confusing error on an older Go.

- `README.md` - what is available and how to load it.

- Any statement that the project ships a C binding is wrong, and should say WebAssembly instead.

## Testing

- A host-side test that loads the module and drives it. Go can be that host, using a runtime library, which keeps the test in the same language as the rest.

- The same round-trip checks the harness already runs, driven through the module instead of the binary, so the reactor is held to the same output as the command.

- A memory test. Allocate, convert, free, repeated enough times to show nothing leaks and the pointer map empties.

- Streaming needs a constant-memory check, the same as the native paths get. A stream that quietly buffers still produces correct output, so correctness tests alone would not catch it.
