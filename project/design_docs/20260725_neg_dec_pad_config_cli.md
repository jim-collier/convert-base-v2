<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Design 20260725: Negative, decimal, and padding symbols in config files and on the command line

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Introduction](#introduction)
- [Related to Issues, PRs](#related-to-issues-prs)
- [Requirements](#requirements)
- [Constraints](#constraints)
- [High-level solution](#high-level-solution)
	- [Why not keep the trailer tokens as an alias](#why-not-keep-the-trailer-tokens-as-an-alias)
	- [Command line shape](#command-line-shape)
- [Detailed solution](#detailed-solution)
	- [1. Symbol spec carries symbols only](#1-symbol-spec-carries-symbols-only)
	- [2. Reject the retired tokens](#2-reject-the-retired-tokens)
	- [3. Config files](#3-config-files)
	- [4. Command line flags](#4-command-line-flags)
	- [5. Optional: one convention in the Go definitions too](#5-optional-one-convention-in-the-go-definitions-too)
- [Touch points](#touch-points)
- [Compatibility](#compatibility)

<!-- /TOC -->

## Introduction

The symbols that mark negative and decimal used to live inside the base definition string itself. Design 20260503 took them out of that string for the base definitions compiled into the binary, and `bases.go` now sets them as named fields. That half is done.

The other two ways a base can be defined were left alone, so the old format is still in use:

- A config file entry can carry `neg=` and `dec=` and `pad=` tokens inside its `symbols` string.

- On the command line, tokens inside `--from-symbols` and `--to-symbols` are the only way to set a marker at all.

So one idea now has two implementations, and the surface a person actually types still has the awkward one. This document covers finishing the job.

There is a second, quieter problem. `mkSpec` parses its symbol string through the same parser but never reads the marker tokens back out, so a `neg=~` accidentally left inside a `BaseSymbols` string is parsed off and thrown away. It produces no error, no marker, and no digit.

## Related to Issues, PRs

- Issues: [#6](https://github.com/jim-collier/convert-base-v2/issues/6)

- Follows: `20260503_rethink_neg_dec_pad.md`

## Requirements

Carried forward from the previous document, unchanged and still correct:

- The markers need to be completely separate from the base symbols string.

- They need to default to the standard symbols if not specified.

- It needs to be possible to positively specify "no negative and/or decimal allowed".

Added here:

- All three ways of defining a base should use the same convention.

- A base definition written in the old format must not be accepted quietly and must not change meaning. It should say what to use instead.

- Setting a marker should not require defining a whole alphabet by hand.

## Constraints

- A marker can be absent, disabled, or set to a value. Three states, not two. Internally this is already a `*string` on `Base`, where `nil` means default, `&""` means disabled, and `&"X"` means an explicit marker. Anything added should map onto that rather than introduce a fourth idea.

- YAML gives absence for free. A missing key is absence, `negative: ""` is disabled.

- Go's `flag` package does not distinguish "flag absent" from "flag given an empty value" when the target is a plain string. Getting the third state on the command line needs a small custom flag type.

- Dropping the reserved tokens without replacing them is not safe. The tokens are currently parsed off before the digit split, so once they are no longer special, `"0 1 2 3 neg=~"` becomes a base 5 whose last digit is the literal text `neg=~`. That is silent alphabet corruption, the same failure mode as the `85ps` comma bug.

- Bases in the registry are shared pointers. Anything that overrides a marker on a named base has to work on a copy.

## High-level solution

The symbol spec means symbols, and nothing else. Markers move to named fields in config, and to named flags on the command line.

Config already has the named fields. It grew `negative:`, `decimal:`, and `pad:` some time ago and simply kept the older path working alongside them, so that side is mostly deletion.

The command line has no named fields at all, so that side is the real work.

### Why not keep the trailer tokens as an alias

Keeping both spellings is what created this. It also has a specific cost here: the parser has to keep reserving `neg=`, `dec=`, and `pad=`, which means it keeps having a magic prefix that a person defining an alphabet has to know about. Retiring them and rejecting them outright is a smaller parser, one convention, and a clear error for anyone with the old syntax in a script.

### Command line shape

Six flags, one per marker per side:

~~~text
--from-neg X   --from-dec X   --from-pad X
--to-neg   X   --to-dec   X   --to-pad   X
~~~

Symmetric on purpose. Padding really does differ by side, since on input it means strip a trailing run and on output it means pad out to the group boundary, so folding the two into one flag would be wrong.

An empty value disables: `--to-neg ''`. An absent flag leaves the base's own setting alone.

These apply to whatever base that side resolved to, whether it came from a name or from `--from-symbols`. Today a marker can only be set on a hand-written alphabet, which is an accident of where the tokens were parsed, not a decision. Being able to write `--from hex --from-neg '~'` is a plain improvement and costs nothing extra.

Comparison, current versus proposed:

~~~bash
# now
convert-base-v2 --from-symbols "aeiouy.-_0 neg=~ dec=/" --to 20w "~y0-._/ooo"

# proposed
convert-base-v2 --from-symbols "aeiouy.-_0" --from-neg '~' --from-dec '/' --to 20w "~y0-._/ooo"

# newly possible
convert-base-v2 --from hex --from-neg '~' --to 10 -- '~ff'
~~~

## Detailed solution

### 1. Symbol spec carries symbols only

`ParseSymbolSpec` stops handling `neg=`, `dec=`, and `pad=`. With the markers gone, the `SymbolSpec` struct has nothing left but its symbol list, so it goes away too and the parser returns the symbols directly. Escapes, the comma split, and the single versus multiple token rules are unaffected.

This also closes the `mkSpec` hole on its own. With no tokens to parse off, a stray marker in a `BaseSymbols` string becomes a duplicate or unexpected digit and gets caught.

### 2. Reject the retired tokens

Any token matching `neg=`, `dec=`, or `pad=` at the start is an error, naming the replacement:

~~~text
symbol spec: "neg=~" is no longer part of the symbol spec.
Use --from-neg / --to-neg on the command line, or the "negative:" field in a config file.
~~~

This check stays permanently rather than for one release. It is a few lines, and the alternative is a corrupted alphabet that looks like it worked. The cost is that those three exact strings can no longer be used as digit symbols, which is acceptable, and a config file can still express them through the list form.

### 3. Config files

Deletion, mostly.

- `configBase.toBase()` drops the branch that copies markers out of the parsed spec.

- The field comments stop describing the trailer as an option, and stop saying that the named fields override it.

- `example.conf` loses its "in-string trailer form" example. The `b8alt` entry is rewritten with `negative:` and `decimal:`.

No new config surface. The existing `negative:`, `decimal:`, `pad:`, and `pademit:` fields already cover everything the tokens did.

### 4. Command line flags

The six flags from above, backed by a small `flag.Value` type that records whether it was set. That gives absent, empty, and set, which maps directly onto the existing `*string` convention. No `Disallow` booleans on the command line, and nothing new to explain.

Applying an override, per side:

1. For a custom alphabet, set the markers on the new base *before* its first `finalize()`. They are part of the definition in that case, and an alphabet that uses `-` or `.` as digits would otherwise be rejected for colliding with a default marker it was about to replace.

1. For a named base, look it up as usual. If no override flag was given for that side, use it as is.

1. Otherwise shallow copy it, set `Negative`, `Decimal`, or `PadSymbol` and `PadEmit` from the flags, and call `finalize()` again. Copy first, because registry bases are shared. `finalize()` rebuilds every derived table from scratch, so calling it a second time is safe.

1. Set `Source` so `--help` shows that the base was modified by flags.

1. Reject the overrides for the `bytes` base. Sign and fractions are meaningless for raw bytes, and every byte value is already a digit, so there is nothing a marker could be set to.

Validation comes along for free. `finalize()` already rejects a marker that collides with a digit, a marker that appears inside a digit symbol, negative and decimal being the same, and a padding character that is also a digit.

Conflicts are reported the same way the existing selector conflicts are, as a note on stderr rather than a behavior change, matching what `--from-symbols` over `--from` does now.

### 5. Optional: one convention in the Go definitions too

`SpecOpts` could drop `NegSymbol` plus `DisallowNeg` in favor of a single `*string` set with `strPtr`, which would make all three surfaces use the identical three-state convention and remove two panic checks from `mkSpec`.

Recommended as a separate decision, not part of this change. `DisallowNeg: true` reads better in a data table than `NegSymbol: strPtr("")`, the field is internal, and the panics already cover the risk. Do it only if the "one convention everywhere" claim should be literally true.

Either way, the unused `PadSymbols` and `DisallowPad` fields should be deleted.

## Touch points

Easy to miss:

- The error messages in `resolveMarker()` and `finalize()` suggest the retired syntax, telling the reader to write `neg=X` or to disable with a bare `dec=`. They have to name the flags and config fields instead, or the tool teaches the format it just rejected.

- `--help` flag descriptions for `--from-symbols` and `--to-symbols`, and the new flags.

- The `--examples` block, which uses a trailer in one example.

- The spec report that `--help` prints when base flags are present, which prints the markers it parsed out of a spec.

Then the usual sweep: `test.bash`, `conversions_test.go`, the `fuzz_test.go` seeds, README, changelog, and the line in `design.md` describing what `symbolspec.go` parses.

## Compatibility

This is a breaking change to input syntax, for scripts using the trailer form and for existing config files.

Pre-1.0 stable is the right time to take it. Nothing breaks silently, since every old spelling produces an error that names its replacement. It goes in the changelog under a breaking heading.
