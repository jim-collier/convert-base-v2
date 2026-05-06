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

import unicodedata
import sys

HARDCODED_EXCLUSIONS = {
	# Spacing Modifier Letters — diacritic clones / phonological
	0x02B0,0x02B1,0x02B2,0x02B3,0x02B4,0x02B5,0x02B6,0x02B7,0x02B8,
	0x02B9,0x02BA,0x02BB,0x02BC,0x02BD,0x02BE,0x02BF,
	0x02C0,0x02C1,0x02C6,0x02C7,
	0x02C8,0x02C9,0x02CA,0x02CB,0x02CC,0x02CD,0x02CE,0x02CF,
	0x02D0,0x02D1,0x02D8,0x02D9,0x02DA,0x02DB,0x02DC,0x02DD,0x02DE,
	0x02E0,0x02E1,0x02E2,0x02E3,0x02E4,0x02EA,0x02EB,0x02EC,0x02ED,
	0x02EE,0x02EF,0x02F0,0x02F1,0x02F2,0x02F3,0x02F4,0x02F5,0x02F6,
	0x02F7,0x02F8,0x02F9,0x02FA,0x02FB,0x02FC,0x02FD,0x02FE,0x02FF,
	# Greek
	0x0374,  # ʹ GREEK NUMERAL SIGN — small tick
	0x0375,  # ͵ GREEK LOWER NUMERAL SIGN
	0x037A,  # ͺ GREEK YPOGEGRAMMENI
	0x0384,  # ΄ GREEK TONOS
	0x0385,  # ΅ GREEK DIALYTIKA TONOS
	# Latin-1 spacing diacritic clones
	0x00A8,  # ¨ DIAERESIS
	0x00AF,  # ¯ MACRON
	0x00B4,  # ´ ACUTE ACCENT
	0x00B8,  # ¸ CEDILLA
	# Armenian
	0x0559,  # ՙ ARMENIAN MODIFIER LETTER LEFT HALF RING
	# Arabic dependent/elongation
	0x0640,  # ـ ARABIC TATWEEL
	0x06E5,  # ۥ ARABIC SMALL WAW
	0x06E6,  # ۦ ARABIC SMALL YEH
	0x08C9,  # ‎ ARABIC SMALL FARSI YEH
	# Samaritan dependent vowels
	0x081A,  # SAMARITAN MODIFIER LETTER EPENTHETIC YUT
	0x0824,  # SAMARITAN MODIFIER LETTER SHORT A
	0x0828,  # SAMARITAN MODIFIER LETTER I
	# Devanagari
	0x0971,  # ॱ DEVANAGARI SIGN HIGH SPACING DOT
	# NKo
	0x07F4,  # ߴ NKO HIGH TONE APOSTROPHE
	0x07F5,  # ߵ NKO LOW TONE APOSTROPHE
	0x07FA,  # ߺ NKO LAJANYALAN
	# Mongolian
	0x1843,  # ᡃ MONGOLIAN LETTER TODO LONG VOWEL SIGN
	# Vai
	0xA60C,  # ꘌ VAI SYLLABLE LENGTHENER
	# Javanese
	0xA9CF,  # ꧏ JAVANESE PANGRANGKEP
	# Myanmar
	0xA9E6,  # ꧦ MYANMAR MODIFIER LETTER SHAN REDUPLICATION
	0xAA70,  # ꩰ MYANMAR MODIFIER LETTER KHAMTI REDUPLICATION
	# Tai Viet
	0xAADD,  # ꫝ TAI VIET SYMBOL SAM
	# Meetei Mayek
	0xAAF3,  # ꫳ MEETEI MAYEK SYLLABLE REPETITION MARK
	0xAAF4,  # ꫴ MEETEI MAYEK WORD REPETITION MARK
	# Tifinagh
	0x2D6F,  # ⵯ TIFINAGH MODIFIER LETTER LABIALIZATION MARK
	# Cyrillic dependent
	0xA67F,  # ꙿ CYRILLIC PAYEROK
	0xA69C,  # ꚜ MODIFIER LETTER CYRILLIC HARD SIGN
	0xA69D,  # ꚝ MODIFIER LETTER CYRILLIC SOFT SIGN
	# Latin diacritic clones
	0x2E2F,  # ⸯ VERTICAL TILDE
	0xA788,  # ꞈ MODIFIER LETTER LOW CIRCUMFLEX ACCENT
	# Halfwidth elongation
	0xFF70,  # ｰ HALFWIDTH KATAKANA-HIRAGANA PROLONGED SOUND MARK
	0xFF9E,  # ﾞ HALFWIDTH KATAKANA VOICED SOUND MARK
	0xFF9F,  # ﾟ HALFWIDTH KATAKANA SEMI-VOICED SOUND MARK
	# Nag Mundari
	0x1E4EB, # 𞓫 NAG MUNDARI SIGN OJOD
	# Adlam
	0x1E94B, # 𞥋 ADLAM NASALIZATION MARK
}

# Name-based exclusion keywords (Lm/Sk/Lo only, confirmed no false positives)
NAME_EXCLUSION_KEYWORDS = [
	'TONE MARK',
	'VIRAMA',
	'ANUSVARA',
	'VISARGA',
	'AVAGRAHA',
	'SUBJOINED',
	'VOWEL SIGN',
	'MEDIAL FORM',
	'TONE BAR',
	'REPH',
	'REPHA',
	'FILLER',
]

# Exceptions to name-based exclusion — retained as independent characters
NAME_EXCLUSION_EXCEPTIONS = {
	0x02E5,  # ˥ MODIFIER LETTER EXTRA-HIGH TONE BAR  }
	0x02E6,  # ˦ MODIFIER LETTER HIGH TONE BAR		 } Chao
	0x02E7,  # ˧ MODIFIER LETTER MID TONE BAR		  } tone
	0x02E8,  # ˨ MODIFIER LETTER LOW TONE BAR		  } letters
	0x02E9,  # ˩ MODIFIER LETTER EXTRA-LOW TONE BAR	}
}

def is_mark(c): return unicodedata.category(c).startswith('M')
def is_format(c): return unicodedata.category(c) == 'Cf'

def is_name_excluded(c):
	cp = ord(c)
	if cp in NAME_EXCLUSION_EXCEPTIONS: return False
	cat = unicodedata.category(c)
	if cat not in ('Lm', 'Sk', 'Lo'): return False
	name = unicodedata.name(c, '')
	return any(kw in name for kw in NAME_EXCLUSION_KEYWORDS)

def extract(text):
	seen = set()
	result = []
	for char in unicodedata.normalize('NFC', text):
		if unicodedata.category(char) in ('Zs', 'Zl', 'Zp'): continue
		cp = ord(char)
		if is_mark(char): continue
		if is_format(char): continue
		if cp in HARDCODED_EXCLUSIONS: continue
		if is_name_excluded(char): continue
		nfd = unicodedata.normalize('NFD', char)
		if len(nfd) > 1:
			if all(is_mark(c) for c in nfd[1:]):
				if cp not in seen:
					seen.add(cp); result.append(char)
			else:
				for c in nfd:
					if is_mark(c) or is_format(c): continue
					cp2 = ord(c)
					if cp2 in HARDCODED_EXCLUSIONS: continue
					if is_name_excluded(c): continue
					if cp2 not in seen:
						seen.add(cp2); result.append(c)
		else:
			if cp not in seen:
				seen.add(cp); result.append(char)
	return ' '.join(result)

if __name__ == '__main__':
	text = ' '.join(sys.argv[1:]) if len(sys.argv) > 1 else sys.stdin.read().strip()
	print(extract(text))
