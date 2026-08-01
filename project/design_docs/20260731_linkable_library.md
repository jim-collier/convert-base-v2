<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Design 20260731: Using convert-base-v2 from other programs

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Status](#status)
- [Introduction](#introduction)
- [The licensing question](#the-licensing-question)
- [Requirements](#requirements)
- [Constraints](#constraints)
- [High-level solution](#high-level-solution)
	- [Two audiences, two mechanisms](#two-audiences-two-mechanisms)
	- [Streaming across a C boundary](#streaming-across-a-c-boundary)
	- [What Python would actually do](#what-python-would-actually-do)
- [What the library is not](#what-the-library-is-not)
- [Detailed solution](#detailed-solution)
	- [1. The module path and its version](#1-the-module-path-and-its-version)
	- [2. Package layout](#2-package-layout)
	- [3. The exported surface](#3-the-exported-surface)
	- [4. Base options](#4-base-options)
	- [5. WebAssembly instead of a C ABI](#5-webassembly-instead-of-a-c-abi)
	- [6. The C surface, if ever](#6-the-c-surface-if-ever)
- [Touch points](#touch-points)
- [Testing](#testing)
- [Compatibility](#compatibility)
- [Outcome](#outcome)
- [Package name](#package-name)

<!-- /TOC -->

## Status

Implemented. Closed 20260801. See [Outcome](#outcome).

Scope note: this document covered three separate things at once, because they were decided together. Each now has its own document, and ongoing work belongs there rather than here:

- `20260801_go_module.md` - the Go module.
- `20260801_wasm_reactor.md` - the WebAssembly builds, and a callable reactor module that does not exist yet.
- `20260801_c_bindings.md` - the native C shared library, still not built.

This document stays as the record of the original decision, including the licensing argument, which the three refer back to rather than repeat.

One thing here was later found to be wrong, and is corrected in the WebAssembly document rather than edited out of the reasoning below. Setting the C library aside in favor of WebAssembly was right for reach, but neither WebAssembly build is callable as a library. Both are programs. A third build shape, a reactor, is what would close that gap.

The Go package split is done, on branch `lib`. So is a pair of WebAssembly builds, which were not part of the original plan and which changed the conclusion about the C shared library.

The licensing question below is settled: the library is Apache-2.0, the command stays GPL-2.0-or-later.

Two things in this document were overtaken by later decisions, and are corrected in place below rather than left to mislead. The module lives at `lib/`, not `source/`, and carries its own version starting at v0.1.0. And the C shared library is no longer the answer for callers outside Go - WebAssembly is, at a fraction of the cost.

## Introduction

Everything this project does is reachable only by running the program. That is fine for a shell, and useless inside another program. A caller who wants base conversion in process today has to shell out, or reimplement.

Reimplementing is not cheap here. Sixty-odd bases, the tail schemes for the big ones, the marker tri-state, and constant-memory streaming for every base that can carry raw bytes are not.

There are two separate things that could be published, and they are worth keeping separate because they have very different costs.

## The licensing question

This is the first decision, and it is not a technical one.

The project is GPL-2.0-or-later. Applied to a library, that reaches through the link into the calling program: anything that links this, statically or dynamically, has to be GPL-compatible. Go makes it sharper, because Go links statically and has no dynamic option at all. So a Go package published as it stands can only be imported by GPL programs.

Some solutions:

| Option | Effect | Cost
|---|---|---
| Keep GPL-2.0-or-later | Free-software callers only. Proprietary callers blocked. | None but smallest audience.
| Apache-2.0 on the library package | Anyone can link it. Attribution propagates through a NOTICE file. | Long text. Gives up reciprocity.
| MIT or BSD-3 clause on the library package | Anyone can link it, minimal ceremony. | Weaker attribution. Nothing carries a credit into a binary distribution.
| MPL-2.0 on the library package | Changes to these files stay open. The calling program is unaffected. | Middle ground, less familiar. Aimed at reciprocity, not credit.
| LGPL | The classic library answer. | Poor fit. Static-only Go linking makes it awkward.

Solution: Two-license split, which is a common arrangement. The command stays GPL-2.0-or-later. The library is Apache-2.0.

The goal here is attribution and exposure, rather than getting changes back. That rules out MPL, whose mechanism is file-level reciprocity and credit requirement is incidental. Among the permissive licenses, Apache-2.0 is the one that actually enforces attribution: section 4 requires a derivative distribution to carry a readable copy of the NOTICE file, so the credit follows the code into someone else's product rather than stopping at a license file nobody opens. It also brings an explicit patent grant and a trademark clause, neither of which MIT or BSD has.

Two consequences:

- Apache-2.0 is incompatible with GPLv2 but compatible with GPLv3. The CLI is GPL-2.0-**or-later**, so a redistributor of the combined binary can elect GPLv3 and the combination is fine. Had the command been GPL-2.0-only this split would not have worked.

- The shipped packages are unchanged and still declare GPL, which is right. They carry the CLI, and the same person holds the copyright on both halves, so combining them creates no obligation to anyone. The Apache text and its notice travel with the source, which is where a linker will look for them.

The vendored SHCL file is MIT, which is compatible with all of the above.

Nothing about the code changes based on this, beyond the per-file license headers. It changes what the README can promise.

## Requirements

- A Go program can add this as a dependency and convert without shelling out.

- Streaming is available to callers, not just one-shot conversion, and stays constant memory.

- The command-line tool keeps every property it has now: one static binary, no cgo, cross-compiles to every current target.

- The library never writes to a stream it does not own, and never touches the caller's filesystem on its own initiative.

- The public surface is small enough to keep stable under semantic versioning.

## Constraints

- The module currently cannot be fetched at all, so this starts with a path fix rather than an API.

- A third package in the module sharpens an existing trap: `go build -o` and `go test -fuzz` reject multiple packages, so every such call has to name one. This already bit once when SHCL was vendored.

- The public API becomes a contract. Base names have been renamed freely until now, most recently a week ago. That freedom ends for anything the library exposes.

- No new dependencies. Standard library plus own source is a property worth keeping.

## High-level solution

### Two audiences, two mechanisms

Go callers get a normal package, imported like any other. This is cheap, and it is the whole job for that audience. Nothing about the shipped binary changes.

Everyone else was going to go through a C ABI, built with `-buildmode=c-shared` or `-buildmode=c-archive`. The costs were never symmetric: the Go package costs a refactor, while the C library costs `CGO_ENABLED=1` for those artifacts, a C toolchain for every cross target, a Go runtime embedded in each `.so`, and an interface that can never be changed once someone ships against it.

WebAssembly turned out to reach the same audience for almost none of that, which is why it was built and the C library was not. See [WebAssembly instead of a C ABI](#5-webassembly-instead-of-a-c-abi).

### Streaming across a C boundary

An earlier read of this said streaming would not survive a C ABI. That was wrong, and it matters, because streaming is half of why the library is worth having.

The internal entry point is already the right shape:

```go
func streamConvert(r io.Reader, w io.Writer, from, to *Base) (bool, error)
```

Three ways to reach that from C, in increasing order of work:

- **File descriptors.** `os.NewFile` turns a descriptor into a reader or a writer, handed straight to the existing function. No refactor, identical code path, identical memory profile, no added copies. The caller passes a pipe, a file, or a socket. Windows takes a handle instead, so that is one platform branch.
- **Callbacks.** The caller supplies read and write function pointers, which get wrapped in types satisfying the two interfaces. The most portable option and the most natural to a C programmer. It costs one crossing per chunk, which at sixty-four kilobytes is not measurable. The caller's context pointer rides across as a `runtime/cgo.Handle`, which is how you avoid handing Go a C pointer to keep.
- **Push.** A `new`, `write`, `finish` trio, the shape zlib uses, for callers that handle neither descriptors nor callbacks comfortably. Implemented by running the existing loop in a goroutine behind an `io.Pipe`. That pattern is already in the codebase, in `streamBytesRoute`, which joins two stages exactly that way.

What genuinely gets harder is error reporting once output has already been partly written, and cancellation. Both are ordinary problems with ordinary answers.

### What Python would actually do

Python is the most likely non-Go caller. It would use `ctypes` or, better, `cffi` against the shared library, and the descriptor form suits it well, since `os.pipe` and `fileno` are readily available.

The work is not the binding. It is the wheels: manylinux, macOS on both architectures, and Windows.

Set against that, `subprocess` against the existing binary deserves an honest hearing. Pipes stream natively, the cost is one process per call, and the packaging burden is nothing beyond the binary that already ships. For a tool built around streaming, that is a real answer and not a consolation prize. It is a reason the C library can wait.

## What the library is not

Most of the program is command-line interface, and none of it belongs in a library. Left behind:

- The whole flag layer, and help, examples, copyright, and version output.
- Every message written to standard error. There are ten, all in `main.go`, which is a good sign the core is already clean. A library returns an error; it does not narrate.
- `ensureUserConfig`. A library must not create files in the caller's home directory. This stays in the tool.
- Near-match name suggestion, the compatibility listing, and index addressing. All ergonomics for a person at a prompt.
- Case forcing. The caller's own language does that better, and it defeats streaming anyway.

`Registry.Print` is the one judgment call. Formatting a table is presentation and does not belong here, but it reads unexported fields, so moving it means widening the surface to let the tool do the same thing from outside. It stays in the library for now, as a convenience a Go caller may reasonably want. It should not be part of the C interface.

## Detailed solution

### 1. The module path and its version

`go.mod` sat in `source/` but declared `github.com/jim-collier/convert-base-v2`, the repository root. The path has to match the directory, so nothing could fetch this at all.

It becomes `github.com/jim-collier/convert-base-v2/lib`, and the directory is renamed to match. `source` was rejected as generic, `go` as wrong once there are non-Go artifacts, and `module` as Go jargon that also misdescribes a directory holding several packages.

A `bindings/go` and `bindings/wasm` arrangement was considered and rejected. Go is not a binding here, it is the implementation, and the `.wasm` is compiled from that same source rather than being a sibling of it. Putting them side by side would advertise two source trees where there is one. If a hand-written C or Python binding ever exists, `bindings/` becomes right that day.

The version is the hard part. Go adds a module's major version into its import path above v1, so a library tagged v2.1.0 would have to be imported as `.../lib/v2/convertbase`. Sharing the command's number would then mean a future convert-base-v3 rewrote the import path, breaking every caller's code over a change that never touched the package.

So the package carries its own version, `convertbase.Version`, starting at v0.1.0. v0 promises nothing about compatibility, which is the signal for an API published for the first time, and leaves room to reshape it. Tags are directory-prefixed, `lib/v0.1.0`, and the release workflow pushes one only when it is absent, so a command-only release is a no-op for the module.

Keeping the module in a subdirectory is what makes that possible. A root `go.mod` is versioned by the repository's bare tags, so it would be permanently pinned to the command's number. The subdirectory is the feature.

The trailing `-v2` in the repository name is safe either way. Go only treats a final path element of exactly `v2` as a major-version marker.

### 2. Package layout

```
lib/
	convertbase/               the library
	cmd/convert-base-v2/       package main, the CLI
	wasm/                      package main, the browser entry point
	shcl/                      vendored, unchanged
web/                           the demo page
```

`convert.go`, `registry.go`, `bases.go`, `symbolspec.go`, and the config reader move into `convertbase`. `main.go` and `userconfig.go` move down into `cmd/`, and import it.

The package name is open to a better one. `convertbase` reads acceptably at a call site, as `convertbase.Convert`.

### 3. The exported surface

Nine unexported identifiers currently cross the line from the core files into `main.go`. Their disposition:

| Identifier | Disposition
|---|---
| `streamConvert`, `streamBytesRoute` | Export. These are the streaming API.
| `finalize` | Export as a method. A caller building a base by hand has to complete it.
| `orderedBases` | Export as an ordered listing. Enumeration is legitimate; formatting is not.
| `powerOfTwoBits` | Export. Callers need it for the same reason the tool does.
| `resolveBase`, `applyMarkers` | Move to the library, reshaped. See below.
| `strPtr` | Stays a private helper on both sides. Too small to export.
| `ensureUserConfig`, `legacyConfigPath` | Stay in the CLI.

One more turned up during the split. The tool reached into two unexported fields to ask whether a newline is a digit of the input base, which is how it tells a terminator from data. That is a fair question for any caller to ask, so it became `Base.HasByteDigit`.

### 4. Base options

`resolveBase` and `applyMarkers` look like command-line plumbing but are not. They are how a caller says "base sixteen, but the negative marker is a tilde", which is a thing any caller might want.

What is command-line specific is `sideFlags` and `optString`, which exist to satisfy the `flag` package. The split is:

- The library gets a plain options struct, tri-state `*string` fields as they already are, and a function that applies it to a base.
- The tool keeps its flag types, which populate that struct.

There is an ordering trap here that has already bitten once, and it has to survive the move. For a custom alphabet the markers must be set before the first `finalize`, or the default `-` collides with a digit. Named bases go the other way: copy, override, then finalize again. Whatever the library exposes has to make that hard to get wrong, or document it loudly.

### 5. WebAssembly instead of a C ABI

Two builds for different purposes.

`GOOS=wasip1` builds the whole command. WASI hands it real standard input and output, so streaming works with no adapter at all - none of the three workarounds sketched for the C boundary are needed, because the boundary simply is not there. It runs under Wasmtime, Wazero, Node, and the WebAssembly edge platforms, and one file runs on every architecture.

`GOOS=js` builds a small entry point in `lib/wasm/` that exposes the library to a page as `convertBase.convert()` and `convertBase.bases()`. It returns a result object rather than throwing, because a bad base name is ordinary input in that setting.

Licensing differs between them on purpose. The WASI build is the command, so it stays GPL. The browser module compiles into somebody else's page, so it is Apache-2.0 like the library it wraps; GPL there would defeat the point of publishing it.

This is why the C library is no longer planned. It reaches the same languages, but a `.wasm` needs no permanent ABI, no cgo, no C toolchain per target, and no per-platform artifact. What C still offers is in-process native speed, so the C surface waits for someone who specifically needs that, rather than for anyone who merely wants to call this from Python.

For a caller that can start a process, shelling out remains the simplest option and always did. The library and the WebAssembly builds are for callers that can't.

### 6. The C surface, if ever

Sketched only, to check that the Go split does not paint it into a corner. Roughly a dozen entry points: registry create, load config, free; base lookup returning an opaque handle; an options struct; one-shot convert with a matching free; stream convert; and last error. Strings cross as UTF-8 byte pointers with explicit lengths, and everything the library allocates is freed by a function the library provides.

Nothing in the Go split forecloses this.

## Touch points

- `lib/go.mod` - module path, and the directory rename from `source/`.

- `lib/*.go` - the package split, and the one SHCL import path.

- `lib/convertbase/` - new, including `version.go`.

- `lib/wasm/`, `web/` - new.

- `Makefile`, `cicd/utility/package.bash`, the cicd fuzz and profiler steps, and every workflow - each `go build -o` and `go test -fuzz` has to name a single package, and every path that said `source/` now says `lib/`. Seventeen files carried that string.

- `.github/workflows/release.yml` - the module tag, pushed only when absent.

- `.github/workflows/pages.yml` - new, publishes `web/`.

- `README.md` - what is available, and the demo link.

- `.golangci.yml` - the vendored exclusion still has to hold.

## Testing

The existing tests mostly move with the code they test. Five files are `package main` today; four of them use `run`, so the ones testing the tool stay with the tool, and the ones testing conversion move.

`conversions_test.go` spans both layers, but the crossing is concentrated in two helpers near the top, plus one test of marker application. It repoints rather than splits.

Nothing about test coverage should change. The integration harness drives the binary and does not care where the packages are.

One check is worth adding: that the library builds and its tests pass without the CLI, so a dependency on the tool cannot creep back in unnoticed.

## Compatibility

No behavior changes. This is a refactor plus a module path fix.

The module path change breaks nothing, because nothing can depend on the module today. Nothing ever could: the repository's bare tags never addressed a module in a subdirectory, so no version of this was ever fetchable. That is the point of settling the path and the tag form now rather than later.

The command's version stays where it is. There is nothing here for a user of the tool to notice. The package's version is new and independent, and starts at v0.1.0.

## Outcome

The conversion core is a package, `lib/convertbase`, and the module path matches its directory so it can be fetched. The tool is `cmd/convert-base-v2/`, holding `main.go`, the flag types and the config-file creation, and imports the library like anyone else would.

One bug came out of the WebAssembly work, and it was a native bug too. `LoadConfig` forgave only `os.IsNotExist`, so any other failure to open a config file was fatal - including on the two paths nobody types. A sandbox with no preopened directory reports `EBADF`, and a `/etc/convert-base-v2` that is really a file reports `ENOTDIR`, so either would have killed the program over a file it was never asked for. "Could not open" and "would not parse" are now separate, and only the first is forgiven, and only for an implicit path.

The split was smaller than expected. Only nine identifiers crossed the line, all ten writes to standard error were already in `main.go`, and the single filesystem write had exactly one caller. Nothing had to be untangled.

The public surface is `Convert`, `StreamConvert`, `StreamBytesRoute`, `Registry` with `NewRegistry`, `Lookup`, `Register`, `LoadConfig`, `OrderedBases` and `Print`, `Base` with `Finalize`, `Name`, `NegSym`, `DecSym`, `RawCodec`, `Tokenize` and `HasByteDigit`, `Options` with `Apply`, plus `ApplyOptions`, `ResolveBase`, `ParseSymbolSpec`, `SpecOpts` and `PowerOfTwoBits`.

Verification: gofmt clean, `go vet ./...` clean, `go test ./...` passes, the harness at 357 of 357, and the three fuzz targets and the profiler benchmark run from their new home. Every command-line output was compared against a binary built before the change - help, examples, both listings, the index count, a dozen conversions, and the error paths that carry a flag name through the new options type. All identical apart from the version string, which differs only because the reference binary was stamped from a git description.

## Package name

Same as the CLI, for the same reasons of potential future changing base definitions.
