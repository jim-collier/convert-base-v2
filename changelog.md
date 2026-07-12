<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD024 -- No duplicate headings [OK with no TOC] -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## NEXT VERSION

### Changed

- `--precision` now defaults to `auto`, which sizes the output fraction to the input's own precision instead of always padding to 50 digits. Converting a short value like `0.1` no longer grows a long, imprecise tail in the target base. Pass `--precision N` for a fixed number of fractional digits (needed for lossless round-tripping, since auto keeps only the digits the input justified at each step).  [20260711]
- The base-65536 encoding is now named `65536qntm` (alias `65536utf32`), matching the `32768qntm` and `2048*` naming. The bare `65536` name is gone, so it can't collide with a future base of that size.  [20260711]

## v1.1.0-beta7 - 2026-07-11

### Notes

- This release also carries the v1.1.0-beta6 changes below, which were never published as a release.

### Added

- Raw binary encode and decode for four more bases, each per its official spec: base45 (RFC 9285), Ascii85 (Adobe/PostScript), Z85 (ZeroMQ RFC 32), and base91 (basE91). These are chunked binary-to-text codecs, so they carry bytes exactly and round-trip at any length (Z85 requires 4-byte-aligned input, per its spec). Powers of two still use the fast bit-packing path. Any other base has no byte-exact mapping and is refused in binary mode.  [20260707]
- `--binary` (aliases `--bin`, `-b`): re-encode directly between two power-of-two text bases as byte data, the way `basenc` does (e.g. hex to base-64), instead of converting the value as a number. Both bases must be powers of two. Piped input streams.  [20260708]
- `--number` (aliases `--num`, `-N`): assert the numeric reading of a conversion and silence the byte-vs-number note.  [20260708]
- `--show-symbols-0`: like `--show-symbols` but separates symbols with a NUL byte, so scripts can split bases whose symbols are more than one character.  [20260708]
- Near-match suggestions on an unknown base, and clearer messages for the common stumbles: flags placed after the number, a negative number typed without the `--` separator, and a mistyped flag.  [20260709]

### Changed

- `--list` gains a RAW column showing which bases can carry a raw binary stream (the power-of-two bases plus the codecs above).  [20260707]
- `--list` gains a leading INDEX column (the value `--by-index` takes). `--by-index` outside a query flag now notes on stderr that it is ignored.  [20260709]
- Crockford base32 (`32c`) now decodes `O` as 0 and `I`/`L` as 1 (case-insensitive), per the spec, while still emitting only the strict alphabet.  [20260709]
- The URL and hex RFC 4648 variants (`64u`, `64h`, `32h`) now pad their binary/codec output to the group boundary like the strict `64`/`32` variants; number-mode output is still never padded, and decode accepts padded or unpadded input.  [20260709]
- Conflicting base selectors (`--from-symbols` vs `--from`, `--to-symbols` or `--to` vs a positional output base) now print a stderr note instead of silently choosing one.  [20260709]
- `--help` and `--examples` write to stdout when explicitly requested, so they can be piped; the no-argument help stays on stderr.  [20260709]
- The 256-value raw-byte base is now named `bytes`. Its former names `binary`, `bin`, and `raw` are removed - use `--from bytes` / `--to bytes`, or `--binary` for text-to-text byte re-encoding.  [20260708]
- Converting between two power-of-two text bases with no mode flag now prints a note on stderr: the value is read as a number (leading zeros dropped), not re-encoded as bytes. Add `--binary` or `--number` to pick a reading.  [20260708]
- The `--raw` output flag is renamed `--no-newline` (`-n`), matching `echo -n`.  [20260708]
- `--show-symbols` now prints the symbols concatenated with no delimiter instead of one per line. Use `--show-symbols-0` for a machine-splittable list.  [20260708]
- The README no longer includes screenshots, and the pipeline no longer regenerates them by default. The generator is kept for on-demand use.  [20260706]

### Fixed

- The Ascii85 base (`85ps`) was defined with 84 symbols instead of 85: its backslash symbol was being dropped by the symbol-spec escape handling. Now a correct 85-symbol alphabet.  [20260707]

### Other work

