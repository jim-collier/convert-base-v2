<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<div align="center">

![Go](https://img.shields.io/badge/Go-00ADD8?logo=go&logoColor=white)
![License: GPL v2](https://img.shields.io/badge/License-GPLv2-blue.svg)
![Lifecycle: RC](https://img.shields.io/badge/Lifecycle-RC-blue)
![Support](https://img.shields.io/badge/Support-Maintained-brightgreen)
![Status: Failing](https://img.shields.io/badge/Status-Failing-red)

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
# convert-base-v1

Converts arbitrarily large numbers between most common predefined standard, and large custom bases - up to base-288.

Why convert a number to a large base? Mostly, to represent it in a more compact form. For example, converting a large number from base-10 to base-128, can be represented in about half the number of characters.

For example, POSIX time (the number of seconds since 1970) can be used as a "unique" serial value, in a shorter form. For example, "2026-01-01 @ 12:15 PM" could be represented as "1fLcL4" in standard base-64url, or "£±Яᛯ" in base-256.

At larger non-standard bases that we invented, careful effort was made to:

- Avoid ambiguous characters that look like existing 0-9 A-Z ASCII characters and symbols.

- Avoid characters that are too wide and render poorly on fixed-width terminals.

- Avoid reserved characters across multiple operating systems and web standards, so that output can be used in those contexts. (Except for predefined standard base definitions that specify such characters, e.g. regular base-64.)

- Keep the character selection consistent across bases.

_Note: The command `convert-base-v2` has a version number on the end, to distinguish it from v1, which as predicted in that project, this v2 has a necessary minor break from in output, in one narrow edge case. And like v1, in the future there may be good reasons for the output to change again in a v3. For example, there are no "official standards" for large bases above 94 as of time of writing, but that could change. So to avoid overwriting an old script on a running system that may rely on it and it's predictable output, a new suffix number will be given to future programs if the output changes, and the two will coexist. That the existing version has a number, indicates that expected inevitability now._

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Status](#status)
- [Limitations](#limitations)
	- [Streaming binary conversion](#streaming-binary-conversion)
- [Input bases](#input-bases)
- [Output bases](#output-bases)
- [Example output](#example-output)
- [Document history](#document-history)
- [Copyright and license](#copyright-and-license)

<!-- /TOC -->

## Status

- [v1.0.0-rc1](https://github.com/jim-collier/convert-base-v2/releases/tag/v1.0.0-rc1) works fine for almost everything, except for:

	- Streaming binary conversions: This is a rare edge use-case for a number-converter application, that you have to go out of your way to do and have a good reason.

		The v1 of this tool didn't even support this and isn't an inherent mode of most "base converters". When data is not aligned on byte boundaries, silent data loss will result.

	- Floating-point: Another rare edge use-case. For decimal places less than 50, the result will get stretched out to 50 places. Sometimes with inherent floating-point imprecision. There is no loss of data to the original value, there's just "hallucinated" precision that wasn't there before. Future versions will limit precision to what was given. Most uses of base converters are for integers.

- Latest commit as of 2026-04-18:

	- Streaming binary conversions:  The streaming conversion bug has been fixed - now it purposely errors to protect potential data integrity. A future fix will pad with placeholders if not byte-aligned.

	- Floating-point: The precision hallucination bug still exists, but still doesn't affect integer conversions, which is the most common use-case for this.

## Limitations

### Streaming binary conversion

Although support for streaming conversion of binary data was added in this compiled v2 release (vs no such thing in the scripted v1 release), "binary encoding/decoding" is not really something that is expected of base converters.

It was really a matter of a "why not" feature, while already adding support for piping input and output. (Which v1 also didn't have.)

But for day-to-day streaming binary conversion, `basenc` is at least 4x faster than this anyway, and has a much longer track-record.

Furthermore, base-64 - which `basenc` supports - is statistically the most compact way to store binary data as UTF-8 text. It might seem strange, but not even qntm's base-65536 (which this program has a named setting for) can beat the space density specifically for UTF-8 encoding. All modern OSes use UTF-8 by default. (For Twitter/𝕏, qntm's base-2048 allegedly optimally encodes binary data. Which this program also has a named setting for.)

The only good reason for using this program for streaming binary conversion, is for bases that no other program supports. (Such as aforementioned bases 2048, 65536 - as well as specialty byte-aligned bases such as the myriad variations of base 32 this supports. Or your own custom 2^N base alphabet.) But until a future fix is put in place, it will gracefully error, if the input is not byte-aligned.

## Input bases


## Output bases

This is a partial list carried over from `convert-base-v1`. This new version has at least double by default, and also accepts arbitrary base input and output alphabets, separately.

| Base        | Description                                                 | Characters                        | Reference
|:---         |:---                                                         |:---                               |:---
| 2           | aka Binary                                                  | 0,1
| 8           | aka Octal                                                   | 0-7
| 10          | aka Decimal [default]                                       | 0-9
| 16          | aka Hexadecimal                                             | 0-9, A-F
| 26          | One-case alphabetic                                         | A-Z
| 32[r]       | RFC 4648                                                    | A-Z, 2-7                          | https://en.wikipedia.org/wiki/Base32
| 32h         | RFC 4648 §7, 'Base32Hex'                                    | 0-9, A-V                          | https://datatracker.ietf.org/doc/html/rfc4648#section-7
| 32w         | Wordsafe Base32                                             | 2-9, CFGHJMPQRVWX, cfghjmpqrvwx   | https://en.wikipedia.org/wiki/Base32#Word-safe_alphabet
| 32c         | Crockford's Base32                                          | 0-9, A-Z no I, L, O, U            | https://en.wikipedia.org/wiki/Base32#Crockford's_Base32
| 36          | Just alphanum                                               | 0-9, A-Z                          | https://en.wikipedia.org/wiki/Base36
| 38username  | Valid *nix username characters
| 38hostname  | Valid *nix host and domain name characters
| 48j1        | 0-9, cfghjmpqrvwx, and lots of Unicode symbols
| 52          | Both-case alphabetic                                        | A-Z, a-z
| 62          | All alphanum                                                | 0-9, A-Z, a-z                     | https://en.wikipedia.org/wiki/Base62
| 64[r]       | RFC 4648                                                    | 0-9, A-Z, a-z, +, /               | https://en.wikipedia.org/wiki/Base64
| 64u         | RFC 4648 §5; URL-safe                                       | 0-9, A-Z, a-z, -, _               | https://en.wikipedia.org/wiki/Base64#Variants_summary_table
| 64j1u       | Alternate to 64u but also programmer-friendly               | 0-9, A-Z, a-z, ʞ, λ
| 64j1uw      | Like 48j1 but with upper-case alpha too
| 128[j1]     | Like 64j1u but with way more Unicode symbols
| 256[j1]     | Base 62 (all alphanum), and lots of Unicode chars
| 288[j1]     | 256j1 with 32 more Unicode chars
<!--
| 94[ascii]   | All lower ASCII chars + space (all typeable US keyboard)
-->

## Example output

The chart below shows a big random base 10 number '2023090613425900000000000000001' in various bases.

Note that some of the larger bases appear to have longer output - but that's only due to being rendered with proportional fonts, combined with some of the wider Unicode characters. Look at the "Chars" column to see the actual # of characters in the output.

This is a partial list carried over from `convert-base-v1`. This new version has at least double just that are hard-coded.

|Base        | Chars | Number representation
|:--         | --:   | :--
|   2        |   101 | 11001100010001111010101010101001101101001000111010011010010010010001000110101111111100000000000000001
|   8        |    34 | 3142172525155107232222106577400001
|  10        |    31 | __2023090613425900000000000000001__
|  16        |    26 | 1988F5553691D3492235FE0001
|  26        |    22 | DXNNAGDDUWPNKQIDYGEAMJ
|  32[r]     |    21 | BTCHVKU3JDU2JEI274AAB
|  32h       |    21 | 1J27LAKR93KQ948QVS001
|  32c       |    21 | 1K27NAMV93MT948TZW001
|  32w       |    21 | 3X49fGcqF5cpF6Cpxr223
|  36        |    20 | 5G53VAIZAJBZ2D5Y2Y9T
|  48j1      |    19 | 153ᚼᛦ🜥⁑h҂▵ᛦ🜿▿▸▿2q🜥q
|  52        |    18 | NftxKBqjrhTdQKHAGJ
|  62        |    17 | gR7BplOIkweh9aKht
|  64[r]     |    17 | PYFLLDf7JII8r/W01
|  64u       |    17 | PYFLLDf7JII8r_W01
|  64j1u     |    17 | PYFLLDf7JII8rʞW01
|  64j1uw    |    17 | hλMXXHᛝ7VRR8▸≠w01
|  94[ascii] |    16 | %+(A}'O^UwzN_{sS
| 128[j1]    |    15 | 6🜥Mᛦ⍩ÑQŵʬμʞᚼä01
| 256[j1]    |    13 | Pĵㅍ‡sĨǍᚧYrぇ01
| 288[j1]    |    13 | 6zф⅖ẄÃЋゲㅎぇúkᛎ

## Document history

- 2026-04-17: First version.

## Copyright and license

> Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)<br>
> Licensed under GNU GPL v2 <https://www.gnu.org/licenses/gpl-2.0.html>. No warranty.