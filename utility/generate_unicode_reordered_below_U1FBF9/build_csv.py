#!/usr/bin/env python3

"""
Build categorized CSV of printable Unicode U+0000..U+1FBF9.

To run:
	- Make sure 'blocks.py' and 'build_csv.py' are in the same directory.
	- Requires Python 3, and the standard library `unicodedata` - in this case 15.0.0.
	- Run: python3 build_csv.py

Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
Licensed under the GNU General Public License v2.0 or later. Full text at:
	https://spdx.org/licenses/GPL-2.0-or-later.html
SPDX-License-Identifier: GPL-2.0-or-later
"""

import unicodedata
import csv
import os
import re
import sys
from collections import defaultdict

MAX_CP = 0x1FBF9
MAX_GROUP_SIZE = 256

def utf8_len(code_point):
	if code_point < 0x80: return 1
	if code_point < 0x800: return 2
	if code_point < 0x10000: return 3
	return 4

def is_printable(code_point):
	char = chr(code_point)
	category = unicodedata.category(char)
	if category.startswith('C') or category in ('Zl','Zp'):
		return False
	return True

def safe_name(code_point):
	try:
		return unicodedata.name(chr(code_point))
	except ValueError:
		return None

# blocks.py sits next to this script; make sure it's importable from any cwd.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blocks import BLOCKS

def block_for(code_point):
	for start,end,name in BLOCKS:
		if start <= code_point <= end:
			return name
	return None

