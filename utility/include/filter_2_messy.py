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
import os
import re
import urllib.request

##
## Tunables
##

ENABLE_ASCII_CONFUSABLES = True
FILTER_SUPERSCRIPT       = True   # reject chars whose Unicode name contains SUPERSCRIPT/SUBSCRIPT/MODIFIER LETTER

##
## Helpers
##

def _is_wide(c):
	return unicodedata.east_asian_width(c) in ('W', 'F')

def _parse_chars(text, fail_log=None):
	chars = []
	for token in text.split():
		for c in token:
			if c in chars:
				continue
			cat = unicodedata.category(c)
			# Skip combining marks (M*) and nonprinting space-like (Zs/Zl/Zp/Cf)
			if cat.startswith('M') or cat in ('Zs', 'Zl', 'Zp', 'Cf'):
				if fail_log is not None:
					reason = 'MARK' if cat.startswith('M') else 'SPACE_FORMAT'
					fail_log.append((ord(c), c, 'FAIL:' + reason, unicodedata.name(c, '')))
				continue
			code_point = ord(c)
			if code_point > 127:
				name = unicodedata.name(c, '')
				is_super_sub = _is_super_sub(name)
				nfkd = unicodedata.normalize('NFKD', c)
				# Non-ASCII that decomposes to multiple chars → combined, drop it
				if len(nfkd) > 1 and not is_super_sub:
					if fail_log is not None:
						fail_log.append((code_point, c, 'FAIL:NFKD_MULTI', name))
					continue
				# Non-ASCII that decomposes to ASCII → masquerading, drop it
				if ord(nfkd) < 128 and not is_super_sub:
					if fail_log is not None:
						fail_log.append((code_point, c, 'FAIL:NFKD_ASCII', name))
					continue
			chars.append(c)
	return chars

# Latin-1 Supplement characters exempt from all per-character filters
_LATIN1_EXEMPT = {
	0x00D8,  # Ø LATIN CAPITAL LETTER O WITH STROKE
	0x00F8,  # ø LATIN SMALL LETTER O WITH STROKE
	0x00DE,  # Þ LATIN CAPITAL LETTER THORN
	0x00FE,  # þ LATIN SMALL LETTER THORN
	0x00E6,  # æ LATIN SMALL LETTER AE
	0x00D7,  # × MULTIPLICATION SIGN
	0x00B7,  # · MIDDLE DOT
}

def _is_super_sub(name):
	return 'SUPERSCRIPT' in name or 'SUBSCRIPT' in name or 'MODIFIER LETTER' in name

##
## Section 1: Universal filters (all characters)
##

_RE_O_LIKE = re.compile(r'\bLETTER O\b|\bLETTER\b.*\bO$|\bOMICRON\b|\bLETTER OH\b')

def _is_o_like(c, name, code_point):
	if code_point < 128: return False
	if not _RE_O_LIKE.search(name): return False
	# Only filter characters whose glyphs actually resemble Latin "O" (NFKD → ASCII)
	return _nfkd_maps_to_ascii(c)

def _nfkd_maps_to_ascii(c):
	"""True if NFKD decomposition produces any ASCII character."""
	return any(ord(x) < 128 for x in unicodedata.normalize('NFKD', c))

def _is_number_like(c, name, cat, code_point):
	if code_point < 128: return False
	# Only filter numbers/digits whose glyphs resemble ASCII (NFKD → ASCII)
	if cat in ('Nd', 'No'):
		return _nfkd_maps_to_ascii(c)
	if re.search(r'\bDIGIT\b|\bNUMBER\b|\bFRACTION\b', name):
		return _nfkd_maps_to_ascii(c)
	if 'TELEGRAPH SYMBOL FOR' in name: return True
	return False

##
## Section 2: Non-wide filters
##

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

def _is_vertical_line(name, code_point):
	if code_point < 128: return False
	return 'VERTICAL LINE' in name or 'VERTICAL BAR' in name

def _is_horizontal_line(name, code_point):
	if code_point < 128: return False
	for kw in ('HORIZONTAL BAR', 'HORIZONTAL LINE', 'EM DASH', 'EN DASH',
			   'FIGURE DASH', 'QUOTATION DASH'):
		if kw in name:
			return True
	return False

_PILCROW_CPS = {
	0x00B6,  # ¶ PILCROW SIGN
	0x204B,  # ⁋ REVERSED PILCROW SIGN
	0x2761,  # ❡ CURVED STEM PARAGRAPH SIGN ORNAMENT
	0x2E0F,  # ⸏ PARAGRAPHOS
	0x2E10,  # ⸐ FORKED PARAGRAPHOS
	0x2E11,  # ⸑ REVERSED FORKED PARAGRAPHOS
	0x2E4D,  # ⹍ PARAGRAPHUS MARK
}

def _is_pilcrow(name, code_point):
	if code_point in _PILCROW_CPS: return True
	return 'PILCROW' in name or 'PARAGRAPHOS' in name

