#!/usr/bin/env python3

"""
Purpose:
	Filters out unicode characters that are too "messy", e.g. have diacritics, or
	are ASCII-like puncuation symbols.

Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
Licensed under the GNU General Public License v2.0 or later. Full text at:
	https://spdx.org/licenses/GPL-2.0-or-later.html
SPDX-License-Identifier: GPL-2.0-or-later
"""

import unicodedata
import sys
import re

# ── Helpers ───────────────────────────────────────────────────────────────────

def _is_wide(c):
	return unicodedata.east_asian_width(c) in ('W', 'F')

def _parse_chars(text):
	chars = []
	for token in text.split():
		for c in token:
			if c in chars:
				continue
			cat = unicodedata.category(c)
			# Skip combining marks (M*) and nonprinting space-like (Zs/Zl/Zp/Cf)
			if cat.startswith('M') or cat in ('Zs', 'Zl', 'Zp', 'Cf'):
				continue
			cp = ord(c)
			if cp > 127:
				nfkd = unicodedata.normalize('NFKD', c)
				# Non-ASCII that decomposes to multiple chars → combined, drop it
				if len(nfkd) > 1:
					continue
				# Non-ASCII that decomposes to ASCII → masquerading, drop it
				if ord(nfkd) < 128:
					continue
			chars.append(c)
	return chars

# ── Section 1: Universal filters (all characters) ────────────────────────────

_RE_O_LIKE = re.compile(r'\bLETTER O\b|\bLETTER\b.*\bO$|\bOMICRON\b|\bLETTER OH\b')

def _is_o_like(name, cp):
	if cp < 128: return False
	return bool(_RE_O_LIKE.search(name))

def _is_number_like(name, cat, cp):
	if cp < 128: return False
	if cat in ('Nd', 'No'): return True
	if re.search(r'\bDIGIT\b|\bNUMBER\b|\bFRACTION\b', name): return True
	if 'TELEGRAPH SYMBOL FOR' in name: return True
	return False

# ── Section 2: Non-wide filters ──────────────────────────────────────────────

def _has_diacritic_name(name):
	idx = name.find(' WITH ')
	if idx < 0: return False
	after = name[idx + 6:]
	if after.startswith('STROKE') or after.startswith('STRIKETHROUGH'):
		return False
	return True

def _is_barred(name):
	for kw in ('WITH STROKE', 'BARRED', 'CROSSED', 'WITH STRIKETHROUGH', 'WITH SLASH'):
		if kw in name:
			if kw == 'WITH SLASH' and 'FRACTION SLASH' in name:
				continue
			return True
	return False

_RE_LIGATURE_NAME = re.compile(r'LIGATURE|DIGRAPH|\bAE\b|\bOE\b|\bOI\b|\bOU\b')

def _is_ligature(c, name):
	if _RE_LIGATURE_NAME.search(name):
		return True
	# NFKD decomposition into 2+ base letters = multi-letter combo (LJ, NJ, DZ, etc.)
	nfkd = unicodedata.normalize('NFKD', c)
	base_count = sum(1 for x in nfkd if unicodedata.category(x).startswith('L'))
	if base_count >= 2:
		return True
	return False

def _is_vertical_line(name, cp):
	if cp < 128: return False
	return 'VERTICAL LINE' in name or 'VERTICAL BAR' in name

def _is_horizontal_line(name, cp):
	if cp < 128: return False
	for kw in ('HORIZONTAL BAR', 'HORIZONTAL LINE', 'EM DASH', 'EN DASH',
			   'FIGURE DASH', 'QUOTATION DASH'):
		if kw in name:
			return True
	return False

def _is_plain_dot(name, cp):
	if 0x2000 <= cp <= 0x206F: return False  # General Punctuation block exempt
	for kw in ('MIDDLE DOT', 'BULLET', 'DOT OPERATOR', 'INTERPUNCT'):
		if kw in name:
			return True
	return False

