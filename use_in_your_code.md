<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<!-- TOC ignore:true -->
# Use it in your own code

Back to the [README](README.md).

The conversion core is a library in its own right, and the command is a thin layer on top of it. Everything below runs that same code, so none of them can disagree with the command about what a base means.

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Five builds](#five-builds)
- [A Go package](#a-go-package)
- [WebAssembly, in a browser](#webassembly-in-a-browser)
- [WebAssembly, anywhere else](#webassembly-anywhere-else)
- [WebAssembly, as a function call](#webassembly-as-a-function-call)
- [Or just run it](#or-just-run-it)
- [Licensing](#licensing)

<!-- /TOC -->

## Five builds

Five separate things get built here, and they aren't interchangeable:

- The command, `convert-base-v2`, is a program. It parses flags, loads config files, and moves data through pipes.

- The Go package, `lib/convertbase`, is a library. Import it and call its functions. It has the permissive Apache 2.0 license.

- The browser module, `web/convert-base.wasm`, is the package compiled for a web page, with a small set of JavaScript calls. Also Apache 2.0.

- The WASI module, `dist/convert-base-v2.wasm`, is the whole command compiled to WebAssembly. A program, not a library.

- The reactor module, `dist/convert-base-reactor.wasm`, is the package compiled for any WebAssembly runtime, exporting plain functions. Also Apache 2.0.

The line between the command and the package is about what each one is allowed to do. Writing a config file into someone's home directory is fine for a program that person chose to run. It isn't fine for a library that got imported into somebody else's project, so the package does none of it. It touches no files, reads no environment variables, and prints nothing. The caller decides all of that.

## A Go package

~~~sh
go get github.com/jim-collier/convert-base-v2/lib/convertbase
~~~

~~~go
reg, _ := convertbase.NewRegistry()
from, _ := convertbase.ResolveBase(reg, "10", "", nil)
to, _ := convertbase.ResolveBase(reg, "62", "", nil)

out, err := convertbase.Convert("86434491232548995369", from, to, -1)
~~~

Convert whole values, or stream through an `io.Reader` and `io.Writer` in constant memory for anything large. Define your own alphabets, override the negative and decimal markers, and read the base registry directly.

[zuid](https://github.com/jim-collier/zuid), a short sortable ID generator, is one example. Its Go module imports this package for every base it offers.

The package version moves on its own, separately from the command's. It's at v0 for now, which means the API may still change.

## WebAssembly, in a browser

The [demo page](https://jim-collier.github.io/convert-base-v2/) is the whole library compiled to WebAssembly, with a small set of JavaScript calls:

~~~js
const res = convertBase.convert({value: "255", from: "10", to: "16"});
// { ok: true, value: "FF" }

convertBase.convert({value: "255", from: "10", to: "hexx"});
// { ok: false, error: 'unknown base "hexx"; did you mean "hex"?', code: 1 }
~~~

A failure comes back as a result, not an exception. Its `code` is the same number the [reactor module](lib/reactor/README.md#error-codes) gives for the same failure, so a page can act on one without matching the text.

Serve the two files next to your page and it works offline, on static hosting, with no backend.

This build talks to JavaScript through the browser, so a page is the only place it runs. It isn't a general WebAssembly library.

## WebAssembly, anywhere else

The command also builds as a WASI module, which runs under Wasmtime, Wazero, Node, and the WebAssembly edge platforms. WASI hands it real argv, standard input, and standard output, so streaming works exactly as it does natively, and one file runs on every architecture. Each release includes it, or `make wasm` builds it.

~~~sh
wasmtime run dist/convert-base-v2.wasm --from hex --to 10 ff
 # 255
~~~

This is the command in a sandbox, not the library made portable. A Rust, Python, or C# program reaches it by starting it under a runtime and wiring up argv and pipes. That is running a program in process. It isn't calling a function, and the module doesn't survive being run a second time in the same instance.

That is still enough to cover callers in any language with a WebAssembly runtime, with no C interface to freeze and no per-platform build to make. What it does not give you is conversion as a plain function call. That is what the reactor module is for.

## WebAssembly, as a function call

The reactor module is the library compiled for any WebAssembly runtime, exporting plain functions the host calls directly: one-shot conversion, base lookup, the radix and zero symbol of a base, symbol counting, and a stable numeric error code set with readable error text. It also slices and pads by symbol rather than by byte, which is what fixed-width identifier fields need once a base reaches outside ASCII and one digit is no longer one byte. Strings cross as a pointer and length through the module's memory, with an exported allocator pair; the full contract is in [`lib/reactor/README.md`](lib/reactor/README.md). Build it with `make reactor` (needs a Go 1.24 or newer toolchain).

Streaming is there too, as a push API: open a stream, write raw bytes as they arrive, read output chunks back, finish. It runs the same constant-memory paths the command uses for piped data. The WASI module above remains the simpler choice when all you want is a pipe.

zuid's C module uses it this way. The identifier code is native Zig, and it calls the reactor module through Wasmtime for each base conversion.

## Or just run it

If you can start a process, that is still the simplest option, and always has been. Input and output are pipes, so a conversion of any size streams through in constant memory whatever language you call it from. The library and the WebAssembly builds are for the cases where you can't shell out.

## Licensing

Which license applies follows the same split.

- The Go package, the browser module, and the reactor module are Apache-2.0. Build them into anything, commercial and closed-source work included. Keep the credit with them and you are done.

- The command stays GPL-2.0-or-later, and so does the WASI module, because that module is the command.
