#!/usr/bin/env python3

"""
Purpose:
    Generate a CSV of printable Unicode characters, grouped by Unicode block.
    Each block becomes one or more rows with ~128-256 chars each (preferring 256).
    Usage: ./generate_unicode_csv.py [output.csv]

Written by Anthropic Claude Opus 4.7 Adaptive 2026-04-26, but
Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ) according to
	https://www.anthropic.com/legal/consumer-terms

Licensed under the GNU General Public License v2.0 or later. Full text at:
	https://spdx.org/licenses/GPL-2.0-or-later.html
SPDX-License-Identifier: GPL-2.0-or-later
"""

import csv
import sys
import unicodedata

output_path = sys.argv[1] if len(sys.argv) > 1 else "unicode_printable.csv"
# Row-sizing preferences
MAX_ROW  = 256   # target max chars per row
MIN_ROW  = 128   # target min chars per row (when splitting)

# Unicode block list in Blocks.txt format: "START..END; Name"
# Source: Unicode Consortium. Update by replacing this block with new Blocks.txt.
BLOCKS_DATA = """
0000..007F; Basic Latin
0080..00FF; Latin-1 Supplement
0100..017F; Latin Extended-A
0180..024F; Latin Extended-B
0250..02AF; IPA Extensions
02B0..02FF; Spacing Modifier Letters
0300..036F; Combining Diacritical Marks
0370..03FF; Greek and Coptic
0400..04FF; Cyrillic
0500..052F; Cyrillic Supplement
0530..058F; Armenian
0590..05FF; Hebrew
0600..06FF; Arabic
0700..074F; Syriac
0750..077F; Arabic Supplement
0780..07BF; Thaana
07C0..07FF; NKo
0800..083F; Samaritan
0840..085F; Mandaic
0860..086F; Syriac Supplement
0870..089F; Arabic Extended-B
08A0..08FF; Arabic Extended-A
0900..097F; Devanagari
0980..09FF; Bengali
0A00..0A7F; Gurmukhi
0A80..0AFF; Gujarati
0B00..0B7F; Oriya
0B80..0BFF; Tamil
0C00..0C7F; Telugu
0C80..0CFF; Kannada
0D00..0D7F; Malayalam
0D80..0DFF; Sinhala
0E00..0E7F; Thai
0E80..0EFF; Lao
0F00..0FFF; Tibetan
1000..109F; Myanmar
10A0..10FF; Georgian
1100..11FF; Hangul Jamo
1200..137F; Ethiopic
1380..139F; Ethiopic Supplement
13A0..13FF; Cherokee
1400..167F; Unified Canadian Aboriginal Syllabics
1680..169F; Ogham
16A0..16FF; Runic
1700..171F; Tagalog
1720..173F; Hanunoo
1740..175F; Buhid
1760..177F; Tagbanwa
1780..17FF; Khmer
1800..18AF; Mongolian
18B0..18FF; Unified Canadian Aboriginal Syllabics Extended
1900..194F; Limbu
1950..197F; Tai Le
1980..19DF; New Tai Lue
19E0..19FF; Khmer Symbols
1A00..1A1F; Buginese
1A20..1AAF; Tai Tham
1AB0..1AFF; Combining Diacritical Marks Extended
1B00..1B7F; Balinese
1B80..1BBF; Sundanese
1BC0..1BFF; Batak
1C00..1C4F; Lepcha
1C50..1C7F; Ol Chiki
1C80..1C8F; Cyrillic Extended-C
1C90..1CBF; Georgian Extended
1CC0..1CCF; Sundanese Supplement
1CD0..1CFF; Vedic Extensions
1D00..1D7F; Phonetic Extensions
1D80..1DBF; Phonetic Extensions Supplement
1DC0..1DFF; Combining Diacritical Marks Supplement
1E00..1EFF; Latin Extended Additional
1F00..1FFF; Greek Extended
2000..206F; General Punctuation
2070..209F; Superscripts and Subscripts
20A0..20CF; Currency Symbols
20D0..20FF; Combining Diacritical Marks for Symbols
2100..214F; Letterlike Symbols
2150..218F; Number Forms
2190..21FF; Arrows
2200..22FF; Mathematical Operators
2300..23FF; Miscellaneous Technical
2400..243F; Control Pictures
2440..245F; Optical Character Recognition
2460..24FF; Enclosed Alphanumerics
2500..257F; Box Drawing
2580..259F; Block Elements
25A0..25FF; Geometric Shapes
2600..26FF; Miscellaneous Symbols
2700..27BF; Dingbats
27C0..27EF; Miscellaneous Mathematical Symbols-A
27F0..27FF; Supplemental Arrows-A
2800..28FF; Braille Patterns
2900..297F; Supplemental Arrows-B
2980..29FF; Miscellaneous Mathematical Symbols-B
2A00..2AFF; Supplemental Mathematical Operators
2B00..2BFF; Miscellaneous Symbols and Arrows
2C00..2C5F; Glagolitic
2C60..2C7F; Latin Extended-C
2C80..2CFF; Coptic
2D00..2D2F; Georgian Supplement
2D30..2D7F; Tifinagh
2D80..2DDF; Ethiopic Extended
2DE0..2DFF; Cyrillic Extended-A
2E00..2E7F; Supplemental Punctuation
2E80..2EFF; CJK Radicals Supplement
2F00..2FDF; Kangxi Radicals
2FF0..2FFF; Ideographic Description Characters
3000..303F; CJK Symbols and Punctuation
3040..309F; Hiragana
30A0..30FF; Katakana
3100..312F; Bopomofo
3130..318F; Hangul Compatibility Jamo
3190..319F; Kanbun
31A0..31BF; Bopomofo Extended
31C0..31EF; CJK Strokes
31F0..31FF; Katakana Phonetic Extensions
3200..32FF; Enclosed CJK Letters and Months
3300..33FF; CJK Compatibility
3400..4DBF; CJK Unified Ideographs Extension A
4DC0..4DFF; Yijing Hexagram Symbols
4E00..9FFF; CJK Unified Ideographs
A000..A48F; Yi Syllables
A490..A4CF; Yi Radicals
A4D0..A4FF; Lisu
A500..A63F; Vai
A640..A69F; Cyrillic Extended-B
A6A0..A6FF; Bamum
A700..A71F; Modifier Tone Letters
A720..A7FF; Latin Extended-D
A800..A82F; Syloti Nagri
A830..A83F; Common Indic Number Forms
A840..A87F; Phags-pa
A880..A8DF; Saurashtra
A8E0..A8FF; Devanagari Extended
A900..A92F; Kayah Li
A930..A95F; Rejang
A960..A97F; Hangul Jamo Extended-A
A980..A9DF; Javanese
A9E0..A9FF; Myanmar Extended-B
AA00..AA5F; Cham
AA60..AA7F; Myanmar Extended-A
AA80..AADF; Tai Viet
AAE0..AAFF; Meetei Mayek Extensions
AB00..AB2F; Ethiopic Extended-A
AB30..AB6F; Latin Extended-E
AB70..ABBF; Cherokee Supplement
ABC0..ABFF; Meetei Mayek
AC00..D7AF; Hangul Syllables
D7B0..D7FF; Hangul Jamo Extended-B
F900..FAFF; CJK Compatibility Ideographs
FB00..FB4F; Alphabetic Presentation Forms
FB50..FDFF; Arabic Presentation Forms-A
FE00..FE0F; Variation Selectors
FE10..FE1F; Vertical Forms
FE20..FE2F; Combining Half Marks
FE30..FE4F; CJK Compatibility Forms
FE50..FE6F; Small Form Variants
FE70..FEFF; Arabic Presentation Forms-B
FF00..FFEF; Halfwidth and Fullwidth Forms
FFF0..FFFF; Specials
10000..1007F; Linear B Syllabary
10080..100FF; Linear B Ideograms
10100..1013F; Aegean Numbers
10140..1018F; Ancient Greek Numbers
10190..101CF; Ancient Symbols
101D0..101FF; Phaistos Disc
10280..1029F; Lycian
102A0..102DF; Carian
102E0..102FF; Coptic Epact Numbers
10300..1032F; Old Italic
10330..1034F; Gothic
10350..1037F; Old Permic
10380..1039F; Ugaritic
103A0..103DF; Old Persian
10400..1044F; Deseret
10450..1047F; Shavian
10480..104AF; Osmanya
104B0..104FF; Osage
10500..1052F; Elbasan
10530..1056F; Caucasian Albanian
10570..105BF; Vithkuqi
105C0..105FF; Todhri
10600..1077F; Linear A
10780..107BF; Latin Extended-F
10800..1083F; Cypriot Syllabary
10840..1085F; Imperial Aramaic
10860..1087F; Palmyrene
10880..108AF; Nabataean
108E0..108FF; Hatran
10900..1091F; Phoenician
10920..1093F; Lydian
10980..1099F; Meroitic Hieroglyphs
109A0..109FF; Meroitic Cursive
10A00..10A5F; Kharoshthi
10A60..10A7F; Old South Arabian
10A80..10A9F; Old North Arabian
10AC0..10AFF; Manichaean
10B00..10B3F; Avestan
10B40..10B5F; Inscriptional Parthian
10B60..10B7F; Inscriptional Pahlavi
10B80..10BAF; Psalter Pahlavi
10C00..10C4F; Old Turkic
10C80..10CFF; Old Hungarian
10D00..10D3F; Hanifi Rohingya
10D40..10D8F; Garay
10E60..10E7F; Rumi Numeral Symbols
10E80..10EBF; Yezidi
10EC0..10EFF; Arabic Extended-C
10F00..10F2F; Old Sogdian
10F30..10F6F; Sogdian
10F70..10FAF; Old Uyghur
10FB0..10FDF; Chorasmian
10FE0..10FFF; Elymaic
11000..1107F; Brahmi
11080..110CF; Kaithi
110D0..110FF; Sora Sompeng
11100..1114F; Chakma
11150..1117F; Mahajani
11180..111DF; Sharada
111E0..111FF; Sinhala Archaic Numbers
11200..1124F; Khojki
11280..112AF; Multani
112B0..112FF; Khudawadi
11300..1137F; Grantha
11380..113FF; Tulu-Tigalari
11400..1147F; Newa
11480..114DF; Tirhuta
11580..115FF; Siddham
11600..1165F; Modi
11660..1167F; Mongolian Supplement
11680..116CF; Takri
116D0..116FF; Myanmar Extended-C
11700..1174F; Ahom
11800..1184F; Dogra
118A0..118FF; Warang Citi
11900..1195F; Dives Akuru
119A0..119FF; Nandinagari
11A00..11A4F; Zanabazar Square
11A50..11AAF; Soyombo
11AB0..11ABF; Unified Canadian Aboriginal Syllabics Extended-A
11AC0..11AFF; Pau Cin Hau
11B00..11B5F; Devanagari Extended-A
11BC0..11BFF; Sunuwar
11C00..11C6F; Bhaiksuki
11C70..11CBF; Marchen
11D00..11D5F; Masaram Gondi
11D60..11DAF; Gunjala Gondi
11EE0..11EFF; Makasar
11F00..11F5F; Kawi
11FB0..11FBF; Lisu Supplement
11FC0..11FFF; Tamil Supplement
12000..123FF; Cuneiform
12400..1247F; Cuneiform Numbers and Punctuation
12480..1254F; Early Dynastic Cuneiform
12F90..12FFF; Cypro-Minoan
13000..1342F; Egyptian Hieroglyphs
13430..1345F; Egyptian Hieroglyph Format Controls
13460..143FF; Egyptian Hieroglyphs Extended-A
14400..1467F; Anatolian Hieroglyphs
16100..1613F; Gurung Khema
16800..16A3F; Bamum Supplement
16A40..16A6F; Mro
16A70..16ACF; Tangsa
16AD0..16AFF; Bassa Vah
16B00..16B8F; Pahawh Hmong
16D40..16D7F; Kirat Rai
16E40..16E9F; Medefaidrin
16F00..16F9F; Miao
16FE0..16FFF; Ideographic Symbols and Punctuation
17000..187FF; Tangut
18800..18AFF; Tangut Components
18B00..18CFF; Khitan Small Script
18D00..18D7F; Tangut Supplement
1AFF0..1AFFF; Kana Extended-B
1B000..1B0FF; Kana Supplement
1B100..1B12F; Kana Extended-A
1B130..1B16F; Small Kana Extension
1B170..1B2FF; Nushu
1BC00..1BC9F; Duployan
1BCA0..1BCAF; Shorthand Format Controls
1CC00..1CEBF; Symbols for Legacy Computing Supplement
1CF00..1CFCF; Znamenny Musical Notation
1D000..1D0FF; Byzantine Musical Symbols
1D100..1D1FF; Musical Symbols
1D200..1D24F; Ancient Greek Musical Notation
1D2C0..1D2DF; Kaktovik Numerals
1D2E0..1D2FF; Mayan Numerals
1D300..1D35F; Tai Xuan Jing Symbols
1D360..1D37F; Counting Rod Numerals
1D400..1D7FF; Mathematical Alphanumeric Symbols
1D800..1DAAF; Sutton SignWriting
1DF00..1DFFF; Latin Extended-G
1E000..1E02F; Glagolitic Supplement
1E030..1E08F; Cyrillic Extended-D
1E100..1E14F; Nyiakeng Puachue Hmong
1E290..1E2BF; Toto
1E2C0..1E2FF; Wancho
1E4D0..1E4FF; Nag Mundari
1E5D0..1E5FF; Ol Onal
1E7E0..1E7FF; Ethiopic Extended-B
1E800..1E8DF; Mende Kikakui
1E900..1E95F; Adlam
1EC70..1ECBF; Indic Siyaq Numbers
1ED00..1ED4F; Ottoman Siyaq Numbers
1EE00..1EEFF; Arabic Mathematical Alphabetic Symbols
1F000..1F02F; Mahjong Tiles
1F030..1F09F; Domino Tiles
1F0A0..1F0FF; Playing Cards
1F100..1F1FF; Enclosed Alphanumeric Supplement
1F200..1F2FF; Enclosed Ideographic Supplement
1F300..1F5FF; Miscellaneous Symbols and Pictographs
1F600..1F64F; Emoticons
1F650..1F67F; Ornamental Dingbats
1F680..1F6FF; Transport and Map Symbols
1F700..1F77F; Alchemical Symbols
1F780..1F7FF; Geometric Shapes Extended
1F800..1F8FF; Supplemental Arrows-C
1F900..1F9FF; Supplemental Symbols and Pictographs
1FA00..1FA6F; Chess Symbols
1FA70..1FAFF; Symbols and Pictographs Extended-A
1FB00..1FBFF; Symbols for Legacy Computing
20000..2A6DF; CJK Unified Ideographs Extension B
2A700..2B73F; CJK Unified Ideographs Extension C
2B740..2B81F; CJK Unified Ideographs Extension D
2B820..2CEAF; CJK Unified Ideographs Extension E
2CEB0..2EBEF; CJK Unified Ideographs Extension F
2EBF0..2EE5F; CJK Unified Ideographs Extension I
2F800..2FA1F; CJK Compatibility Ideographs Supplement
30000..3134F; CJK Unified Ideographs Extension G
31350..323AF; CJK Unified Ideographs Extension H
E0000..E007F; Tags
E0100..E01EF; Variation Selectors Supplement
"""

