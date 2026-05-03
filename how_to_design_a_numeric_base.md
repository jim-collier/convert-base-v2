<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<div align="center">

![License: GPL v2](https://img.shields.io/badge/License-GPLv2-blue.svg)
![Support](https://img.shields.io/badge/Support-Maintained-brightgreen)

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
# How to design a numeric base

## General considerations

When creating a new base from scratch, you should answer a few questions, starting with the most important: Is the base intended to represent a positional notation numbering system, or a binary-to-text encoding/decoding scheme?

### Symbol selection for a positional notation numbering system

- In what contexts will the new base alphabet be rendered? For example, are Unicode characters OK?

	- All modern OSes work with UTF-8, which can display any Unicode character.

		- But it's up to the application and the font to insure that.

		- Unicode characters for pre-boot environments are a no-go. Linux systems at least, have code-paths in the early boot process that are limited to ASCII/ANSI.

	- All modern terminal applications can handle UTF-8, depending on the rendering font.

		- Legacy Windows `conhost.txt` (the legacy application for hosting `cmd.exe`), can work with UTF-8, but only if the code page is set to UTF-8 ("`chcp 65001`"), and a compatible font is used (e.g., Consolas, Cascadia Mono).

- Will the base be used in fixed-width scenarios (including a terminal)? In that case then the rendered width of each character in the base alphabet is very important. Otherwise the characters will run together and become illegible.

	- Most terminals don't deal well with Unicode characters that are visually wide. So a base should stick to "narrow" symbols. Unfortunately that usually means no emojis, for example.

- Are the resulting strings likely to be used in filesystem file or folder names? URLs? Programming contexts? Usernames, hostnames, and/or email addresses?

	- If so, you should be very careful in your selection of single-byte UTF-8 characters (e.g. ASCII), and avoid as many keyboard-typable symbols as you can - most of which are used as "reserved" characters or have special meanings in various contexts.

- Are you going for human-legibility and reduced manual transcription mistakes due to ambiguity?

	- If so, consider removing some or all of 0 and 1, as well as upper and lower-case I, J, L, O, Q, S, T, U, V, Y, Z - and anything higher that can be confused with them.

		- There are some other potential ambiguities as well (e.g. 8 and B), but at some point if you go too far, _everything_ is ambiguous and you have nothing left for an alphabet.

- Should your symbols go in ASCII/ANSI/Unicode order?

	- This isn't strictly necessary - many bases seem random.

		- But when they don't go in order, there's usually a strongly-argued reason behind it. (E.g. "reduced typing mistakes", "stronger checksum", etc.)

		- But in general, yes - they should go in code point order, especially at lower code point values where they tend to be naturally sorted better.

	- For positional notation, it's usually important to start with the base-10 symbols (`0-9`), followed in ASCII/ANSI/Unicode code point order by `A-Z` (a convention started early on by _hexadecimal_ notation), then by `a-z`.

		- These general blocks preserve code point order, but don't include symbols in-between. Most of the most widely-used bases (e.g. base 64) move some of those symbols, out of code point order, to the end of `a-z`.

			- To sort a space-delimited string by Unicode code point, run - for example: `echo "z a 中 あ A 9" | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' '`

	- You may want "exotic" symbols that are logically similar but don't appear consecutively in code point order, to be purposefully rearranged so that they appear more natural as values increase one at a time in your base. E.g. all triangles of each type, grouped together, appearing in a consistent order; then all circled number balls in order, etc. (Those examples don't actually appear in an the order you'd naturally expect, when sorted by code point.)

- Any other conventions to be aware of?

	- Unless you have a good reason not to, you should start with `0-9`, then `A-Z`, than `a-z`. Then try to stick to Unicode code point order from there. (Skipping characters as necessary.) This insures that smaller numbers up to 61, encode to what people typically "expect" of a "hexadecimal"-style base alphabet definition.

		"Hexadecimal"-style base alphabets dominate bases less than 64, and so is a strong convention and expectation to follow. (Base-64 base alphabets in particular though have some odd ducks.)

		- RFC 4648 §4 and 5 (for base 64 binary-to-text de/encoding), for example, inexplicably start with A-Z, then a-z, then 0-9. This isn't even in ASCII/ANSI code page / Unicode code point order. There is apparently no historically argued reason for this, other than "it's for de/encoding streaming binary so it doesn't matter, as long as it's agreed upon".

		Which - if true - to be fair is kind of a reasonable argument.

### Symbol selection for a binary-to-text encoding/decoding scheme

The idea here is usually to pack binary data into text as efficiently as possible.

Since the output of binary encoding usually looks essentially random, there's not as strong of an argument for starting a binary-to-text alphabet with the hex convention of `0-9A-Za-z`.

The volume of data in a binary-to-text scheme is usually too high for manual transcription, so symbol disambiguation is also usually not as important either.

Bases for binary/text conversion should ideally be a power of 2 (e.g. base 8, 16, 32, 64, 128, etc.), otherwise there's extra work, less efficiency, and more opportunity for confusion - for little or no gain.

Bases 32 and 64 are mostly solved problems. There's room at higher bases for innovation.

#### UTF-8 and base-64

UTF-8 is a variable-width encoding scheme, so higher code points consume more bytes - meaning less efficient bit-packing. In that case, staying as low in the character set as reasonable should be a key design consideration.

- __A base 64 encoding scheme, using as many traditional 1-byte Unicode characters as possible (i.e. "ASCII"), is the most efficient binary to UTF8 text encoding scheme possible__.

	- The traditional challenge has been, there's only 94 visible, printable 1-byte Unicode characters.

	- Out of those 94, most of the symbols that appear on a keyboard, should be avoided as "unsafe" for reserved characters for filesystems, URLs, etc.

	- That leaves essentially the 62 characters `0-9A-Za-z`.

		Almost all base 64 alphabets simply disagree on what order those three groups of alphanumeric symbols should go in, and what two extra "keyboard" symbols should go at the end to make the full set add up to 64.

#### UTF-16 and base-32768

Base 32768 provides optimal effciency for UTF-16 binary-to-text encoding/decoding schemes.

- Many programming languages, and the Windows API, use UTF-16.

- There's plenty of room for innovation here. but 32,768 characters is so many, that factors like "existing adoption" and "code point efficiency" are arguably far more important than "visual elegance".

#### UTF-32 and base-65536

Base 65536 is optimal for UTF-32 binary-to-text encoding/decoding schemes.

UTF-32 is rarely used for storage or interchange. It's used sometimes by code libraries, when the indexing efficiency gains of fixed-width data structures are more important than space efficiency.

## General notes on symbols that work, and that don't

These aren't "official" Unicode classifications, just some general notes and ideas to help you get started, from lower in the Unicode code point.

### OK symbols for an alphabet a little over base 256

Abbreviations:

- BMP: "Basic Multilingual Plane"

The symbols below are narrow enough to fit in a monospace display, and aren't _too_ high in the Unicode symbol set. Some are reordered to make more sense for a positional notation numbering system - for example:

- Rather than a bunch of "A"-like characters one after another, variations are listed in approximate alphabetic order.

- Things like numbered balls are ordered correctly - 0 to 9 or 10 to 9, rather than sometimes seemingly random or styles mixed together.

This should not be considered a cononical list! There are practically uncountable Unicode characters that could work. And especially for binary-to-text encoding/decoding in UTF-8, you should strive to exhaust all 2-byte characters first.

| General categories          | Unicode block                     | Bytes | Characters                                             | Best
| :--                         | :--                               |   --: | :--                                                    | :--
| Extended latin ("EL")       | BMP, U+0000–U+FFFF                | 2     | ¢£¥§±µ¿÷Ʊɤʬ                                            | Too visually wide: ©®¶·ºðƍɸɷʊʭ
| EL - Circumflex             | (multiple)                        | 2*    | ÂĈÊĜĤÎĴÔŜÛŴŶẐâĉêĝĥîĵôŝûŵŷẑ                             | * Ẑẑ are 3-bytes wide.
| EL - Tilde                  | (multiple)                        | 2*    | ÃẼĨÑÕŨỸãẽĩñõũỹ                                         | * Ẽẽ Ỹỹ are 3-bytes wide.
| EL - Diaeresis              | (multiple)                        | 2*    | ÄËÏÖÜẄẌŸäëḧïöẗüẅẍÿ                                     | * ẄẌḧẗẅẍ are 3-bytes wide; Ḧ is visually too wide.
| EL - Diaeresis and macron   | Latin Ext-B                       | 2     | ǟȫǖ
| EL - Acute                  | (multiple)                        | 2*    | ÁĆÉǴÍĹŃÓŔŚÚẂÝŹáćéǵíḱĺńóŕśúẃýź                          | * Ẃḱẃ are 3-bytes wide; not used: ḰḾḿ
| EL - Double acute           | Latin Ext-A                       | 2     | ŐőŰű
| EL - Macron                 | (multiple)                        | 2*    | ĀĪĒŌŪȲāēḡīōūȳ                                          | * ḡ is 3-bytes wide; Ḡ is too visually wide.
| EL - Caron                  | Latin Ext-A, Latin Ext-B          | 2     | ǍČĎĚǦȞǏǨĽŇǑŘŠŤǓǎčďěǧȟǐǩǰľňǒřšťǔ
| EL - Stroke                 | Latin Ext-A, Latin Ext-B, IPA Ext | 2     | ȺɃȻĐɆĦƗɈľɌŦɎƀȼɇđħɨɉłɍŧɏ
| EL - Hook                   | Latin Ext-B                       | 2     | Ƒƒ
| EL - Middle tilde           | Latin Ext-B, IPA Ext              | 2     | Ɵɫ
| EL - Bar                    | IPA Ext                           | 2     | ʉ
| Greek                       | Greek                             | 2     | ΞφψΩϠδλμϟ
| Cyrillic                    | Cyrillic, Armenian                | 2     | ЋДЖЯѢѦѪѮджфяѣѧѫѯ҂ՃՊՖ                                   | Cluttered or too visually wide: ЋЖЯѢф҂
| turned                      | Latin Ext-B, IPA Ext              | 2     | Ʌɐǝʞɹʇʌʎ
| inverted                    | Latin-1 Sup, IPA Ext              | 2     | ¡¿ʁ
| Currency                    | Latin-1 Sup, Currency Symbols     | 2, 3  | ¢¥₤₸                                                   | ¢¥ 2-byte; ₤₸ 3-byte
| Misc                        | (multiple)                        | 2,3   | ⁑ ⋆ ⍣ ʉ ʬ                                              | ʉʬ 2-byte; ⁑⋆⍣ 3-byte
| Math                        | (multiple)                        | 2,3   | ≠ ≈ ‡ ± ∞ ∮                                            | ± 2-byte; ≠≈‡∞∮ 3-byte
| Fractions, in code order    | Latin-1 Sup, Number Forms         | 2,3   | ½ ⅓ ⅔ ¼ ¾ ⅕ ⅖ ⅗ ⅘ ⅙ ⅚ ⅛ ⅜ ⅝ ⅞                         | ½¼¾ 2-byte; rest 3-byte
| Fractions, small to big     | Latin-1 Sup, Number Forms         | 2,3   | ⅛ ⅙ ⅕ ¼ ⅓ ⅜ ⅖ ½ ⅗ ⅝ ⅔ ¾ ⅘ ⅚ ⅞                         | ½¼¾ 2-byte; rest 3-byte
| Digits - Arabic-Indic       | Arabic                            |  2   | ٠ ١ ٢ ٣ ٤ ٥ ٦ ٧ ٨ ٩                                    | Arabic
| Digits - Devanagari         | Devanagari                        |  3   | ० १ २ ३ ४ ५ ६ ७ ८ ९                                    | Hindi, Marathi, Nepali
| Digits - Bengali            | Bengali                           |  3   | ০ ১ ২ ৩ ৪ ৫ ৬ ৭ ৮ ৯
| Digits - Gurmukhi           | Gurmukhi                          |  3   | ੦ ੧ ੨ ੩ ੪ ੫ ੬ ੭ ੮ ੯                                    | Punjabi
| Digits - Tamil              | Tamil                             |  3   | ௦ ௧ ௨ ௩ ௪ ௫ ௬ ௭ ௮ ௯
| Digits - Telugu             | Telugu                            |  3   | ౦ ౧ ౨ ౩ ౪ ౫ ౬ ౭ ౮ ౯
| Digits - Gujarati           | Gujarati                          |  3   | ૦ ૧ ૨ ૩ ૪ ૫ ૬ ૭ ૮ ૯
| Digits - Thai               | Thai                              |  3   | ๐ ๑ ๒ ๓ ๔ ๕ ๖ ๗ ๘ ๙
| Digits - Kannada            | Kannada                           |  3   | ೦ ೧ ೨ ೩ ೪ ೫ ೬ ೭ ೮ ೯
| Digits - China/Japan/Korea  | CJK Unified                       |  3   | 〇 一 二 三 四 五 六 七 八 九                           | Non-positional traditionally
| Korean                      | Hangul Compat Jamo                | 3     | ㅈㅊㅍㅎㅠㅱㅸㅿ
| (random) Japanese           | Hiragana, Katakana                | 3     | ソッゞぅぇォゲサじすスせちづでネビべぺまミもモゟヲ
| (random) Technical          | Misc Technical                    | 3     | ⌲ ⍋ ⍒ ⍢ ⍤ ⍩
| (random) Shapes             | Geometric Shapes                  | 3     | ■ □ ▢ ▣ ▤ ▥ ▦ ▧ ▨ ▩ ▪ ▫ ▬ ▭ ▮ ▯ ▰ ▱ ▲ △ ▴ ▵ ▶ ▷ ▸ ▹ ► ▻ ▼ ▽ ▾ ▿ ◀ ◁ ◂ ◃ ◄ ◅ ◆ ◇ ◈ ◉ ◊ ○ ◌ ◍ ◎ ● ◐ ◑ ◒ ◓ ◔ ◕ ◖ ◗ ◘ ◙ ◚ ◛ ◜ ◝ ◞ ◟ ◠ ◡ ◢ ◣ ◤ ◥ ◦ ◧ ◨ ◩ ◪ ◫ ◬ ◭ ◮ ◯ ◰ ◱ ◲ ◳ ◴ ◵ ◶ ◷ ◸ ◹ ◺ ◻ ◼ ◽ ◾ ◿ | Nice: ◂ ▸ ▵ ▿
| People                      | Hangul Syllables                  | 3     | 웃 유
| Runes (that fit)            | Runic                             | 3     | ᚠ ᚤ ᚧ ᚬ ᚼ ᛎ ᛏ ᛘ ᛝ ᛦ ᛨ ᛬ ᛯ
| Alchemy (that fit)          | Alchemical Symbols                | 4     | 🜌 🜣 🜥 🜿 🝅                                           | Outside BMP
| v1 extended alphabet             | (multiple)                   | (multi) | ʞ λ μ ᛎ ᛏ ᛘ ᛯ ᛝ ᛦ ᛨ ᚠ ᚧ ᚬ ᚼ 🜣 🜥 🜿 🝅 ▵ ▸ ▿ ◂ ҂ ‡ ± ⁑ ÷ ∞ ≈ ≠ Ω Ʊ Ξ ψ Ϡ δ ϟ Ћ Ж Я Ѣ ф ¢ £ ¥ § ¿ ɤ ʬ ⍤ ⍩ ⌲ ⍋ ⍒ ⍢ Â Ĉ Ê Ĝ Ĥ Î Ĵ Ô Ŝ Û Ŵ Ŷ Ẑ â ĉ ê ĝ ĥ î ĵ ô ŝ û ŵ ŷ ẑ Ã Ẽ Ĩ Ñ Õ Ũ Ỹ ã ẽ ĩ ñ õ ũ ỹ Ä Ë Ï Ö Ü Ẅ Ẍ Ÿ ä ë ï ö ü ẅ ẍ ÿ Á Ć É Ǵ Í Ń Ó Ŕ Ś Ú Ẃ Ý Ź á ć é ǵ í ń ó ŕ ś ú ẃ ý ź Ā Ē Ī Ō Ū Ȳ ā ē ī ō ū ȳ Ǎ Č Ď Ě Ǧ Ȟ Ǩ Ň Ǒ Ř Š Ǔ ǎ č ď ě ǧ ȟ ǩ ň ǒ ř š ǔ ǝ ɹ ʇ ʌ ₸ ᛬ 웃 유 ㅈ ㅊ ㅍ ㅎ ㅱ ㅸ ㅠ ソ ッ ゞ ぅ ぇ ォ ゲ サ じ す ス せ ち づ で ネ ビ べ ぺ ま モ ゟ ヲ ½ ⅓ ⅔ ¼ ¾ ⅕ ⅖ ⅗ ⅘ ⅙ ⅚ ⅛ ⅜ ⅝ ⅞ | Not necessarily "better", just backward-compatible with v1.
| List above, sorted by code point | (multiple)                   | (multi) | ¢ £ ¥ § ± ¼ ½ ¾ ¿ Á Â Ã Ä É Ê Ë Í Î Ï Ñ Ó Ô Õ Ö Ú Û Ü Ý á â ã ä é ê ë í î ï ñ ó ô õ ö ÷ ú û ü ý ÿ Ā ā Ć ć Ĉ ĉ Č č Ď ď Ē ē Ě ě Ĝ ĝ Ĥ ĥ Ĩ ĩ Ī ī Ĵ ĵ Ń ń Ň ň Ō ō Ŕ ŕ Ř ř Ś ś Ŝ ŝ Š š Ũ ũ Ū ū Ŵ ŵ Ŷ ŷ Ÿ Ź ź Ʊ Ǎ ǎ Ǒ ǒ Ǔ ǔ ǝ Ǧ ǧ Ǩ ǩ Ǵ ǵ Ȟ ȟ Ȳ ȳ ɤ ɹ ʇ ʌ ʞ ʬ Ξ Ω δ λ μ ψ ϟ Ϡ Ћ Ж Я ф Ѣ ҂ ᚠ ᚧ ᚬ ᚼ ᛎ ᛏ ᛘ ᛝ ᛦ ᛨ ᛬ ᛯ Ẃ ẃ Ẅ ẅ Ẍ ẍ Ẑ ẑ Ẽ ẽ Ỹ ỹ ‡ ⁑ ₸ ⅓ ⅔ ⅕ ⅖ ⅗ ⅘ ⅙ ⅚ ⅛ ⅜ ⅝ ⅞ ∞ ≈ ≠ ⌲ ⍋ ⍒ ⍢ ⍤ ⍩ ▵ ▸ ▿ ◂ ぅ ぇ じ す せ ち づ で べ ぺ ま ゞ ゟ ォ ゲ サ ス ソ ッ ネ ビ モ ヲ ㅈ ㅊ ㅍ ㅎ ㅠ ㅱ ㅸ 웃 유 🜣 🜥 🜿 🝅
| v1 "word-safe" extended alphabet | (multiple)                   | (multi) | ʞ λ μ ᛎ ᛏ ᛘ ᛯ ᛝ ᛦ ᛨ ᚠ ᚧ ᚬ ᚼ 🜣 🜥 🜿 🝅 ▵ ▸ ▿ ◂ ҂ ‡ ± ⁑ ÷ ∞ ≈ ≠ Ω Ʊ Ξ ψ Ϡ δ ϟ Ћ Ж Я Ѣ ф ¢ £ ¥ § ¿ ɤ ʬ ⍤ ⍩ ⌲ ⍋ ⍒ ⍢ Â Ĉ Ê Ĝ Ĥ Ĵ Ŝ Ŵ Ŷ â ĉ ê ĝ ĥ ĵ ŝ ŵ ŷ Ã Ẽ Ñ Ỹ ã ẽ ñ ỹ Ä Ë Ẅ Ẍ Ÿ ä ë ẅ ẍ ÿ Á Ć É | Not necessarily "better", just backward-compatible with v1.

### Not great

| General categories          | Characters
| :--                         | :--
| Bad for filesystems         | * / : < > ? \ \|
| Bad for internet            | $ & + , / : ; = ? @
| Bad for programmers         | ! " $ % & ' ( ) * + , -  / : ; < = > ? @ [ \ ] ^ _ ` { | } ~
| Greek - Too wide, and/or ambiguous | ΔΘΛϕθϢϪπϡϣϫϖ
| Fractions - don't fit       | ↉ ⅐ ⅑ ⅒

## Supporting work

Note: The following are directory listings that typically contain a raw `.csv` file, the same data in a better-formatted Gnumeric spreadsheet, and an Excel version.

LibreOffice would have been much preferred to [Gnumeric](https://download.cnet.com/gnumeric/) (both are multi-platform open-source spreadsheets), except that for these large spreadsheets covering most or all Unicode, LibreOffice chokes too hard to use. (Even on 32 cores and 128GB RAM in 2026.) Gnumeric handles it with ease, seemingly even better than Excel.

Also, font rendering for Unicode look significantly smoother on Linux (with B&W font-smoothing with no hinting), than Excel for Windows. (Though to be fair, my version of Excel is older and still uses ClearType, with RGB subpixel hinting and overly-strong hinting.) MacOS should look great too.

Unicode listings:

- [All printable Unicode characters, ordered by block](https://github.com/jim-collier/convert-base-v2/tree/main/reference/unicode_all_grouped_by_block).

- [Nicely AI-ordered lists of printable Unicode characters <= U+1FBF9](https://github.com/jim-collier/convert-base-v2/tree/main/reference/unicode_ordered_below_U1FBF9) (i.e. directly printable in most modern fonts).

	Characters are, in many cases at higher code points, re-ordered to look nice and "expected" in a positional notation numbering system. (I.e. numbered balls grouped by type and go in order, arrows grouped by style and rotate from "north" to "northwest".

	This is a great reference to start from, for designing a large base.

## Document history

- 2026-04-17: First version.
- 2026-04-22: Added list of unicode characters used.

## Copyright and license

> Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)<br>
> Licensed under GNU GPL v2 <https://www.gnu.org/licenses/gpl-2.0.html>. No warranty.