def _is_plain_dot(name, code_point):
	if 0x2000 <= code_point <= 0x206F: return False  # General Punctuation block exempt
	for kw in ('MIDDLE DOT', 'BULLET', 'DOT OPERATOR', 'INTERPUNCT'):
		if kw in name:
			return True
	return False

_RE_DOT_GROUP = re.compile(r'ELLIPSIS|TWO DOT|THREE DOT|FOUR DOT|FIVE DOT|SIX DOT')

def _is_dot_group(name, code_point):
	if 0x2000 <= code_point <= 0x206F: return False  # General Punctuation block exempt
	return bool(_RE_DOT_GROUP.search(name))

# Emoji-like blocks (color/graphical emoji, not general symbols)
# Matches filter_3_visual.py's EMOJI_BLOCKS list
_EMOJI_BLOCKS = [
	(0x1F300, 0x1F5FF),  # Misc Symbols and Pictographs
	(0x1F600, 0x1F64F),  # Emoticons
	(0x1F650, 0x1F67F),  # Ornamental Dingbats
	(0x1F680, 0x1F6FF),  # Transport and Map
	(0x1F700, 0x1F77F),  # Alchemical Symbols
	(0x1F780, 0x1F7FF),  # Geometric Shapes Extended
	(0x1F800, 0x1F8FF),  # Supplemental Arrows-C
	(0x1F900, 0x1F9FF),  # Supplemental Symbols and Pictographs
	(0x1FA00, 0x1FA6F),  # Chess Symbols
	(0x1FA70, 0x1FAFF),  # Symbols and Pictographs Extended-A
	(0x2600,  0x26FF),   # Misc Symbols
	(0x2700,  0x27BF),   # Dingbats
	(0xFE00,  0xFE0F),   # Variation Selectors
]

# Name keywords that indicate emoji/graphical colored characters
_EMOJI_NAME_KEYWORDS = [
	'EMOJI', 'EMOTICON', 'PICTOGRAPH',
]

def _is_emoji_like(name, cat, code_point):
	for lo, hi in _EMOJI_BLOCKS:
		if lo <= code_point <= hi:
			return True
	if any(kw in name for kw in _EMOJI_NAME_KEYWORDS):
		return True
	return False

def _is_bitmap_symbol(name, code_point):
	if 0x2500 <= code_point <= 0x257F: return True  # Box Drawing
	if 0x2580 <= code_point <= 0x259F: return True  # Block Elements
	if 0x2800 <= code_point <= 0x28FF: return True  # Braille
	for kw in ('BRAILLE', 'SHADE', 'QUADRANT', 'SEXTANT', 'OCTANT'):
		if kw in name:
			return True
	return False

def _is_tofu_like(name):
	return 'WHITE SQUARE' in name or 'WHITE RECTANGLE' in name

# Math symbol blocks (keep Sm chars in these)
_MATH_BLOCKS = [
	(0x0000, 0x007F),   # ASCII
	(0x0080, 0x00FF),   # Latin-1 Supplement (×, ÷, ±, ¬)
	(0x2200, 0x22FF),   # Mathematical Operators
	(0x27C0, 0x27EF),   # Misc Mathematical Symbols-A
	(0x2980, 0x29FF),   # Misc Mathematical Symbols-B
	(0x2A00, 0x2AFF),   # Supplemental Mathematical Operators
	(0x1D400, 0x1D7FF), # Mathematical Alphanumeric Symbols
]

def _is_stray_math(c, cat, code_point):
	if cat != 'Sm': return False
	if code_point < 128: return False
	for lo, hi in _MATH_BLOCKS:
		if lo <= code_point <= hi:
			return False
	# Keep non-Latin math symbols with visually distinct glyphs
	if not _nfkd_maps_to_ascii(c):
		return False
	return True

##
## ASCII confusables
##

_CONFUSABLES_URL  = 'https://www.unicode.org/Public/security/latest/confusables.txt'
_CONFUSABLES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'confusables.txt')
_ASCII_ALPHANUM   = set('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789')

def _load_confusables():
	if not os.path.exists(_CONFUSABLES_PATH):
		print(f"Fetching confusables.txt from Unicode.org...", file=sys.stderr)
		urllib.request.urlretrieve(_CONFUSABLES_URL, _CONFUSABLES_PATH)
		print(f"Saved to {_CONFUSABLES_PATH}", file=sys.stderr)
	ascii_confusables = set()
	with open(_CONFUSABLES_PATH, encoding='utf-8-sig') as f:
		for line in f:
			line = line.strip()
			if not line or line.startswith('#'):
				continue
			parts = line.split(';')
			if len(parts) < 2:
				continue
			src_hex = parts[0].strip().split()
			tgt_hex = parts[1].strip().split()
			if len(src_hex) == 1 and len(tgt_hex) == 1:
				try:
					src_cp = int(src_hex[0], 16)
					tgt_cp = int(tgt_hex[0], 16)
					if chr(tgt_cp) in _ASCII_ALPHANUM:
						ascii_confusables.add(src_cp)
				except ValueError:
					pass
	return ascii_confusables

##
## Post-pass: dedup adjacent near-identical
##

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

##
## Core API
##