# Windows-1252 byte positions 0x80-0xFF mapped to their Unicode code points.
# (Unassigned Win-1252 positions 0x81, 0x8D, 0x8F, 0x90, 0x9D are omitted.)
WIN1252_EXTENSIONS = [
	0x20AC, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6,
	0x2030, 0x0160, 0x2039, 0x0152, 0x017D, 0x2018, 0x2019, 0x201C,
	0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A,
	0x0153, 0x017E, 0x0178,
] + list(range(0xA0, 0x100))


def parse_blocks(data):
	blocks = []
	for line in data.strip().splitlines():
		line = line.strip()
		if not line or line.startswith('#'):
			continue
		rng, name = line.split(';', 1)
		start, end = rng.strip().split('..')
		blocks.append((int(start, 16), int(end, 16), name.strip()))
	return blocks


def is_printable(cp):
	if 0xD800 <= cp <= 0xDFFF:	# surrogates
		return False
	try:
		c = chr(cp)
	except ValueError:
		return False
	cat = unicodedata.category(c)
	if cat[0] == 'C':			  # Cc, Cf, Cs, Co, Cn
		return False
	if cat in ('Zl', 'Zp'):		# line/paragraph separators
		return False
	return True


def utf8_bytes(cp):
	if cp <= 0x7F:	return 1
	if cp <= 0x7FF:   return 2
	if cp <= 0xFFFF:  return 3
	return 4


