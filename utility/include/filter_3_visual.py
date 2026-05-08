#!/usr/bin/env python3

"""
Purpose:
	Filter Unicode characters by visual acceptability for terminal/editor use.
	Reads characters from arguments or stdin (same format as filter_out_unicode_junk.py).
	Outputs space-separated passing characters on one line.

	Usage: ./filter_visual.py [--debug] [--debug-dir PATH] [chars ...]
	       echo "chars" | ./filter_visual.py [--debug] [--debug-dir PATH]

	--debug:           writes unicode_visual_debug_<LO>-<HI>.png
	--debug-dir PATH:  directory for debug PNG (default: directory of this script)

TODO:
	- Add to filter:
		- Horizontally disconnected
		- Too many vertical strokes
		- Math-like symbols
		- Heavily slanted symbols

Copyright © 2026 Jim Collier
Licensed under the GNU General Public License v2.0 or later.
SPDX-License-Identifier: GPL-2.0-or-later
"""

import sys
import os
import unicodedata
import urllib.request
from copy import copy
from dataclasses import dataclass
from PIL import Image, ImageFont, ImageDraw

# ── Configuration ──────────────────────────────────────────────────────────────

LABEL_FONT_PATH  = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'
LABEL_FONT_SIZE  = 10
LABEL_H          = 18              # height of codepoint label below each cell
FONT_LABEL_H     = 20              # height of font-name header above each grid
COLS             = 32              # columns in debug grid (an even power of 16)
BORDER_W         = 4               # border thickness around each debug cell

# Default pixel thresholds (can be overridden per FontConfig)
FONT_SIZE_UNIFONT    = 32
FONT_SIZE_SCALABLE   = int(round(FONT_SIZE_UNIFONT * 1.0, 0))
BLANK_THRESHOLD      = 30     # fewer dark pixels → blank; default: 15
DARK_PIXEL_MAX       = 180    # luminance below this = "dark"; default: 180
EDGE_MARGIN_H        = 0.05   # fraction of cell dimension that counts as touching edge, horizontally; smaller is more tolerant; good: 0.05?
EDGE_MARGIN_V        = 0.01   # fraction of cell dimension that counts as touching edge, vertically; smaller is more tolerant; good: 0.01
CENTER_H_TOLERANCE   = 0.3    # fraction of CELL_W; larger is more tolerant of off-center; good val: 0.3
CENTER_V_TOLERANCE   = 0.2    # fraction of CELL_H; larger is more tolerant of off-center; good val: 0.5?
COLOR_SATURATION_MIN = 30     # per-channel diff to count as "colored" pixel; default: 30
COLOR_PIXEL_THRESHOLD= 5      # more than this many colored pixels → emoji-like; default: 5
DISCONNECT_H_GAP     = 0.01   # fraction of cell_w; horizontal whitespace gap between components → disconnected
DISCONNECT_ANY_GAP   = 0.10   # fraction of cell dimension; whitespace gap in any direction → disconnected

CONFUSABLES_URL  = 'https://www.unicode.org/Public/security/latest/confusables.txt'
CONFUSABLES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'confusables.txt')

# Directory for debug PNG output; empty = directory of this script
home = os.environ["HOME"]
DEBUG_OUTPUT_DIR = path = os.path.join(home, "var/unicode-visual-debug")

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

# ── Font configurations ─────────────────────────────────────────────────────────