LETTER_ORDER = {c:i for i,c in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")}

DIGIT_WORDS = {
	'ZERO':0,'ONE':1,'TWO':2,'THREE':3,'FOUR':4,'FIVE':5,'SIX':6,'SEVEN':7,'EIGHT':8,'NINE':9,
	'TEN':10,'ELEVEN':11,'TWELVE':12,'THIRTEEN':13,'FOURTEEN':14,'FIFTEEN':15,'SIXTEEN':16,
	'SEVENTEEN':17,'EIGHTEEN':18,'NINETEEN':19,'TWENTY':20,
}

DIR_MAP = {
	'UPWARDS':0, 'UP':0, 'NORTHWARDS':0, 'NORTH':0, 'UPPER':0,
	'NORTHEAST':1, 'UPPERRIGHT':1,
	'RIGHTWARDS':2, 'RIGHT':2, 'EASTWARDS':2, 'EAST':2,
	'SOUTHEAST':3, 'LOWERRIGHT':3,
	'DOWNWARDS':4, 'DOWN':4, 'SOUTHWARDS':4, 'SOUTH':4, 'LOWER':4,
	'SOUTHWEST':5, 'LOWERLEFT':5,
	'LEFTWARDS':6, 'LEFT':6, 'WESTWARDS':6, 'WEST':6,
	'NORTHWEST':7, 'UPPERLEFT':7,
}

def _normalize_compounds(text):
	text = re.sub(r'\bNORTH\s+WEST\b','NORTHWEST',text)
	text = re.sub(r'\bNORTH\s+EAST\b','NORTHEAST',text)
	text = re.sub(r'\bSOUTH\s+WEST\b','SOUTHWEST',text)
	text = re.sub(r'\bSOUTH\s+EAST\b','SOUTHEAST',text)
	text = re.sub(r'\bUPPER\s+LEFT\b','UPPERLEFT',text)
	text = re.sub(r'\bUPPER\s+RIGHT\b','UPPERRIGHT',text)
	text = re.sub(r'\bLOWER\s+LEFT\b','LOWERLEFT',text)
	text = re.sub(r'\bLOWER\s+RIGHT\b','LOWERRIGHT',text)
	return text

# Back-compat (used elsewhere as a set-of-direction-tokens)
DIR_ORDER = {k: v for k, v in DIR_MAP.items()}

def direction_key(name):
	upper_name = _normalize_compounds(name.upper())
	# Priority 1: what's before POINTING wins (canonical pointing direction)
	match = re.search(r'\b(NORTHWEST|NORTHEAST|SOUTHEAST|SOUTHWEST|UPPERLEFT|UPPERRIGHT|LOWERLEFT|LOWERRIGHT|LEFTWARDS|LEFT|RIGHTWARDS|RIGHT|UPWARDS|UP|DOWNWARDS|DOWN|NORTH|SOUTH|EAST|WEST)[\s-]*POINTING\b', upper_name)
	if match:
		return DIR_MAP[match.group(1)]
	# Priority 2: first direction token that appears in name
	match = re.search(r'\b(NORTHWEST|NORTHEAST|SOUTHEAST|SOUTHWEST|UPPERLEFT|UPPERRIGHT|LOWERLEFT|LOWERRIGHT|LEFTWARDS|LEFT|RIGHTWARDS|RIGHT|UPWARDS|UP|DOWNWARDS|DOWN|NORTHWARDS|NORTH|SOUTHWARDS|SOUTH|EASTWARDS|EAST|WESTWARDS|WEST|UPPER|LOWER)\b', upper_name)
	if match:
		return DIR_MAP.get(match.group(1), 99)
	return 99

def wave_split_items(sorted_items):
	"""Split sorted [(cp, dk), ...] into waves where each wave has no
	repeated direction. If all items share one direction (no cycling
	possible), keep together as a single wave."""
	if not sorted_items:
		return []
	by_dir = defaultdict(list)
	for code_point, direction in sorted_items:
		by_dir[direction].append(code_point)
	if len(by_dir) == 1:
		return [sorted_items]
	max_count = max(len(codepoints) for codepoints in by_dir.values())
	if max_count == 1:
		return [sorted_items]
	waves = []
	for i in range(max_count):
		wave = []
		for direction in sorted(by_dir.keys()):
			if i < len(by_dir[direction]):
				wave.append((by_dir[direction][i], direction))
		waves.append(wave)
	return waves

DIACRITIC_ORDER = [
	'CIRCUMFLEX','TILDE','DIAERESIS','ACUTE','DOUBLE ACUTE',
	'MACRON','CARON','STROKE','HOOK','MIDDLE TILDE','BAR',
	'GRAVE','BREVE','DOT ABOVE','DOT BELOW','RING ABOVE','RING BELOW','CEDILLA',
	'OGONEK','COMMA BELOW','HORN','LINE BELOW','TONOS','DIALYTIKA',
]

def diacritic_priority(mods):
	for i, diacritic in enumerate(DIACRITIC_ORDER):
		if diacritic in mods:
			return i
	return len(DIACRITIC_ORDER) + 1

def parse_letter_name(name):
	match = re.match(r'^(LATIN|GREEK|CYRILLIC|COPTIC|ARMENIAN|HEBREW)\s+(SMALL|CAPITAL)\s+LETTER\s+([A-Z][A-Z ]*?)(?:\s+WITH\s+(.+))?$', name)
	if match:
		return (match.group(1), match.group(2), match.group(3).strip(), match.group(4) or '')
	match = re.match(r'^(LATIN|GREEK|CYRILLIC)\s+LETTER\s+(.+?)(?:\s+WITH\s+(.+))?$', name)
	if match:
		return (match.group(1), 'OTHER', match.group(2).strip(), match.group(3) or '')
	return None

def parse_digit_name(name):
	match = re.search(r'\b(ZERO|ONE|TWO|THREE|FOUR|FIVE|SIX|SEVEN|EIGHT|NINE|TEN|ELEVEN|TWELVE|THIRTEEN|FOURTEEN|FIFTEEN|SIXTEEN|SEVENTEEN|EIGHTEEN|NINETEEN|TWENTY)\b', name)
	if match:
		return DIGIT_WORDS[match.group(1)]
	match = re.search(r'\b(\d+)\b', name)
	if match:
		return int(match.group(1))
	return None

def chunk_group(label, cps, max_size=MAX_GROUP_SIZE):
	if len(cps) <= max_size:
		yield (label, cps)
		return
	total = len(cps)
	nchunks = (total + max_size - 1) // max_size
	for i in range(nchunks):
		chunk = cps[i*max_size:(i+1)*max_size]
		yield (f"{label} (part {i+1}/{nchunks})", chunk)

def format_ranges(cps):
	if not cps:
		return ""
	cps = sorted(cps)
	ranges = []
	start = cps[0]; prev = start
	for code_point in cps[1:]:
		if code_point == prev + 1:
			prev = code_point; continue
		if start == prev:
			ranges.append(f"U+{start:04X}")
		else:
			ranges.append(f"U+{start:04X}-U+{prev:04X}")
		start = code_point; prev = code_point
	if start == prev:
		ranges.append(f"U+{start:04X}")
	else:
		ranges.append(f"U+{start:04X}-U+{prev:04X}")
	return ", ".join(ranges)

# ---- processors ----

def process_basic_latin(cps):
	digits = [code_point for code_point in cps if 0x30 <= code_point <= 0x39]
	upper = [code_point for code_point in cps if 0x41 <= code_point <= 0x5A]
	lower = [code_point for code_point in cps if 0x61 <= code_point <= 0x7A]
	letterset = set(digits+upper+lower)
	rest = [code_point for code_point in cps if code_point not in letterset]
	space = [code_point for code_point in rest if unicodedata.category(chr(code_point)) == 'Zs']
	punct = [code_point for code_point in rest if unicodedata.category(chr(code_point)).startswith('P')]
	sym = [code_point for code_point in rest if unicodedata.category(chr(code_point)).startswith('S')]
	if digits: yield ("ASCII digits 0-9", digits)
	if upper: yield ("ASCII uppercase A-Z", upper)
	if lower: yield ("ASCII lowercase a-z", lower)
	if space: yield ("ASCII space", space)
	if punct: yield ("ASCII punctuation", sorted(punct))
	if sym: yield ("ASCII symbols", sorted(sym))

def process_latin1_sup(cps):
	upper = []; lower = []; other_letters = []; sym = []; punct = []; num = []
	for code_point in cps:
		category = unicodedata.category(chr(code_point))
		if category == 'Lu': upper.append(code_point)
		elif category == 'Ll': lower.append(code_point)
		elif category.startswith('L'): other_letters.append(code_point)
		elif category.startswith('N'): num.append(code_point)
		elif category.startswith('P'): punct.append(code_point)
		else: sym.append(code_point)
	def dkey(code_point):
		parsed = parse_letter_name(safe_name(code_point) or '')
		if parsed:
			_,_,base,mods = parsed
			return (diacritic_priority(mods), mods, LETTER_ORDER.get(base, 99), code_point)
		return (99, '', 99, code_point)
	upper.sort(key=dkey); lower.sort(key=dkey)
	if sym: yield ("Latin-1 symbols", sorted(sym))
	if punct: yield ("Latin-1 punctuation", sorted(punct))
	if num: yield ("Latin-1 fractions and numerals", sorted(num))
	if upper: yield ("Latin-1 uppercase letters with diacritics", upper)
	if lower: yield ("Latin-1 lowercase letters with diacritics", lower)
	if other_letters: yield ("Latin-1 other letters", sorted(other_letters))

def process_latin_extended(cps, block_label):
	groups = defaultdict(list)
	unparsed = []
	for code_point in cps:
		name = safe_name(code_point)
		if not name: unparsed.append(code_point); continue
		parsed = parse_letter_name(name)
		if not parsed or parsed[0] != 'LATIN':
			unparsed.append(code_point); continue
		_, case, base, mods = parsed
		if not mods:
			groups[('_plain',)].append(code_point)
		else:
			groups[(mods,)].append(code_point)
	def gk(k):
		if k == ('_plain',): return (-1,'')
		return (diacritic_priority(k[0]), k[0])
	for k in sorted(groups.keys(), key=gk):
		cp_list = groups[k]
		def ck(code_point):
			parsed = parse_letter_name(safe_name(code_point) or '')
			if not parsed: return (9,99,code_point)
			_, case, base, _ = parsed
			case_rank = {'CAPITAL':0,'SMALL':1,'OTHER':2}.get(case,3)
			base_rank = LETTER_ORDER.get(base, 100 + (ord(base[0]) if base else 999))
			return (case_rank, base_rank, code_point)
		cp_list.sort(key=ck)
		if k == ('_plain',):
			label = f"{block_label}: plain letters"
		else:
			label = f"{block_label}: WITH {k[0]}"
		yield (label, cp_list)
	if unparsed:
		yield (f"{block_label}: other", sorted(unparsed))

def process_greek(cps, block_label):
	cap = []; small = []; other_l = []; punct = []; sym = []; num = []
	for code_point in cps:
		category = unicodedata.category(chr(code_point))
		name = safe_name(code_point) or ''
		if category == 'Lu': cap.append(code_point)
		elif category == 'Ll': small.append(code_point)
		elif category.startswith('L'): other_l.append(code_point)
		elif category.startswith('N'): num.append(code_point)
		elif category.startswith('P'): punct.append(code_point)
		else: sym.append(code_point)
	def gk(code_point):
		parsed = parse_letter_name(safe_name(code_point) or '')
		if parsed:
			_,_,base,mods = parsed
			return (diacritic_priority(mods), mods, code_point)
		return (999,'',code_point)
	cap.sort(key=gk); small.sort(key=gk)
	if num: yield (f"{block_label}: numerals", sorted(num))
	if punct: yield (f"{block_label}: punctuation", sorted(punct))
	if sym: yield (f"{block_label}: symbols", sorted(sym))
	if cap: yield (f"{block_label}: capital letters", cap)
	if small: yield (f"{block_label}: small letters", small)
	if other_l: yield (f"{block_label}: other letters", sorted(other_l))

def process_arrows(cps, block_label):
	groups = defaultdict(list)
	DIRS = set(DIR_MAP.keys())
	SKIP = {'ARROW','ARROWS','AND','A','AN','THE','ON','POINTING'}
	for code_point in cps:
		name = safe_name(code_point) or ''
		normalized_name = _normalize_compounds(name.upper()).replace('-POINTING',' POINTING')
		tokens = re.findall(r'[A-Z][A-Z-]*[A-Z]|[A-Z]', normalized_name)
		dir_count = sum(1 for token in tokens if token in DIRS)
		dir_indices = [i for i, token in enumerate(tokens) if token in DIRS]
		adjacent_dirs = any(dir_indices[i+1] - dir_indices[i] == 1 for i in range(len(dir_indices)-1))
		has_over = 'OVER' in tokens
		def extract_style_tokens(also_skip=()):
			seen = set()
			out = []
			for token in tokens:
				if token in SKIP: continue
				if token in also_skip: continue
				if token in DIRS: continue
				if token in seen: continue
				seen.add(token)
				out.append(token)
			return tuple(out)
		if has_over and dir_count >= 2:
			style = ('paired',) + extract_style_tokens(also_skip={'OVER'})
		elif adjacent_dirs and dir_count >= 2 and not has_over:
			style = ('bidirectional',) + extract_style_tokens()
		else:
			# Strip first direction only; keep secondary dirs and other modifiers
			first_dir_found = False
			style_tokens = []
			for token in tokens:
				if token in SKIP: continue
				if token in DIRS and not first_dir_found:
					first_dir_found = True
					continue
				style_tokens.append(token)
			style = tuple(style_tokens)
		direction = direction_key(name)
		groups[style].append((code_point, direction))
	for style in sorted(groups.keys(), key=lambda s: (len(s), s)):
		items = groups[style]
		items.sort(key=lambda x: (x[1], x[0]))
		waves = wave_split_items(items)
		style_str = ' '.join(token.lower() for token in style) if style else '(plain)'
		for i, wave in enumerate(waves):
			suffix = '' if len(waves) == 1 else f' (v{i+1})'
			yield (f"{block_label}: arrows {style_str}{suffix}", [code_point for code_point,_ in wave])

def process_geometric_shapes(cps, block_label):
	groups = defaultdict(list)
	SHAPE_NAMES = ['TRIANGLE','SQUARE','CIRCLE','DIAMOND','RECTANGLE','PENTAGON',
				   'HEXAGON','STAR','PARALLELOGRAMS','PARALLELOGRAM','LOZENGE',
				   'OCTAGON','HEPTAGON','ELLIPSE']
	DIRS = set(DIR_MAP.keys())
	for code_point in cps:
		name = safe_name(code_point) or ''
		shape = None
		for shape_name in SHAPE_NAMES:
			if shape_name in name:
				shape = shape_name; break
		# Fill classification
		if 'HALF' in name and ('BLACK' in name or 'WHITE' in name):
			fill = 'HALF'
		elif 'WHITE' in name and 'BLACK' not in name:
			fill = 'WHITE'
		elif 'BLACK' in name and 'WHITE' not in name:
			fill = 'BLACK'
		else:
			fill = 'MID'
		# Style sub-signature (what distinguishes this char within its shape+fill)
		normalized_name = _normalize_compounds(name.upper()).replace('-POINTING',' POINTING')
		tokens = re.findall(r'[A-Z][A-Z-]*[A-Z]|[A-Z]', normalized_name)
		# Corner form = has UPPER/LOWER compound direction but no POINTING
		has_pointing = 'POINTING' in tokens
		has_corner = bool(re.search(r'\b(UPPERLEFT|UPPERRIGHT|LOWERLEFT|LOWERRIGHT)\b', normalized_name)) and not has_pointing
		# Build style tokens: strip first direction, fill words, shape word, common skips
		SKIP = {'AND','FROM','TO','THROUGH','ABOVE','BELOW','A','AN','THE','ON',
				'POINTING','BLACK','WHITE'}
		first_dir_found = False
		style_tokens = []
		for token in tokens:
			if token in SKIP: continue
			if shape and token == shape: continue
			if token in DIRS and not first_dir_found:
				first_dir_found = True
				continue
			style_tokens.append(token)
		# Prepend a shape-form marker for triangles so pointing vs corner are separate
		if shape == 'TRIANGLE':
			if has_pointing:
				style_tokens = ['pointing'] + style_tokens
			elif has_corner:
				style_tokens = ['corner'] + style_tokens
		style = tuple(style_tokens)
		direction = direction_key(name)
		groups[(shape or '_other', fill, style)].append((code_point, direction))
	FILL_ORDER = {'WHITE':0,'MID':1,'HALF':2,'BLACK':3}
	FILL_NAME = {'WHITE':'white','MID':'other','HALF':'half-shaded','BLACK':'black'}
	SHAPE_ORDER = ['CIRCLE','ELLIPSE','TRIANGLE','SQUARE','RECTANGLE','PARALLELOGRAM',
				   'PARALLELOGRAMS','DIAMOND','LOZENGE','PENTAGON','HEXAGON',
				   'HEPTAGON','OCTAGON','STAR','_other']
	for shape in SHAPE_ORDER:
		shape_keys = [k for k in groups.keys() if k[0] == shape]
		shape_keys.sort(key=lambda k: (FILL_ORDER.get(k[1], 99), k[2]))
		for key in shape_keys:
			_, fill, style = key
			items = sorted(groups[key], key=lambda x: (x[1], x[0]))
			waves = wave_split_items(items)
			style_str = ' '.join(style) if style else ''
			fill_str = FILL_NAME[fill]
			shape_str = shape.lower()
			for i, wave in enumerate(waves):
				suffix = '' if len(waves) == 1 else f' (v{i+1})'
				if style_str:
					label = f"{block_label}: {fill_str} {shape_str} {style_str}{suffix}"
				else:
					label = f"{block_label}: {fill_str} {shape_str}s{suffix}"
				yield (label, [code_point for code_point,_ in wave])

def process_enclosed_alphanum(cps, block_label):
	groups = defaultdict(list)
	for code_point in cps:
		name = safe_name(code_point) or ''
		match = re.match(r'^(PARENTHESIZED|CIRCLED|NEGATIVE CIRCLED|DOUBLE CIRCLED|DINGBAT CIRCLED|DINGBAT NEGATIVE CIRCLED|SQUARED|NEGATIVE SQUARED|SQUARED LATIN)\s+(.+)$', name)
		enc = match.group(1) if match else 'OTHER'
		if 'DIGIT' in name or 'NUMBER' in name:
			ctype = 'num'; value = parse_digit_name(name) or 999
		elif 'LATIN SMALL' in name:
			ctype = 'latin-small'; value = 0
		elif 'LATIN CAPITAL' in name:
			ctype = 'latin-capital'; value = 0
		elif 'HANGUL' in name or 'IDEOGRAPH' in name or 'KATAKANA' in name:
			ctype = 'cjk'; value = 0
		else:
			ctype = 'other'; value = 0
		groups[(enc, ctype)].append((code_point, value, name))
	ENC_ORDER = ['CIRCLED','DINGBAT CIRCLED','NEGATIVE CIRCLED','DINGBAT NEGATIVE CIRCLED','DOUBLE CIRCLED','PARENTHESIZED','SQUARED','SQUARED LATIN','NEGATIVE SQUARED','OTHER']
	CTYPE_ORDER = ['num','latin-capital','latin-small','cjk','other']
	for enc in ENC_ORDER:
		for ct in CTYPE_ORDER:
			key = (enc, ct)
			if key not in groups: continue
			items = groups[key]
			if ct == 'num':
				items.sort(key=lambda x: (x[1], x[0]))
			elif ct.startswith('latin'):
				def lk(x):
					match = re.search(r'LETTER\s+([A-Z])', x[2])
					return (ord(match.group(1)) if match else 999, x[0])
				items.sort(key=lk)
			else:
				items.sort(key=lambda x: x[0])
			yield (f"{block_label}: {enc.lower()} {ct}", [x[0] for x in items])

def process_playing_cards(cps, block_label):
	SUIT_ORDER = {'SPADES':1,'HEARTS':2,'DIAMONDS':3,'CLUBS':4,'TRUMPS':5,'JOKER':6,'BACK':0}
	RANK_ORDER = {'ACE':1,'TWO':2,'THREE':3,'FOUR':4,'FIVE':5,'SIX':6,'SEVEN':7,'EIGHT':8,'NINE':9,'TEN':10,
				  'JACK':11,'KNIGHT':12,'QUEEN':13,'KING':14}
	groups = defaultdict(list)
	for code_point in cps:
		name = safe_name(code_point) or ''
		if 'TRUMP' in name or 'JOKER' in name:
			value = parse_digit_name(name) or 0
			groups['TRUMPS'].append((code_point, value))
			continue
		if 'BACK' in name:
			groups['BACK'].append((code_point, 0)); continue
		suit = None
		for suit_name in ['SPADES','HEARTS','DIAMONDS','CLUBS']:
			if suit_name in name: suit = suit_name; break
		rank = None
		for rank_name in RANK_ORDER:
			if rank_name in name: rank = rank_name; break
		groups[suit or 'OTHER'].append((code_point, RANK_ORDER.get(rank, 99)))
	for suit in ['BACK','SPADES','HEARTS','DIAMONDS','CLUBS','TRUMPS','JOKER','OTHER']:
		if suit not in groups: continue
		items = groups[suit]
		items.sort(key=lambda x: (x[1], x[0]))
		yield (f"{block_label}: {suit.lower()}", [x[0] for x in items])

def process_math_alphanum(cps, block_label):
	STYLE_ORDER = ['','BOLD','ITALIC','BOLD ITALIC','SCRIPT','BOLD SCRIPT','FRAKTUR','BOLD FRAKTUR',
				   'DOUBLE-STRUCK','SANS-SERIF','SANS-SERIF BOLD','SANS-SERIF ITALIC','SANS-SERIF BOLD ITALIC',
				   'MONOSPACE','DOUBLE-STRUCK ITALIC']
	STYLE_PRI = {s:i for i,s in enumerate(STYLE_ORDER)}
	groups = defaultdict(list)
	for code_point in cps:
		name = safe_name(code_point) or ''
		style = ''
		match = re.match(r'^MATHEMATICAL\s+(.+?)\s+(CAPITAL|SMALL|DIGIT)\s+', name)
		if match:
			style = match.group(1).strip()
		if 'DIGIT' in name:
			kind = 'digits'
			value = parse_digit_name(name) or 0
			sort_rank = value
		elif 'CAPITAL' in name:
			kind = 'capital'
			letter_match = re.search(r'CAPITAL\s+([A-Z])', name)
			sort_rank = ord(letter_match.group(1)) if letter_match else 999
		elif 'SMALL' in name:
			kind = 'small'
			letter_match = re.search(r'SMALL\s+([A-Z])', name)
			sort_rank = ord(letter_match.group(1)) if letter_match else 999
		else:
			kind = 'other'; sort_rank = 999
		groups[(style, kind)].append((code_point, sort_rank))
	KIND_ORDER = {'digits':0,'capital':1,'small':2,'other':3}
	keys = sorted(groups.keys(), key=lambda k: (STYLE_PRI.get(k[0],99), k[0], KIND_ORDER[k[1]]))
	for k in keys:
		items = groups[k]
		items.sort(key=lambda x: (x[1], x[0]))
		style, kind = k
		label = f"Math alphanumerics: {(style+' ').strip()} {kind}".strip()
		yield (label, [code_point for code_point,_ in items])

def process_block_elements(cps, block_label):
	groups = defaultdict(list)
	for code_point in cps:
		name = safe_name(code_point) or ''
		if 'SHADE' in name: key='shades'
		elif 'QUADRANT' in name: key='quadrants'
		elif 'HALF BLOCK' in name: key='half blocks'
		elif 'BLOCK' in name: key='blocks'
		else: key='other'
		groups[key].append(code_point)
	for k in ['blocks','half blocks','quadrants','shades','other']:
		if k in groups:
			yield (f"{block_label}: {k}", sorted(groups[k]))

def process_dingbats(cps, block_label):
	groups = defaultdict(list)
	arrow_cps = []
	triangle_cps = []
	for code_point in cps:
		name = safe_name(code_point) or ''
		if 'DIGIT' in name:
			value = parse_digit_name(name) or 0
			groups['digits'].append((code_point, value))
		elif 'CHECK' in name or 'TICK' in name:
			groups['checks'].append((code_point, 0))
		elif 'BALLOT' in name and 'X' in name:
			groups['crosses'].append((code_point, 0))
		elif re.search(r'\bCROSS\b', name):
			groups['crosses'].append((code_point, 0))
		elif 'ARROW' in name:
			arrow_cps.append(code_point)
		elif 'STAR' in name or 'ASTERISK' in name or 'STARBURST' in name:
			groups['stars'].append((code_point, 0))
		elif 'HEART' in name:
			groups['hearts'].append((code_point, 0))
		elif 'FLOWER' in name or 'FLORETTE' in name:
			groups['flowers'].append((code_point, 0))
		elif 'TRIANGLE' in name:
			triangle_cps.append(code_point)
		elif 'SPARKLE' in name:
			groups['sparkles'].append((code_point, 0))
		elif 'BRACKET' in name or 'PARENTHESIS' in name or 'QUOT' in name:
			groups['brackets/quotes'].append((code_point, 0))
		elif 'PENCIL' in name or 'HAND' in name or 'FIST' in name or 'SCISSOR' in name or 'WRITING' in name:
			groups['hands/tools'].append((code_point, 0))
		else:
			groups['other'].append((code_point, 0))
	for k in ['digits','stars','sparkles','flowers','hearts','checks','crosses']:
		if k in groups:
			items = sorted(groups[k], key=lambda x: (x[1], x[0]))
			yield (f"{block_label}: {k}", [x[0] for x in items])
	if arrow_cps:
		yield from process_arrows(arrow_cps, block_label)
	if triangle_cps:
		yield from process_geometric_shapes(triangle_cps, block_label)
	for k in ['brackets/quotes','hands/tools','other']:
		if k in groups:
			items = sorted(groups[k], key=lambda x: (x[1], x[0]))
			yield (f"{block_label}: {k}", [x[0] for x in items])

def process_miscellaneous_symbols(cps, block_label):
	groups = defaultdict(list)
	for code_point in cps:
		name = safe_name(code_point) or ''
		upper_name = name
		key = 'other'
		if any(w in upper_name for w in ['SUN','MOON','STAR','CLOUD','RAIN','SNOW','COMET','UMBRELLA','LIGHTNING','THERMOMETER']):
			key = 'weather and celestial'
		elif 'HEART' in upper_name:
			key = 'hearts'
		elif any(w in upper_name for w in ['SPADE','CLUB SUIT','DIAMOND SUIT','SUIT']):
			key = 'card suits'
		elif 'CHESS' in upper_name:
			key = 'chess'
		elif 'MUSIC' in upper_name or 'NOTE' in upper_name or 'BEAMED' in upper_name or 'FLAT' in upper_name or 'SHARP' in upper_name or 'NATURAL' in upper_name:
			key = 'musical'
		elif any(w in upper_name for w in ['ARIES','TAURUS','GEMINI','CANCER','LEO','VIRGO','LIBRA','SCORPIUS','SAGITTARIUS','CAPRICORN','AQUARIUS','PISCES','ZODIAC']):
			key = 'zodiac'
		elif any(w in upper_name for w in ['MALE','FEMALE','GENDER','MERCURY','VENUS','MARS','JUPITER','SATURN','URANUS','NEPTUNE','PLUTO','EARTH','PLANET']):
			key = 'astrological/gender'
		elif 'ARROW' in upper_name:
			key = 'arrows'
		elif 'CROSS' in upper_name or 'CRUCIFIX' in upper_name:
			key = 'crosses'
		elif 'CIRCLE' in upper_name or 'BULLET' in upper_name or 'LOZENGE' in upper_name:
			key = 'circles/bullets'
		elif any(w in upper_name for w in ['TELEPHONE','ENVELOPE','AIRPLANE','PENCIL','SCISSORS','CUP','UMBRELLA','ANCHOR']):
			key = 'objects'
		elif 'FACE' in upper_name or 'SMILING' in upper_name or 'FROWNING' in upper_name:
			key = 'faces'
		elif any(w in upper_name for w in ['YIN','YANG','ANKH','STAR OF DAVID','WHEEL OF DHARMA','KHANDA','ORTHODOX','OM','FARSI','KHAMSA','HAMMER','SICKLE','PEACE']):
			key = 'religious/cultural'
		elif 'DICE' in upper_name or 'DOMINO' in upper_name:
			key = 'games'
		elif 'HAND' in upper_name or 'FINGER' in upper_name or 'FIST' in upper_name:
			key = 'hands'
		elif 'FLAG' in upper_name:
			key = 'flags'
		elif 'WARNING' in upper_name or 'SIGN' in upper_name or 'RADIOACTIVE' in upper_name or 'BIOHAZARD' in upper_name or 'RECYCLING' in upper_name or 'SKULL' in upper_name:
			key = 'signs/warnings'
		groups[key].append(code_point)
	ORDER = ['weather and celestial','hearts','card suits','chess','musical','zodiac','astrological/gender',
			 'religious/cultural','faces','hands','objects','games','flags','signs/warnings',
			 'arrows','crosses','circles/bullets','other']
	for k in ORDER:
		if k in groups:
			yield (f"{block_label}: {k}", sorted(groups[k]))

def process_emoji_pictographs(cps, block_label):
	CATEGORIES = [
		('faces and emotions', ['FACE','SMILIN','GRIN','CRY','TEAR','ANGRY','HUGGING','WINK','KISS','WEARY','SLEEP','EYE','MOUTH','ZIPPER-MOUTH','MOUTH FACE','EXPLOD','THINKING']),
		('hands and body parts', ['HAND','FINGER','THUMB','FIST','PALM','ARM','LEG','FOOT','MUSCLE','EAR','NOSE','BONE','FLEXED','TONGUE','PINCH']),
		('people', ['PERSON','MAN','WOMAN','BABY','CHILD','BOY','GIRL','ADULT','ELDER','OLDER','FAMILY','COUPLE','RUNNER','DANCER','WALKING','POLICE','ASTRONAUT','JUDGE','TEACHER','FARMER','DETECTIVE','PILOT','CONSTRUCTION','FACTORY','TECHNOLOGIST','OFFICE','SCIENTIST','MECHANIC','HEALTH','COOK','GUARD','NINJA','SUPERVILLAIN','SUPERHERO','ZOMBIE','FAIRY','GENIE','ELF','MERPERSON','MERMAID','MERMAN','VAMPIRE','MAGE','FROWNING','POUTING','GESTURING','TIPPING','ROWBOAT','SURFER','SWIMMER','BIKING','GOLFER','KNEELING','STANDING','CLIMBER','WRESTLERS','JUGGLING','LOTUS','LIFTER','BATH','BED','SPEAKING','BUST','HEADSET','PREGNANT','BREAST','BOTTLE']),
		('animals', ['DOG','CAT','MOUSE','HAMSTER','RABBIT','FOX','BEAR','PANDA','KOALA','TIGER','LION','COW','PIG','FROG','MONKEY','CHICKEN','PENGUIN','BIRD','EAGLE','DUCK','OWL','BAT','WOLF','HORSE','UNICORN','ZEBRA','DEER','GIRAFFE','CAMEL','LLAMA','ELEPHANT','RHINOCEROS','HIPPOPOTAMUS','GOAT','RAM','SHEEP','BOAR','TURKEY','ROOSTER','DRAGON','SAUROPOD','T-REX','WHALE','DOLPHIN','FISH','SHARK','OCTOPUS','SHRIMP','LOBSTER','SQUID','CRAB','TURTLE','SNAKE','LIZARD','SPIDER','SCORPION','MOSQUITO','FLY','ANT','HONEYBEE','BEETLE','BUG','CATERPILLAR','BUTTERFLY','SNAIL','WORM','MICROBE','POODLE','BADGER','OTTER','SLOTH','KANGAROO','SKUNK','FLAMINGO','PEACOCK','PARROT','SWAN','DODO','SEAL','CRICKET','MAMMOTH','BISON','BEAVER','ORANGUTAN','DINOSAUR','PAW','BLOWFISH','GUIDE DOG','SERVICE DOG','MOOSE','GOOSE','TROPICAL FISH']),
		('plants and nature', ['FLOWER','TREE','PLANT','LEAF','HERB','SHAMROCK','CACTUS','PALM','EVERGREEN','DECIDUOUS','POTTED','TULIP','ROSE','BOUQUET','HIBISCUS','BLOSSOM','SEEDLING','MUSHROOM','CHESTNUT','FOUR LEAF','MAPLE','CLOVER']),
		('food and drink', ['APPLE','BANANA','GRAPE','STRAWBERRY','WATERMELON','MELON','LEMON','ORANGE','PINEAPPLE','PEAR','PEACH','CHERRY','KIWI','TOMATO','CUCUMBER','CARROT','BROCCOLI','CORN','PEPPER','EGGPLANT','POTATO','AVOCADO','BREAD','CHEESE','MEAT','DRUMSTICK','BACON','HAMBURGER','FRENCH','PIZZA','HOT DOG','SANDWICH','TACO','BURRITO','STUFFED','SALAD','POPCORN','BOWL','RICE','SPAGHETTI','SUSHI','BENTO','CURRY','NOODLE','OYSTER','FORTUNE','ICE CREAM','CAKE','COOKIE','DONUT','DOUGHNUT','CANDY','CHOCOLATE','HONEY','PIE','CUPCAKE','MILK','TEA','COFFEE','BEER','WINE','WHISKEY','COCKTAIL','CHAMPAGNE','BOTTLE','DRINK','BUBBLE','PANCAKE','TAKEOUT','WAFFLE','FALAFEL','BAGEL','EGG','BUTTER','FONDUE','CHOPSTICKS','KNIFE','FORK','SPOON','PEANUTS','BONE','CROISSANT','BACON']),
		('weather and nature', ['SUN','MOON','CLOUD','RAIN','SNOW','LIGHTNING','RAINBOW','STAR ','FIRE','WATER','DROPLET','OCEAN','WAVE','FOG','TORNADO','UMBRELLA','SNOWMAN','SNOWFLAKE','COMET','THERMOMETER','STARS','GLOBE','PLANET','RING PLANET']),
		('transport', ['CAR','TRUCK','BUS','TAXI','AMBULANCE','POLICE CAR','FIRE ENGINE','TRACTOR','MOTORCYCLE','BICYCLE','SCOOTER','SKATEBOARD','ROLLER','BOAT','SHIP','YACHT','FERRY','CANOE','SPEEDBOAT','AIRPLANE','HELICOPTER','ROCKET','FLYING SAUCER','TRAIN','TRAM','SUBWAY','LOCOMOTIVE','STATION','RAILWAY','TROLLEY','SAILBOAT','MOUNTAIN CABLEWAY','AERIAL','SUSPENSION']),
		('places and buildings', ['HOUSE','BUILDING','HOSPITAL','BANK','HOTEL','SCHOOL','SHOP','POST','OFFICE','FACTORY','CASTLE','WEDDING','CHURCH','MOSQUE','SYNAGOGUE','TEMPLE','STATUE','STADIUM','BRIDGE','FOUNTAIN','WINDOW','DOOR','DESK','CONVENIENCE','DEPARTMENT','LOVE HOTEL','BALLOT','MAP','FERRIS','ROLLER COASTER','CAROUSEL','MILKY WAY']),
		('celebration and events', ['BALLOON','PARTY','CONFETTI','RIBBON','GIFT','TROPHY','MEDAL','AWARD','SPARKL','FIREWORK','CHRISTMAS','JACK-O-LANTERN','HALLOWEEN','PINATA','MIRROR BALL','FIRE SPARK','WIND CHIME','CARP STREAMER','TANABATA']),
		('sports and games', ['SOCCER','BASEBALL','BASKETBALL','FOOTBALL','TENNIS','VOLLEYBALL','GOLF','HOCKEY','CRICKET','BADMINTON','SKI','SNOWBOARD','SLED','ICE SKATE','BOWLING','GAME','DICE','JOYSTICK','CHESS','DART','SLOT','FISHING','MARTIAL','DIVING','CURLING','BOOMERANG','SKATE','FRISBEE','LACROSSE','NESTING','YO-YO','KITE','POOL','BOX','YO YO']),
		('objects and tools', ['TOOL','HAMMER','WRENCH','SCREWDRIVER','GEAR','NAIL','CHAIN','LOCK','KEY','TOOLBOX','MAGNET','BALANCE','PROBING','LADDER','PICK','AXE','PICKAXE','LABEL','CARPENTRY','TELEPHONE','PHONE','MOBILE','COMPUTER','LAPTOP','KEYBOARD','PRINTER','FAX','CAMERA','TELEVISION','RADIO','FILM','VIDEO','SATELLITE','BATTERY','ELECTRIC','PLUG','BULB','FLASHLIGHT','CANDLE','PAPER','BOOK','MAIL','ENVELOPE','LETTER','FILING','CABINET','FOLDER','CARD FILE','BRIEFCASE','CLIPBOARD','CHART','SCROLL','PAGE','BOOKMARK','PENCIL','PEN','CRAYON','PAINTBRUSH','NEWSPAPER','ABACUS','MONEY','DOLLAR','BANKNOTE','CREDIT','COIN','GEM','STONE','BRICK','ROCK','CAMPING','TENT','CHAIR','COUCH','BATHTUB','TOILET','SHOWER','SOAP','SPONGE','TOOTHBRUSH','SCISSORS','BAND-AID','PILL','SYRINGE','DNA','MICROSCOPE','TELESCOPE','CRYSTAL BALL','PLUNGER','BROOM','BASKET','PAIL','ROLL','MOUSE TRAP','RECEIPT','COFFIN','FUNERAL','PASSPORT','TICKET','ADMISSION','LUGGAGE','ORB','SUITCASE','BACKPACK','HANDBAG','PURSE','POUCH','SHOPPING','SATCHEL','WATCH','HOURGLASS','TIMER','ALARM','CLOCK','BELL','SPEAKER','LOUDSPEAKER','MEGAPHONE','SHIELD','CLAMP','LINK','LEDGER','NOTEBOOK','PACKAGE','INBOX','OUTBOX','FILE','NOTEPAD','MEMO','HOOK','ID CARD','ATM','BATH','DOORWAY','KEY ','OLD KEY','LIPSTICK','NAIL POLISH']),
		('clothing', ['SHIRT','T-SHIRT','JEANS','DRESS','GOWN','KIMONO','SARI','WOMANS','SUIT','TIE','SCARF','GLOVES','COAT','SOCKS','HAT','CAP','CROWN','HELMET','SHOE','BOOT','SANDAL','SNEAKER','BALLET','RING','BIKINI','BRIEFS','THONG','LABCOAT','SAFETY VEST']),
		('music and instruments', ['MUSICAL','MUSIC','NOTE','VIOLIN','GUITAR','SAXOPHONE','TRUMPET','DRUM','PIANO','BANJO','MICROPHONE','HEADPHONE','ACCORDION','LONG DRUM','MARACAS','FLUTE']),
		('arrows', ['ARROW']),
		('geometric shapes', ['CIRCLE','SQUARE','TRIANGLE','DIAMOND','LOZENGE','STAR','PENTAGON','HEXAGON']),
		('signs and symbols', ['WARNING','NO ENTRY','PROHIBITED','SIGN','MARK','RECYCLING','BIOHAZARD','RADIOACTIVE','CROSS','CHECK','HEAVY','BALLOT','EIGHT-POINT','TRIGRAM','HEXAGRAM','KEYCAP','INFORMATION','SYMBOL','CIRCLED IDEOGRAPH','SQUARED','ATOM','FLEUR','STAFF','ATM','WC','MENS','WOMENS','BABY SYMBOL','RESTROOM','TRANSGENDER','PASSPORT CONTROL','CUSTOMS','BAGGAGE','LEFT LUGGAGE','CINEMA','NO SMOKING','SMOKING','LITTER','NO LITTER','POTABLE','NON-POTABLE','BICYCLE','NO PEDESTRIAN','CHILDREN CROSSING','NO BICYCLE','MOUNTAIN','UMBRELLA ON GROUND']),
		('time and clock', ['CLOCK','HOURGLASS','WATCH','TIMER','ALARM']),
		('letters and numbers', ['REGIONAL INDICATOR','LATIN','SMALL LETTER','CAPITAL LETTER','TAG LATIN','NUMBER','DIGIT','KEYCAP']),
	]
	groups = defaultdict(list)
	arrow_cps = []
	for code_point in cps:
		name = safe_name(code_point) or ''
		upper_name = name
		assigned = False
		for cat_name, kws in CATEGORIES:
			if any(kw in upper_name for kw in kws):
				if cat_name == 'arrows':
					arrow_cps.append(code_point)
				else:
					groups[cat_name].append(code_point)
				assigned = True; break
		if not assigned:
			groups['other'].append(code_point)
	for cat_name, _ in CATEGORIES:
		if cat_name == 'arrows':
			if arrow_cps:
				yield from process_arrows(arrow_cps, block_label)
		elif cat_name in groups:
			yield (f"{block_label}: {cat_name}", sorted(groups[cat_name]))
	if 'other' in groups:
		yield (f"{block_label}: other", sorted(groups['other']))

def process_numerics(cps, block_label):
	digit_items = []; other = []
	for code_point in cps:
		name = safe_name(code_point) or ''
		value = parse_digit_name(name)
		if value is not None and any(k in name for k in ['DIGIT','NUMBER','FRACTION','SUBSCRIPT','SUPERSCRIPT','ROMAN','NUMERAL']):
			digit_items.append((code_point, value))
		else:
			other.append(code_point)
	digit_items.sort(key=lambda x: (x[1], x[0]))
	if digit_items:
		yield (f"{block_label}: numerals by value", [code_point for code_point,_ in digit_items])
	if other:
		yield (f"{block_label}: other", sorted(other))

def process_default(cps, block_label):
	yield (block_label, sorted(cps))

PROCESSORS = {
	"Basic Latin": process_basic_latin,
	"Latin-1 Supplement": process_latin1_sup,
	"Latin Extended-A": lambda cps: process_latin_extended(cps, "Latin Ext-A"),
	"Latin Extended-B": lambda cps: process_latin_extended(cps, "Latin Ext-B"),
	"Latin Extended-C": lambda cps: process_latin_extended(cps, "Latin Ext-C"),
	"Latin Extended-D": lambda cps: process_latin_extended(cps, "Latin Ext-D"),
	"Latin Extended-E": lambda cps: process_latin_extended(cps, "Latin Ext-E"),
	"Latin Extended-F": lambda cps: process_latin_extended(cps, "Latin Ext-F"),
	"Latin Extended-G": lambda cps: process_latin_extended(cps, "Latin Ext-G"),
	"Latin Extended Additional": lambda cps: process_latin_extended(cps, "Latin Ext Add"),
	"Greek and Coptic": lambda cps: process_greek(cps, "Greek and Coptic"),
	"Greek Extended": lambda cps: process_greek(cps, "Greek Extended"),
	"Arrows": lambda cps: process_arrows(cps, "Arrows"),
	"Supplemental Arrows-A": lambda cps: process_arrows(cps, "Sup Arrows-A"),
	"Supplemental Arrows-B": lambda cps: process_arrows(cps, "Sup Arrows-B"),
	"Supplemental Arrows-C": lambda cps: process_arrows(cps, "Sup Arrows-C"),
	"Miscellaneous Symbols and Arrows": lambda cps: process_arrows(cps, "Misc Symbols and Arrows"),
	"Geometric Shapes": lambda cps: process_geometric_shapes(cps, "Geometric Shapes"),
	"Geometric Shapes Extended": lambda cps: process_geometric_shapes(cps, "Geometric Shapes Ext"),
	"Enclosed Alphanumerics": lambda cps: process_enclosed_alphanum(cps, "Enclosed Alphanumerics"),
	"Enclosed Alphanumeric Supplement": lambda cps: process_enclosed_alphanum(cps, "Enclosed Alphanumeric Sup"),
	"Playing Cards": lambda cps: process_playing_cards(cps, "Playing Cards"),
	"Mathematical Alphanumeric Symbols": lambda cps: process_math_alphanum(cps, "Math Alphanumerics"),
	"Block Elements": lambda cps: process_block_elements(cps, "Block Elements"),
	"Dingbats": lambda cps: process_dingbats(cps, "Dingbats"),
	"Miscellaneous Symbols": lambda cps: process_miscellaneous_symbols(cps, "Misc Symbols"),
	"Miscellaneous Symbols and Pictographs": lambda cps: process_emoji_pictographs(cps, "Misc Symbols Pictographs"),
	"Supplemental Symbols and Pictographs": lambda cps: process_emoji_pictographs(cps, "Sup Symbols Pictographs"),
	"Symbols and Pictographs Extended-A": lambda cps: process_emoji_pictographs(cps, "Symbols Pictographs Ext-A"),
	"Transport and Map Symbols": lambda cps: process_emoji_pictographs(cps, "Transport and Map"),
	"Emoticons": lambda cps: process_emoji_pictographs(cps, "Emoticons"),
	"Ornamental Dingbats": lambda cps: process_dingbats(cps, "Ornamental Dingbats"),
	"Number Forms": lambda cps: process_numerics(cps, "Number Forms"),
	"Superscripts and Subscripts": lambda cps: process_numerics(cps, "Superscripts and Subscripts"),
	"Aegean Numbers": lambda cps: process_numerics(cps, "Aegean Numbers"),
	"Ancient Greek Numbers": lambda cps: process_numerics(cps, "Ancient Greek Numbers"),
	"Coptic Epact Numbers": lambda cps: process_numerics(cps, "Coptic Epact Numbers"),
	"Counting Rod Numerals": lambda cps: process_numerics(cps, "Counting Rod Numerals"),
	"Kaktovik Numerals": lambda cps: process_numerics(cps, "Kaktovik Numerals"),
	"Mayan Numerals": lambda cps: process_numerics(cps, "Mayan Numerals"),
	"Rumi Numeral Symbols": lambda cps: process_numerics(cps, "Rumi Numerals"),
	"Common Indic Number Forms": lambda cps: process_numerics(cps, "Common Indic Numbers"),
	"Sinhala Archaic Numbers": lambda cps: process_numerics(cps, "Sinhala Archaic Numbers"),
	"Cuneiform Numbers and Punctuation": lambda cps: process_numerics(cps, "Cuneiform Numbers"),
	"Indic Siyaq Numbers": lambda cps: process_numerics(cps, "Indic Siyaq Numbers"),
	"Ottoman Siyaq Numbers": lambda cps: process_numerics(cps, "Ottoman Siyaq Numbers"),
}

TALL_BLOCKS = [
	(0x1D100, 0x1D1FF),  # Musical Symbols
	(0x1D200, 0x1D24F),  # Ancient Greek Musical Notation
	(0x1F700, 0x1F77F),  # Alchemical Symbols
	(0x2E80, 0x2EFF),	# CJK Radicals Supplement
	(0x2F00, 0x2FDF),	# Kangxi Radicals
]
TALL_CODEPOINTS = {
	0x222B, 0x222C, 0x222D, 0x2A0B, 0x2A0C, 0x2A0D, 0x2A0E, 0x2A0F,  # integrals
	0x2211, 0x220F, 0x2210, 0x2A00, 0x2A01, 0x2A02, 0x2A03, 0x2A04,  # n-ary ops
	0x23B4, 0x23B5, 0x23B6, 0x23DC, 0x23DD, 0x23DE, 0x23DF, 0x23E0, 0x23E1,  # brackets/braces
	0x2308, 0x2309, 0x230A, 0x230B,  # ceilings/floors
	0x2329, 0x232A, 0x27E8, 0x27E9, 0x27EA, 0x27EB,  # angle/double-angle brackets
	0x23B0, 0x23B1, 0x23B2, 0x23B3,  # summation/integral pieces
}
TALL_NAME_KEYWORDS = ('COMBINING','STACKED','TWO-LINE','N-ARY',
					  'OVERLINE','UNDERLINE','OVERBAR','UNDERBAR',
					  'DOUBLE INTEGRAL','TRIPLE INTEGRAL','SUMMATION')

def char_width(code_point):
	"""Return 0 (combining/zero-advance), 1 (single cell), or 2 (double-wide)."""
	try:
		char = chr(code_point)
		category = unicodedata.category(char)
		if category in ('Mn', 'Me', 'Cf'):
			return 0
		width = unicodedata.east_asian_width(char)
		if width in ('W', 'F'):
			return 2
		return 1
	except Exception:
		return 1

def char_height(code_point):
	"""Heuristic: 1 (normal line), 2 (likely taller than line / may clip in terminal)."""
	try:
		char = chr(code_point)
		category = unicodedata.category(char)
		if category in ('Mn', 'Me', 'Mc'):
			return 2
		if code_point in TALL_CODEPOINTS:
			return 2
		for start, end in TALL_BLOCKS:
			if start <= code_point <= end:
				return 2
		name = unicodedata.name(char, '')
		if any(kw in name for kw in TALL_NAME_KEYWORDS):
			return 2
		return 1
	except Exception:
		return 1

def main():
	by_block = defaultdict(list)
	for code_point in range(0, MAX_CP + 1):
		if not is_printable(code_point): continue
		block_name = block_for(code_point) or "Unassigned"
		by_block[block_name].append(code_point)

	rows = []
	for start, end, block_name in BLOCKS:
		if block_name not in by_block: continue
		cps = by_block[block_name]
		byte_length = utf8_len(cps[0])
		# Confirm all same byte length; split if not (rare)
		processor = PROCESSORS.get(block_name, lambda cps: process_default(cps, block_name))
		try:
			for label, cp_list in processor(cps):
				for sub_label, sub_cps in chunk_group(label, cp_list):
					rows.append((byte_length, sub_label, sub_cps))
		except Exception as error:
			print(f"Processor failed for {block_name}: {error}", file=sys.stderr)
			for sub_label, sub_cps in chunk_group(block_name, sorted(cps)):
				rows.append((byte_length, sub_label, sub_cps))

	rows.sort(key=lambda r: r[0])  # stable sort by byte length

	with open('unicode_printable.csv','w',newline='',encoding='utf-8') as f:
		writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
		writer.writerow(['Unicode range(s)', 'UTF-8 bytes', 'Group name', 'Characters', 'Width', 'Height'])
		for byte_length, name, cps in rows:
			range_str = format_ranges(cps)
			chars_str = ' '.join(chr(code_point) for code_point in cps)
			width = max((char_width(code_point) for code_point in cps), default=1)
			height = max((char_height(code_point) for code_point in cps), default=1)
			writer.writerow([range_str, byte_length, name, chars_str, width, height])

	total_chars = sum(len(r[2]) for r in rows)
	chars_by_byte = defaultdict(int)
	for byte_length,_,cps in rows: chars_by_byte[byte_length] += len(cps)
	print(f"Total rows: {len(rows)}")
	print(f"Total chars: {total_chars}")
	for byte_length in sorted(chars_by_byte):
		print(f"  {byte_length}-byte: {chars_by_byte[byte_length]}")

if __name__ == '__main__':
	main()
