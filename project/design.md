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
	- [Logical code organization](#logical-code-organization)
	- [API](#api)
- [Code review BxZNl - recommendations](#code-review-bxznl---recommendations)
	- [Input handling and CLI contract](#input-handling-and-cli-contract)
	- [Alphabets, markers, and specs](#alphabets-markers-and-specs)
	- [Binary and streaming paths](#binary-and-streaming-paths)
	- [Fractions](#fractions)
	- [Registry and config](#registry-and-config)
	- [Versioning](#versioning)
	- [Testing](#testing)
	- [Docs](#docs)
- [CI/CD and release flow](#cicd-and-release-flow)

<!-- /TOC -->

## Goal

## Architecture

### Language and stack

### Logical code organization

### API

## Code review BxZNl - recommendations

Recommendations from the 20260708 code review. Numbers match the backlog items; deeper notes are kept outside the repo.

### Input handling and CLI contract

- BxZNl-1: pick one stdin contract and enforce it. Cleanest option: when stdin is a pipe and exactly one positional is given that resolves as a base name, treat it as OUTBASE, matching the synopsis. If that feels too magical, hard-error on "pipe attached but NUMBER given on argv" instead. Silent success is the one wrong answer.
- BxZNl-16: four cheap message fixes. When the rejected extra positional starts with "-", say flags must come before the number. When an unknown flag looks like a negative number, suggest the `--` separator. Give the flag package a one-line usage hint instead of a no-op. Append "see --list" to unknown-base errors, with an optional edit-distance-1 suggestion.
- BxZNl-17: conflicting inputs should error, or at least warn: `--to` plus a different positional OUTBASE, and `--from` plus `--from-symbols`. The precedence is documented in a code comment, not to the user.
- BxZNl-18: pass a writer into the help/examples printers; stdout when explicitly requested, stderr on the no-args error path.
- BxZNl-19: add an index column to --list, and warn or error when --by-index is set without a query flag.

### Alphabets, markers, and specs

- BxZNl-2: in finalize(), when symbols have mixed lengths, reject sets where one symbol is a proper prefix of another. Prefix-freeness makes the existing greedy tokenizer provably correct, so validation is the whole fix. The error should name the two conflicting symbols.
- BxZNl-3: also reject an effective negative or decimal marker that appears as a substring of any digit symbol (and the reverse). The alternative, folding marker detection into tokenization, is more invasive and only needed if substring collisions should be legal.
- BxZNl-5: route \t and \n through the same placeholder trick already used for escaped space, restoring them after the whitespace split. Or drop them from the documented escape list.
- BxZNl-13: either implement comma-split in the multi-token branch or fix the doc comment; add a test either way.
- BxZNl-15: reject a raw U+FFFE in the spec before unescaping, since it is the placeholder rune.

### Binary and streaming paths

- BxZNl-4: after the read loop in streaming encode, return any error that is not EOF or unexpected-EOF instead of finishing the tail. Mirrors what the decode side already does.
- BxZNl-6: make leniency identical on both channels. Streaming decode should accept pad bytes only as a trailing run; buffered decode should get the same CR/LF skip streaming has (for single-byte bases whose alphabet lacks those bytes). base91 should skip only whitespace and error on other unknown bytes; reference encoders never emit them, so interop is unaffected.
- BxZNl-25: longer term, either route the buffered binary conversions through the stream implementation (wrap argv input in a reader), or keep the fast paths and pin them with the equivalence tests in BxZNl-22. One implementation per direction ends this class of bug.

### Fractions

- BxZNl-7: after the emit loop, round the final digit to nearest (compare twice the remaining numerator against the denominator, carry into the integer part on overflow). Combine with the input-precision clamp; clamping makes truncation drift proportionally larger, so do both together.
- Input-precision clamp (done): `--precision` defaults to `auto`. Rather than always emitting the fixed maximum, auto sizes the output fraction to the input's information content - the input's fractional digit count scaled by the base-size ratio `log(fromBase)/log(toBase)`, plus one guard digit, then trailing zeros trimmed. This stops a short decimal like `0.1` from implying 50 digits of precision it never had. It is bounded by the input length so it cannot run away, and an explicit `--precision N` remains available when a fixed or lossless-round-trip width is wanted. The tradeoff, accepted deliberately: auto round-trips lose precision at each hop, since every hop keeps only the digits the prior value justified.
- BxZNl-8: treat an all-zero emitted fraction as no fraction before the zero and sign logic, so tiny values print "0" instead of "0.000" or "-0.000".

### Registry and config

- BxZNl-10: when a registered base fully shadows an existing one, replace it in the ordered list; when it steals only some aliases, drop those from the shadowed row (derive the ALIASES column from the live alias map) or mark the row overridden. Keeps --list truthful and the --by-index space meaningful.
- BxZNl-11: track whether --config was explicitly set (flag.Visit); explicit and missing is an error, the implicit /etc and XDG paths stay lenient.
- BxZNl-12: check every integer alias, not just the first, and run the check on the normalized name so "b99" style aliases cannot bypass it.
- BxZNl-14: make `pad: ""` clear the pad to honor the documented explicit-fields-win rule, matching the tri-state behavior negative and decimal already have. A separate emit flag would let config bases express accept-but-do-not-emit pads.
- BxZNl-20: the padding rule is by mode, not by base. Positional (number) conversion is never padded; the binary-to-text codec path pads to the group boundary. Among the options (document the deviation, add padded siblings, or flip), it was decided to flip 32hex/64url/64hex to emit padding in codec mode, so all RFC 4648 variants behave alike and match the strict stdlib decoders. Decode stays lenient, accepting padded or unpadded input, so no valid input is rejected; only the codec-mode output of those three bases changes.
- BxZNl-21: a small optional decode-alias map on Base (extra input bytes mapping to existing digit values) covers Crockford's O/I/L rule without touching encoding.

### Versioning

- BxZNl-9: change `const version` to `var version = "dev"` so the linker's -X actually lands, tag releases, and let git describe be the single source of truth. That retires the keep-two-places-in-sync rule and the stale-version failure mode at once.

### Testing

- BxZNl-22: priority order for Go tests: streaming-vs-buffered equivalence over random lengths for every power-of-2 base and pad variant; the codec and big-base spec vectors ported from test.bash; table-driven Convert cases for sign, fraction, marker tri-state, and multi-char symbols; ParseSymbolSpec and config-load cases. Until then, make the Makefile test target also run cicd/test.bash so the canonical entry point gates something.
- BxZNl-23: in test.bash, add one pinned known-value vector per predefined base (a single number and its exact expected string) to catch symmetric bugs; a fractional block with fixed vectors, negatives, precision 0, and an exact power-of-2 round trip; a config block using temp YAML files; a spec block pinning the 85ps symbol count and escape handling; a minimum-count assertion after the --list scrape; a loud SKIPPED when the v1 binary is absent.
- BxZNl-24: a minimal gate is enough: build, vet, go test, then test.bash with low fuzz iterations. cicd.bash stays the release pipeline, not the only test runner.

### Docs

- BxZNl-26: regenerate the README bases table from --list and --show-symbols output rather than hand-fixing rows; the example-output table earlier in the README already matches the binary, so only the bases table drifted. Fix --examples to use 2048x or register a bare "2048" alias. Correct the serial-number example (the string shown is 64h of undivided seconds), the example.conf marker-collision comment, the UTF byte columns, and the changelog year typos.

## CI/CD and release flow

- Branching: dev is the integration branch. Feature branches merge to dev; main is release-only.
- Hosted CI is a bare safety net (vet, test, build on push and PR, via GitHub Actions). The full pipeline (fuzz, profiling, dogfood, package, publish) stays local in cicd/.
- Two native builds. The debug build (symbols kept) is what the tests and profiler run against. The optimized build (stripped) is smoke-checked, dogfooded, and matches what the cross stage ships, so day-to-day use is the real thing.
- Packaging is self-contained (cicd/utility/package.bash), not goreleaser. Rationale: goreleaser cannot run on the dev box (not installed, and it is a heavy orchestrator), and the project already favors bespoke, dependency-light tooling. The same script runs locally and in the release workflow, so what ships is what was built and tested here.
  - Targets: linux, darwin, freebsd, windows on both amd64 and arm64. ARM is built unconditionally - Go cross-compiles it at native speed, so there is no reason to gate it behind a flag.
  - Artifacts per platform: a tarball (or zip on Windows) of the bare static binary; a .deb and .rpm for each Linux arch (via nfpm, which cross-packages any arch without native rpmbuild/dpkg); a single-file Windows installer .exe per arch (via makensis) that drops the binary, puts it on PATH, registers an uninstaller, and overwrites an existing install when re-run; and a checksums file. Go binaries are static, so nothing bundles a runtime.
  - macOS .dmg and a native FreeBSD .pkg are deferred - both need their own OS tooling to build and sign; those platforms ship as tarballs for now.
- Releases are automatic on a merge to main. The version var in source/main.go is the source of truth. A guard runs first (cicd/utility/check-release.bash) and FAILS the workflow if the version was not bumped (its tag already exists), if it sorts behind the newest tag, or if the README Lifecycle badge does not match the version stage. Because main is release-only, an un-bumped merge is a mistake, not a silent no-op. On success the workflow tags, packages, and publishes with gh.
- Release prep on dev is: rename the changelog's NEXT VERSION heading to the version and date (the workflow lifts that section as the release notes), bump the version var, and set the Lifecycle badge to match the stage (alpha/beta/rc/none -> Alpha/Beta/RC/Stable).
- Tool versions (golangci-lint, staticcheck, govulncheck, nfpm) are pinned in cicd/tool-versions.env, one place read by both the local pipeline and the workflows. Dependabot files grouped weekly update PRs against dev.