def extract(text, debug=False):
	fail_log = [] if debug else None
	chars = _parse_chars(text, fail_log=fail_log)
	if not chars:
		if debug and fail_log:
			_print_fail_log(fail_log)
		return ''

	ascii_confusables = _load_confusables() if ENABLE_ASCII_CONFUSABLES else set()

	result = []
	for c in chars:
		code_point = ord(c)
		name = unicodedata.name(c, '')
		cat = unicodedata.category(c)
		wide = _is_wide(c)

		# ASCII: only keep alphanumerics
		if code_point < 128:
			if not c.isalnum():
				if fail_log is not None:
					fail_log.append((code_point, c, 'FAIL:ASCII_NON_ALNUM', name))
				continue
			result.append(c)
			continue

		# Latin-1 Supplement exemptions — always pass
		if code_point in _LATIN1_EXEMPT:
			result.append(c)
			continue

		# Superscript/subscript/modifier letters
		if _is_super_sub(name):
			if FILTER_SUPERSCRIPT:
				if fail_log is not None:
					fail_log.append((code_point, c, 'FAIL:SUPERSCRIPT', name))
				continue
			result.append(c)
			continue

		# Section 1: Universal
		reason = None
		if _is_o_like(c, name, code_point):           reason = 'O_LIKE'
		elif _is_number_like(c, name, cat, code_point):  reason = 'NUMBER_LIKE'
		elif _is_emoji_like(name, cat, code_point):   reason = 'EMOJI_LIKE'
		elif code_point in ascii_confusables:         reason = 'ASCII_CONFUSABLE'

		# Section 2: Non-wide only
		if not reason and not wide:
			if _has_diacritic_name(name):      reason = 'DIACRITIC'
			elif _is_barred(name):             reason = 'BARRED'
			elif _is_ligature(c, name):        reason = 'LIGATURE'
			elif _is_vertical_line(name, code_point):  reason = 'VERTICAL_LINE'
			elif _is_horizontal_line(name, code_point):reason = 'HORIZONTAL_LINE'
			elif _is_pilcrow(name, code_point):        reason = 'PILCROW'
			elif _is_plain_dot(name, code_point):      reason = 'PLAIN_DOT'
			elif _is_dot_group(name, code_point):      reason = 'DOT_GROUP'
			elif _is_bitmap_symbol(name, code_point):  reason = 'BITMAP'
			elif _is_tofu_like(name):          reason = 'TOFU_LIKE'
			elif _is_stray_math(c, cat, code_point):   reason = 'STRAY_MATH'

		if reason:
			if fail_log is not None:
				fail_log.append((code_point, c, 'FAIL:' + reason, name))
			continue

		result.append(c)

	# Post-pass: drop non-ASCII uppercase when its lowercase is also present
	lowercase_cps = {ord(c.lower()) for c in result if ord(c) > 127 and c.lower() != c}
	prev_result = result
	result = [c for c in result if ord(c) < 128 or ord(c) in _LATIN1_EXEMPT or c.lower() == c or ord(c.lower()) not in lowercase_cps]
	if fail_log is not None:
		dropped = set(prev_result) - set(result)
		for c in prev_result:
			if c in dropped:
				fail_log.append((ord(c), c, 'FAIL:UPPERCASE_DUP', unicodedata.name(c, '')))
				dropped.discard(c)

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
					if fail_log is not None:
						fail_log.append((ord(c), c, 'FAIL:STRAY_ASCII', unicodedata.name(c, '')))
					continue
			elif has_prev and prev_non_ascii:
				if fail_log is not None:
					fail_log.append((ord(c), c, 'FAIL:STRAY_ASCII', unicodedata.name(c, '')))
				continue
			elif has_next and next_non_ascii:
				if fail_log is not None:
					fail_log.append((ord(c), c, 'FAIL:STRAY_ASCII', unicodedata.name(c, '')))
				continue
		filtered.append(c)
	result = filtered

	# Post-pass: dedup adjacent near-identical
	prev_result = result
	result = _dedup_similar_adjacent(result)
	if fail_log is not None:
		kept = set()
		for c in result:
			kept.add(id(c))
		# Use index tracking since same char can appear multiple times
		result_set = list(result)
		for c in prev_result:
			if c not in result_set:
				fail_log.append((ord(c), c, 'FAIL:DEDUP_ADJACENT', unicodedata.name(c, '')))
			else:
				result_set.remove(c)

	if debug and fail_log:
		_print_fail_log(fail_log)

	return ' '.join(result)


def _print_fail_log(fail_log):
	print(f"\nFiltered out {len(fail_log)} characters:", file=sys.stderr)
	col_result_w = max(len(r) for _, _, r, _ in fail_log)
	for code_point, c, reason, name in fail_log:
		print(f"  U+{code_point:04X}  {c}  {reason:<{col_result_w}}  '{name.lower()}'", file=sys.stderr)

##
## CLI
##

if __name__ == '__main__':
	debug = '--debug' in sys.argv
	args = [a for a in sys.argv[1:] if a != '--debug']
	text = ' '.join(args) if args else sys.stdin.read().strip()
	print(extract(text, debug=debug))


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
