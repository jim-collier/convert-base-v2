<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Project design

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Goal](#goal)
- [Architecture](#architecture)
	- [Language and stack](#language-and-stack)
	- [Code organization](#code-organization)
	- [CLI contract](#cli-contract)
- [Key design decisions](#key-design-decisions)
- [CI/CD and release flow](#cicd-and-release-flow)

<!-- /TOC -->

## Goal

One small, fast, portable command line tool that does two related jobs well:

- Convert a number of any size between any two bases, including negatives and fractions.
- Encode and decode raw binary to and from text in the bases that can carry bytes exactly.

It should cover the everyday standards (base 10, 16, RFC 4648 base 32 and 64) and a wide set of named and custom bases, match published reference encoders byte for byte, and stay stable and deterministic so scripts can rely on its output for years.

## Architecture

### Language and stack

- Go, module `github.com/jim-collier/convert-base-v2`, one `main` package under `source/`.
- One dependency, `gopkg.in/yaml.v3`, for optional config files.
- Ships as a single static binary. Release builds are stripped and trimmed with `CGO_ENABLED=0`.

### Code organization

- `main.go` reads flags and config, resolves the conversion, and handles stdin and pipes. It also holds the version string.
- `convert.go` is the conversion core. It has two paths: an arbitrary-precision path (handles sign and fractions) and a fast bit-packing path used when a base is a power of two.
- `registry.go` defines the `Base` type, the lookup registry, and config loading.
- `bases.go` lists the predefined named bases and their alphabets. A new base is one more entry here.
- `symbolspec.go` parses user-supplied alphabets and the `neg` / `dec` / `pad` marker tokens.

### CLI contract

- Usage is `convert-base-v2 [flags] NUMBER [OUTBASE]`. A positional `NUMBER` always wins, so a pipe is read only when the input is `-`.
- If `--from` is unset the input base is 10. If neither `--to` nor a positional `OUTBASE` is given, the output base is 10 too. Under `--binary`, an omitted side defaults to `bytes`.
- Conflicting selectors (for example `--to` and a different positional base) do not silently pick one. They emit a note on stderr and follow a documented precedence.
- Query flags (`--list`, `--show-symbols`, and friends) each print one value and exit, so scripts can read the base set from the program itself.

## Key design decisions

The rationale behind the choices most likely to be questioned later. Each was settled during pre-1.0 review.

- **Two binary paths, kept separate.** Streaming (constant memory, linear time) and buffered positional (quadratic time) are genuinely different jobs, so they stay as two implementations rather than being merged. An equivalence test pins them together, and fails if they ever diverge.

- **Padding is by mode, not by base.** Positional number output is never padded. The binary-to-text codec path pads to the group boundary for every RFC 4648 variant, matching the strict standard decoders. Decoding stays lenient and accepts padded or unpadded input either way.

- **Fractional precision defaults to `auto`.** The output fraction is sized to the input's own precision instead of always stretching to a fixed maximum, so a short value like `0.1` does not grow an invented tail in another base. Auto round-trips are lossy by design; `--precision N` is available when a fixed or lossless width is wanted.

- **Markers are tri-state.** A base's negative and decimal markers can be unset (use the global default), explicitly disabled, or set to a specific symbol. This keeps custom alphabets that reuse `-` or `.` as digits working.

- **Custom alphabets must be prefix-free.** For multi-character symbols, no symbol may be a prefix of another, and a marker may not appear inside a digit. That keeps the simple left-to-right tokenizer provably correct, so the fix is validation, not a more complex parser.

- **Config override keeps the base list truthful.** When a config base shadows a built-in one, the shadowed entry is dropped or loses only the stolen aliases, so `--list` and the index space stay accurate.

- **The version is a `var`, not a `const`.** The release build patches it through a linker flag, which only works on a var. The source value is the single source of truth for what version ships.

- **Output stays deterministic and stable.** Given the same input and base, the output never changes across runs or platforms. Any future change that would alter output goes to a new version suffix so old scripts keep working.

## CI/CD and release flow

- Branching: `dev` is the integration branch. Feature branches merge to `dev`; `main` is release-only.
- Hosted CI is a bare safety net: vet, test, and build on every push and pull request. The full pipeline (fuzz, profiling, dogfood, package, publish) stays local.
- Two native builds. The debug build (symbols kept) is what tests and the profiler run against. The optimized build (stripped) is smoke-checked, dogfooded, and matches what ships, so day-to-day use is the real thing.
- Packaging is self-contained (`cicd/utility/package.bash`). The same script runs locally and in the release workflow, so what ships is what was built and tested here.
	- Targets: linux, darwin, freebsd, and windows on amd64 and arm64. ARM is built unconditionally, since Go cross-compiles it at native speed.
	- Per platform: a tarball (zip on Windows) of the static binary, a `.deb` and `.rpm` for each Linux arch, a single-file Windows installer that adds the tool to PATH and can update an existing install, and a checksums file. macOS `.dmg` and a native FreeBSD `.pkg` are deferred; those platforms ship as tarballs for now.
- Releases are automatic on a merge to `main`. The version var in `source/main.go` is the source of truth. A guard runs first and fails the workflow if the version was not bumped, if it sorts behind the newest tag, or if the README Lifecycle badge does not match the version stage. On success the workflow tags, packages, and publishes.
- Release prep on `dev`: rename the changelog's next-version heading to the version and date, bump the version var, and set the Lifecycle badge to match the stage.
- Tool versions are pinned in `cicd/tool-versions.env`, read by both the local pipeline and the workflows. Dependabot files grouped weekly update pull requests against `dev`.
