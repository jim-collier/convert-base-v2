#!/usr/bin/env python3

"""
Purpose:
	Filter Unicode characters by visual acceptability for terminal/editor use.
	Reads characters from arguments or stdin (same format as filter_out_unicode_junk.py).
	Outputs space-separated passing characters on one line.

	Usage: ./filter_visual.py [--debug] [chars ...]
	       echo "chars" | ./filter_visual.py [--debug]

	--debug: also writes unicode_visual_debug.png

Written by Jim Collier and Anthropic Claude Opus 4.7, 2026-05.
Copyright © 2026 Jim Collier
Licensed under the GNU General Public License v2.0 or later.
SPDX-License-Identifier: GPL-2.0-or-later
"""

import sys
import os
import unicodedata
import urllib.request
from PIL import Image, ImageFont, ImageDraw

# ── Configuration ──────────────────────────────────────────────────────────────

FONT_PATH        = '/usr/share/fonts/opentype/unifont/unifont_jp.otf'  ## Unifont only one that can render everything, but ugly
#FONT_PATH       = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'
#FONT_PATH       = '/usr/share/fonts/truetype/jc/noto/NotoSansMono-VariableFont_wdth,wght.ttf'
LABEL_FONT_PATH  = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'
FONT_SIZE        = 64              # 40 is good for DejaVuSansMono. But Unifont's only native size is 16. (So use 16, 32, or 64)
LABEL_FONT_SIZE  = 12
CELL_H           = FONT_SIZE+4     # pixel cell size; ideal: FONT_SIZE + divisible by 2 padding.
CELL_W           = (CELL_H//2)+int(round(FONT_SIZE*.32, 0))   # pixel cell size; ideal: CELL_H*2. Unifont is wonky though, even though it's technically 2:1, needs some extra width to avoid false filter hits, so it gets (CELL_H//2)+int(round(FONT_SIZE*.32, 0))
LABEL_H          = 18              # height of codepoint label below cell
COLS             = 32              # columns in debug grid (an even power of 16)
BORDER_W         = 4               # border thickness around each debug cell

# Pixel thresholds (tune here)
BLANK_THRESHOLD      = 15     # fewer dark pixels → blank; default: 15
DARK_PIXEL_MAX       = 180    # luminance below this = "dark"; default: 180
EDGE_MARGIN_H        = 0.1    # fraction of cell dimension that counts as touching edge, horizontally; smaller is more tolerant; good: 0.1
EDGE_MARGIN_V        = 0.01   # fraction of cell dimension that counts as touching edge, vertically; smaller is more tolerant; good: 0.01
CENTER_H_TOLERANCE   = 0.3    # fraction of CELL_W; larger is more tolerant of off-center; good val: 0.3
CENTER_V_TOLERANCE   = 0.5    # fraction of CELL_H; larger is more tolerant of off-center; good val: 0.5?
COLOR_SATURATION_MIN = 30     # per-channel diff to count as "colored" pixel; default: 30
COLOR_PIXEL_THRESHOLD= 5      # more than this many colored pixels → emoji-like; default: 5

CONFUSABLES_URL  = 'https://www.unicode.org/Public/security/latest/confusables.txt'
CONFUSABLES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'confusables.txt')

# ASCII alphanumerics to check confusables against
ASCII_ALPHANUM = set('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789')