_RE_DOT_GROUP = re.compile(r'ELLIPSIS|TWO DOT|THREE DOT|FOUR DOT|FIVE DOT|SIX DOT')

def _is_dot_group(name, cp):
	if 0x2000 <= cp <= 0x206F: return False  # General Punctuation block exempt
	return bool(_RE_DOT_GROUP.search(name))

# Emoji-like blocks (color/graphical emoji, not general symbols)
_EMOJI_BLOCKS = [
	(0x1F300, 0x1F5FF),  # Misc Symbols and Pictographs
	(0x1F600, 0x1F64F),  # Emoticons
	(0x1F650, 0x1F67F),  # Ornamental Dingbats
	(0x1F680, 0x1F6FF),  # Transport and Map
	(0x1F900, 0x1F9FF),  # Supplemental Symbols and Pictographs
	(0x1FA00, 0x1FA6F),  # Chess Symbols
	(0x1FA70, 0x1FAFF),  # Symbols and Pictographs Extended-A
]

# Name keywords that indicate emoji/graphical colored characters
_EMOJI_NAME_KEYWORDS = [
	'EMOJI', 'EMOTICON', 'PICTOGRAPH',
]

def _is_emoji_like(name, cat, cp):
	for lo, hi in _EMOJI_BLOCKS:
		if lo <= cp <= hi:
			return True
	if any(kw in name for kw in _EMOJI_NAME_KEYWORDS):
		return True
	return False

def _is_bitmap_symbol(name, cp):
	if 0x2500 <= cp <= 0x257F: return True  # Box Drawing
	if 0x2580 <= cp <= 0x259F: return True  # Block Elements
	if 0x2800 <= cp <= 0x28FF: return True  # Braille
	for kw in ('BRAILLE', 'SHADE', 'QUADRANT', 'SEXTANT', 'OCTANT'):
		if kw in name:
			return True
	return False

def _is_tofu_like(name):
	return 'WHITE SQUARE' in name or 'WHITE RECTANGLE' in name

# Math symbol blocks (keep Sm chars in these)
_MATH_BLOCKS = [
	(0x0000, 0x007F),   # ASCII
	(0x2200, 0x22FF),   # Mathematical Operators
	(0x27C0, 0x27EF),   # Misc Mathematical Symbols-A
	(0x2980, 0x29FF),   # Misc Mathematical Symbols-B
	(0x2A00, 0x2AFF),   # Supplemental Mathematical Operators
	(0x1D400, 0x1D7FF), # Mathematical Alphanumeric Symbols
]

def _is_stray_math(cat, cp):
	if cat != 'Sm': return False
	if cp < 128: return False
	for lo, hi in _MATH_BLOCKS:
		if lo <= cp <= hi:
			return False
	return True

# ── Post-pass: dedup adjacent near-identical ──────────────────────────────────

_STRIP_QUALIFIERS = re.compile(
	r'\b(?:BLACK|WHITE|HEAVY|LIGHT|MEDIUM|DOUBLE|TRIPLE|'
	r'SMALL|LARGE|BIG|TALL|WIDE|NARROW|'
	r'LEFT|RIGHT|UP|DOWN|UPPER|LOWER|'
	r'OPEN|CLOSED|FILLED|OUTLINE|'
	r'NORTH|SOUTH|EAST|WEST)\b'
)

def _canonical_name(c):
	name = unicodedata.name(c, '')
	return _STRIP_QUALIFIERS.sub('', name).strip()

def _dedup_similar_adjacent(chars):
	if not chars: return chars
	result = [chars[0]]
	prev_canon = _canonical_name(chars[0])
	for c in chars[1:]:
		canon = _canonical_name(c)
		if canon and canon == prev_canon and ord(c) > 127 and not _is_wide(c):
			continue  # skip near-duplicate
		result.append(c)
		prev_canon = canon
	return result

# ── Core API ──────────────────────────────────────────────────────────────────

