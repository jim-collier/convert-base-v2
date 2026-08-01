<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Design 20260801: Native C bindings

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Status](#status)
- [Introduction](#introduction)
- [What exists now](#what-exists-now)
- [End goals](#end-goals)
- [What a C binding actually promises](#what-a-c-binding-actually-promises)
- [The surface](#the-surface)
- [Streaming across the boundary](#streaming-across-the-boundary)
- [Costs](#costs)
- [Comparison with the alternatives](#comparison-with-the-alternatives)
- [What Python would actually do](#what-python-would-actually-do)
- [When this becomes worth building](#when-this-becomes-worth-building)
- [Licensing](#licensing)

<!-- /TOC -->

## Status

Not built, and not currently planned. Kept as a live document because the question comes up, and because the Go split was checked to make sure it does not block this later.

Split out of `20260731_linkable_library.md`, which planned a C library first and then set it aside once WebAssembly was built. This document holds the reasoning so it does not have to be worked out again.

## Introduction

A native C binding means a shared library and a header. A caller writes `#include`, links against a `.so`, `.dylib` or `.dll`, and calls a function. Nothing else is needed at runtime.

That is the most direct way for a non-Go program to use this in process. It is also the most expensive to build and the hardest to change afterwards.

## What exists now

Nothing. There is no C code, no cgo, and no C surface anywhere in the tree.

- No file imports `"C"`, and no function is marked `//export`.

- Release builds set `CGO_ENABLED=0` and are fully static. The packaging script states that nothing it produces bundles a runtime.

- Cross-compilation currently works for every target with no C toolchain at all, which is why the builds are simple.

None of that is accidental, and a C binding would change all three for the artifacts it applies to.

## End goals

If this were built, it would aim for:

- A caller in C, Python, Rust, or anything with a foreign function interface can convert in process, with no subprocess and no WebAssembly runtime.

- Streaming is available, and stays constant memory.

- The command and the Go library keep every property they have now, including static builds with no cgo.

The last point is what keeps this from being a small change. The C artifacts need `CGO_ENABLED=1`, so they are a separate build from everything else that ships.

## What a C binding actually promises

This is worth stating plainly, because "wrap it in a C binding" is sometimes used loosely to mean any way of calling from C.

- A C binding means a header and a library file. The caller links it. There is no runtime to install, no module to load, and no extra process.

- Calling a `.wasm` from C is a different thing. The caller embeds a WebAssembly runtime, and that runtime's C API is the binding. The module is the payload, not the interface. That option is covered in `20260801_wasm_reactor.md`.

Both are legitimate. They are not the same promise, and a README should not describe one as the other.

## The surface

Sketched only, to confirm the Go split does not paint this into a corner. Roughly a dozen entry points:

- Registry create, load config, free.

- Base lookup, returning an opaque handle.

- An options struct, matching the library's `Options`.

- One-shot convert, and a matching free for what it returns.

- Stream convert.

- Last error.

Rules that would apply throughout:

- Strings cross as UTF-8 byte pointers with explicit lengths. Not null-terminated, because digits can contain any byte.

- Everything the library allocates is freed by a function the library provides. The caller never frees Go memory itself.

- No Go pointer is ever handed to C to hold. A `runtime/cgo.Handle` carries the reference instead.

`Registry.Print` would not be part of this. Formatting a table is presentation, and a C caller can format its own.

## Streaming across the boundary

An early read of this said streaming could not survive a C ABI. That was wrong, and the correction is why this is deferred rather than ruled out.

The internal entry point is already the right shape:

```go
func streamConvert(r io.Reader, w io.Writer, from, to *Base) (bool, error)
```

Three ways to reach it, in increasing order of work:

| Route | How it works | Pros | Cons
|---|---|---
| File descriptors | `os.NewFile` turns a descriptor into a reader or writer, handed straight to the existing function | No refactor. Identical code path, identical memory profile, no added copies. | Windows takes a handle instead, so that is one platform branch.
| Callbacks | The caller supplies read and write function pointers, wrapped in types satisfying the two interfaces | The most portable, and the most natural to a C programmer. | One crossing per chunk. At sixty-four kilobytes that is not measurable.
| Push | A `new`, `write`, `finish` trio, the shape zlib uses | Suits callers that handle neither descriptors nor callbacks comfortably. | Holds state between calls, so the caller has to free it.

The push form would be implemented by running the existing loop in a goroutine behind an `io.Pipe`. That pattern is already in the codebase, in `streamBytesRoute`.

What genuinely gets harder is reporting an error after output has already been partly written, and cancellation. Both are ordinary problems with ordinary answers.

## Costs

These are the reasons this has not been built:

- `CGO_ENABLED=1` for the C artifacts, which the rest of the project does not use.

- A C toolchain for every cross target. Today there is none, and cross builds are simple because of it.

- A copy of the Go runtime inside each `.so`, so the artifacts are large and there is one per platform and architecture.

- An interface that cannot be changed once somebody ships against it. The Go library is at v0 and can still be reshaped. A C ABI has no such freedom.

- Packaging. For Python that means manylinux wheels, macOS on two architectures, and Windows. That work is larger than the binding itself.

## Comparison with the alternatives

| | Subprocess | WebAssembly reactor | Native C library
|---|---|---|---
| Exists today | Yes | No | No
| Caller needs | Ability to start a process | A WebAssembly runtime | Nothing at runtime
| Artifacts to build | None, the binary already ships | One, runs everywhere | One per platform and architecture
| Interface can change later | Yes, it is a command line | Yes, while unversioned | No, once shipped
| Speed | Process startup per call | Slower than native, not yet measured | Native
| Streaming | Free, through pipes | Has to be designed | Has to be designed

For a caller that can start a process, the subprocess route is the simplest and always was. Pipes stream natively, and the cost is one process per call. For a tool built around streaming that is a real answer, not a consolation prize.

## What Python would actually do

Python is the most likely non-Go caller, so it is worth being concrete.

- With a C library, it would use `ctypes` or `cffi`. The descriptor form suits it well, because `os.pipe` and `fileno` are readily available.

- With a WebAssembly reactor, it would use a runtime binding, and handle memory through the module's allocator.

- With the existing binary, it would use `subprocess`, and get streaming for free.

The work in the first case is not the binding. It is the wheels.

## When this becomes worth building

The case for this is in-process native speed. That is the one thing neither of the alternatives offers.

So it is worth building when someone needs conversion inside a hot path, in a language that is not Go, at a volume where process startup or WebAssembly overhead actually shows up in a measurement.

Until then the other two routes cover the same languages at a fraction of the cost. Nothing in the Go split forecloses this, which was checked at the time and is the reason it can wait.

## Licensing

A C library would wrap the library, not the command, so it would be Apache-2.0.

That is what makes it usable by a proprietary caller, and it is the same reasoning that applies to the Go package and the browser module. The full argument is in `20260731_linkable_library.md`.