@dataclass
class FontConfig:
	font_path:            str
	label:                str   = ''
	font_size:            int   = FONT_SIZE_UNIFONT
	blank_threshold:      int   = BLANK_THRESHOLD
	dark_pixel_max:       int   = DARK_PIXEL_MAX
	edge_margin_h:        float = EDGE_MARGIN_H
	edge_margin_v:        float = EDGE_MARGIN_V
	center_h_tolerance:   float = CENTER_H_TOLERANCE
	center_v_tolerance:   float = CENTER_V_TOLERANCE
	disconnect_h_gap:     float = DISCONNECT_H_GAP
	disconnect_any_gap:   float = DISCONNECT_ANY_GAP
	cell_h:               int   = 0   # auto-computed from font_size if 0
	cell_w:               int   = 0   # auto-computed from font_size if 0
	extra_cell_w:         int   = 0   # added to auto-computed cell_w (e.g. for wide glyphs)

	def __post_init__(self):
	#	if self.cell_h == 0: self.cell_h = int(round(self.font_size + 4, 0))  ## A couple of pixle wiggle room top & bottom
	#	if self.cell_w == 0: self.cell_w = int(round( (self.cell_h // 2) + self.extra_cell_w ))
		if self.cell_h == 0: self.cell_h = int(round(FONT_SIZE_UNIFONT + 4, 0))  ## A couple of pixle wiggle room top & bottom
		if self.cell_w == 0: self.cell_w = int(round( (self.cell_h // 2) + self.extra_cell_w ))

FONTS = [
	FontConfig(
		## Unifont the only one that can render everything, but ugly.
		font_path = '/usr/share/fonts/opentype/unifont/unifont.otf',
		label     = 'Unifont',
		## The only native size is 16 (so use 16, 32, 64, etc or it will just be blurry.)
		extra_cell_w = int(round(FONT_SIZE_UNIFONT * 0.34)),  # Unifont is technically 2:1 but needs extra width to avoid false filter hits for some reason
	#	font_size    = 32,
	),
	FontConfig(
		## DejaVu supposedly has good unicode coverage, but seemingly not.
		font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
		label     = 'DejaVu Sans Mono',
		extra_cell_w = int(round(FONT_SIZE_SCALABLE * 0.34)),  # Should technically be 2:1 but needs extra width to avoid false filter hits for some reason
		font_size = int(round(FONT_SIZE_SCALABLE * 0.87, 0)),
	),
	FontConfig(
		## This is the second-most complete font. Listed third so it's under Unifont in a 4-panel.
		font_path = '/usr/share/fonts/truetype/freefont/FreeMono.ttf',
		label     = 'Free Mono',
		extra_cell_w = int(round(FONT_SIZE_SCALABLE * 0.34)),  # Should technically be 2:1 but needs extra width to avoid false filter hits for some reason
		font_size = int(round(FONT_SIZE_SCALABLE * 1.1, 0)),
	),
	FontConfig(
		font_path = '/usr/share/fonts/truetype/jc/noto/NotoSansMono-VariableFont_wdth,wght.ttf',
		label     = 'Noto Sans Mono',
		extra_cell_w = int(round(FONT_SIZE_SCALABLE * 0.34)),  # Should technically be 2:1 but needs extra width to avoid false filter hits for some reason
		font_size = int(round(FONT_SIZE_SCALABLE * 1.05, 0)),
	),
#	FontConfig(
#		font_path = '/usr/share/fonts/truetype/jc/envy/Envy Code R.ttf',
#		label     = 'Envy Code R',
#		extra_cell_w = int(round(FONT_SIZE_SCALABLE * 0.34)),  # Should technically be 2:1 but needs extra width to avoid false filter hits for some reason
#		font_size = int(round(FONT_SIZE_SCALABLE * 0.95, 0)),
#	),
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

# ── Missing glyph detection ────────────────────────────────────────────────────

def get_missing_glyph_pixels(font, cfg):
	"""Render U+FFFF (guaranteed absent from compliant fonts) as a per-font fingerprint."""
	cell = render_char('\uFFFF', font, cfg)
	return tuple(cell.convert('L').getdata())

def is_missing_glyph(cell_img, missing_pixels):
	"""Return True if cell_img matches the missing-glyph fingerprint for this font."""
	return tuple(cell_img.convert('L').getdata()) == missing_pixels

# ── Pixel analysis ─────────────────────────────────────────────────────────────

def render_char(c, font, cfg):
	cell = Image.new('RGB', (cfg.cell_w, cfg.cell_h), (255, 255, 255))
	draw = ImageDraw.Draw(cell)
	try:
		bbox = font.getbbox(c)
		glyph_w = bbox[2] - bbox[0]
		glyph_h = bbox[3] - bbox[1]
		x = (cfg.cell_w - glyph_w) // 2 - bbox[0]
		y = (cfg.cell_h - glyph_h) // 2 - bbox[1]
		draw.text((x, y), c, fill=(0, 0, 0), font=font)
	except Exception:
		pass
	return cell

def analyze_cell(cell_img, cfg):
	"""Returns dict of pixel metrics."""
	gray = cell_img.convert('L')
	pixels = list(gray.getdata())
	dark = [idx for idx, p in enumerate(pixels) if p < cfg.dark_pixel_max]
	if len(dark) < cfg.blank_threshold:
		return {'blank': True, 'dark_count': len(dark)}
	rows_px = [idx // cfg.cell_w for idx in dark]
	cols_px = [idx  % cfg.cell_w for idx in dark]
	min_r, max_r = min(rows_px), max(rows_px)
	min_c, max_c = min(cols_px), max(cols_px)
	margin_h = round(cfg.cell_w * cfg.edge_margin_h)
	margin_v = round(cfg.cell_h * cfg.edge_margin_v)
	touches_edge = (
		min_r <= margin_v or max_r >= cfg.cell_h - 1 - margin_v or
		min_c <= margin_h or max_c >= cfg.cell_w - 1 - margin_h
	)
	center_c = (min_c + max_c) / 2
	center_r = (min_r + max_r) / 2
	off_h = abs(center_c - cfg.cell_w / 2)
	off_v = abs(center_r - cfg.cell_h / 2)
	poorly_centered = (
		off_h > cfg.cell_w * cfg.center_h_tolerance or
		off_v > cfg.cell_h * cfg.center_v_tolerance
	)
	# Disconnected-component detection: find fully-white column/row gaps
	# within the dark-pixel bounding box
	dark_cols = set(cols_px)
	dark_rows = set(rows_px)
	# Horizontal gaps (empty columns within bounding box)
	max_h_gap = 0
	gap = 0
	for col in range(min_c, max_c + 1):
		if col not in dark_cols:
			gap += 1
			max_h_gap = max(max_h_gap, gap)
		else:
			gap = 0
	# Vertical gaps (empty rows within bounding box)
	max_v_gap = 0
	gap = 0
	for row in range(min_r, max_r + 1):
		if row not in dark_rows:
			gap += 1
			max_v_gap = max(max_v_gap, gap)
		else:
			gap = 0
	h_gap_frac = max_h_gap / cfg.cell_w if cfg.cell_w else 0
	v_gap_frac = max_v_gap / cfg.cell_h if cfg.cell_h else 0
	disconnected = (
		h_gap_frac >= cfg.disconnect_h_gap or
		v_gap_frac >= cfg.disconnect_any_gap or
		h_gap_frac >= cfg.disconnect_any_gap
	)
	return {
		'blank': False,
		'dark_count': len(dark),
		'touches_edge': touches_edge,
		'poorly_centered': poorly_centered,
		'disconnected': disconnected,
		'off_h': off_h,
		'off_v': off_v,
	}

# ── Debug rendering ─────────────────────────────────────────────────────────────

def render_font_grid(chars, fnt, cfg, label_font, ascii_confusables, missing_pixels, char_decisions):
	"""Render a debug grid image for one font, with pass/fail/no-glyph colored borders.
	   Green  = pass
	   Blue   = pass, but this font has no glyph (abstained)
	   Black  = ASCII confusable
	   Orange = failed other non-visual rule (emoji metadata)
	   Red    = failed visual vote AND this font voted "no"
	   C08080 = failed visual vote BUT this font voted "yes" or abstained (tofu)
	   East-Asian wide (W/F) characters are drawn at double width.
	"""
	slot_w        = cfg.cell_w + 2 * BORDER_W
	slot_h        = cfg.cell_h + 2 * BORDER_W
	row_px_limit  = slot_w * COLS   # wrap rows at this many pixels

	# ── Pre-pass: compute (row_num, sx, is_wide) for each char ──
	layout  = []
	row_num = 0
	row_x   = 0
	for c in chars:
		wide  = unicodedata.east_asian_width(c) in ('W', 'F')
		w_px  = slot_w * (2 if wide else 1)
		if row_x > 0 and row_x + w_px > row_px_limit:
			row_num += 1
			row_x = 0
		layout.append((row_num, row_x, wide))
		row_x += w_px
	num_rows = (layout[-1][0] + 1) if layout else 1

	header_h = FONT_LABEL_H if cfg.label else 0
	grid_w   = row_px_limit
	grid_h   = header_h + (slot_h + LABEL_H) * num_rows
	grid     = Image.new('RGB', (grid_w, grid_h), (180, 180, 180))
	gdraw    = ImageDraw.Draw(grid)

	if cfg.label:
		gdraw.rectangle([0, 0, grid_w - 1, header_h - 1], fill=(60, 60, 60))
		gdraw.text((4, 4), cfg.label, fill=(220, 220, 220), font=label_font)

	for i, c in enumerate(chars):
		row_num, sx, wide = layout[i]
		cp   = ord(c)
		sy   = header_h + row_num * (slot_h + LABEL_H)
		w_px = slot_w * (2 if wide else 1)

		# Filter checks use standard-width cell so is_missing_glyph comparison stays valid
		fails    = []
		if is_emoji_by_metadata(cp):
			fails.append('EMOJI_META')
		if cp > 127 and cp in ascii_confusables:
			fails.append('ASCII_CONFUSABLE')
		std_cell = render_char(c, fnt, cfg)
		no_glyph = is_missing_glyph(std_cell, missing_pixels)
		if not no_glyph and not fails:
			# For wide chars, re-render in double-width cell for analysis
			if wide:
				acfg = copy(cfg)
				acfg.cell_w = cfg.cell_w * 2
				analysis_cell = render_char(c, fnt, acfg)
			else:
				acfg = cfg
				analysis_cell = std_cell
			if has_color_pixels(analysis_cell):
				fails.append('EMOJI_COLOR')
			metrics = analyze_cell(analysis_cell, acfg)
			if metrics['blank']:
				fails.append('BLANK')
			else:
				if metrics.get('touches_edge'):
					fails.append('EDGE')
				if metrics.get('poorly_centered'):
					fails.append('OFFCENTER')
				if metrics.get('disconnected'):
					fails.append('DISCONNECTED')

		# Display: render into wide cell if needed (disp_w = slot minus equal border on each side)
		disp_w    = w_px - 2 * BORDER_W
		disp_cell = Image.new('RGB', (disp_w, cfg.cell_h), (255, 255, 255))
		ddraw     = ImageDraw.Draw(disp_cell)
		try:
			bbox = fnt.getbbox(c)
			gw = bbox[2] - bbox[0]
			gh = bbox[3] - bbox[1]
			ddraw.text(((disp_w - gw) // 2 - bbox[0], (cfg.cell_h - gh) // 2 - bbox[1]),
				c, fill=(0, 0, 0), font=fnt)
		except Exception:
			pass

		decision = char_decisions.get(c, 'pass')
		if decision == 'fail_confusable':
			border_color = (0x00, 0x00, 0x00)  # black  = ASCII confusable
		elif decision == 'fail_meta':
			border_color = (0xff, 0x88, 0x00)  # orange = other non-visual rule (emoji metadata)
		elif decision == 'fail_visual':
			this_font_voted_no = any(f not in ('EMOJI_META', 'ASCII_CONFUSABLE') for f in fails)
			border_color = (0xff, 0x00, 0x00) if this_font_voted_no else (0xc0, 0x80, 0x80)
		else:
			border_color = (60, 60, 180) if no_glyph else (0, 180, 0)
		gdraw.rectangle([sx, sy, sx + w_px - 1, sy + slot_h - 1], fill=border_color)
		grid.paste(disp_cell, (sx + BORDER_W, sy + BORDER_W))
		gdraw.text((sx + BORDER_W + 1, sy + slot_h + 1), f"{cp:04X}",
			fill=(60, 60, 60), font=label_font)

	return grid

def composite_images(images):
	"""Arrange images left-to-right, top-to-bottom in the cols×rows layout closest to 16:9,
	   without the composite exceeding 2:1 or 3:4 aspect ratio.
	   Each grid cell is sized to the maximum image width/height across all images.
	"""
	if len(images) == 1:
		return images[0]

	n      = len(images)
	cell_w = max(img.width  for img in images)
	cell_h = max(img.height for img in images)

	TARGET = 16 / 9   # ideal aspect ratio
	MAX_AR =  2 / 1   # wider than this → excluded
	MIN_AR =  3 / 4   # taller than this → excluded

	best_cols     = None
	best_ar_diff  = float('inf')

	GAP = 16
	for cols in range(1, n + 1):
		rows    = (n + cols - 1) // cols
		ar      = (GAP + cols * (cell_w + GAP)) / (GAP + rows * (cell_h + GAP))
		if ar > MAX_AR or ar < MIN_AR:
			continue
		diff = abs(ar - TARGET)
		if diff < best_ar_diff:
			best_ar_diff = diff
			best_cols    = cols

	if best_cols is None:
		# All layouts exceed bounds; pick the one with aspect ratio closest to target anyway
		best_cols    = 1
		best_ar_diff = float('inf')
		for cols in range(1, n + 1):
			rows = (n + cols - 1) // cols
			ar   = (GAP + cols * (cell_w + GAP)) / (GAP + rows * (cell_h + GAP))
			diff = abs(ar - TARGET)
			if diff < best_ar_diff:
				best_ar_diff = diff
				best_cols    = cols

	cols    = best_cols
	rows    = (n + cols - 1) // cols
	GAP     = 16
	total_w = GAP + cols * (cell_w + GAP)
	total_h = GAP + rows * (cell_h + GAP)
	out     = Image.new('RGB', (total_w, total_h), (0, 0, 0))

	for i, img in enumerate(images):
		x = GAP + (i % cols) * (cell_w + GAP)
		y = GAP + (i // cols) * (cell_h + GAP)
		out.paste(img, (x, y))

	return out

# ── Core filtering ─────────────────────────────────────────────────────────────

def _filter_chars(chars):
	"""Core filter: takes a list of unique characters, returns (passed, fail_log).
	   passed:   list of characters that passed all filters.
	   fail_log: list of (cp, char, 'FAIL:reason+...', name) tuples for failures.
	"""
	ascii_confusables = load_confusables()

	# Load all fonts and compute per-font missing-glyph fingerprints
	font_setups = []  # list of (cfg, fnt, missing_pixels)
	for cfg in FONTS:
		fnt        = ImageFont.truetype(cfg.font_path, cfg.font_size)
		missing_px = get_missing_glyph_pixels(fnt, cfg)
		font_setups.append((cfg, fnt, missing_px))

	passed   = []
	fail_log = []

	for c in chars:
		cp    = ord(c)
		# ASCII characters always pass — no filter applies
		if cp < 128:
			passed.append(c)
			continue
		name  = unicodedata.name(c, '')
		fails = []

		# ── Filter 1: emoji by metadata ──
		if is_emoji_by_metadata(cp):
			fails.append('EMOJI_META')

		# ── Filter 2: ASCII confusable (skip if char is itself ASCII) ──
		if cp > 127 and cp in ascii_confusables:
			fails.append('ASCII_CONFUSABLE')

		# ── Filters 3-5: per-font pixel checks ──
		# Each font that can render the glyph casts a pass/fail vote.
		# The character fails only if >= 50% of voting fonts reject it.
		wide = unicodedata.east_asian_width(c) in ('W', 'F')
		if not fails:
			votes_total    = 0
			votes_fail     = 0
			all_font_fails = []
			for cfg, fnt, missing_px in font_setups:
				cell = render_char(c, fnt, cfg)
				if is_missing_glyph(cell, missing_px):
					continue  # this font abstains
				# Re-render wide chars in a double-width cell for accurate analysis
				if wide:
					wcfg = copy(cfg)
					wcfg.cell_w = cfg.cell_w * 2
					cell = render_char(c, fnt, wcfg)
				else:
					wcfg = cfg
				votes_total += 1
				font_fails = []
				if has_color_pixels(cell):
					font_fails.append('EMOJI_COLOR')
				metrics = analyze_cell(cell, wcfg)
				if metrics['blank']:
					font_fails.append('BLANK')
				else:
					if metrics.get('touches_edge'):
						font_fails.append('EDGE')
					if metrics.get('poorly_centered'):
						font_fails.append('OFFCENTER')
					if metrics.get('disconnected'):
						font_fails.append('DISCONNECTED')
				if font_fails:
					votes_fail += 1
					all_font_fails.extend(font_fails)
			if votes_total == 0:
				fails.append('NO_GLYPH')
			elif votes_fail / votes_total >= 0.5:
				seen = set()
				for f in all_font_fails:
					if f not in seen:
						seen.add(f)
						fails.append(f)

		if not fails:
			passed.append(c)
		else:
			fail_log.append((cp, c, 'FAIL:' + '+'.join(fails), name))

	return passed, fail_log, ascii_confusables, font_setups


def _parse_chars(text):
	"""Parse space-separated text into a list of unique characters."""
	chars = []
	for token in text.split():
		for c in token:
			if c not in chars:
				chars.append(c)
	return chars


def extract(text):
	"""Filter characters by visual acceptability.
	   Input:  space-separated characters string.
	   Output: space-separated string of passing characters.
	"""
	chars = _parse_chars(text)
	if not chars:
		return ''
	passed, _, _, _ = _filter_chars(chars)
	return ' '.join(passed)


# ── Main (CLI) ─────────────────────────────────────────────────────────────────

def main():
	debug      = '--debug' in sys.argv
	debug_dir  = DEBUG_OUTPUT_DIR
	raw_args   = sys.argv[1:]
	if '--debug-dir' in raw_args:
		idx       = raw_args.index('--debug-dir')
		debug_dir = raw_args[idx + 1]
		raw_args  = raw_args[:idx] + raw_args[idx + 2:]
	args = [a for a in raw_args if a != '--debug']

	if args:
		raw = ' '.join(args)
	else:
		raw = sys.stdin.read().strip()

	chars = _parse_chars(raw)
	if not chars:
		return

	passed, fail_log, ascii_confusables, font_setups = _filter_chars(chars)

	# ── Build per-char decision map for debug rendering ──
	char_decisions = {c: 'pass' for c in passed}
	for _cp, _c, _result, _name in fail_log:
		_reasons = set(_result.replace('FAIL:', '').split('+'))
		if _reasons <= {'EMOJI_META', 'ASCII_CONFUSABLE'}:
			char_decisions[_c] = 'fail_confusable' if 'ASCII_CONFUSABLE' in _reasons else 'fail_meta'
		else:
			char_decisions[_c] = 'fail_visual'

	# ── Output ──
	print(' '.join(passed))

	# Failure summary to stderr
	if fail_log:
		print(f"\nFiltered out {len(fail_log)} characters:", file=sys.stderr)
		col_result_w = max(len(result) for _, _, result, _ in fail_log)
		for cp, c, result, name in fail_log:
			print(f"  U+{cp:04X}  {c}  {result:<{col_result_w}}  '{name.lower()}'", file=sys.stderr)

	if debug:
		label_font = ImageFont.truetype(LABEL_FONT_PATH, LABEL_FONT_SIZE)
		grids = []
		for cfg, fnt, missing_px in font_setups:
			grid = render_font_grid(chars, fnt, cfg, label_font, ascii_confusables, missing_px, char_decisions)
			grids.append(grid)
		out_img   = composite_images(grids)
		codepoints = [ord(c) for c in chars]
		cp_lo, cp_hi = min(codepoints), max(codepoints)
		base_name = f"unicode_visual_debug_{cp_lo:04X}-{cp_hi:04X}.png"
		out_dir   = debug_dir if debug_dir else os.path.dirname(os.path.abspath(__file__))
		os.makedirs(out_dir, exist_ok=True)
		out_path  = os.path.join(out_dir, base_name)
		out_img.save(out_path)
		print(f"Debug grid saved to {out_path}", file=sys.stderr)

if __name__ == '__main__':
	main()
