<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Base naming and aliases, rationalized

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [The problem](#the-problem)
- [Rules](#rules)
- [Rename table](#rename-table)
- [Breaking-change accounting](#breaking-change-accounting)
- [Additional problems to fix](#additional-problems-to-fix)
- [Implementation checklist](#implementation-checklist)

<!-- /TOC -->

## The problem

Base names and aliases grew organically and are inconsistent on several axes at once: word-radix order (`mayan20` vs `30rock`), capitalization (`Crockford`, `basE91`, `PostScript` vs everything else), when a bare number is a name, which alias comes second, and how many aliases a base carries. (Some have way to many which makes thing harder not easier.)

Each new base addition reopened all of these questions, and caused design and interface churn. This doc defines a policy, so that future churn is reduced or eliminated.

## Rules

1. **Lowercase, always**. Every name and alias is lowercase ASCII. Lookup was already case-insensitive, so caps were pure display, and display caps meant a fresh judgment call per base (`ZBase32`? `basE91`? `ArabicIndic`?). Zero caps means zero future judgment calls. Proper-noun respect (Crockford, Mayan) lives in README prose, not in identifiers.

2. **Radix first**. A qualified name is `<radix><qualifier>`: `10cjk`, `20mayan`, `64emoji`, `69nice`, `85ps`, `2048llfourn`. The radix is the family, the qualifier is the variant, and every name sorts and tab-completes by family.

	Two exceptions only:

	- Established published names keep their own spelling as an alias, never reordered: `z85`, `zbase32`, `ascii85`, `newbase60`, `base91`, `pluscode`. A proper name is not a systematic name.

	- Pure words with no radix are allowed as the memorable alias when unambiguous registry-wide: `hex`, `dozenal`, `crockford`, `mayan`, `hostname`, `email`, `keyboard`, `nice`.

	- *Note: `30rock` needs no exception: it is already radix-first, and the joke requires that order. `69nice` also lands in this order: someone says "69", you say "nice" (because you are 12)*.

3. **A bare number means "what you'd assume"**. A bare radix is a name only when the alphabet is the one a reasonable person means by "base N": the 0-9 A-Z a-z extension order (2, 3, ... 24, 30, 36, 42, 62), the universally assumed set (10, 16, 26, 52), or the sole published base of that size (45 = RFC 9285, 91 = basE91, 98).

	Where a radix is genuinely contested among published variants - 32 and 64 (RFC 4648 defines two of each), 60, 85, 2048 and up - no variant gets the bare number as its display name; every variant carries a qualifier. Consequences:

	- The `h` ("hex-style") suffix becomes redundant on bare-number bases, since bare now implies hex-style by rule. All the `12h`/`16h`/`20h`/`24h`/`36h`/`42h`/`62h`/`30h` aliases go away. The suffix survives, spelled out, exactly where the hex-style variant could not take the bare number: `32hex` and `64hex`.

	- Bare `32` and `64` keep resolving (v1/v1b scripts pass them, and both legacy tools accepted them), but as last-position aliases pointing where they always pointed (the RFC alphabets). They disappear from the display name and the README. Resolving is a compatibility promise; advertising is a choice.

4. **Fixed alias template, in this order, four slots max**:

	1. Canonical systematic name
	2. The memorable name - what the README "First alias" column will show
	3. An ergonomic short form, only if it is a legacy or previously shipped spelling
	4. Legacy contract names, always last.

	Skip empty slots. A base with no memorable name has one alias and a blank README column.

5. **The memorable slot prefers, in order**:

	1. The standard's citation (`rfc4648s6`, `rfc9285`, `rfc1924`)
	2. The published proper name (`crockford`, `zbase32`, `z85`, `ascii85`, `base91`, `newbase60`, `pluscode`)
	3. The purpose word (`hex`, `dozenal`, `hostname`, `keyboard`)

	Short and well-known beats long and official: `hex` not `hexadecimal`, `dozenal` not `duodecimal`, `alphanum` not `alphanumeric`.

6. **RFC citations are `rfc<number>[s<section>]`**.

	- When the RFC defines several: `rfc4648s4`, `rfc4648s5`, `rfc4648s6`, `rfc4648s7`.
	- One per RFC otherwise, e.g.: `rfc9285`, `rfc1924`.

7. **A name never changes meaning**. A rename either keeps the old spelling resolving to the same alphabet (as a trailing alias) or retires it to a loud unknown-base error with suggestions. No spelling is ever silently re-pointed at a different alphabet. Legacy contract names ("required" comments in bases.go, enforced by test) are permanent.

8. **Jokes live in descriptions, not aliases**. `venti`, `nerd`, `bestagon`, `TheUltimateAnswer` go away; the README prose can still tell the joke. Exception: a base whose name is the point keeps it as its identity (`30rock`, `69nice`, `42`'s `answer`).

The `tt` family and every compatibility base are untouched, per standing constraints. `bytes` is a mode, not a named base, and stays as-is.

## Rename table

Order within each row is the final alias order. Names in the Dropped column stop resolving (unknown-base error with suggestions; see Breaking below).

| Now | Proposed | Dropped |
|---|---|---|
| 2 | 2 | |
| 3, ternary | 3, ternary | |
| 4, quarternary | 4, quaternary | quarternary (typo) |
| 5, quinary | 5, quinary | |
| 6, senary, seximal, bestagon | 6, senary | seximal, bestagon |
| 7, septenary | 7, septenary | |
| 8, octal, oct | 8, octal | oct |
| 9, nonary | 9, nonary | |
| 10, decimal, dec, arabic | 10, decimal | dec, arabic |
| cjk10, CJK | 10cjk, cjk | |
| hindi10, Hindi | 10hindi, devanagari | hindi10, bare hindi |
| arabicindic10, ArabicIndic | 10arabicindic, easternarabic | |
| rods10, rods | 10rods, rods | |
| blocks10, blocks | 10blocks, blocks | |
| 12, dozenal, 12h, duodecimal | 12, dozenal | 12h, duodecimal |
| 16, hex, 16h, 16hex, hexadecimal, nerd | 16, hex | 16h, 16hex, hexadecimal, nerd |
| 20, vigesimal, 20h, venti | 20, vigesimal | 20h, venti |
| 20ws, wordsafe20, 20w, google20, 20g | 20ws, pluscode | wordsafe20, 20w, google20, 20g |
| mayan20, Mayan | 20mayan, mayan | |
| 24, 24h | 24 | 24h |
| 26, alphabet, alpha | 26, alphabet | alpha |
| 30rock, 30h | 30rock, 30 | 30h |
| 32, RFC4648s6, 32r, 32rfc, 32rfc4648s6 | 32rfc, rfc4648s6, 32r, 32 | 32rfc4648s6 |
| 32h, RFC4648s7, 32rfc4648s7, 32tt | 32hex, rfc4648s7, 32tt, 32h | 32rfc4648s7 |
| 32crock, Crockford, 32c, 32crockford | 32crock, crockford, 32c | 32crockford |
| 32ws, 32wordsafe, 32w, 32google, 32g | 32ws, 32wordsafe, 32w | 32google, 32g |
| 32zbase, ZBase32, 32z | 32z, zbase32 | 32zbase |
| 36, alphanum, alphanumeric, 36h | 36, alphanum | alphanumeric, 36h |
| 38hostname, hostname, 38jc1 | 38hostname, hostname, 38jc1 | |
| 39username, username, 39un | 39username, username | 39un (not a legacy spelling; v1b used 39us/39jc1, which v2 never honored) |
| 42, TheUltimateAnswer, 42h | 42, answer | TheUltimateAnswer, 42h |
| 45, RFC9285, 45rfc9285, 45r | 45, rfc9285 | 45rfc9285, 45r (45r was never a legacy spelling; neither legacy tool had RFC base-45) |
| 45email, email, 45jc1 | 45email, email, 45jc1 | |
| 52, upperlower | 52, upperlower | |
| Sumerian, sexagesimal, Babylonian, hexagesimal, 60jc | 60jc, sexagesimal | sumerian, babylonian, hexagesimal |
| 60tc, NewBase60 | 60tc, newbase60 | |
| 62, 62h | 62 | 62h |
| 64, rfc4648s4, 64r, 64rfc, 64rfc4648s4 | 64rfc, rfc4648s4, 64r, 64 | 64rfc4648s4 |
| 64u, rfc4648s5, 64url, 64ru, 64rfc4648s5 | 64url, rfc4648s5, 64u | 64ru, 64rfc4648s5 |
| 64h, 64hu, 64hurl | 64hex, 64h | 64hu, 64hurl |
| 64code, programmer, 64p, 64j1u | 64code, programmer, 64j1u | 64p |
| emoji64 | 64emoji | emoji64 |
| 64tt | 64tt | |
| nice69 | 69nice, nice | nice69 |
| emoji69 | 69emoji | emoji69 |
| 85z, z85, 85zeromq | 85z, z85 | 85zeromq |
| PostScript, 85postscript, 85ps, 85adobe | 85ps, ascii85 | postscript, 85postscript, 85adobe |
| 85ipv6, 85rfc1924, 85elz | 85ipv6, rfc1924 | 85rfc1924, 85elz |
| 91hk, basE91 | 91hk, base91 | (same key: basE91 already registers as 91 after the base-prefix strip, so 91, b91, base91 all resolve, before and after) |
| keyboard, 98, text, ascii, kbd | 98keyboard, keyboard, 98 | text, ascii (misleading: the base is not ASCII exactly), kbd |
| 128tt | 128tt | |
| bytes | bytes | |
| 256tt / 512tt / 1024tt / 2048tt | unchanged | |
| 2048twitter, 2048x, 2048qntm | 2048qntm, 2048twitter | 2048x |
| 2048rust, 2048llfourn | 2048llfourn | 2048rust |
| 32768qntm, 32768utf16 | 32768qntm, 32768utf16 | |
| 65536qntm, 65536utf32 | 65536qntm, 65536utf32 | |
| all *_compat_v1[b] bases | unchanged | |

Notes:

- **Bare 32 and 64 demoted, not removed**. They keep resolving to the RFC alphabets (v1/v1b scripts pass them bare) but stop being display names. Full removal was considered (matching the 65536 precedent) and rejected: both legacy tools accepted the bare spellings, so removal breaks the v1-scripts-keep-working promise, and unlike 65536 there is no silent-meaning-change risk since they point where they always did.

- **2048qntm becomes the canonical, 2048twitter the alias**. Both 2048s target Twitter, so "twitter" cannot disambiguate them; author/implementation is the only axis that does, and it matches the settled siblings 32768qntm and 65536qntm. The README column still shows 2048twitter, which is the better "what is this for" answer.

- **nice69/emoji69 flip to 69nice/69emoji**. Radix-first consistency. The pure alias `nice` keeps the joke one keystroke away, and "69, nice" arguably tells it better.

- **keyboard becomes 98keyboard**. Matches 38hostname/39username/45email. The word `keyboard` stays as the memorable alias, so nothing gets harder to type.

- **hindi10 becomes 10hindi with devanagari as the shown name**. Devanagari is the script (also Marathi, Nepali); Hindi is a language. The canonical stays short, the shown name becomes precise.

- **Seximal and bestagon die**. Both have real nerd-culture currency, but the alias list is not the place; the README row for base 6 can name-drop them.

- **45 keeps the bare number** even though 45email shares the radix, because only one base-45 is a standard and the other is in-house. This is the boundary of the "contested radix" rule: contested means multiple published variants, not multiple registry rows.

## Breaking-change accounting

Retiring a spelling produces the existing unknown-base error with did-you-mean suggestions, which already handles this well (all the dropped `N h`/`Nrfc...` forms prefix-match their survivors). This batch rides v2.1.0, which is already a breaking release with base-name removals in the changelog (65536, binary/bin, the word-safe set). Renamed canonicals that shipped in v2.0.0 keep their old spelling as a trailing alias wherever that spelling appears in the table's Proposed column; the rest were introduced after v2.0.0 and were never released.

## Additional problems to fix

- **test.bash legacy maps are stale**: V1_MAP and V1B_MAP invoke v2 as `code64`, but the bases rework renamed it to `64code`. A fresh run with the legacy binaries present fails the cross-check. (The dogfooded binary predates the rename, which is why this has not surfaced.) Fix regardless of this proposal.

- **`64r` is an unmarked contract name**. Both legacy scripts accept `"64r"*` exactly as they accept `"32r"*`, but only 32r carries the "required, don't delete" comment. 64r should be marked the same.

- **The base-prefix strip applies at registration too**, so an alias spelled `base91` registers under the key `91`. Worth a comment in registry.go; it is load-bearing for the 91 row above.

- **`quarternary` is a typo** for quaternary.

- v1b matched base names by prefix glob (`"45em"*`), so v1b users could type many spellings. v2 honors one curated spelling per legacy base and that stays the policy; happily, most proposed canonicals (64rfc, 64url, 64hex, 32hex, 32crock, 32ws) are themselves valid under those old globs.

## Status

Implemented 20260730 on branch `names`, merged to dev. All checklist items below are done; the harness passes at 356 checks including both legacy cross-check suites.

Later change, 20260803: `2048tt` was removed. The table below still records what its name was at the time of this pass, which is what the pass decided; it is no longer a base.

## Implementation checklist

- bases.go: alias arrays per the table, comment updates (required-alias notes for 64r and the demoted bare 32/64), quaternary typo.

- test.bash: fix `code64` to `64code` in both maps; move map v2-side names to the new canonicals; re-derive any scraped name lists (they come from the binary, so mostly automatic).

- README: regenerate the bases table from the binary; switch the aliases column to the single "First alias" column; sweep prose for renamed spellings.

- main.go `--examples`, cicd/demo-scenario.toml, default-config.shcl comments: sweep for renamed spellings (32wordsafe survives, so the demo scenario is likely untouched).

- changelog: list every retired spelling under the v2.1.0 breaking notes.