- Broadened the test harness: raw round-trips now cover every base the RAW column advertises, with fixed spec vectors for each codec and a check that non-codec bases refuse raw binary. Added a resource profile (peak memory and wall time) and a codec throughput guard, both skipped by `--quick`.  [20260707]
- Added real Go unit tests (number, codec, native-base, padding, marker, and spec-parser vectors, plus a streaming-vs-buffered equivalence test), so `make test` gates the conversion logic instead of running only benchmarks. Filled several test-harness gaps and pinned known-value vectors for bases that previously had only self-round-trip coverage.  [20260709]
- Documentation accuracy sweep: regenerated the README bases table from the program (fixing stale aliases and the swapped 32/32h alphabets), corrected the serial-number and 85ps examples, and fixed the UTF byte-count table and changelog dates.  [20260709]
- Hosted CI: every push and pull request now builds, vets, and tests on GitHub Actions. The full local pipeline is unchanged.  [20260711]
- Releases are now cut automatically when dev merges to main: the workflow tags the version from the source and publishes the release with all six platform archives plus a checksums file, notes taken from this changelog.  [20260711]
- Release packaging moved to goreleaser, keeping the same archive names and layout as before.  [20260711]
- The pipeline's lint and audit tools are pinned to fixed versions, and dependency and workflow updates now arrive as grouped pull requests against dev.  [20260711]

## v1.1.0-beta6 - 2026-07-06

### Added

- Flags to query bases from a script: `--get-index-count`, `--get-base-name`, and `--show-symbols`. A base can be chosen by name, alias, or `--by-index`.
- User-defined bases can opt into RFC-style output padding with a `pad=X` token in the symbol spec (or a `pad:` field in a config file). It follows the same group-boundary rule as the built-in base32/base64 bases: encode pads to the boundary, decode accepts input with or without it. A pad character that is also a digit is rejected.
- New base "keyboard" (base 98): every printable keyboard character of a plain-text document, plus tab, newline, and return. The alphabet leads with the 62 alphanumerics 0-9 A-Z a-z, then the remaining characters in code-point order. Source code, prose, JSON, HTML, and embedded base64 are all valid input as-is, so a text file can be converted without escaping. Aliases: 98, text, ascii, kbd.
- New base "emoji64" (base 64): the Unicode emoticon faces, U+1F600 through U+1F63F (56 yellow faces and 8 cat faces), all single code points with no skin-tone variants. Being a power of two it also encodes binary streams, so a file can be turned straight into emoji and back.
- New base "emoji10" (base 10): ten hand-picked emoji as the digits 0-9, with a carrot for negative and a soccer ball for the decimal point.

### Changed

- Streaming binary conversion is much faster in both directions. Piped input streams straight to output with no whole-file buffering, and the standard bases (16, 32, 64) use hand-unrolled, byte-aligned inner loops like the system tools. Encoding and decoding to and from base-64/32/16 now run at hundreds of MiB/s; on the test bench, base-64 decode is faster than `base64` and `basenc`, and encode is close behind. Output is unchanged, and decoding tolerates line-wrapped input, so it reads `base64`'s default output. See the throughput table in the README.
- Bases whose symbols include `-` now use `~` as the negative marker, instead of the en-dash, which is too visually confusing. Affects base 45, 64u, 64h, and 69prsh.
- `--list` no longer repeats the base name in its aliases column.
- Clearer help text for the base-query flags.
- Base64 (RFC 4648 s4) and base32 (RFC 4648 s6) binary output is now padded with `=` to the standard group boundary. The URL and hex variants stay unpadded, and decoding accepts input with or without padding.

### Fixed

- Binary encoding to base 2048 (both variants), 32768, and 65536 now round-trips at every input length and matches the published third-party encodings byte-for-byte, using each one's own secondary alphabet for the final partial chunk. Before, some lengths came back with an extra trailing byte.  [20260706]

### Other work

- Added `utility/bench-encoders.bash`, a repeatable streaming-throughput benchmark that pits the tool against base64, base32, basenc, openssl, and xxd. All I/O runs in a tmpfs so results don't depend on disk speed, and it auto-skips tools that aren't installed. The README throughput table is generated from it.  [20260706]

- Broadened the test harness: every power-of-2 base now round-trips raw bytes at lengths that force a partial final chunk, and the long run reports streaming throughput with the system base64 alongside for reference. [20260706]

- Reworked the CI/CD scripts [20260703]:
	- Split the pipeline into a generic engine and a per-project config.
	- The pipeline now formats, builds, tests, cross-compiles, dogfoods a fixed-name local copy, then (as before) backs up and publishes quietly.
	- Replaced the old test harness with a self-contained, table-driven one. It covers the CLI, conversions, custom bases, errors, oversized and hostile input, binary round-trips, and fuzzing across every defined base. The base list is read from the program, so new bases are tested automatically.
	- Added byte-for-byte back-compat checks against v1b every shared base, in both directions. (Copy included in the repo.)
	- Moved old scripts to `legacy/`.

