<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Project backlog

This is a product backlog just for pre-v1.0.0 release. After that, bugs, features, and enhancements will be managed in Github Issues, and/or [todo.md](../todo.md)

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Conventions](#conventions)
- [Backlog](#backlog)
	- [Todo](#todo)
	- [Bugs](#bugs)
	- [New features and enhancements](#new-features-and-enhancements)
	- [Done](#done)
		- [Done - Bugs](#done---bugs)
		- [Done - New features and enhancements](#done---new-features-and-enhancements)
	- [Deferred](#deferred)
	- [Canceled](#canceled)

<!-- /TOC -->

## Conventions

In each section, items are listed approximately from newest to oldest.

| Icon | Status
| :--: | :--
| 🔘   | Not started
| 🛠️   | Started, and/or partially complete
| ✋   | Defer
| ✅   | Complete
| 🚫   | Canceled

## Backlog

### Todo

- 🔘 Add this to README.md:
	- To avoid confusion when working with binary data, you can add these aliases to your shell startup script:

		~~~bash
		## Streaming binary/text codec
		alias convert-base-v2-bin="convert-base-v2 --binary"

		## Positional notation base conversion
		alias convert-base-v2-num="convert-base-v2 --number"
		~~~

### Bugs

### New features and enhancements

### Done

#### Done - Bugs

- ✅ Piped stdin silently ignored when a positional is given. (BxZNl-1) Kept argv-wins semantics (changing it would break `prog NUMBER` in scripts whose stdin is an inherited pipe, and could consume a pipe it should not touch). Instead: a real pipe with data plus one positional that names a known base now prints a stderr note pointing at `-`, and the synopsis is corrected to require `-` for the pipe form.

- ✅ Non-prefix-free custom alphabets decoded wrong. (BxZNl-2) finalize() now rejects a symbol set where one symbol is a byte-prefix of another (only possible with multi-byte symbols; builtins are single code points and unaffected).

- ✅ A marker inside a multi-char digit symbol corrupted parsing. (BxZNl-3) finalize() rejects a base whose negative/decimal marker appears inside any digit symbol (the "a.b" case is also caught by the new prefix-free check).

- ✅ Streaming encode swallowed read errors as EOF. (BxZNl-4) streamEncode now returns a real read error instead of finishing the tail on it; only io.EOF / io.ErrUnexpectedEOF end the stream.

- ✅ `\t` / `\n` escapes in symbol specs did nothing. (BxZNl-5) They now route through noncharacter placeholders like escaped space, so they survive the whitespace split; `neg=\t` sets a tab marker.

- ✅ Decode strictness depended on the channel. (BxZNl-6) Buffered decode now tolerates line breaks; streaming decode now rejects a digit after padding (matching the buffered interior-pad error); base91 decode errors on junk and only skips whitespace.

- ✅ Fractional output truncated instead of rounding. (BxZNl-7) Fractional part is rounded half-up to precision (carry propagates into the integer part); 0.1 -> hex -> back is now stable.

- ✅ Tiny fractions printed "0.000" / "-0.000". (BxZNl-8) A value below one output digit now rounds to nothing, so no spurious zero fraction or sign (fixed by the same rounding rewrite).

- ✅ Version stamping was a no-op. (BxZNl-9) `version` is now a var, so the `-X main.version` ldflag actually patches it. (Tagging v1.1.0 remains a separate repo action.)

- ✅ Config override left the registry misleading. (BxZNl-10) A fully-shadowed builtin is dropped from the index/count, and --list shows only aliases that still resolve to each base (using the first live one as the name).

- ✅ A typo'd explicit `--config` path was silently ignored. (BxZNl-11) An explicitly-passed missing/unreadable config now errors; the default /etc and XDG paths stay missing-is-OK.

- ✅ Integer-alias check was easy to bypass. (BxZNl-12) Every alias is checked (not just the first), against its normalized form, so ["3","99"] and "b99" are both rejected.

- ✅ Comma-split in multi-token specs was unimplemented. (BxZNl-13) Each token in a multi-token spec is now comma-split, so "0,1 2 3" is four digits.

- ✅ YAML `pad: ""` could not disable a trailer pad. (BxZNl-14) An explicit empty `pad:` clears it, and a new `pademit:` field allows a strip-only (accept-but-not-emit) pad.

- ✅ A literal U+FFFE (or the new tab/newline placeholders) in a spec became a space digit. (BxZNl-15) A raw spec containing any reserved noncharacter is now rejected up front.

#### Done - New features and enhancements

- ✅ Docs accuracy sweep. (BxZNl-26) Regenerated the README bases table's Name and Aliases columns from the program (matching rows by alphabet so the swapped 32/32h rows self-corrected and the jc->jc1 renames applied; every alias now resolves). Fixed the serial-number example (1fLcL4 is 64h not 64u, whole-seconds value, softened the /60 prose), the stale 85ps example-output row, the `--examples` bare `2048` (now `2048x`), the UTF byte-count table and prose in both copies of how_to_design_a_numeric_base.md (3-byte UTF-16 is 2, 4-byte is 4/4), the example.conf silent-disable claim and undocumented `pad:` field, and the changelog 2025->2026 year typos. Added NEXT VERSION changelog entries for this batch of enhancements.

- ✅ Closed the test.bash blind spots. (BxZNl-23) Added independent known-value pins for bases that only had self-round-trip fuzz (58btc, 62hex, 36, 85ipv6), more fixed fractional vectors (signed, mixed, imprecise tail), a config-file load test (custom base via `--config`, plus the absent and missing-file cases), spec-parser edge cases (comma-split alphabet, escaped-space digit, marker-in-digit rejection), an 85ps 85-symbol count pin, minimum-count floors on both `--list` scrapes, and a loud SKIPPED when the v1 binary is absent.

- ✅ Two binary paths kept separate but pinned, not merged. (BxZNl-25) Merging the streaming (constant-memory, linear) and buffered (positional, quadratic) paths was judged the wrong move; they are different concepts and the fast streaming path was hard-won. The debt is instead covered by the streaming-vs-buffered equivalence test from BxZNl-22, which fails if the two ever diverge.

- ✅ Real Go tests, so `make test` gates the conversion logic instead of running only benchmarks. (BxZNl-22) New `conversions_test.go`: number vectors (sign, fractions, leading zeros, rounding), the codec and native big-base vectors (same reference values as test.bash), RFC padding, Crockford asymmetry, custom symbols and markers, spec-parser and finalize rejections, random round-trips, and the key streaming-vs-buffered equivalence test (171 comparisons across power-of-2 bases and many lengths, byte-for-byte).

- ✅ Padding story settled: it depends on mode, not on the base. (BxZNl-20) Positional/number output is never padded; the binary-to-text codec path now pads every RFC 4648 variant (64u/64h/32h flipped to emit `=` to the group boundary, matching the strict s4/s6 variants and the stdlib decoders). Decode stays lenient (padded or unpadded input both accepted).

- ✅ `--list` now has a leading INDEX column (the value `--by-index` takes), and `--by-index` outside a query prints a stderr note that it is ignored. (BxZNl-19) Help wording for `--by-index` now points at the INDEX column instead of a fragile "above".

- ✅ `--help` and `--examples` now write to stdout when explicitly requested, so `--help | less` works. (BxZNl-18) The no-args error path keeps help on stderr (exit 2, clean stdout). Threaded a writer through printHelp/printExamples/printCopyright.

- ✅ Conflicting base selectors now emit a stderr note instead of silently picking one. (BxZNl-17) `--from-symbols` over `--from`, `--to-symbols` over any output name, and `--to` over a positional OUTBASE. A `--to` and positional that name the same base stay quiet. Behavior unchanged (note only), matching the BxZNl-1 approach.

- ✅ Friendlier messages for the four common stumbles. (BxZNl-16) Flags after the NUMBER now say flags come first; a bare `-123` points at the `--` separator; an unknown flag points at `--help`; an unknown base points at `--list` and suggests near matches (prefix or small edit distance, closest tier only). Flag parsing moved to ContinueOnError so these can be caught.

- ✅ Crockford base32 (32c) now decodes O as 0 and I/L as 1, case-insensitive, per the spec's asymmetric rule. It still emits only the strict alphabet. Added a `DecodeAliases` mechanism on Base for input-only symbol aliases; README and test.bash updated. (BxZNl-21)

- ✅ Allow any base to be prefaced with "base", "base-", or "base_", and still work. (github #8)

- ✅ `--show-symbols` should list with no delimiters. (Currently lists with newline in between each.) #1n4xq9d
	- Now concatenated with a single trailing newline. Added `--show-symbols-0` (NUL-separated) so scripts can still split multi-char symbols; fuzz harness uses it.

- ✅ Added a `--upper` flag, the opposite of `--lower`. Uppercases text output, and like `--lower` errors on a mixed-case output base (where changing case would collide two distinct digits). The two flags reject each other.

- ✅ Byte-mode re-encoding between text bases. Two power-of-2 text bases (e.g. hex and base-64) used to convert only as a positional number, which silently drops leading zeros and is not a byte re-encoding.
	- Now `--binary` (`--bin`, `-b`) re-encodes them as byte data the way `basenc` does, by routing through the raw-byte base; piped input streams.
	- `--number` (`--num`, `-N`) asserts the numeric reading.
	- With neither flag, a power-of-2 text-to-text conversion prints a note on stderr so the ambiguity is no longer silent.

- ✅ Renamed the 256-value raw-byte base to `bytes` and dropped its `binary`/`bin`/`raw` aliases, so the base name no longer collides with the new `--binary` mode flag (and "binary" no longer misleadingly names the byte base rather than base-2).

- ✅ Renamed the `--raw` output flag to `--no-newline` (`-n`), matching `echo -n`; its old name was unclear and overlapped the raw-byte base.

- ✅ Raw binary conversion now covers, besides the powers of two, the defined streaming binary-to-text codecs: base45, Ascii85, Z85, and base91, each implemented per its official spec.
	- Any other non-2^N base has no byte-exact mapping and is refused in binary mode.
	- `--list` shows which bases qualify (RAW column). (An earlier attempt to make every base work via whole-value base-x was reverted in favor of this, since a positional whole-value encoding isn't what a streaming codec means.)

- ✅ Screenshots retired. The README no longer shows them and the CICD stage is off by default; the generator is kept so they can be made again if wanted. Dropped the orphaned image files.

- ✅ Rigorous CICD testing. Raw round-trips now cover every base (not just powers of two) at lengths that force padding, with fixed base-x vectors pinning the leading-zero convention. Added a resource profile (peak memory and wall time) and a base-x timing guard, both skipped by `--quick`.

- ✅ Create a new base that covers all possible printable keyboard characters in a plain text document. (Including programming code, regular human writing, email addresses, newline, return, tab, etc.)
	- Without worrying about higher unicode alternatives (e.g. curly-quotes, mdash, etc.) - those would have to go through some separate conversion preprocessing in order to work with this base. I believe this should also covers Rich-Text format (which I believe has no special characters), MD, HTML, XML, JSON, embedded base64, etc., as-is.

- ✅ Create a base64 that's all emojis
	- Only emojis noted/suggested by unicode to print graphically.
	- Symbols in LANG=C order.
	- Use generic yellow emojis for skintone-based ones, not skin-tone variants.
	- Skip emojis that look too similar; use only the first one.

- ✅ Improve the performance of streaming binary-to-text conversion and vice-versa, to better approach existing linux utilities. Go should be able to get close.

- ✅ An optional padding scheme for custom bases (not necessarily `===`). The published big bases and the RFC base32/base64 bases already pad correctly; this is about letting user-defined bases opt into padding too.

- ✅ Update comments in code, help output, readme.md, and design.md to properly use "radix" and/or "base" in context, etc. But not the actual program interface, don't change that.

- ✅ Base64 (RFC 4648 s4) and base32 (RFC 4648 s6) binary output is now padded with `=` to the standard group boundary, matching the RFC test vectors. The URL and hex variants stay unpadded, and decoding accepts input with or without padding.

- ✅ Binary conversions to the big published bases (both base 2048's, 32768, 65536) round-trip at any input length and match the reference encoders byte-for-byte, using each one's own secondary alphabet for the final partial chunk. Odd-length tails no longer come back a byte long. Fixed vectors from the reference implementations guard the interop.

- ✅ Bases with '-' in the symbol set now use '~' as the negative marker instead of the en-dash. '~' was free in all four affected bases (45, 64u, 64h, 69prsh).

- ✅ Help: clarified the text for the index-related flags (`--get-index-count`, `--get-base-name`, `--show-symbols`, `--by-index`).

- ✅ `--list`: the NAME is no longer repeated in the ALIASES column.

### Deferred

- ✋ Some hosted or hook-based CI gate. (BxZNl-24) Deferred. Nothing runs unless cicd.bash is invoked by hand, but `make test` now gates real logic locally (BxZNl-22), and the equivalence tests add genuine value. A hosted workflow or pre-push hook can be added later if wanted; left as documented deliberate debt for now.

### Canceled

- 🚫 Backwards compatible base '128v1compat' has a subtly incorrect alphabet difinition. (github #1)
	- The base definition for '128j1' in v1 is - annoyingly - a "word-safe" version.
		- (I can't remember if that was intentional. It shouldn't have been, because base 256 and 288 aren't. Base 128 should have been a subset of 256.)
	- When writing the alphabets for v2, rather than copying the v1 alphabets verbatim, I made an incorrect assumptions about 128's logical structure. The difference can be very subtle - especially since 128 is an even power of 2. Which means some binary encodings might be off by only a single character.
	- Step 1: Carefully compare the alphabet strings for v1, v1b, and v2. (Just paste all three on three lines in a doc, do `eyeball diff`.)
	- Result: compared v2 against the bundled v1b for all 128 values. v2 `128v1compat` and `128jc1` are byte-for-byte identical to v1b's, and the test.bash v1 cross-check passes. Cannot substantiate a discrepancy without the original v1 (not v1b) alphabet, and altering the alphabet now would break the verified v1b compatibility. Needs the original v1 reference to proceed.