def extract(text):
	chars = _parse_chars(text)
	if not chars:
		return ''

	result = []
	for c in chars:
		cp = ord(c)
		name = unicodedata.name(c, '')
		cat = unicodedata.category(c)
		wide = _is_wide(c)

		# ASCII: only keep alphanumerics
		if cp < 128:
			if not c.isalnum():
				continue
			result.append(c)
			continue

		# Section 1: Universal
		if _is_o_like(name, cp): continue
		if _is_number_like(name, cat, cp): continue
		if _is_emoji_like(name, cat, cp): continue

		# Section 2: Non-wide only
		if not wide:
			if _has_diacritic_name(name): continue
			if _is_barred(name): continue
			if _is_ligature(c, name): continue
			if _is_vertical_line(name, cp): continue
			if _is_horizontal_line(name, cp): continue
			if _is_plain_dot(name, cp): continue
			if _is_dot_group(name, cp): continue
			if _is_bitmap_symbol(name, cp): continue
			if _is_tofu_like(name): continue
			if _is_stray_math(cat, cp): continue

		result.append(c)

	# Post-pass: drop non-ASCII uppercase when its lowercase is also present
	lowercase_cps = {ord(c.lower()) for c in result if ord(c) > 127 and c.lower() != c}
	result = [c for c in result if ord(c) < 128 or c.lower() == c or ord(c.lower()) not in lowercase_cps]

	# Post-pass: drop stray ASCII among non-ASCII neighbors
	# If both neighbors exist, both must be non-ASCII; at edges, the one neighbor must be non-ASCII
	filtered = []
	for i, c in enumerate(result):
		if ord(c) < 128:
			has_prev = i > 0
			has_next = i < len(result) - 1
			prev_non_ascii = has_prev and ord(result[i - 1]) > 127
			next_non_ascii = has_next and ord(result[i + 1]) > 127
			if has_prev and has_next:
				if prev_non_ascii and next_non_ascii:
					continue
			elif has_prev and prev_non_ascii:
				continue
			elif has_next and next_non_ascii:
				continue
		filtered.append(c)
	result = filtered

	# Post-pass: dedup adjacent near-identical
	result = _dedup_similar_adjacent(result)

	return ' '.join(result)

# ── CLI ───────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
	text = ' '.join(sys.argv[1:]) if len(sys.argv) > 1 else sys.stdin.read().strip()
	print(extract(text))


"""
Use the same CLI interface, and a simiar Python-importable API as 'filter_1_junk.py' and 'filter_3_visual.py'. Requirements:
1. For unicode input, which may or may not be delimited with whitespace, filter out characters:
1.1 Universal:
	- Anything that looks even a little like a Capital or lowercase letter "O"
	- Obvious numbers (e.g. numbered balls, fractions, etc.)
1.2 Except for complex east-asian "wide" characters:
	- Characters with built-in diacritics
	- Most middle-barred characters that look "crossed-out"
	- Things that look like ASCII keyboard symbols
	- Combined Letters, e.g. "ᴁ"
	- Glyphs that look like the same horizontally repeated symbol, or different symbols separated horizontally
	- Straight vertical lines that look like pipe symbol
	- Straight horizontal lines that look like dash or mdash
	- Plain middle dots except for symbols code block
	- Any grouping of just dots
	- Graphical symbols (e.g. emoji)
	- Adjacent symbols that look nearly identical (keep the first occurrence)
	- Nearby symbols in same set that differ only by a tiny extra flourish (keep the simplest)
	- Bitmap-rendered symbols [this script can't fix]
	- Real symbols that look like symbols for tofu "can't render"
	- Math symbols unless in ANSI or a math symbols code block
	- If an ASCII character is in between two non-ASCII characters, remove it
	- If a character decomposes to two characters, remove them both
1.3 Misc
	- Try not to repeat logic from 'filter_1_junk.py', unless necessary.
	- Don't repeat the visual system from 'filter_3_visual.py'. Just do the best you can with metadata or online reference.
	- Don't modify 'filter_1_junk.py' or 'filter_3_visual.py'
"""