def fmt_cp(cp):
	return f"U+{cp:04X}" if cp <= 0xFFFF else f"U+{cp:05X}"


def fmt_range(start, end):
	return f"{fmt_cp(start)}-{fmt_cp(end)}"


def split_chunks(chars, target_max):
	"""Split into ceil(n/target_max) chunks of near-equal size."""
	n = len(chars)
	num = max(1, (n + target_max - 1) // target_max)
	base = n // num
	extra = n % num
	chunks = []
	idx = 0
	for i in range(num):
		size = base + (1 if i < extra else 0)
		chunks.append(chars[idx:idx + size])
		idx += size
	return chunks


def main():
	blocks = parse_blocks(BLOCKS_DATA)

	with open(output_path, 'w', newline='', encoding='utf-8') as f:
		w = csv.writer(f)
		w.writerow([
			"Range", "Block name", "Block range",
			"UTF-8 bytes", "Count", "Characters", "Comments"
		])

		# Row 1: printable ASCII (U+0020 - U+007E)
		ascii_chars = [chr(cp) for cp in range(0x20, 0x7F)]
		w.writerow([
			fmt_range(0x20, 0x7E), "Basic Latin", fmt_range(0x0000, 0x007F),
			1, len(ascii_chars), " ".join(ascii_chars),
			"Printable 7-bit ASCII"
		])

		# Row 2: Windows-1252 (ANSI) extensions beyond ASCII
		ansi_chars = [chr(cp) for cp in WIN1252_EXTENSIONS]
		w.writerow([
			"0x80-0xFF (Win-1252)", "(various)", "(various)",
			"2/3", len(ansi_chars), " ".join(ansi_chars),
			"Windows-1252 byte positions 0x80-0xFF; maps to scattered Unicode points"
		])

		# Remaining blocks
		for start, end, name in blocks:
			if start == 0x0000 and end == 0x007F:
				continue   # covered by Row 1
			if start == 0x0080 and end == 0x00FF:
				continue   # covered by Row 2

			chars = [chr(cp) for cp in range(start, end + 1) if is_printable(cp)]
			if not chars:
				continue

			block_range = fmt_range(start, end)
			for chunk in split_chunks(chars, MAX_ROW):
				row_start = ord(chunk[0])
				row_end   = ord(chunk[-1])
				w.writerow([
					fmt_range(row_start, row_end),
					name,
					block_range,
					utf8_bytes(row_start),
					len(chunk),
					" ".join(chunk),
					""
				])


main()
print(f"Wrote {output_path}")
