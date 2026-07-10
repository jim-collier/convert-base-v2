<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<div align="center">

![License: GPL v2](https://img.shields.io/badge/License-GPLv2-blue.svg)

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

Note: Although "character", "symbol", and "glyph" have subtly different meanings in some contexts, they are used mostly interchangeably in this document without contextual ambiguity. However, words that are distinctly _not_ interchangeable, are "character" and "byte". That equality started disappearing in the early 1990s, and was gone completely by the early 00s. ...And wasn't even technically valid before the late 80s, when ASCII was 7-bit. (So was really only ever a "thing" for maybe a couple or few decades in human history.) Unfortunately there are still some straggler utilities across OSes that fail to make that distinction.

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [General considerations](#general-considerations)
	- [Printable character counts for each UTF byte range](#printable-character-counts-for-each-utf-byte-range)
	- [Positional notation numbering system](#positional-notation-numbering-system)
		- [What's the use context](#whats-the-use-context)
		- [Reserved symbols](#reserved-symbols)
		- [Legibility and ambiguity](#legibility-and-ambiguity)
		- [Value order vs list sorting order](#value-order-vs-list-sorting-order)
		- [Existing conventions and standards](#existing-conventions-and-standards)
		- [OS and application support](#os-and-application-support)
		- [TrueType and OpenType limitations](#truetype-and-opentype-limitations)
		- [Terminal emulators](#terminal-emulators)
		- [Monospace text editors](#monospace-text-editors)
	- [Binary-to-text encoding/decoding scheme](#binary-to-text-encodingdecoding-scheme)
		- [UTF-8 and base-64](#utf-8-and-base-64)
		- [UTF-16 and base-32768](#utf-16-and-base-32768)
		- [UTF-32 and base-65536](#utf-32-and-base-65536)
		- [General NON-concerns for binary-to-text encoding](#general-non-concerns-for-binary-to-text-encoding)
	- [Printable character counts for each UTF byte range](#printable-character-counts-for-each-utf-byte-range)
- [Guidelines on what to avoid during symbol selection](#guidelines-on-what-to-avoid-during-symbol-selection)
	- [Class 1; things that break either system](#class-1-things-that-break-either-system)
	- [Class 2; things that make a positional notation numbering system hard to read and use](#class-2-things-that-make-a-positional-notation-numbering-system-hard-to-read-and-use)
	- [Class 3; general confusion for a positional notation numbering system](#class-3-general-confusion-for-a-positional-notation-numbering-system)
- [Document history](#document-history)
- [Copyright and license](#copyright-and-license)

<!-- /TOC -->

## General considerations

When creating a new base from scratch, you start by answering a few questions - beginning with the most important: Are you going for a _positional notation numbering system_, or a _binary-to-text encoding/decoding scheme_?

- _Or both? They can generally be used interchangeably - if not necessarily very optimally - even if not the original intent._

### Printable character counts for each UTF byte range

Especially for binary-to-text encoding/decoding schemes, the idea is usually to be as efficient as possible for a given Unicode encoding scheme. For UTF-8 and UTF-16, that means packing as many <= 2-byte symbols into the base alphabet as possible. (But for positional notation number systems, the UTF-8 character byte count is usually irrelevant.)

You only have 95 printable 1-byte characters, and 33 are potentially problematic symbols that are "reserved" in various contexts (e.g. filesystem name delimiter "/", ":", or "\"). So for anything over about base-64 more-or-less, you have to accept that eventually you'll have to start eating into the 2-byte UTF-8 range. (And 1-byte symbols save you nothing in UTF-16, other than a tiny % more headroom for more 2-byte symbols before eating into the 4-byte (surrogate-pair) range for very large bases.)

| Byte count | UTF-8 bitmask                       | Mathly max count | Actual usable character count <sup>1</sup> | UTF-8 bytes | UTF-16 bytes | Comments
| --:        | :--                                  | --:              | --:                                        | --:         | --:          | :--
| 1          | 0xxxxxxx                             | 128              | 95                                         | 1           | 2            | 62 printable if you subtract all "keyboard" symbols used as reserved symbols in various contexts.
| 2          | 110xxxxx-10xxxxxx                    | 2,048            | 1,166                                      | 2           | 2            |
| 3          | 1110xxxx-10xxxxxx-10xxxxxx           | 65,536           | 51,600                                     | 3           | 2            |
| 4          | 11110xxx-10xxxxxx-10xxxxxx-10xxxxxx  | 2,097,152        | 90,764                                     | 4           | 4            | Unicode caps at U+10FFFF for UTF-16 surrogate pair scheme compatibility, so the mathly max is actually 1,114,112.

<sup>*</sup> _Footnote: "Actual usable character count" excludes non-printing control characters, ranges reserved for private use, combining marks, and RTL or "right-to-left" symbols. And the U+10FFFF cap._

Other modern text encoding schemes are usually subsets or supersets of a UTF scheme. (E.g. GB18030, a Chinese standard, a UTF-8 superset.)

### Positional notation numbering system

Such a thing is, by it's nature, meant to be _readable by, and useful to, humans_.

This automatically implies a few things:

- Need symbols that are legible and reasonably unambiguous.

- General human aesthetics become important. Ancient humans loved their Eyes Horus and/or moons in their numbering systems. Lots of moons.

- Symbols should be available in most fonts, if you don't have exact control over font selection.

- Lists should ideally be sortable in codepoint order, congruent with increasing numeric value.

- If values below 36 (in base-10) are not uncommon, you should really start with `0-9` then `A-Z`. (And `a-z` after that.) That way, a decimal value of "8", for example, will display as "8" in your base. And decimal "15" will display as "F", which is second-nature to hexadecimal users. And so on.

	- On the other hand, if you are specifically going for novelty, then skipping well beyond `0-9A-Za-z` - and starting somewhere in the 2-byte UTF-8 range - might be called for.

More specifically...

#### What's the use context

In what contexts will the new base alphabet be rendered? For example, are Unicode characters OK? Are frequently "reserved" ASCII keyboard-typable symbols OK?

#### Reserved symbols

Are the symbols in your base likely to be considered "reserved" by OSes for filesystem paths? URLs? Programming contexts? Usernames, hostnames, and/or email addresses?

- If so, you should be very careful in your selection of single-byte UTF-8 characters (aka legacy "ASCII"), and avoid as many keyboard-typable symbols as you can - most or all of which are considered "reserved" characters or have special meanings in countless contexts. (Why is that? Because all printable ASCII characters are on most keyboards, and various applications often need one or more special delimiters or meaningful identifier symbols that humans can physically type, that aren't alphanumeric. Unfortunately no one has universally agreed on a limited set of such reserved symbols - so they have all been, are, or will someday eventually be "reserved".)

	- If your base is just slightly higher than 62, then using two UTF-8 bytes instead of one for the symbols beyond `0-9A-Za-z` - but just for a small % of the characters - is usually a trivial and acceptable price to pay, for all but guaranteeing collision avoidance with various "reserved" symbols.

		- And for positional notation specifically, it's usually no price at all - since usually no one is counting storage bytes. Symbol count, yes; bytes consumed, no. So do yourself a favor and consider not even thinking about ASCII characters that aren't `0-9A-Za-z`.

			> The only reason we have so many weird "established" bases that try to duck and dodge reserved ASCII symbols for various use-cases, is because ASCII used to be all there was - and they were (usually application-specific) binary-to-text encoding schemes, not general positional notation numbering systems.

	- If your base is very large, then it will be dominated by 2-byte and possibly even 3- and 4-byte symbols anyway. In that case, again, losing a comparatively tiny % of 1-byte symbols, may be a trivial cost.

	> _Well into the 21st century now, the safest approach is generally just to not use any ASCII keyboard symbols in a positional notation numbering system at all- and stick to the 62 upper and lower-case alphanumeric symbols to start with. Then reach into the 2-, 3-, and even 4-byte UTF-8 range for additional symbols. Or for novelty, don't use any 1-byte UTF-8 symbols at all._

#### Legibility and ambiguity

Are you going for human-legibility and reduced manual transcription mistakes due to ambiguity? For a positional notation numbering system, the answer is almost certainly "yes". (Unless you are specifically going for a "light layer of obfuscation".)

- If so, consider removing symbols that can be confused with the "sacred" decimal digits. Notably, 0 and 1. Secondarily, 2 and 5. (After that, all digits start getting confusable.)

	So at minimum, if reduced manual transcription mistakes is a goal, consider removing upper-case I and O, and lower-case l. Secondarily, S and Z. Letters can also be confused for each other in some fonts - notoriously, upper-case I and lower-case l. But also upper and/or lower-case J, Q, U, V, Y - and anything higher in Latin-based alphabets that can be confused with them (or are literally the same but repeated in a different codepoint).

- There are nearly countless other potential ambiguities as well (e.g. 8 and B), but at some point if you go too far, _everything_ is ambiguous and you have nothing left for an alphabet. And if you consider 8 and B ambiguous, for example, and your base is large, then even a committee or a machine could be driven into insanity, trying to select a small set of perfectly "unambiguous" characters from all of Unicode.

Hastily-assembled, gnarly things that were meant to be temporary placeholders, have an annoying way of becoming permanent and ubiquitous.

- So in one sense, "getting it right the first time" is important. I mean, we're talking about a _positional notation numbering system_. The oldest with a placeholder for 0 is >4,000 years old. There is a non-zero chance that all of humanity in a distant future may judge you for your stupid symbol selection for your new base definition that they are all forced to use by then-archaic convention.

- On the other hand, you probably have better odds of winning a quintillion-dollar lottery. Specifically because no such thing exists. "'Perfection' is the enemy of 'Good'", and also an insane asylum is waiting for anyone who thinks they can construct the "Perfect Base".

#### Value order vs list sorting order

Should your symbols go in ASCII/ANSI/Unicode codepoint order?

- Unless you have a good reason, they probably should, particularly for this case of a positional notation numbering system. You don't need to include every symbol, but the ones that are included, should be in codepoint order. That way, "numbers" will sort "numerically", if (in Linux) `LC_COLLATE=C`.

	- Some 'standard' bases seem random (e.g. `Zbase32` or `Bech32m`), or at least not in codepoint order. Even the universal RFC 4648 §4 base-64 is not in codepoint order.

		- But those examples aren't for positional notation numbering systems. They were designed for binary-to-text encoding. Totally different goals and guidelines. Sorting binary blobs (e.g. MIME-encoded JPEG content) is generally not a "thing".

		- When they don't go in codepoint order, there's usually a strongly-argued reason behind it. (E.g. "reduced typing mistakes", "stronger checksum", etc.)

	- For positional notation, it's usually important to start with the base-10 symbols (`0-9`), followed in ASCII/ANSI/Unicode codepoint order by `A-Z` (a convention reinforced early on by _hexadecimal_ notation), then by `a-z`.

		- These general blocks preserve codepoint order, but don't include symbols in-between. Most of the most widely-used bases (e.g. base 64) move some of those symbols, out of codepoint order, to the end of `a-z`. Technically, that wouldn't sort properly with `LC_COLLATE=C`. (Another strong argument for not using _any_ non-alphanumeric ASCII symbols in a base alphabet definition.)

			> _Note: To sort a space-delimited string by Unicode codepoint, run - for example: `echo "z a 中 あ A 9" | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' '`_

	- You may want geometric symbols that are logically similar but don't appear consecutively in codepoint order, to be purposefully rearranged so that they appear more natural as values increase one at a time in your base. (If that is more important than proper sorting - say, for some weird clock that counts seconds.)

		For example, triangles and arrows are arranged in Unicode usually logical order, that you may not like and that most people might find "aesthetically displeasing". For example, it lists all "left-pointing" arrows of multiple styles, together incrementally. But you may want them to tick by in order, eight arrows of exactly the same design style, starting at "North"-pointing, and moving clockwise through the compass all the way back to "Northwest". And so on with the next arrow style. Or triangles, etc.

		A more obvious example is "number balls" grouped by pictographic "number" in Unicode codepoint order, rather than by "ball style". It makes little sense to watch a numbering system increase by one, each time by showing a "#1" ball four times in a row in four different styles. (Rather than going up in the same style from #1 ball to #10 ball, then repeating for the next ball style.)

		> _A good compromise in that case, and arguably "better" solution, is to just avoid using symbols that have Arabic numerals in them, or otherwise would work better out of Unicode codepoint order. That includes numbered "balls", playing cards, numbered superscripts and subscripts, fractions, arrows, directional triangles, etc. Many of those "Narrow" width symbols are too wide for display on terminal emulators anyway._

#### Existing conventions and standards

Unless you are going for novelty, all numeric bases <= base-64 are "solved" - either with published standards (e.g. RFC documents), by strong historical precedent (e.g. hexadecimal), and/or by obvious convention (e.g. `A-Z` = base-26).

- Even if a base < 62 has no published standard, the most logical and unsurprising way to derive it is simply by truncating the 62 characters `0-9A-Za-z` from the right, to the length of your base.

Unless you have a good reason not to, there are overwhelming benefits to starting with `0-9A-Za-z`, for a positional notation numbering system. (Or truncations thereof.) Including:

- Most bases <= 62 are already subsets of that.

- It's a convention that is both obvious, and a pattern that became established with the hexadecimal alphabet in the 60s.

- Decimal values <= 9 encode to the same characters as decimal, and <= decimal 15 are the same as hexadecimal. (And so on.)

If going higher from there, it's a good general idea to try to still stick to Unicode codepoint order. (Skipping characters as necessary or aesthetically desired.)

However, base-64 and especially base-32 alphabets in particular, have some odd "standard" ducks:

- As mentioned previously, RFC 4648 §4 and 5 (for base 64 binary-to-text de/encoding), inexplicably start with A-Z, then a-z, then 0-9. This isn't in ASCII/ANSI code page / Unicode codepoint order. There is apparently no historically argued reason for this, other than "it's for de/encoding streaming binary so it doesn't matter, as long as it's agreed upon".

	Which - to be fair - is kind of a reasonable argument, if true. But, there's no reason those bases can't be used for positional notation as well.

- Base-32 has numerous published non-codepoint order bases, such as "word-safe" variants that make it harder for an encoding or value to accidentally "spell" things that look like "naughty words".

> _The established numeric base alphabets that don't stick to "hexadecimal"-style codepoint order of `0-9A-Za-z` were either designed for binary-to-text encoding/decoding, and/or had very niche application-specific reasons for doing so that had nothing to do with aesthetics._

#### OS and application support

All modern OSes support UTF-8 natively, which can display any Unicode character. But:

- It's up to the application and the font to insure that they display correctly.

- Unicode characters for pre-boot environments are a no-go. Linux systems at least, have code-paths in the early boot process that are limited to legacy ASCII.

#### TrueType and OpenType limitations

TrueType and OpenType are limited to 65,536 (2^16) glyphs max.

- But beware that few fonts, even among the most commonly installed, use even a fraction of that capacity for defined symbols. (Except for some that explicitly strive for higher Unicode coverage, e.g. Unifont, Noto.)

- For missing codepoint definitions in a font, most (if not all) browsers, many editors, and even some terminal emulators will fall back on a chain of fonts until it finds one that can render what the user-chosen font can't.

	- But if the targeted application for your base can't do that, you need to take that into consideration. And if you have no control over what font will be used for displaying your base, you may be severely constrained in how "high" your base can even practically go - at least for a positional notation numbering system, where the whole point is typically for humans to be able to read the symbols.

	- This fact also makes it harder to pick fonts with broader coverage, and/or test how a base renders. Most browsers and editors, and even terminal emulators, "lie" to you about what your selected font is able to render.

#### Terminal emulators

All modern terminal emulator applications can handle UTF-8, depending on the rendering font.

__But__: terminal emulators are generally terrible at displaying "Narrow" characters that are nevertheless too wide to display in a fixed cell. Which you'll quickly run into even in the Unicode 2-byte range.

So _very_ careful symbol selection, while checking multiple monospace fonts across multiple terminals, is important.

Perhaps ironically, symbols marked with the Unicode "Wide" designation, usually display fine in terminal emulators. These are typically eastern-asian symbol sets such as CJK. They are specified as having _two_ character spaces to display, and terminal emulators usually honor that.

Legacy Windows `conhost.txt` (the old application for hosting `cmd.exe`), can work with UTF-8, but only if the code page is set to UTF-8 ("chcp 65001"), and a compatible font is used (e.g., Consolas, Cascadia Mono, Noto Sans Mono, etc.).

#### Monospace text editors

Text editors usually render "Narrow" UTF-8 symbols that are "too-wide" for terminals, just fine. Because if they can also display proportional fonts properly (most can even if rarely asked to), then they already have the plumbing to vary monospaced font width if necessary. This may manifest as columns of text not lining up exactly, as you might have come to expect when using a monospaced font with regular ASCII text.

### Binary-to-text encoding/decoding scheme

In this context, binary data will be encoded to Unicode text, and then eventually back again to binary. (For example - a JPEG image, executable program, audio file, or even streaming data.)

Usually this is done to skirt limitations of systems that can only deal with text - which you might think of as "tricking" them into storing binary data.

- _For example, embedding images and binary attachments into a text-only email standard, via the 7-bit MIME standard. Email clients recognize and present such data as "attachments", even though the whole thing is just plain 7-bit ASCII text message._

> Bases for binary/text conversion should ideally (but not necessarily) be a power of 2 - e.g. base 8, 16, 32, 64, 128, etc. Otherwise there's extra work, less efficiency, and more opportunity for confusion - for little or no gain.

#### UTF-8 and base-64

Since UTF-8 is variable-width, higher codepoints consume more bytes - meaning less efficient bit-packing. In that case, staying as low in the character set as reasonable should be a key design consideration for binary-to-text encoding.

__A base 64 encoding scheme, using as many traditional 1-byte Unicode characters as possible (i.e. "ASCII"), is the mathematically most efficient binary to UTF8 text encoding scheme possible__.

The traditional challenge has been:

- There is only 94 visible, printable 1-byte Unicode (formerly ASCII) characters.

- Out of those 94, most or all of the non-alphanumeric symbols that appear on a keyboard should be avoided as "unsafe" - for reserved characters for filesystems, URLs, etc. (Unless the purpose for encoding is very narrow and well-defined.)

	_Now entering the second quarter of the 21st century, there's arguably no good, defensible reason to __not__ stick to alphanumeric, from the already tiny set of 1-byte UTF-8 symbols. The storage space saved by including a few extra 1-byte non-alphanumeric symbols from ASCII, is generally not worth the symbol collision risk. Even if the intended purpose is narrow and well-defined, and you may think there's no way anyone else will ever use your base definition - such things have a funny way of escaping into the wild and adopted for broader purposes._

- That leaves essentially the 62 characters `0-9A-Za-z`.

> _Almost all base 64 alphabets simply disagree on what order those three groups of alphanumeric symbols should go in, and what two extra "keyboard" symbols should go at the end to make the full set add up to 64._

#### UTF-16 and base-32768

A base-32768 (e.g. [this one](https://github.com/qntm/base32768)) provides optimal efficiency for UTF-16 binary-to-text encoding/decoding schemes.

- Many programming languages, and the Windows API, use UTF-16.

- There's plenty of room for innovation here. but 32,768 characters is so many, that factors like "existing adoption" and "codepoint efficiency" are far more important than "aesthetics".

#### UTF-32 and base-65536

A base-65536 (e.g. [this one](https://github.com/qntm/base65536)) is optimal for UTF-32 binary-to-text encoding/decoding schemes.

UTF-32 is rarely used for storage or interchange. It's used sometimes by code libraries, when the indexing efficiency gains of fixed-width data structures with no surrogate pairs, are more important than space efficiency.

#### General NON-concerns for binary-to-text encoding

1. __Aesthetics__: This is generally less important if even a remote concern at all. The idea behind most encoding/decoding schemes is that the text is never even _seen_ by humans. Or if seen, not meant to be made sense of. (Unless you can convert - say - a binary data stream into an MPEG video with sound and moving images, in your mind, using only your mind.)

1. __Symbol width overflowing display cells__: Since human-readable output to a text-based terminal is generally irrelevant, you generally don't need to be concerned with overflowing and therefore illegible characters. For example, it's probably completely unconcerning if "Narrow" Unicode symbols visually overflow their assigned terminal cells. (Because if you're even seeing it on a terminal in the first place, you probably forgot to include a piped operation somewhere in a command.)

1. __codepoint order__: Since the output of binary encoding usually looks essentially random, there's not much argument for starting a binary-to-text alphabet with the hex convention of `0-9A-Za-z`, or maintaining Unicode codepoint order at all. (Other that minimizing programmer confusion, and the usually equally valid argument of "why _not_ maintain codepoint order"?)

1. __Symbol ambiguity__: The volume of data in a binary-to-text scheme is usually too high for manual transcription, so symbol disambiguation is usually irrelevant. As long as they are numerically distinct at the codepoint level.

Bases 32 and 64 are already exhaustively solved problems. There's room at higher bases for innovation.

### Printable character counts for each UTF byte range

The idea is usually to be as efficient as possible for a given Unicode encoding scheme. For UTF-8 and UTF-16, that means packing as many <= 2-byte symbols into the base alphabet as possible.

But you only have 95 printable 1-byte characters, and 33 are potentially problematic symbols that are "reserved" in various contexts (e.g. filesystem name delimiter "/", ":", or "\"). So for anything over about base-64 more-or-less, you have to accept that eventually you'll have to start eating into the 2-byte UTF-8 range. (And 1-byte symbols save you nothing in UTF-16, other than a tiny % more headroom for more 2-byte symbols before eating into the 4-byte (surrogate-pair) range for very large bases.)

| Byte count | UTF-8 bitmask                       | Mathly max count | Actual usable character count <sup>1</sup> | UTF-8 bytes | UTF-16 bytes | Comments
| --:        | :--                                  | --:              | --:                                        | --:         | --:          | :--
| 1          | 0xxxxxxx                             | 128              | 95                                         | 1           | 2            | 62 printable if you subtract all "keyboard" symbols used as reserved symbols in various contexts.
| 2          | 110xxxxx-10xxxxxx                    | 2,048            | 1,166                                      | 2           | 2            |
| 3          | 1110xxxx-10xxxxxx-10xxxxxx           | 65,536           | 51,600                                     | 3           | 2            |
| 4          | 11110xxx-10xxxxxx-10xxxxxx-10xxxxxx  | 2,097,152        | 90,764                                     | 4           | 4            | Unicode caps at U+10FFFF for UTF-16 surrogate pair scheme compatibility, so the mathly max is actually 1,114,112.

<sup>*</sup> _Footnote: "Actual usable character count" excludes non-printing control characters, ranges reserved for private use, combining marks, and RTL or "right-to-left" symbols. And the U+10FFFF cap._

Other modern encoding schemes are usually subsets or supersets of a UTF scheme. (E.g. GB18030, a Chinese standard, a UTF-8 superset.)

## Guidelines on what to avoid during symbol selection

__Binary-to-text encoding/decoding scheme__:

As long as you avoid the "Class 1" restrictions below, nearly any symbol will work, even if a particular font can't render it.

And thus, there is arguably little benefit in creating a new base for binary-to-text encoding/decoding, rather than choosing an existing one. (Perhaps unless you have a specific niche requirement for a specific base size, character set, etc.)

Do at least understand the "Class 2" restrictions as well.

The only additional caveat would be to try to avoid the ASCII keyboard symbols; i.e. any 1-byte symbol outside `0-9A-Za-z`, for reasons noted in prior sections.

__Positional notation numbering system__: In very approximate and subjective order of importance, below is a list of guidelines. (And guidelines are meant to be broken - especially once you know why they exist, and the argument for breaking it.)

### Class 1; things that break either system

- Any right-to-left ("RTL") encoded symbol.

	- This is assuming you are aiming for left-to-right, otherwise you'd be more limited in the highest base you could reach if using only right-to-left.

	- RTL symbols wreak havoc on the display and especially cursor navigation, _when mixed with LTR symbols_, depending on the application.

	- This is encoded by the `Bidi_Class` property of each codepoint.

	- Strong RTL classes such as Hebrew (`R`) and Arabic (`AL`) may still have a few LTR symbols sprinkled in though, just to keep things interesting.

- Diacritic characters meant for combining with other characters.

	- Although valid printing unicode, they will break the display of a positional notation numbering system, as well as some processing systems that might be involved in a binary-to-text encoding/decoding scheme. (They won't inherently break binary-to-text encoding/decoding, but underlying storage/cloud systems may not like it, and/or do unexpected thing with it.)

- Decomposable combined codepoints. (E.g. `e` U+0065 + ` ́` U+0301.) This isn't really a problem if each selected symbol is encoded by a single Unicode codepoint. Basing symbol selection on an ordered list of single Unicode codepoints, solves this problem.

### Class 2; things that make a positional notation numbering system hard to read and use

- ASCII symbols besides `0-9`, `A-Z`, and `a-z`.

	- As noted several times previously, by restricting a base to these 62 characters, you only "give up" 33 single-byte UTF-8 symbols. (Which yes is over 50% of the baseline, but usually a fraction of the total symbol count for a given base, larger or smaller.) But the gain in freedom from worry, knowing that a resulting output will conflict with virtually _no_ "reserved" symbol used for any filesystem, URL, HTML, JSON, or programming language, is high. (Yes that means that ideally, the extra two characters for a base-64 alphabet should ideally come from the 2-byte range. Except specifically in the case of 7-bit MIME encoding. Then the extra two symbols are required to come from the 1-byte range of "forbidden" keyboard symbols.)

- Single-width characters that render too wide. These can make numbers impossible to read on a terminal emulator, and other applications that can't vary the display width even for "monospaced" fonts (as most text editors can and do).

	- It is one of the biggest challenges selecting symbols for large bases, that don't violate this. Much testing has to be done with multiple fonts. Programmatic visual analysis can help a great deal here.

	- This is a shame, as many really cool and unique symbols render too wide for their single-width space. For example, most Buginese symbols, like: "ᨀᨁᨂᨃᨄᨅᨆᨇᨈᨉᨊᨋᨌᨍᨎᨏᨐᨑᨒᨓᨔᨕᨖ"

	- _Most characters annotated as "Wide", like emoji and many eastern asian glyphs, render fine on terminals - as they are given two spaces to render. Even when mixed in with single-width characters. These are fine to use._

- Letters with built-in diacritics (i.e. letters with diacritics built in to a single unicode codepoint).

	- This can make for a visual and indiscernible mess, out of the innumerable occurrences of the same symbol varying only by tiny locale-specific visual flourishes somewhere on the character. (Including thousands of "familiar" Latin characters.) If all were allowed, a given random output can wind up looking like a bunch of repeated regular ASCII characters but with dust or visual garbage sprinkled all over.

	- Just because you might happen to be - say, a Spanish-native speaker and perfectly comfortable with acutes, tildes, and diaereses - doesn't mean you won't be equally visually confused by the absolute barrage of same or similar letters with umlauts, macrons, breves, ogoneks, double acutes, thorns, strokes, etc. (And that's just to get started.)

	- Symbols differentiated from each other only by a few pixels of flourish, dominate the bottom 3/4 of Unicode.

	- It can be an incredible - and maddening - challenge to find and choose only baseline, unadorned, visually unique symbols. Especially without programmatic help.

- _Any_ character that can be decomposed, which includes the previous "baked-in" diacritic characters, but also and ligatures like Æ. The look cool, but confusing in context. And often overflow their allotted cells on terminal emulators.

- Most middle-barred letters that look "crossed-out". Technically part of the previous point about diacritics, but worth calling out separately. Like other diacritics, it makes for hard-to-read, visually messy output.

### Class 3; general confusion for a positional notation numbering system

- Anything with intentional Arabic numbers in a "visual" representation - e.g. numbered balls, fractions, playing cards, certain emojis, etc. When these appear in numeric output but have no correlation to their underlying value, it's confusing.

- Single glyphs that _look_ like the same horizontally repeated symbol, or two separate symbols together horizontally (including many eastern asian glyphs).

	- But if vertically repeated, that's less problematic.

- Things that look like ASCII keyboard symbols.

- Anything that looks even a _little_ like a "0" (zero), or capital or lowercase letter "O".

- Ascenders or descenders that are too long. It can help with uniqueness, but if two symbols touch each other vertically, that's problematic. Also they usually - not always - make the output look less aesthetic. (Though some, like "", can look quite pleasantly metal.)

- Thin straight vertical lines that look like pipe symbol

- Thin straight horizontal lines that look like dash or mdash

- Plain middle dots

- Any groups of nothing but dots. They might look cool, but are confusing in context.

- Graphical symbols (e.g. emoji), _unless_ the base is nothing but emoji and/or graphical symbols.

	- Be aware though that not all fonts render emoji and graphical symbols, as "graphics" in their uniquely defined colors. Some emoji/symbols render seemingly randomly as regular flat fonts, in the font's color. (And not necessarily due to intelligent font fallback rendering.)

- Adjacent symbols that look nearly identical (For consistency across guidelines, keep the first.)

- Nearby symbols in same set that differ only by a tiny extra flourish, not covered by the diacritics guideline. (Keep the first.)

- Symbols rendered as bitmaps in most or all fonts.

	- This is usually due to the system using the same "last-resort" fallback bitmapped font, but in a few cases it's pretty universally for historic/archaic languages.

- Things that look like various font tofu symbols for "can't render" (but aren't).

- Symbols poorly centered in the render box (usually intentionally but sometimes sloppily), especially horizontally.

	- Vertically off-center is less problematic, unless extreme.

	- Programmatic help can weed out offenders quickly.

- Symbols that have more than one parts disconnected from each other, separated by too much space, esp. horizontally.

- Severely slanted symbols can add confusion with adjacent characters.

- The extra vertical strokes of symbols like "M" and "W" are hard to distinguish, especially if it fills the whole rendering block.

- Avoid math symbols unless in ANSI or a math symbol code block.

	- In general, try to keep only the first one you come across (in general but especially for math symbols).

- Literal ASCII characters as part of non-ASCII blocks.

- Characters from the "[ASCII-confusable](https://www.unicode.org/Public/security/latest/confusables.txt)" table.

<!--
### OK symbols for an alphabet a little over base 256

Abbreviations:

- BMP: "Basic Multilingual Plane"

The symbols below are narrow enough to fit in a monospace display, and aren't _too_ high in the Unicode symbol set. Some are reordered to make more sense for a positional notation numbering system - for example:

- Rather than a bunch of "A"-like characters one after another, variations are listed in approximate alphabetic order.

- Things like numbered balls are ordered correctly - 0 to 9 or 10 to 9, rather than sometimes seemingly random or styles mixed together.

This should not be considered a canonical list! There are practically uncountable Unicode characters that could work. And especially for binary-to-text encoding/decoding in UTF-8, you should strive to exhaust all 2-byte characters first.

| General categories          | Unicode block                     | Bytes | Characters                                             | Best
| :--                         | :--                               |   --: | :--                                                    | :--
| Extended Latin ("EL")       | BMP, U+0000–U+FFFF                | 2     | ¢£¥§±µ¿÷Ʊɤʬ                                            | Too visually wide: ©®¶·ºðƍɸɷʊʭ
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
| List above, sorted by codepoint | (multiple)                   | (multi) | ¢ £ ¥ § ± ¼ ½ ¾ ¿ Á Â Ã Ä É Ê Ë Í Î Ï Ñ Ó Ô Õ Ö Ú Û Ü Ý á â ã ä é ê ë í î ï ñ ó ô õ ö ÷ ú û ü ý ÿ Ā ā Ć ć Ĉ ĉ Č č Ď ď Ē ē Ě ě Ĝ ĝ Ĥ ĥ Ĩ ĩ Ī ī Ĵ ĵ Ń ń Ň ň Ō ō Ŕ ŕ Ř ř Ś ś Ŝ ŝ Š š Ũ ũ Ū ū Ŵ ŵ Ŷ ŷ Ÿ Ź ź Ʊ Ǎ ǎ Ǒ ǒ Ǔ ǔ ǝ Ǧ ǧ Ǩ ǩ Ǵ ǵ Ȟ ȟ Ȳ ȳ ɤ ɹ ʇ ʌ ʞ ʬ Ξ Ω δ λ μ ψ ϟ Ϡ Ћ Ж Я ф Ѣ ҂ ᚠ ᚧ ᚬ ᚼ ᛎ ᛏ ᛘ ᛝ ᛦ ᛨ ᛬ ᛯ Ẃ ẃ Ẅ ẅ Ẍ ẍ Ẑ ẑ Ẽ ẽ Ỹ ỹ ‡ ⁑ ₸ ⅓ ⅔ ⅕ ⅖ ⅗ ⅘ ⅙ ⅚ ⅛ ⅜ ⅝ ⅞ ∞ ≈ ≠ ⌲ ⍋ ⍒ ⍢ ⍤ ⍩ ▵ ▸ ▿ ◂ ぅ ぇ じ す せ ち づ で べ ぺ ま ゞ ゟ ォ ゲ サ ス ソ ッ ネ ビ モ ヲ ㅈ ㅊ ㅍ ㅎ ㅠ ㅱ ㅸ 웃 유 🜣 🜥 🜿 🝅
| v1 "word-safe" extended alphabet | (multiple)                   | (multi) | ʞ λ μ ᛎ ᛏ ᛘ ᛯ ᛝ ᛦ ᛨ ᚠ ᚧ ᚬ ᚼ 🜣 🜥 🜿 🝅 ▵ ▸ ▿ ◂ ҂ ‡ ± ⁑ ÷ ∞ ≈ ≠ Ω Ʊ Ξ ψ Ϡ δ ϟ Ћ Ж Я Ѣ ф ¢ £ ¥ § ¿ ɤ ʬ ⍤ ⍩ ⌲ ⍋ ⍒ ⍢ Â Ĉ Ê Ĝ Ĥ Ĵ Ŝ Ŵ Ŷ â ĉ ê ĝ ĥ ĵ ŝ ŵ ŷ Ã Ẽ Ñ Ỹ ã ẽ ñ ỹ Ä Ë Ẅ Ẍ Ÿ ä ë ẅ ẍ ÿ Á Ć É | Not necessarily "better", just backward-compatible with v1.

### Not great

Note that characters with diacritics (e.g. Â Ã Ä Á Ǎ etc.) should generally be avoided if possible, for a positional notation alphabet. (Even though they were just listed in the previous section.) The reason being, they visually "pollute" results. The same can be said for barred and strikethrough characters.

Or more generally, anything that relies on decorations or adornments of perviously defined symbols, should be avoided if possible, for positional notation. (But not for binary-to-text, where you want as many symbols consuming less than three and especially four UTF-8 bytes as possible. So you may not be able to be as picky. Which is fine, because for that use-case, proper display in a terminal may not be important.)

| General categories          | Symbols
| :--                         | :--
| Bad for filesystems         | * / : < > ? \ \|
| Bad for internet            | $ & + , / : ; = ? @
| Bad for programmers         | ! " $ % & ' ( ) * + , -  / : ; < = > ? @ [ \ ] ^ _ ` { | } ~
| Greek - Too wide, and/or ambiguous | ΔΘΛϕθϢϪπϡϣϫϖ
| Fractions - don't fit       | ↉ ⅐ ⅑ ⅒
| Diacritics, barred, strikethrough, etc.
-->

<!--
## Supporting work

Note: The following are directory listings that typically contain a raw `.csv` file, the same data in a better-formatted Gnumeric spreadsheet, and an Excel version.

LibreOffice would have been much preferred to [Gnumeric](https://download.cnet.com/gnumeric/) (both are multi-platform open-source spreadsheets), except that for these large spreadsheets covering most or all Unicode, LibreOffice chokes too hard to use. (Even on 32 cores and 128GB RAM in 2026.) Gnumeric handles it with ease, seemingly even better than Excel.

Also, font rendering for Unicode look significantly smoother on Linux (with B&W font-smoothing with no hinting), than Excel for Windows. (Though to be fair, my version of Excel is older and still uses ClearType, with RGB subpixel hinting and overly-strong hinting.) MacOS should look great too.

Unicode listings:

- [All printable Unicode characters, ordered by block](https://github.com/jim-collier/convert-base-v2/tree/main/reference/unicode_all_grouped_by_block).

- [Nicely ordered lists of printable Unicode characters <= U+1FBF9](https://github.com/jim-collier/convert-base-v2/tree/main/reference/source/unicode_ordered_below_U1FBF9) (i.e. directly printable in most modern fonts).

	Characters are, in many cases at higher codepoints, re-ordered to look nice and "expected" in a positional notation numbering system. (I.e. numbered balls grouped by type and go in order, arrows grouped by style and rotate from "north" to "northwest".

	This is a great reference to start from, for designing a large base.
-->

## Document history

- 2026-05-12: Non-trivial content update.
- 2026-04-22: Added list of unicode characters used.
- 2026-04-17: First version.

## Copyright and license

> Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)<br>
> Licensed under GNU GPL v2 <https://www.gnu.org/licenses/gpl-2.0.html>. No warranty.