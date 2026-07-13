<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<div align="center">

![Go](https://img.shields.io/github/go-mod/go-version/jim-collier/convert-base-v2?filename=source%2Fgo.mod&logo=go&logoColor=white&label=Go)
![License: GPL v2](https://img.shields.io/badge/License-GPLv2-blue.svg)
![Lifecycle: Beta](https://img.shields.io/badge/Lifecycle-Beta-yellow)
![Support](https://img.shields.io/badge/Support-Maintained-brightgreen)
![CI](https://img.shields.io/github/actions/workflow/status/jim-collier/convert-base-v2/ci.yml?branch=main&label=CI)
![Release](https://img.shields.io/github/v/release/jim-collier/convert-base-v2?include_prereleases&label=Release)

</div>
<!--
[![!#/bin/bash](https://img.shields.io/badge/-%23!%2Fbin%2Fbash-1f425f.svg?logo=gnu-bash)](https://www.gnu.org/software/bash/)
![License: GPL v2](https://img.shields.io/badge/License-GPLv2-blue.svg)
![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Lifecycle: Alpha](https://img.shields.io/badge/Lifecycle-Alpha-orange)
![Lifecycle: Beta](https://img.shields.io/badge/Lifecycle-Beta-yellow)
![Lifecycle: RC](https://img.shields.io/badge/Lifecycle-RC-blue)
![Lifecycle: Stable](https://img.shields.io/badge/Lifecycle-Stable-brightgreen)
![Lifecycle: Deprecated](https://img.shields.io/badge/Lifecycle-Deprecated-red)
![Status: Deprecated](https://img.shields.io/badge/Status-Deprecated-orange)
![Status: Archived](https://img.shields.io/badge/Status-Archived-lightgrey)
![Lifecycle: EOL](https://img.shields.io/badge/Lifecycle-EOL-lightgrey)
![Coverage](https://img.shields.io/badge/Coverage-25%25-red)
![Coverage](https://img.shields.io/badge/Coverage-50%25-orange)
![Coverage](https://img.shields.io/badge/Coverage-75%25-yellow)
![Coverage](https://img.shields.io/badge/Coverage-90%25-brightgreen)
![Status: Passing](https://img.shields.io/badge/Status-Passing-brightgreen)
![Status: Failing](https://img.shields.io/badge/Status-Failing-red)
-->

<!-- TOC ignore:true -->
# convert-base-v2

<table style="border: none; border-collapse: collapse;">
	<tr style="border: none; border-collapse: collapse;">
		<td style="border: none; border-collapse: collapse;"><img src="https://github.com/jim-collier/convert-base-v2/blob/main/assets/mascot.png?raw=true" alt="Logo" width="320"/></td>
		<td style="border: none;">A cross-platform CLI program written in Go, to convert any number of any size, to and from any arbitrary base. Dozens of predefined named bases, or specify your own. And all the standards like base-10, 16, RFC base-64, etc.<br /><br />Supports negatives and floating-point (even for bases originally designed for binary stream encoding), and piped binary data.<br /><br />Supports binary-to-text encoding and decoding for power-of-two bases and the standard chunked codecs (base45, Ascii85, Z85, base91).</td>
	</tr style="border: none; border-collapse: collapse;">
</table>

<!--
<p align="center"><img src="assets/logo.png" alt="P" width="128"></p>
>

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Features](#features)
- [Why convert a number to a large base](#why-convert-a-number-to-a-large-base)
	- [Also why the -v2?](#also-why-the--v2)
- [Speed](#speed)
- [Complex third-party binary encode/decode algorithms](#complex-third-party-binary-encodedecode-algorithms)
- [Example output](#example-output)
- [List of predefined bases and their positional notation symbols](#list-of-predefined-bases-and-their-positional-notation-symbols)
- [How to design a numeric base](#how-to-design-a-numeric-base)
- [Document history](#document-history)
- [Copyright and license](#copyright-and-license)

<!-- /TOC -->

## Features

A universal cross-platform CLI number conversion program, written in Go, that:

- Converts any number of arbitrary size, to and from any arbitrary base.

- The number can be arbitrarily large.

- Supports negative and floating-point numbers in most bases. (Except a few for which that makes no sense.) Even bases designed only for binary-to-text encoding (RFC 4648 §4), can usually be used "off-label" for positional notation - and thus negative and fractional numbers.

	- The program supports defining alternate symbols for "negative" and "decimal", if the regular ones clash with symbols already in the base.

- There are dozens of predefined named bases to specify as input or output.

- You can define your own arbitrary base and alphabet (the set of positional notation symbols), just by providing the alphabet.

	- E.g.: "`a 0 c X 🫪 だ`" is a perfectly valid, functional base-6 (for some reason).

- Encodes and decodes binary data to and from text, for every power-of-two base (2 through 256, plus 2048, 32768, and 65536) and the standard chunked codecs base45, Ascii85, Z85, and base91. Other bases have no byte-exact mapping, so binary mode reports which bases qualify (the RAW column of `--list`) and refuses the rest.

	- In other words, it can do what `basenc` can do, also in O(N) linear time, at roughly the same speed - plus bases `basenc` never heard of, like base-2048 and base-65536.

	- To re-encode directly between two text bases as byte data (e.g. hex to base-64, the way `basenc` does), add `--binary`. Without it, two power-of-two text bases convert as a positional number instead, which drops leading zeros; a note on stderr points this out. Use `--number` to assert the numeric reading and silence the note.

		- *Regular finite positional base conversion, however, necessarily works in O(N^2) quadratic time*.

	- Binary-to-text encoding and decoding is a separate concept - and code path - than positional base translation. Only the power-of-two bases and the defined codecs have a spec for carrying raw bytes; the rest are positional-only.

- Accepts data from the command line, and/or from `stdin` (e.g. piped data).

## Why convert a number to a large base

There are myriad useful technical reasons, that would otherwise require chaining together a series of standard tools. Or, that would require using a web-based tool in a way that can't be scripted.

- As a trivial example, let's say you want to manually generate "serial numbers" now and then for physical, real-world use. You need, say, at most minute-level precision to ensure uniqueness. But you need short, human-readable, unambiguous characters rather than a long date or number.

	You could use POSIX time (the number of seconds since 1970), optionally divided by 60 for shorter minute-level precision, then convert that integer to a compact readable base.

	As another example, the whole-seconds POSIX value for "2026-01-01 @ 12:15 PM" (1767269700) could be represented as "1fLcL4" in hex-style base-64 `64h`, or "£±Яᛯ" in base-256 `256jc1`.

- The more obvious example is encoding binary data to text. Base 64 (`64r`, `64u`, `64jc1`) is the most efficient way to encode binary to UTF-8 text.

	- But even higher bases are available for niche cases - e.g. base-2048 `2048twitter`, specifically designed by qntm for Twitter; or base-65536 `65536qntm` for optimal UTF-32 binary-to-text encoding.

At larger non-standard bases that this project created (e.g. `base-256jc1`), careful effort was made to:

- Avoid ambiguous characters that look like existing 0-9 A-Z ASCII characters and symbols.

- Avoid characters that are too wide and render poorly on fixed-width terminals.

- Avoid reserved characters across multiple operating systems and web standards, so that output can be used in those contexts. (Except for predefined standard base definitions that specify such characters, e.g. regular base-64.)

- Keep the character selection consistent across bases.

### Also why the -v2?

As you've probably noticed, the command `convert-base-v2` has a version number on the end - this is, possibly as a non-answer, to distinguish it from v1.

As predicted as an eventual possibility in the v1 project (also on github), this v2 has a necessary minor break in output from v1, in one narrow edge case. And like v1, in the future there may be good reasons for the output to change again in some future v3.

- *For example, there are no "official standards" for large bases above 94 as of time of writing. But that could change. This program has dozens of large named base defitions, that could someday result in a "name collision" with some future official standard. Unlikely, but possible. So to avoid overwriting an old script on a running system that may rely on this program and its predictable, stable, fully deterministic output - a new suffix number will be given to future programs if the output changes, and the two can coexist. "-v2" is there to coexist with "-v1" (and "-v1b"), and also leaves room for the possibility of new name collisions in the future, e.g. with a "-v3"*.

## Speed

`convert-base-v2` is very fast.

Binary/text stream encoding/decoding is the most easily benchmarked (and relevant in terms of raw speed), so here are benchmarked throughput results against the standard tools - one table per format.

(You can see that `convert-base-v2` smokes the "competition" on decoding. On encoding, it's only fractionally slower - not magnitudes.)

**Base-64**

| Program | text -> binary | binary -> text |
| :-- | --: | --: |
| `convert-base-v2` | **744** | 755 |
| coreutils `base64` | 323 | 1,056 |
| coreutils `basenc` | 323 | 1,048 |
| openssl `base64` | 276 | **1,221** |

**Base-32**

| Program | text -> binary | binary -> text |
| :-- | --: | --: |
| `convert-base-v2` | **596** | 716 |
| coreutils `base32` | 400 | **855** |
| coreutils `basenc` | 376 | 851 |

**Hex**

| Program | text -> binary | binary -> text |
| :-- | --: | --: |
| `convert-base-v2` | **521** | **850** |
| `xxd` | 57 | 102 |

Numbers are MiB/s. Mean of 10 runs, one process each, all I/O in a tmpfs (RAM) so disk speed doesn't enter into it. Every program gets identical input: the same 256 MiB blob of random bytes to encode, and each format's own canonical text to decode. Each tool is single-threaded. Reproducible with `github/utility/bench-encoders.bash` (it auto-skips tools you don't have). Test bench: AMD Ryzen 9 3950X (16 cores / 32 threads, Zen 2), 128 GiB DDR4-3600.

FYI: Base-64 is statistically the most compact way to store binary data as UTF-8 text. (Which makes sense when you understand how UTF-8 encoding works.)
	- All modern OSes use UTF-8 by default.
	- But some APIs use UTF-16 internally (best is a Base 32768)
	- Other APIs use UTF-32 (best is a Base 65536).

For embedding binary data in Twitter/𝕏 posts, qntm's base-2048 is allegedly optimal.

## Complex third-party binary encode/decode algorithms

This program faithfully recreates four complex (or at least non-direct and non-trivial) binary-to-text encoding algorithms - that ordinarily require custom implementation in JS, Rust, and/or Python:

- [Base 2048](https://github.com/qntm/base2048) - [qntm](https://github.com/qntm/)'s original JS version. Allegedly the most dense possible radix specifically for encoding binary data in a Twitter/𝕏 post. Not an official standard, but "published".

- [Base 2048](https://github.com/LLFourn/rust-base2048) - [LLFourn](https://github.com/LLFourn/)'s version written in Rust. Not an official standard, but published.

- [Base 32768](https://github.com/qntm/base32768) by [qntm](https://github.com/qntm/). You normally have to run the JS just to get this base's alphabet. This radix is the most optimal binary-to-text encoding for UTF-16. Not an official standard, but "published".

- [Base 65536](https://github.com/qntm/base65536) by [qntm](https://github.com/qntm/), "Unicode's answer to Base64". (Most optimal radix for binary-to-text encoding for UTF-32. Not an official standard, but "published".)

Note: This program doesn't use any of their published open-source code - they were engineered "clean-room" style, directly from their specs. (Only because - well, Go isn't those other languages.)

## Example output

The table below shows one base-10 number, `2023090613425900000000000000001`, represented in every displayable base.

Note that some of the larger bases appear to have longer output - but that's only due to being rendered with proportional fonts, combined with double-width Unicode characters. Look at the "Chars" column to see the actual # of characters in the output.

| Base | Chars | Number representation
| :-- | --: | :--
| 2 | 101 | 11001100010001111010101010101001101101001000111010011010010010010001000110101111111100000000000000001
| 3 | 64 | 1202201120001110000211111111000012020020211210201212121022221002
| 4 | 51 | 121202033111111031221013103102102020311333200000001
| 5 | 44 | 13422100331010142033403004300000000000000001
| 6 | 39 | 524050351143055143115550221055402541345
| 7 | 36 | 522454125411321305156044543040553134
| 8 | 34 | 3142172525155107232222106577400001
| 9 | 32 | 52646043024444005206753655538832
| 10 | 31 | 2023090613425900000000000000001
| Kanji | 31 | 二〇二三〇九〇六一三四二五九〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇一
| Hanzi | 31 | 二零二三零九零六一三四二五九零零零零零零零零零零零零零零零零一
| Hindi | 31 | २०२३०९०६१३४२५९००००००००००००००००१
| ArabicIndic | 31 | ٢٠٢٣٠٩٠٦١٣٤٢٥٩٠٠٠٠٠٠٠٠٠٠٠٠٠٠٠٠١
| Rods | 31 | 𝍡〇𝍡𝍢〇𝍨〇𝍥𝍠𝍢𝍣𝍡𝍤𝍨〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇𝍠
| emoji10 | 31 | 😔😀😔😘😀🤔😀😬😑😘😜😔😠🤔😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😑
| 12 | 29 | 12888834200A750490B5219507855
| 16 | 26 | 1988F5553691D3492235FE0001
| 20 | 24 | 284DDI4C93BCC6HA00000001
| 20ws | 24 | 4C6MMW6JF5HJJ8VG22222223
| Mayan | 24 | 𝋢𝋨𝋤𝋭𝋭𝋲𝋤𝋬𝋩𝋣𝋫𝋬𝋬𝋦𝋱𝋪𝋠𝋠𝋠𝋠𝋠𝋠𝋠𝋡
| 24 | 22 | KN64BEC5EL1B0FA7K0IN2H
| 26 | 22 | DXNNAGDDUWPNKQIDYGEAMJ
| 30rock | 21 | 5O1SFD937J0RIKG5HR13B
| 32 | 21 | BTCHVKU3JDU2JEI274AAB
| 32h | 21 | 1J27LAKR93KQ948QVS001
| 32c | 21 | 1K27NAMV93MT948TZW001
| 32ws | 21 | 3X49fGcqF5cpF6Cpxr223
| 32z | 21 | bun8ikw5jdw4jre49hyyb
| 32bip | 21 | pnz8425mfr56fyg6luqqp
| 36 | 20 | 5G53VAIZAJBZ2D5Y2Y9T
| hostname | 20 | 1-4f69y3fbk6p3ra3373
| username | 20 | 17g.tz4pd-v96vag5kgz
| 42 | 19 | C9WWELMBNbCYNbYf1XB
| 45 | 19 | 3O042V/4:O66ETECKMB
| email | 19 | 3o042v[4]o66eteckmb
| 48 | 19 | 153ZUblDieUcgfg2HbH
| 48ws | 19 | 375ᛎwᛘ🜥Mᚬᛦwᛯᚠᛨᚠ4VᛘV
| 48v1compat | 19 | 153ᚼᛦ🜥⁑h҂▵ᛦ🜿▿▸▿2q🜥q
| 52 | 18 | NftxKBqjrhTdQKHAGJ
| 58btc | 18 | 38MmRfXd5dKbYUdnVe
| 60jc | 18 | 1BhkGcLkiywKrfTclg
| 60tc | 18 | 1BhkGcMkizxLsfVcmg
| 62 | 17 | gR7BplOIkweh9aKht
| 64 | 17 | ZiPVVNpHTSSI1/gAB
| 64u | 17 | ZiPVVNpHTSSI1_gAB
| 64h | 17 | PYFLLDf7JII8r_W01
| 64jc1 | 17 | PYFLLDf7JII8rλW01
| 64w | 17 | mμQffMᛨ9XWWC◂Ʊʞ23
| 64v1compat | 17 | hʞMXXHᛝ7VRR8▸≠w01
| emoji64 | 17 | 😙😢😏😕😕😍😩😇😓😒😒😈😵😿😠😀😁
| 69prsh | 17 | Ht2KiYhQQD8K*hSqv
| 85ps | 16 | 8.Q79^?7nOXr.!"J
| 85z | 16 | ndMmoZum[KT@d01F
| 85ipv6 | 16 | NDmMOzUM@kt{D01f
| 91hk | 16 | Id1{DPXs1>wM2:=:
| keyboard | 16 | 2'hT;7pK%*rS\\YyP
| 128jc1 | 15 | 6nFg҂ɤH£▿aZlĜ01
| 128w | 15 | 8🝅Qᚠ⍋ûVî⍩ᛏᛎ🜥ã23
| 128v1compat | 15 | 6🜥Mᛦ⍩ÑQŵʬμλᚼä01
| 256jc1 | 13 | Pĵㅍ‡sĨǍᚧYrぇ01
| 288jc1 | 13 | 6zф⅖ẄÃЋゲㅎぇúkᛎ
| 2048twitter | 10 | BМཔટਲੴफɱྈ9
| 2048rust | 10 | ÀɈႎஈଦଽਆƗႫµ
| 32768qntm | 7 | ⇢䓪秉㓚䫈鉜ҡ
| 65536qntm | 7 | 㐙𠻵訶𡟓縢櫾㐁

## List of predefined bases and their positional notation symbols

Any number of any size can be converted to and from any of these bases. Most support negative numbers and decimals, if the intention makes sense.

You can define your own arbitrary base of any size >1. These are just all of the common, standard, and/or published ones - plus a number of [well-thought-through](how_to_design_a_numeric_base.md) custom bases (of debatable varying utility).

| Base  | Name [arg]           | Aliases                                               | Description                      | Specification | Symbol alphabet [or at least first and last 64 tokens]
| --:   | :--                  | :--                                                   | :--                             | :--           | :---
| 2     | 2                    | deux                                                  | Text ones and zeros              |               | 01
| 3     | 3                    | ternary, tern                                         | Rarely used in computers         |               | 012
| 4     | 4                    | quarternary, quart                                   |                                  |               | 0123
| 5     | 5                    | quinary, quin                                         |                                  |               | 01234
| 6     | 6                    | senary, seximal, bestagon                             |                                  |               | 012345
| 7     | 7                    | septenary                                             |                                  |               | 0123456
| 8     | 8                    | octal, oct                                            | Older base for programming       |               | 01234567
| 9     | 9                    | nonary                                                |                                  |               | 012345678
| 10    | 10                   | decimal, dec, arabic                                  |                                  |               | 0123456789
| 10    | Kanji                | 10kanji, Japan, Nippon, 日本                           |                                 |                | 〇一二三四五六七八九
| 10    | Hanzi                | 10hanzi, China, Zhōngguó, 中国                         |                                 |                | 零一二三四五六七八九
| 10    | Hindi                | 10hindi, India, Hārat, भारत                            |                                  |               | ०१२३४५६७८९
| 10    | ArabicIndic          | 10arabicindic, 10easternarabic, EasternArabic         |                                  |               | ٠١٢٣٤٥٦٧٨٩
| 10    | Rods                 | 10rods                                                |                                  |               | 〇𝍠𝍡𝍢𝍣𝍤𝍥𝍦𝍧𝍨
| 10    | emoji10              |                                                       | Base-10 in emoji (neg 🥕, dec ⚽) |               | 😀😑😔😘😜😠😬😮🙄🤔
| 12    | 12                   | 12h, 12hex, dozenal, duodecimal                       |                                  |               | 0123456789AB
| 16    | 16                   | 16h, 16hex, hex, hexadecimal, NerdNumber, OnePounder  |                                  |               | 0123456789ABCDEF
| 20    | 20                   | 20h, 20hex, vigesimal, venti                          |                                  |               | 0123456789ABCDEFGHIJ
| 20    | 20ws                 | 20wordsafe, 20google, 20g, 20nofks, 20w               |                                  |               | 23456789CFGHJMPQRVWX
| 20    | Mayan                | 20mayan                                               |                                  |               | 𝋠𝋡𝋢𝋣𝋤𝋥𝋦𝋧𝋨𝋩𝋪𝋫𝋬𝋭𝋮𝋯𝋰𝋱𝋲𝋳
| 24    | 24                   | 24h, 24hex                                            |                                  |               | 0123456789ABCDEFGHIJKLMN
| 26    | 26                   | alphabet, alpha                                       |                                  |               | ABCDEFGHIJKLMNOPQRSTUVWXYZ
| 30    | 30rock               | 30h, 30hex                                            |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRST
| 32    | 32h                  | 32hex, 32rfc4648s7, RFC4648s7, TheOneTrue32           |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUV
| 32    | 32                   | 32r, 32rfc, 32rfc4648s6, RFC4648s6                    |                                  |               | ABCDEFGHIJKLMNOPQRSTUVWXYZ234567
| 32    | 32c                  | 32crock, 32crockford, Crockford                       | Decodes O as 0, I/L as 1         |               | 0123456789ABCDEFGHJKMNPQRSTVWXYZ
| 32    | 32ws                 | 32wordsafe, 32google, 32g, 32nofks, 32w               |                                  |               | 23456789CFGHJMPQRVWXcfghjmpqrvwx
| 32    | 32z                  | 32zbase, ZBase32                                      |                                  |               | ybndrfg8ejkmcpqxot1uwisza345h769
| 32    | 32bip                | 32btc, 32bitcoin, 32segwit, Bech32, Bech32m           |                                  |               | qpzry9x8gf2tvdw0s3jn54khce6mua7l
| 36    | 36                   | 36h, 36hex, alphanum, alphanumeric                    |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ
| 38    | hostname             | 38hostname, 38jc1                                     |                                  |               | 0123456789abcdefghijklmnopqrstuvwxyz-.
| 39    | username             | 39username, 39jc1                                     |                                  |               | 0123456789abcdefghijklmnopqrstuvwxyz-_.
| 42    | 42                   | 42h, 42hex, TheUltimateAnswer                         |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef
| 45    | 45rfc9285            | 45r                                                   | RFC 9285, space is a symbol
| 45    | email                | 45email, 45jc1                                        |                                  |               | 0123456789abcdefghijklmnopqrstuvwxyz-_%+.:@[]
| 48    | 48                   | 48h, 48hex                                            |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijkl
| 48    | 48ws                 | 48WordSafe, 48jc1ws, 48nofks, 48w                     |                                  |               | 23456789CFGHJMPQRVWXcfghjmpqrvwxʞλμᛎᛏᛘᛯᛝᛦᛨᚠᚧᚬᚼ🜣
| 48    | 48v1compat           | 48depr, 48j1                                          |                                  |               | 0123456789CFGHJMPQRVWXcfghjmpqrvwxʞλμᛎᛏᛘᛯᛝᛦᛨᚠᚧᚬ
| 52    | 52                   | upperlower                                            |                                  |               | ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
| 58    | 58btc                | 58bitcoin                                             |                                  |               | 123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
| 60    | 60jc                 | 60jc1, sexagesimal, hexagesimal                       |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYabcdefghijklmnopqrstuvwxy
| 60    | 60tc                 | newbase60                                             |                                  |               | 0123456789ABCDEFGHJKLMNPQRSTUVWXYZ_abcdefghijkmnopqrstuvwxyz
| 62    | 62                   | 62h, 62hex                                            |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
| 64    | 64h                  | 64hex, 64hexurl, 64hu                                 | Tightest binary-to-text encoding for UTF-8 (Linux, macOS, Windows). | | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_
| 64    | 64jc1                | 64j1u                                                 | Almost tightest binary-to-text encoding for UTF-8.                  | | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzʞλ
| 64    | 64                   | 64r, 64rfc, 64rfc4648s4, rfc4648s4                    | Tied for tightest binary-to-text encoding for UTF-8.                         | | ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
| 64    | 64u                  | 64url, 64ru, 64rfc4648s5, rfc4648s5                   |                                  |               | ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_
| 64    | 64w                  | 64ws, 64wordsafe, 64jc1ws, 64nofks                    |                                  |               | 23456789CFGHJMPQRVWXcfghjmpqrvwxʞλμᛎᛏᛘᛯᛝᛦᛨᚠᚧᚬᚼ🜣🜥🜿🝅▵▸▿◂҂‡±⁑÷∞≈≠ΩƱ
| 64    | 64v1compat           | 64depr, 64j1uw                                        |                                  |               | 0123456789CFGHJMPQRVWXcfghjmpqrvwxʞλμᛎᛏᛘᛯᛝᛦᛨᚠᚧᚬᚼ🜣🜥🜿🝅▵▸▿◂҂‡±⁑÷∞≈≠
| 64    | emoji64              |                                                       | Emoji faces (U+1F600..1F63F); also encodes binary. |     | 😀😁😂😃😄😅😆😇😈😉😊😋😌😍😎😏😐😑😒😓😔😕😖😗😘😙😚😛😜😝😞😟😠😡😢😣😤😥😦😧😨😩😪😫😬😭😮😯😰😱😲😳😴😵😶😷😸😹😺😻😼😽😾😿
| 69    | 69prsh               | 69pshihn                                              |                                  |               | ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/-*<>\|
| 85    | 85z                  | z85, 85zeromq                                         |                                  |               | 0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?&<>()[]{}@%$#
| 85    | 85ps                 | 85postscript, 85adobe, postscript                     |                                  |               | !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_\`abcdefghijklmnopqrstu
| 85    | 85ipv6               | 85rfc1924, 85aprilfools, 85fools, 85elz               |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_\`{\|}~
| 91    | 91hk                 | 91bas                                                 |                                  |               | ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&()*+,./:;<=>?@[]^_\`{\|}~"
| 98    | keyboard             | 98, text, ascii, kbd                                  | Any plain-text document is valid input as-is. |      | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz\t\n\r !"#$%&'()*+,-./:;<=>?@[\\]^_\`{\|}~
| 128   | 128jc1               |                                                       |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzʞλμᛎᛏᛘᛯᛝᛦᛨᚠᚧᚬᚼ🜣🜥🜿🝅▵▸▿◂҂‡±⁑÷∞≈≠ΩƱΞψϠδϟЋЖЯѢф¢£¥§¿ɤʬ⍤⍩⌲⍋⍒⍢ÂĈÊĜĤÎĴÔŜÛŴ
| 128   | 128v1compat          | 128depr                                               |                                  |               | 0123456789CFGHJMPQRVWXcfghjmpqrvwxʞλμᛎᛏᛘᛯᛝᛦᛨᚠᚧᚬᚼ🜣🜥🜿🝅▵▸▿◂҂‡±⁑÷∞≈≠ΩƱΞψϠδϟЋЖЯѢф¢£¥§¿ɤʬ⍤⍩⌲⍋⍒⍢ÂĈÊĜĤĴŜŴŶâĉêĝĥĵŝŵŷÃẼÑỸãẽñỹÄËẄẌŸäëẅẍÿÁĆÉ
| 256   | 256jc1               | 256j1                                                 |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzʞλ ...to... óŕśúẃýźĀĒĪŌŪȲāēīōūȳǍČĎĚǦȞǨŇǑŘŠǓǎčďěǧȟǩňǒřšǔǝɹʇʌ₸᛬웃유ㅈㅊㅍㅎㅱㅸㅠソッゞぅぇォ
| 256   | bytes                |                                                       |                                  |               | (256 raw bytes, 0x00–0xFF)
| 288   | 288jc1               | 288j1                                                 |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzʞλ ...to... čďěǧȟǩňǒřšǔǝɹʇʌ₸᛬웃유ㅈㅊㅍㅎㅱㅸㅠソッゞぅぇォゲサじすスせちづでネビべぺまモゟヲ½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞
| 2048  | 2048twitter          | 2048x, 2048qntm                                       |                                  |               | 89ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzÆÐØÞßæðøþĐ ...to... ྈྉྊྋྌကခဂဃငစဆဇဈဉညဋဌဍဎဏတထဒဓနပဖဗဘမယရလဝသဟဠအဢဣဤဥဧဨဩဪဿ၀၁၂၃၄၅၆၇၈၉ၐၑၒၓၔၕ
| 2048  | 2048rust             | 2048llfourn                                           | Tightest binary-to-text encoding for Twitter. |               | ØµºÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿ ...to... ႫႬႭႮႯႰႱႲႳႴႵႶႷႸႹႺႻႼႽႾႿჀჁჂჃჄჅაბგდევზთიკლმნოპჟრსტუფქღყშჩცძწჭხჯჰჱჲჳ྾
| 32768 | 32768qntm            | 32768utf16                                            | Tightest binary-to-text encoding for UTF-16.  |               | ҠҡҢңҤҥҦҧҨҩҪҫҬҭҮүҰұҲҳҴҵҶҷҸҹҺһҼҽҾҿԀԁԂԃԄԅԆԇԈԉԊԋԌԍԎԏԐԑԒԓԔԕԖԗԘԙԚԛԜԝԞԟ ...to... ꞀꞁꞂꞃꞄꞅꞆꞇꞈ꞉꞊ꞋꞌꞍꞎꞏꞐꞑꞒꞓꞔꞕꞖꞗꞘꞙꞚꞛꞜꞝꞞꞟꡀꡁꡂꡃꡄꡅꡆꡇꡈꡉꡊꡋꡌꡍꡎꡏꡐꡑꡒꡓꡔꡕꡖꡗꡘꡙꡚꡛꡜꡝꡞꡟ
| 65536 | 65536                | 65536qntm, 65536utf32                                 | Tightest binary-to-text encoding for UTF-32.  |               | 㐀㐁㐂㐃㐄㐅㐆㐇㐈㐉㐊㐋㐌㐍㐎㐏㐐㐑㐒㐓㐔㐕㐖㐗㐘㐙㐚㐛㐜㐝㐞㐟㐠㐡㐢㐣㐤㐥㐦㐧㐨㐩㐪㐫㐬㐭㐮㐯㐰㐱㐲㐳㐴㐵㐶㐷㐸㐹㐺㐻㐼㐽㐾㐿 ...to... [encoded but not printable by non-dedicated fonts]

## How to design a numeric base

[This document](how_to_design_a_numeric_base.md) (in this repo) describes how to design a good numeric base - either as a positional notation system, and/or as a binary-to-text codec. It's not as easy as you might think. (Hence all the whacky bases as "official standards".)

## Document history

- 2026-06-06:
	- Updates to reflect program updates.
	- Removed some unnecessary sections.
	- Updated base lists.
- 2026-05-03:
	- Fixed incorrect lifecycle and status badges.
	- Minor corrections.
- 2026-04-22: Added list of unicode characters used.
- 2026-04-17: First version.

## Copyright and license

> Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)<br />
> Licensed under GNU GPL v2 <https://www.gnu.org/licenses/gpl-2.0.html>. No warranty.