# Unicode emoji-related blocks / properties (block ranges, inclusive)
EMOJI_BLOCKS = [
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

# ── Confusables ────────────────────────────────────────────────────────────────

def fetch_confusables():
	if not os.path.exists(CONFUSABLES_PATH):
		print(f"Fetching confusables.txt from Unicode.org...", file=sys.stderr)
		urllib.request.urlretrieve(CONFUSABLES_URL, CONFUSABLES_PATH)
		print(f"Saved to {CONFUSABLES_PATH}", file=sys.stderr)

def load_confusables():
	fetch_confusables()
	ascii_confusables = set()
	with open(CONFUSABLES_PATH, encoding='utf-8-sig') as f:
		for line in f:
			line = line.strip()
			if not line or line.startswith('#'):
				continue
			parts = line.split(';')
			if len(parts) < 2:
				continue
			# Source: one or more space-separated hex codepoints
			src_hex = parts[0].strip().split()
			# Target: one or more space-separated hex codepoints
			tgt_hex = parts[1].strip().split()
			# Only care about single-char source that maps to single ASCII alphanum
			if len(src_hex) == 1 and len(tgt_hex) == 1:
				try:
					src_cp = int(src_hex[0], 16)
					tgt_cp = int(tgt_hex[0], 16)
					if chr(tgt_cp) in ASCII_ALPHANUM:
						ascii_confusables.add(src_cp)
				except ValueError:
					pass
	return ascii_confusables

# ── Emoji detection ────────────────────────────────────────────────────────────

def is_emoji_by_metadata(cp):
	# Check known emoji blocks
	for lo, hi in EMOJI_BLOCKS:
		if lo <= cp <= hi:
			return True
	# Check Unicode emoji property via category heuristics
	c = chr(cp)
	if unicodedata.category(c) == 'So':
		# "Other Symbol" — many emoji live here; not all, but combined with block check sufficient
		# Only flag if outside BMP or in known symbol ranges
		if cp > 0x2000:
			return True
	return False

def has_color_pixels(cell_img):
	"""Return True if the cell contains non-grayscale pixels (colored emoji)."""
	rgb = cell_img.convert('RGB')
	count = 0
	for r, g, b in rgb.getdata():
		if max(abs(r-g), abs(r-b), abs(g-b)) >= COLOR_SATURATION_MIN:
			count += 1
			if count > COLOR_PIXEL_THRESHOLD:
				return True
	return False

# ── Pixel analysis ─────────────────────────────────────────────────────────────

def render_char(c, font):
	cell = Image.new('RGB', (CELL_W, CELL_H), (255, 255, 255))
	draw = ImageDraw.Draw(cell)
	try:
		bbox = font.getbbox(c)
		glyph_w = bbox[2] - bbox[0]
		glyph_h = bbox[3] - bbox[1]
		x = (CELL_W - glyph_w) // 2 - bbox[0]
		y = (CELL_H - glyph_h) // 2 - bbox[1]
		draw.text((x, y), c, fill=(0, 0, 0), font=font)
	except Exception:
		pass
	return cell

def analyze_cell(cell_img):
	"""Returns dict of pixel metrics."""
	gray = cell_img.convert('L')
	pixels = list(gray.getdata())
	dark = [idx for idx, p in enumerate(pixels) if p < DARK_PIXEL_MAX]
	if len(dark) < BLANK_THRESHOLD:
		return {'blank': True, 'dark_count': len(dark)}
	rows_px = [idx // CELL_W for idx in dark]
	cols_px = [idx % CELL_W for idx in dark]
	min_r, max_r = min(rows_px), max(rows_px)
	min_c, max_c = min(cols_px), max(cols_px)
	margin_h = max(1, round(CELL_W * EDGE_MARGIN_H))
	margin_v = max(1, round(CELL_H * EDGE_MARGIN_V))
	touches_edge = (
		min_r <= margin_v or max_r >= CELL_H - 1 - margin_v or
		min_c <= margin_h or max_c >= CELL_W - 1 - margin_h
	)
	center_c = (min_c + max_c) / 2
	center_r = (min_r + max_r) / 2
	off_h = abs(center_c - CELL_W / 2)
	off_v = abs(center_r - CELL_H / 2)
	poorly_centered = (
		off_h > CELL_W * CENTER_H_TOLERANCE or
		off_v > CELL_H * CENTER_V_TOLERANCE
	)
	return {
		'blank': False,
		'dark_count': len(dark),
		'touches_edge': touches_edge,
		'poorly_centered': poorly_centered,
		'off_h': off_h,
		'off_v': off_v,
	}

# ── Main ───────────────────────────────────────────────────────────────────────

def main():
	debug = '--debug' in sys.argv
	args = [a for a in sys.argv[1:] if a != '--debug']

	if args:
		raw = ' '.join(args)
	else:
		raw = sys.stdin.read().strip()

	# Split on whitespace to get individual characters
	chars = []
	for token in raw.split():
		for c in token:
			if c not in chars:
				chars.append(c)

	if not chars:
		return

#	print("Loading confusables...", file=sys.stderr)
	ascii_confusables = load_confusables()

	font = ImageFont.truetype(FONT_PATH, FONT_SIZE)

	if debug:
		label_font = ImageFont.truetype(LABEL_FONT_PATH, LABEL_FONT_SIZE)
		SLOT_W = CELL_W + 2 * BORDER_W
		SLOT_H = CELL_H + 2 * BORDER_W
		ROWS = (len(chars) + COLS - 1) // COLS
		grid_w = SLOT_W * COLS
		grid_h = (SLOT_H + LABEL_H) * ROWS
		grid = Image.new('RGB', (grid_w, grid_h), (180, 180, 180))
		gdraw = ImageDraw.Draw(grid)

	passed = []
	fail_log = []

	for i, c in enumerate(chars):
		cp = ord(c)
		name = unicodedata.name(c, '')
		fails = []

		# ── Filter 1: emoji by metadata ──
		if is_emoji_by_metadata(cp):
			fails.append('EMOJI_META')

		# ── Filter 2: ASCII confusable ──
		if cp in ascii_confusables:
			fails.append('ASCII_CONFUSABLE')

		# ── Render ──
		cell = render_char(c, font)

		# ── Filter 3: color pixels (emoji heuristic) ──
		if has_color_pixels(cell):
			if 'EMOJI_META' not in fails:
				fails.append('EMOJI_COLOR')

		# ── Filter 4 & 5: pixel geometry ──
		metrics = analyze_cell(cell)
		if metrics['blank']:
			fails.append('BLANK')
		else:
			if metrics.get('touches_edge'):
				fails.append('EDGE')
			if metrics.get('poorly_centered'):
				fails.append('OFFCENTER')

		result = 'PASS' if not fails else 'FAIL:' + '+'.join(fails)

		if not fails:
			passed.append(c)
		else:
			fail_log.append((cp, c, result, name))

		# ── Debug grid ──
		if debug:
			row, col = divmod(i, COLS)
			slot_x = int(col * SLOT_W)
			slot_y = int(row * (SLOT_H + LABEL_H))
			# Fill entire slot with border color, then paste cell inset — border is the colored surround
			border_color = (255, 0, 0) if fails else (0, 180, 0)
			gdraw.rectangle([slot_x, slot_y, slot_x + int(SLOT_W) - 1, slot_y + int(SLOT_H) - 1],
				fill=border_color)
			grid.paste(cell, (slot_x + BORDER_W, slot_y + BORDER_W))
			gdraw.text((slot_x + BORDER_W + 1, slot_y + int(SLOT_H) + 1), f"{cp:04X}",
				fill=(60, 60, 60), font=label_font)

	# ── Output ──
	print(' '.join(passed))

	# Failure summary to stderr
	if fail_log:
		print(f"\nFiltered out {len(fail_log)} characters:", file=sys.stderr)
		for cp, c, result, name in fail_log:
			print(f"  U+{cp:04X} {c}  {result}  {name}", file=sys.stderr)

	if debug:
		out_path = 'unicode_visual_debug.png'
		grid.save(out_path)
		print(f"Debug grid saved to {out_path}", file=sys.stderr)

if __name__ == '__main__':
	main()
