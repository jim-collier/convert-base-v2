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

### Bugs

- 🔘 Backwards compatible base '128v1compat' has a subtly incorrect alphabet difinition. (github #1)
	- The base definition for '128j1' in v1 is - annoyingly - a "word-safe" version.
		- (I can't remember if that was intentional. It shouldn't have been, because base 256 and 288 aren't. Base 128 should have been a subset of 256.)
	- When writing the alphabets for v2, rather than copying the v1 alphabets verbatim, I made an incorrect assumptions about 128's logical structure. The difference can be very subtle - especially since 128 is an even power of 2. Which means some binary encodings might be off by only a single character.
	- Step 1: Carefully compare the alphabet strings for v1, v1b, and v2. (Just paste all three on three lines in a doc, do `eyeball diff`.)

- 🔘 Piped stdin is silently ignored when a positional argument is given. (code review BxZNl-1)
	- `echo 255 | convert-base-v2 16` treats 16 as the number, never reads the pipe, and prints 16 with exit 0.
	- The help synopsis shows `something | convert-base-v2 [flags] [OUTBASE]`, so the documented form gives plausible wrong output silently.
	- Either treat a lone positional as OUTBASE when stdin is a pipe, or error on the ambiguity, and fix the synopsis.

- 🔘 Custom alphabets that are not prefix-free decode to the wrong value. (code review BxZNl-2)
	- A base-12 defined the obvious way, with digits "10" and "11", round-trips 12 back as 10 with no error.
	- Symbol validation never checks decodability, and tokenizing is greedy longest-match.
	- Reject prefix-ambiguous symbol sets at definition time, naming the two conflicting symbols.

- 🔘 A marker character inside a multi-char digit symbol breaks parsing. (code review BxZNl-3)
	- A digit like "a.b" with the default "." marker gets split into integer and fraction parts, so its value silently changes and round trips corrupt.
	- A digit like "a-b" with the "-" marker errors out entirely, so the base cannot read its own output.
	- Same root cause both ways: markers are found in the raw string before tokenization, and the collision check only catches exact digit matches.

- 🔘 A read error during streaming encode is treated as end of input: truncated output, exit 0. (code review BxZNl-4)
	- Streaming decode already handles this correctly; encode just stops on any error and finishes the tail as if the stream ended.

- 🔘 The documented \t and \n escapes in symbol specs do not work. (code review BxZNl-5)
	- The escape becomes real whitespace before the spec splits on whitespace, so the symbol silently vanishes and the base is one digit smaller than intended.
	- `neg=\t` collapses to a bare `neg=`, silently disabling the sign marker.

- 🔘 Decode strictness depends on the input channel. (code review BxZNl-6)
	- Piped decode accepts "=" padding anywhere in the input; the same string as an argument is correctly rejected.
	- Line-wrapped base64 decodes fine from a pipe but errors as an argument.
	- base91 decode skips every unknown byte, so corrupt input decodes to garbage with exit 0, while every other codec errors.

- 🔘 Fractional output truncates instead of rounding. (code review BxZNl-7)
	- 0.1 to hex and back comes out 0.0999...9. Rounding the last emitted digit would make simple round trips stable.
	- Separate from the already-planned precision clamp, and worth doing in the same pass.

- 🔘 A fraction smaller than the output precision prints as "0.000", or worse "-0.000". (code review BxZNl-8)

- 🔘 Version stamping is broken twice over. (code review BxZNl-9)
	- The Makefile's version injection does nothing because `version` is a const, and the linker only patches vars. Silent no-op, every build reports the hardcoded string.
	- Meanwhile the const still says v1.1.0-beta5 and no v1.1.0 tag exists, so nothing anywhere reports the released version.

- 🔘 Config bases that override a builtin leave the registry misleading. (code review BxZNl-10)
	- The shadowed builtin keeps its `--list` row, still advertising aliases that now resolve to the new base.
	- `--get-index-count` grows, and `--by-index` can return a name that resolves to a different base than the index it came from.

- 🔘 A typo'd `--config` path is silently ignored. (code review BxZNl-11)
	- Missing-is-OK is right for the default /etc and XDG paths, wrong when the user typed the path: their custom bases silently vanish and later errors blame the base name.

- 🔘 The integer-alias sanity check is easy to bypass. (code review BxZNl-12)
	- Only the first integer alias is checked, so aliases ["3", "99"] on a 3-symbol base register "99" as a working name.
	- The check runs on the raw alias but registration uses the normalized name, so "b99" sneaks through too.

- 🔘 Documented comma-split in multi-token symbol specs is not implemented. (code review BxZNl-13)
	- The doc's own example "0,1 2 3" is described as 4 digits but parses as 3, one of them the literal symbol "0,1".

- 🔘 A YAML `pad: ""` cannot disable a pad set in the symbols trailer, though the docs say explicit fields win. (code review BxZNl-14)
	- Also, config-defined pads are always emit-mode; there is no way to define accept-but-do-not-emit padding like the builtin URL variants have.

- 🔘 A literal U+FFFE in a symbol spec silently becomes a space digit. (code review BxZNl-15)
	- It collides with the internal escape placeholder. Rejecting it up front with a clear error is enough.

### New features and enhancements

- 🔘 `--show-symbols` should list with no delimiters. (Currently lists with newline in between each.) #1n4xq9d

- 🔘 Add Crockford's decode aliases (O reads as 0, I and L as 1) to 32c, or note the limitation. (code review BxZNl-21)

- 🔘 Allow any base to be prefaced with "base", "base-", or "base_", and still work. (github #8)

- 🔘 Better error messages for the four most common stumbles. (code review BxZNl-16)
	- Flags after the number: "unexpected extra positional argument: --lower" should say flags come first.
	- Negative numbers without `--`: a bare "flag provided but not defined: -123" with no hint about the `--` separator, on a headline feature.
	- Unknown flag: no pointer to --help.
	- Unknown base: no pointer to --list and no near-match suggestion, with 66 bases behind non-obvious naming rules.

- 🔘 Error or warn when inputs conflict instead of silently picking one. (code review BxZNl-17)
	- `--to` beats a positional OUTBASE, and `--from-symbols` beats `--from`, both silently. Classic script-mistake masking.

- 🔘 Send --help and --examples to stdout when explicitly requested. (code review BxZNl-18)
	- `--help | less` currently shows nothing. Keep stderr for the no-args error path.

- 🔘 Give --list an index column, and warn when --by-index is passed outside query mode. (code review BxZNl-19)
	- --by-index is defined as "position in the --list order", but --list never shows indexes; and during a normal conversion --by-index is silently ignored.

- 🔘 Decide the padding story for the 32hex and 64url variants. (code review BxZNl-20)
	- RFC 4648 defaults to mandatory padding for those sections too, and Go's stdlib decoders reject the current unpadded output.
	- Options: flip them to padded, add padded sibling aliases, or document the deviation. The output-stability policy argues against a silent flip.

- 🔘 Real Go tests, so `make test` stops being a vacuous green. (code review BxZNl-22)
	- There are zero Test functions, benchmarks only, so `go test` gates nothing for ~3300 lines of conversion logic.
	- Port the codec and big-base vectors already in test.bash, add table-driven cases for sign, fractions, markers, multi-char symbols, and the spec parser.
	- Highest value: a streaming-vs-buffered equivalence test over random blobs, since the two paths must match byte-for-byte and are only ever tested against themselves.

- 🔘 Close the test.bash blind spots. (code review BxZNl-23)
	- Round-trip fuzz cannot catch a bug mirrored in encode and decode; one pinned known-value vector per base closes that hole cheaply.
	- No fractional, config-file, or symbol-spec coverage; the fixed 85ps escape bug has no regression pin.
	- The --list scrape passes vacuously if the table format ever changes; assert minimum counts after scraping.
	- The v1 cross-check silently skips when the v1 binary is missing; say SKIPPED loudly.

- 🔘 Some hosted or hook-based CI gate. (code review BxZNl-24)
	- Known and deliberate gap, but worth restating: nothing runs unless cicd.bash is run by hand, and bare `go test` proves nothing until BxZNl-22 lands.

- 🔘 Fold the buffered and streaming binary paths together, or pin them with equivalence tests. (code review BxZNl-25)
	- Two hand-tuned implementations of the same encodings must agree byte-for-byte, and every encoding change is a two-place fix today. BxZNl-6 is this debt already biting.

- 🔘 Docs accuracy sweep. (code review BxZNl-26)
	- README bases table is stale: the "32"/"32h" alphabets are swapped, and about two dozen listed aliases do not resolve. Regenerate it from --list. (The old "binary" row that misdocumented the raw-bytes base is fixed - it is now the `bytes` row.)
	- --examples ships a command that errors: bare "2048" is not a base name.
	- The README serial-number example labels 64h output as 64u and never does the divide-by-60 it describes.
	- The 85ps row of the example-output table predates the alphabet fix; every other row still matches.
	- example.conf says a colliding default marker is "silently disabled"; the program deliberately errors. The pad: field is undocumented there.
	- The UTF byte-count table in how_to_design_a_numeric_base.md has wrong UTF-8/UTF-16 columns, in both copies; the changelog has 2025/2026 year typos.

### Done

#### Done - Bugs

#### Done - New features and enhancements

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

### Canceled