- Updated to CI/CD scripts [20260519]:
	- Updated for less boilerplate.
	- Changed license (of CI/CD scripts) from GPL2 to MIT.
	- Moved from ./utility to ./cicd/utility to be more logical, and consistent with other projects.
	- Refreshed local copies of n8git_backup-and-publish and n8lib_test.
	- Updated to side-step known potential edge-case unexpected behavior in `while...do...done`, by following all `done` with 'true'.

## v1.1.0-beta5 - 2026-05-12

### Added

- Uncommented base-45 definition, got it working with " " space as a valid symbol, and fixed a bug related to that.

### Changed

- Addressed Issue #6, "[Need a better way to define neg, dec, pad](https://github.com/jim-collier/convert-base-v2/issues/6)". Neg and dec are now defined independently of the base symbols, using structs. (Per [design document](https://github.com/jim-collier/convert-base-v2/blob/main/design_docs/20260503_rethink_neg_dec_pad.md).)

### Other work

- Renamed ci/cd scripts from `.sh` to `.bash` to make it clear they aren't POSIX scripts.

- Created helper utilities to help with base symbol selection
	- Python scripts
		- `filter_1_junk.py`
		- `filter_2_messy.py`
		- `filter_3_visual.py`
		- `populate_unicode_spreadsheets_with_filtered_results.py`
	- Bash wrappers:
		- `test_filter_all_from_xclipboard_input.bash`
		- `unicode_1_junk_alter_xclipboard_contents.bash`
		- `unicode_2_messy_alter_xclipboard_contents.bash`
		- `unicode_3_visual_alter_xclipboard_contents.bash`

- Exported `unicode_good_base_symbols.gnumeric` to `unicode_good_base_symbols.ods`, as the new main spreadsheet and single-source of truth.
	- Data from that trickles down to `unicode_good_base_symbols.gnumeric` and `unicode_good_base_symbols.xlsx`.
	- Notes:
		- The `.xlsx` is _way_ too slow and painful to be the main spreadsheet. And is the most likely to be out of sync. It's essentially unusable for actual editing.
		- The `.gnumeric` sheet used to be the main, because Gnumeric seems to be the fastest by far with this much data, but...
		- Once you use the `.ods` sheet for a while, it speeds up. Must be some memory caching or optimizing hapening. It starts out as slow as Excel (basically unusable), but slowly speeds up to rival Gnumeric. So given that, and the better features of LibreOffice sheets over Gnumeric, LibreOffice is the new main.

- Not-trivial updates to `how_to_design_a_numeric_base.md`.

## v1.1.0-beta4 - 2026-05-03

### Changed

- Fixed a bug that only affects backwards-compatibility, which are already discouraged to be used in help and README. [20260428]

### Other work

- Added CI/CD scripts. [20260428]

- Minor tweaks to `cicd.sh` to make paths more explicit and hopefully less prone to future errors. [20260503]

- Minor updates to this file be more "changelog idiomatic". [20260503]

- Minor corrections to README.md, including lifecycle and status badges. [20260503]

## v1.0.0-rc3 - 2026-04-19

### Added

- Added over a dozen more bases, including other languages for base-10, a few novelty bases, and v1 backwards-compatibility bases.  [20260419]

### Changed

- Made word-safe bases all consistent, while maintaining backward-compatibility with `convert-base-v1`. [20260419]
- Fixed an _eggregious_ bug where RFCs 4648 §4 and §5 were defined completely wrong. Like not even close.
	- They were defined - totally rationally - as "hex-style".
	- But the RFC standards define numbers as coming almost last, inexplicably.
	- As a streaming binary-to-text encoder, that's fine.
		- But it also means that as a base converter, 3→"C", and "12"→"M". Which is weird.
		- For most bases ≥ 12, 3→"3", 12→"C".
		- But, it's the published RFC standard. We say it's the RFC standard base, and not compute the RFC standard base.
- Added a _new_ hex-style base-64, with a new name "64hex", which the old base-64-URL RFC was previously defined as..

## v1.0.0-rc2 - 2026-04-19

### Changed

- Now errors if binary conversion doesn't align on boundary, to avoid losing data at end. (Will add padding in future release.)

### Other work

- Added README.md, license.md, changelog.md, todo.md

## v1.0.0-rc1 - 2026-04-18

### Added

- First binary release.

### Other work

- Created repo and project structure [20260417]
- Finished first draft of README.md [20260418]
- Added testing script. (Tests pass for most common scenarios - e.g. all integers with bases <= 288.)
