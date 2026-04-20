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
# convert-base-v2

A cross-platform CLI program written in Go, that:

- Converts a number to and from any arbitrary base.

- The number can be arbitrarily large.

- Supports negative and floating-point numbers in any base.

	- And the ability to define alternate symbols for "negative" and "decimal", if the regular ones clash with symbols in the base.

- There are dozens of predefined named bases to specify as input or output.

- You can define your own arbitrary base and alphabet, just by providing the alphabet.

	- E.g.: "`a 0 c X 🫪 だ`" is a perfectly valid, functional base-6 for some reason.

- Supports streaming encoding to and from binary input/output.

	- In other words, it can do what `basenc` can do, and also in O(N) linear time. (Which is unlike its regular base conversion operation, which necessarily works in O(N^2) quadradic time.)

	- But since this is first and foremost a _base converter_ and not an _encoder/decoder_, it's not as fast as `basenc`. The only benefit over `basenc` is that it can encode/decode to/from any arbitrary base that's a power of 2. `basenc` can "only" handle three bases (plus three variations).

- Accepts data from the command line, and/or from `stdin` (e.g. piped data).

- Why convert a number to a large base? There are myriad useful technical reasons, that would otherwise require chaining together a series of standard tools. Or, that would require using a web-based tool in a way that can't be scripted.

	- As a trivial example, let's say you want to manually generate "serial numbers" now and then for physical, real-world use. You need, say, at most minute-level precision to insure uniqueness. But you need short, human-readable, unambiguous characters rather than a long date or number.

		You could use POSIX time (the number of seconds since 1970), divided by 60 for shorter minute-level precision, then convert that integer to Bitcoin's original base-58 "readable" scheme. For example, "2026-01-01 @ 12:15 PM" could be represented as "1fLcL4" in standard base-64url, or "£±Яᛯ" in base-256.

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
- [Example output](#example-output)
- [List of bases and their alphabet tokens](#list-of-bases-and-their-alphabet-tokens)
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

## Example output

The chart below shows a big random base 10 number '0000000000000001' in various bases.

<!--
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
-->

## List of bases and their alphabet tokens

Any number of any size can be converted to and from any of these bases. Most support negative numbers and decimals, if the intention makes sense.

(_About missing base alphabets: they exist in the program, just not in this doc yet._)

| Base  | Name [arg]           | Aliases                                               | Description                      | Specification | Alphabet [or at least first and last 64 tokens]
| --:   | :--                  | :--                                                   | :--                             | :--           | :---
| 2     | 2                    | binary, bike                                          | Text ones and zeros              |               | 01
| 3     | 3                    | ternary, trike                                        | Rarely used in computers         |               | 012
| 4     | 4                    | quarternary, quad                                     |                                  |               | 0123
| 5     | 5                    | quinary, stuiver                                      |                                  |               | 01234
| 6     | 6                    | senary, seximal, bestagon                             |                                  |               | 012345
| 7     | 7                    | septenary                                             |                                  |               | 0123456
| 8     | 8                    | octal, oct, octopus                                   | Older base for programming       |               | 01234567
| 9     | 9                    | nonary, non                                           |                                  |               | 012345678
| 10    | 10                   | decimal, dec, arabic, dime                            |                                  |               | 0123456789
| 10    | kanji                | 10kanji, japan, nippon, 日本                           |                                 |                | 〇一二三四五六七八九
| 10    | hanzi                | 10hanzi, china, zhōngguó, 中国                         |                                 |                | 零一二三四五六七八九
| 10    | hindi                | 10hindi, india, hārat, भारत                            |                                  |               | 0१२३४५६७८९
| 10    | arabicindic          | 10arabicindic, 10easternarabic, easternarabic         |                                  |               | ٠١٢٣٤٥٦٧٨٩
| 10    | rods                 | 10rods                                                |                                  |               | 〇𝍠𝍡𝍢𝍣𝍤𝍥𝍦𝍧𝍨
| 12    | 12                   | 12hex, 12h, dozenal, duodecimal                       |                                  |               | 0123456789AB
| 16    | 16                   | 16hex, 16h, hex, hexadecimal, nerdnumber, onepounder  |                                  |               | 0123456789ABCDEF
| 20    | 20                   | 20hex, 20h, vigesimal, venti                          |                                  |               | 0123456789ABCDEFGHIJ
| 20    | 20wordsafe           | 20ws, 20w, 20google, 20g, 20nofks                     |                                  |               | 23456789CFGHJMPQRVWX
| 20    | mayan                | 20maya                                                |                                  |               | 𝋠𝋡𝋢𝋣𝋤𝋥𝋦𝋧𝋨𝋩𝋪𝋫𝋬𝋭𝋮𝋯𝋰𝋱𝋲𝋳
| 24    | 24                   | 24hex, 24h                                            |                                  |               | 0123456789ABCDEFGHIJKLMN
| 26    | 26                   | alphabet                                              |                                  |               |
| 30    | 30rock               | 30hex, 30h, 30                                        |                                  |               |
| 32    | 32                   | 32hex, 32h, triacontakaidecimal, theonetrue32         |                                  |               |
| 32    | 32rfc                | 32r                                                   |                                  |               |
| 32    | crockford            | 32crockford, 32crock, 32c                             |                                  |               |
| 32    | 32wordsafe           | 32ws, 32w, 32google, 32g, 32nofks                     |                                  |               |
| 32    | zbase32              | 32zbase, 32z                                          |                                  |               |
| 32    | 32bip                | 32bitcoin, 32btc, 32segwit, bech32, bech32m           |                                  |               |
| 36    | 36                   | 36hex, 36h                                            |                                  |               |
| 38    | hostname             | 38hostname, 38jc                                      |                                  |               |
| 39    | username             | 39username, 39jc                                      |                                  |               |
| 42    | 42                   | 42hex, 42h                                            |                                  |               |
| 45    | email                | 45email, 45jc                                         |                                  |               |
| 48    | 48                   | 48hex, 48h                                            |                                  |               |
| 48    | 48wordsafe           | 48w, 48ws, 48jcws, 48nofks                            |                                  |               |
| 48    | 48v1compat           | 48j1                                                  |                                  |               |
| 52    | 52                   | upperlower                                            |                                  |               |
| 58    | 58bitcoin            | 58btc                                                 |                                  |               |
| 60    | 60jc                 | sexagesimal, hexagesimal                              |                                  |               |
| 60    | 60tc                 | newbase60                                             |                                  |               |
| 62    | 62                   | 62hex, 62h                                            |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
| 64    | 64hex                | 64hexurl, 64hexu, 64hu                                | Tightest binary-to-text encoding for UTF-8 (Lunix, macOS, Windows). |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_
| 64    | 64jc                 | 64p, 64j1u                                            |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzʞλ
| 64    | 64rfc                | 64r                                                   |                                  |               | ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
| 64    | 64rfcurl             | 64rfcu, 64ru                                          |                                  |               | ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_
| 64    | 64wordsafe           | 64ws, 64w, 64jcws, 64nofks                            |                                  |               | 23456789CFGHJMPQRVWXcfghjmpqrvwxʞλμᛎᛏᛘᛯᛝᛦᛨᚠᚧᚬᚼ🜣🜥🜿🝅▵▸▿◂҂‡±⁑÷∞≈≠ΩƱ
| 64    | 64v1compat           | 64j1uw                                                |                                  |               |
| 69    | 69pshihn             |                                                       |                                  |               | ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/-*<>\|
| 85    | z85                  | 85z, 85zeromq                                         |                                  |               |
| 85    | postscript           | 85adobe, 85postscript, 85ps                           |                                  |               |
| 85    | 85ipv6               | 85rfc1924, 85aprilfools, 85fools, 85elz               |                                  |               |
| 91    | 91hk                 | 91bas                                                 |                                  |               |
| 128   | 128jc                | 128p                                                  |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzʞλμᛎᛏᛘᛯᛝᛦᛨᚠᚧᚬᚼ🜣🜥🜿🝅▵▸▿◂҂‡±⁑÷∞≈≠ΩƱΞψϠδϟЋЖЯѢф¢£¥§¿ɤʬ⍤⍩⌲⍋⍒⍢ÂĈÊĜĤÎĴÔŜÛŴ
| 128   | 128v1compat          | 128j1                                                 |                                  |               |
| 256   | 256jc                | 256p, 256j1                                           |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzʞλ ...to... óŕśúẃýźĀĒĪŌŪȲāēīōūȳǍČĎĚǦȞǨŇǑŘŠǓǎčďěǧȟǩňǒřšǔǝɹʇʌ₸᛬웃유ㅈㅊㅍㅎㅱㅸㅠソッゞぅぇォ
| 256   | binary               | bin, bytes, raw                                       |                                  |               |
| 288   | 288jc                | 288p, 288j1                                           |                                  |               | 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzʞλ ...to... čďěǧȟǩňǒřšǔǝɹʇʌ₸᛬웃유ㅈㅊㅍㅎㅱㅸㅠソッゞぅぇォゲサじすスせちづでネビべぺまモゟヲ½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞
| 2048  | 2048twitter          | 2048x, 2048qntm                                       |                                  |               | 89ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzÆÐØÞßæðøþĐ ...to... ྈྉྊྋྌကခဂဃငစဆဇဈဉညဋဌဍဎဏတထဒဓနပဖဗဘမယရလဝသဟဠအဢဣဤဥဧဨဩဪဿ၀၁၂၃၄၅၆၇၈၉ၐၑၒၓၔၕ
| 2048  | 2048rust             | 2048llfourn                                           | Tightest binary-to-text encoding for Twitter. |               | ØµºÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿ ...to... ႫႬႭႮႯႰႱႲႳႴႵႶႷႸႹႺႻႼႽႾႿჀჁჂჃჄჅაბგდევზთიკლმნოპჟრსტუფქღყშჩცძწჭხჯჰჱჲჳ྾
| 32768 | 32768qntm            | 32768utf16                                            | Tightest binary-to-text encoding for UTF-16.  |               | ҠҡҢңҤҥҦҧҨҩҪҫҬҭҮүҰұҲҳҴҵҶҷҸҹҺһҼҽҾҿԀԁԂԃԄԅԆԇԈԉԊԋԌԍԎԏԐԑԒԓԔԕԖԗԘԙԚԛԜԝԞԟ ...to... ꞀꞁꞂꞃꞄꞅꞆꞇꞈ꞉꞊ꞋꞌꞍꞎꞏꞐꞑꞒꞓꞔꞕꞖꞗꞘꞙꞚꞛꞜꞝꞞꞟꡀꡁꡂꡃꡄꡅꡆꡇꡈꡉꡊꡋꡌꡍꡎꡏꡐꡑꡒꡓꡔꡕꡖꡗꡘꡙꡚꡛꡜꡝꡞꡟ
| 65536 | 65536                | 65536qntm, 65536utf32                                 | Tightest binary-to-text encoding for UTF-32.  |               | 㐀㐁㐂㐃㐄㐅㐆㐇㐈㐉㐊㐋㐌㐍㐎㐏㐐㐑㐒㐓㐔㐕㐖㐗㐘㐙㐚㐛㐜㐝㐞㐟㐠㐡㐢㐣㐤㐥㐦㐧㐨㐩㐪㐫㐬㐭㐮㐯㐰㐱㐲㐳㐴㐵㐶㐷㐸㐹㐺㐻㐼㐽㐾㐿 ...to... 𨗀𨗁𨗂𨗃𨗄𨗅𨗆𨗇𨗈𨗉𨗊𨗋𨗌𨗍𨗎𨗏𨗐𨗑𨗒𨗓𨗔𨗕𨗖𨗗𨗘𨗙𨗚𨗛𨗜𨗝𨗞𨗟𨗠𨗡𨗢𨗣𨗤𨗥𨗦𨗧𨗨𨗩𨗪𨗫𨗬𨗭𨗮𨗯𨗰𨗱𨗲𨗳𨗴𨗵𨗶𨗷𨗸𨗹𨗺𨗻𨗼𨗽𨗾𨗿

## Document history

- 2026-04-17: First version.

## Copyright and license

> Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)<br>
> Licensed under GNU GPL v2 <https://www.gnu.org/licenses/gpl-2.0.html>. No warranty.