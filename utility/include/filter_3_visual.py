#!/usr/bin/env python3

"""
Purpose:
	Filter Unicode characters by visual acceptability for terminal/editor use.
	Reads characters from arguments or stdin (same format as filter_out_unicode_junk.py).
	Outputs space-separated passing characters on one line.

	Usage:
		./filter_visual.py [--debug] [--debug-dir PATH] [chars ...]
		echo "chars" | ./filter_visual.py [--debug] [--debug-dir PATH]

	--debug:           writes unicode_visual_debug_<LO>-<HI>.png
	--debug-dir PATH:  directory for debug PNG (default: directory of this script)

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


##
## Configuration

LABEL_FONT_PATH  = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'
LABEL_FONT_SIZE  = 16
LABEL_H          = 24              # height of codepoint label below each cell
FONT_LABEL_H     = 30              # height of font-name header above each grid
COLS             = 32              # columns in debug grid (an even multiple of 16)
BORDER_W         = 4               # border thickness around each debug cell

# Default pixel thresholds (can be overridden per FontConfig)
FONT_SIZE_UNIFONT       = 64       # Unifont size should be X=2^y.
FONT_SIZE_SCALABLE      = int(round(FONT_SIZE_UNIFONT * 1.0, 0))
BLANK_THRESHOLD         = 25       # fewer dark pixels → blank; lower=more agressive; default: 15; good = 25 to 33
DARK_PIXEL_MAX          = 180      # luminance below this = "dark"; default: 180
EDGE_MARGIN_H           = 0.08     # fraction of cell dimension that counts as touching edge, horizontally; smaller is more tolerant; good: 0.05 to 0.15
EDGE_MARGIN_V           = 0.02     # fraction of cell dimension that counts as touching edge, vertically; smaller is more tolerant; good: 0.01 to 0.1
EDGE_MARGIN_H_WIDE      = 0.01     # same but for Wide east-asian glyphs (W/F), horizontally; complex glyphs need more tolerance
EDGE_MARGIN_V_WIDE      = 0.02     # same but for Wide east-asian glyphs (W/F), vertically; complex glyphs need more tolerance
CENTER_H_TOLERANCE      = 0.17     # fraction of CELL_W; larger is more tolerant of off-center; good val: 0.15 or 0.3; 0.17 sweet spot?
CENTER_V_TOLERANCE      = 0.21     # fraction of CELL_H; larger is more tolerant of off-center; good val: 0.15 to 0.4
COLOR_SATURATION_MIN    = 30       # per-channel diff to count as "colored" pixel; default: 30
COLOR_PIXEL_THRESHOLD   = 5        # more than this many colored pixels → emoji-like; default: 5
DISCONNECT_H_GAP        = 0.01     # fraction of cell_w; horizontal whitespace gap between components = disconnected
DISCONNECT_ANY_GAP      = 0.30     # fraction of cell dimension; whitespace gap in any direction = disconnected
DISCONNECT_H_GAP_WIDE   = 0.08    # same but for Wide east-asian glyphs (W/F)
DISCONNECT_ANY_GAP_WIDE = 0.40    # same but for Wide east-asian glyphs (W/F)
MAX_VERT_LINES          = 3       # chars with >= this many vertical lines are rejected; <1 disables
MAX_VERT_LINES_WIDE     = 0       # same for Wide east-asian glyphs (W/F); <1 disables
VERT_LINE_MIN_DENSITY   = 0.55    # fraction of bbox height that must be dark in a column to count as "vertical"
VERT_LINE_MIN_HEIGHT    = 0.40    # bbox must span at least this fraction of cell_h for rule to apply
VERT_LINE_COL_MERGE     = 2       # adjacent vertical columns within this gap merge as one line (angle tolerance)
DEBUG_OVERLAY           = True    # when True and --debug is set, draw margin/center overlays on cells

CONFUSABLES_URL  = 'https://www.unicode.org/Public/security/latest/confusables.txt'
CONFUSABLES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'confusables.txt')

# Directory for debug PNG output; empty = directory of this script
home = os.environ["HOME"]
DEBUG_OUTPUT_DIR = path = os.path.join(home, "var/unicode-visual-debug")

# ASCII alphanumerics to check confusables against
ASCII_ALPHANUM = set('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz')

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


##
## Font configurations

@dataclass
class FontConfig:
	font_path:                str
	label:                    str   = ''
	font_size:                int   = FONT_SIZE_UNIFONT
	blank_threshold:          int   = BLANK_THRESHOLD
	dark_pixel_max:           int   = DARK_PIXEL_MAX
	edge_margin_h:            float = EDGE_MARGIN_H
	edge_margin_v:            float = EDGE_MARGIN_V
	edge_margin_h_wide:       float = EDGE_MARGIN_H_WIDE
	edge_margin_v_wide:       float = EDGE_MARGIN_V_WIDE
	center_h_tolerance:       float = CENTER_H_TOLERANCE
	center_v_tolerance:       float = CENTER_V_TOLERANCE
	disconnect_h_gap:         float = DISCONNECT_H_GAP
	disconnect_any_gap:       float = DISCONNECT_ANY_GAP
	disconnect_h_gap_wide:    float = DISCONNECT_H_GAP_WIDE
	disconnect_any_gap_wide:  float = DISCONNECT_ANY_GAP_WIDE
	max_vert_lines:           int   = MAX_VERT_LINES
	max_vert_lines_wide:      int   = MAX_VERT_LINES_WIDE
	vert_line_min_density:    float = VERT_LINE_MIN_DENSITY
	vert_line_min_height:     float = VERT_LINE_MIN_HEIGHT
	vert_line_col_merge:      int   = VERT_LINE_COL_MERGE
	cell_h:                   int   = 0   # auto-computed from font_size if 0
	cell_w:                   int   = 0   # auto-computed from font_size if 0
	extra_cell_w:             int   = 0   # added to auto-computed cell_w (e.g. for wide glyphs)
	extra_cell_w_wide:        int   = 0   # extra padding added to wide (2-cell) characters' cell width

	def __post_init__(self):
		if self.cell_h == 0: self.cell_h = int(round(FONT_SIZE_UNIFONT + 4, 0))  ## A couple of pixle wiggle room top & bottom
		if self.cell_w == 0: self.cell_w = int(round( (self.cell_h // 2) + int(round(FONT_SIZE_UNIFONT * 0.34)) + self.extra_cell_w ))
			## Unifont is technically 1:2 but needs extra width to avoid false filter hits for some reason, as do the others
		self.cell_w_wide = self.cell_h + self.extra_cell_w_wide  # true 2:1 ratio + independent wide padding

FONTS = [
	FontConfig(
		## Unifont the only one that can render everything, but ugly.
		font_path = '/usr/share/fonts/opentype/unifont/unifont.otf',
		label     = 'Unifont',
		extra_cell_w = 0,
	),
	FontConfig(
		## DejaVu supposedly has good unicode coverage, but seemingly not.
		font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
		label     = 'DejaVu Sans Mono',
		extra_cell_w = 0,
		font_size = int(round(FONT_SIZE_SCALABLE * 0.87, 0)),
	),
	FontConfig(
		## This is the second-most complete font. Listed third so it's under Unifont in a 4-panel.
		font_path = '/usr/share/fonts/truetype/freefont/FreeMono.ttf',
		label     = 'Free Mono',
		extra_cell_w = 0,
		font_size = int(round(FONT_SIZE_SCALABLE * 1.035, 0)),
	),
#	FontConfig(
#		font_path = '	/usr/share/fonts/truetype/jc/liberation/LiberationMono-Regular.ttf',
#		label     = 'Liberation Sans Mono',
#		extra_cell_w = 0,
#		font_size = int(round(FONT_SIZE_SCALABLE * 1.05, 0)),
#	),
#	FontConfig(
#		font_path = '/usr/share/fonts/Monaspace/Monaspace NerdFonts/Monaspace Argon/MonaspaceArgonNF-SemiBold.otf',
#		label     = 'Monaspace Argon',
#		extra_cell_w = 0,
#		font_size = int(round(FONT_SIZE_SCALABLE * 0.82, 0)),
#	),
	FontConfig(
		font_path = '/usr/share/fonts/truetype/jc/noto/NotoSansMono-VariableFont_wdth,wght.ttf',
		label     = 'Noto Sans Mono',
		extra_cell_w = 0,
		font_size = int(round(FONT_SIZE_SCALABLE * 0.82, 0)),
	),
#	FontConfig(
#		font_path = '/usr/share/fonts/truetype/jc/envy/Envy Code R.ttf',
#		label     = 'Envy Code R',
#		extra_cell_w = 0,
#		font_size = int(round(FONT_SIZE_SCALABLE * 0.95, 0)),
#	),
]


##
## ASCII Confusables

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


##
## Emoji detection

def is_emoji_by_metadata(code_point):
	# Check known emoji blocks
	for block_lo, block_hi in EMOJI_BLOCKS:
		if block_lo <= code_point <= block_hi:
			return True
	return False

def has_color_pixels(cell_img):
	"""Return True if the cell contains non-grayscale pixels (colored emoji)."""
	rgb = cell_img.convert('RGB')
	colored_count = 0
	for r, g, b in rgb.getdata():
		if max(abs(r-g), abs(r-b), abs(g-b)) >= COLOR_SATURATION_MIN:
			colored_count += 1
			if colored_count > COLOR_PIXEL_THRESHOLD:
				return True
	return False


##
## Missing glyph detection

def get_missing_glyph_pixels(font, cfg):
	"""Render U+FFFF (guaranteed absent from compliant fonts) as a per-font fingerprint."""
	cell = render_char('\uFFFF', font, cfg)
	return tuple(cell.convert('L').getdata())

def is_missing_glyph(cell_img, missing_pixels):
	"""Return True if cell_img matches the missing-glyph fingerprint for this font."""
	return tuple(cell_img.convert('L').getdata()) == missing_pixels

def get_reference_center(font, cfg):
	"""Render 'H' and return its dark-pixel bounding-box center (col, row).
	   Used as the expected center when checking off-center glyphs, so that
	   scripts positioned relative to the baseline aren't penalized."""
	cell = render_char('H', font, cfg)
	gray = cell.convert('L')
	pixels = list(gray.getdata())
	dark = [idx for idx, p in enumerate(pixels) if p < cfg.dark_pixel_max]
	if not dark:
		return (cfg.cell_w / 2, cfg.cell_h / 2)
	rows_px = [idx // cfg.cell_w for idx in dark]
	cols_px = [idx  % cfg.cell_w for idx in dark]
	center_col = (min(cols_px) + max(cols_px)) / 2
	center_row = (min(rows_px) + max(rows_px)) / 2
	return (center_col, center_row)


##
##  Pixel analysis

def render_char(c, font, cfg):
	cell = Image.new('RGB', (cfg.cell_w, cfg.cell_h), (255, 255, 255))
	draw = ImageDraw.Draw(cell)
	try:
		# Use font metrics for consistent positioning across all glyphs,
		# so that off-center glyphs (subscripts, superscripts, etc.) are
		# genuinely off-center in the rendered cell rather than individually centered.
		ascent, descent = font.getmetrics()
		advance_width = font.getlength(c)
		if advance_width <= 0:
			advance_width = font.getlength('M')
		text_x = (cfg.cell_w - advance_width) / 2
		text_y = (cfg.cell_h - (ascent + descent)) / 2
		draw.text((text_x, text_y), c, fill=(0, 0, 0), font=font)
	except Exception:
		pass
	return cell

def analyze_cell(cell_img, cfg, ref_center=None):
	"""Returns dict of pixel metrics.
	   ref_center: (col, row) expected center from reference glyph; defaults to cell center."""
	gray = cell_img.convert('L')
	pixels = list(gray.getdata())
	dark = [idx for idx, p in enumerate(pixels) if p < cfg.dark_pixel_max]
	if len(dark) < cfg.blank_threshold:
		return {'blank': True, 'dark_count': len(dark)}
	rows_px = [idx // cfg.cell_w for idx in dark]
	cols_px = [idx  % cfg.cell_w for idx in dark]
	min_row, max_row = min(rows_px), max(rows_px)
	min_col, max_col = min(cols_px), max(cols_px)
	margin_h = round(cfg.cell_w * cfg.edge_margin_h)
	margin_v = round(cfg.cell_h * cfg.edge_margin_v)
	touches_edge = (
		min_row <= margin_v or max_row >= cfg.cell_h - 1 - margin_v or
		min_col <= margin_h or max_col >= cfg.cell_w - 1 - margin_h
	)
	center_col = (min_col + max_col) / 2
	center_row = (min_row + max_row) / 2
	ref_col = ref_center[0] if ref_center else cfg.cell_w / 2
	ref_row = ref_center[1] if ref_center else cfg.cell_h / 2
	off_h = abs(center_col - ref_col)
	off_v = abs(center_row - ref_row)
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
	for col in range(min_col, max_col + 1):
		if col not in dark_cols:
			gap += 1
			max_h_gap = max(max_h_gap, gap)
		else:
			gap = 0
	# Vertical gaps (empty rows within bounding box)
	max_v_gap = 0
	gap = 0
	for row in range(min_row, max_row + 1):
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
	# Vertical-line count: count distinct vertical lines coexisting in the
	# same horizontal band.  A sliding window of height vert_line_min_height
	# scans the bbox; at each position we find columns whose dark density
	# within that window meets vert_line_min_density, merge adjacent columns
	# into line groups, and track the maximum group count across all windows.
	vert_line_count = 0
	bbox_h = max_row - min_row + 1
	min_band_h = max(1, int(cfg.cell_h * cfg.vert_line_min_height))
	if cfg.max_vert_lines >= 1 and bbox_h >= min_band_h:
		# Build a per-column, per-row presence map within the bounding box
		col_row_dark = {}  # col -> set of rows with dark pixels
		for idx in dark:
			row = idx // cfg.cell_w
			col = idx  % cfg.cell_w
			if min_row <= row <= max_row and min_col <= col <= max_col:
				if col not in col_row_dark:
					col_row_dark[col] = set()
				col_row_dark[col].add(row)
		# Slide a window of height min_band_h across the bbox rows
		for win_top in range(min_row, max_row - min_band_h + 2):
			win_bot = win_top + min_band_h - 1
			win_h = min_band_h
			# Find columns dense enough within this window
			vert_cols = set()
			for col in range(min_col, max_col + 1):
				if col not in col_row_dark:
					continue
				count = sum(1 for row in col_row_dark[col] if win_top <= row <= win_bot)
				if count / win_h >= cfg.vert_line_min_density:
					vert_cols.add(col)
			# Merge adjacent columns into line groups
			if vert_cols:
				sorted_vert_cols = sorted(vert_cols)
				groups = 1
				for i in range(1, len(sorted_vert_cols)):
					if sorted_vert_cols[i] - sorted_vert_cols[i - 1] > cfg.vert_line_col_merge + 1:
						groups += 1
				if groups > vert_line_count:
					vert_line_count = groups
	too_many_vert_lines = cfg.max_vert_lines >= 1 and vert_line_count >= cfg.max_vert_lines
	return {
		'blank': False,
		'dark_count': len(dark),
		'touches_edge': touches_edge,
		'poorly_centered': poorly_centered,
		'disconnected': disconnected,
		'too_many_vert_lines': too_many_vert_lines,
		'vert_line_count': vert_line_count,
		'off_h': off_h,
		'off_v': off_v,
		'center_c': center_col,
		'center_r': center_row,
	}


##
##  Debug rendering

def render_font_grid(chars, font, cfg, label_font, ascii_confusables, missing_pixels, char_decisions, ref_center=None):
	"""Render a debug grid image for one font, with pass/fail/no-glyph colored borders.
	   Green  = pass
	   Blue   = pass, but this font has no glyph (abstained)
	   Black  = ASCII confusable
	   Orange = failed other non-visual rule (emoji metadata)
	   Purple  = failed vertical-line count (VERT_LINES)
	   Cyan    = failed disconnection check (DISCONNECTED)
	   Magenta = failed off-center check (OFFCENTER)
	   Red     = failed edge check (touches cell boundary)
	   Muted variants (lighter shades) = this font voted "yes" or abstained (tofu)
	   East-Asian wide (W/F) characters are drawn at double width.
	"""
	cell_gap      = 4                # gap between adjacent glyph boxes
	slot_w        = cfg.cell_w + 2 * BORDER_W
	slot_w_wide   = cfg.cell_w_wide + 2 * BORDER_W
	slot_h        = cfg.cell_h + 2 * BORDER_W
	step_w        = slot_w + cell_gap
	step_w_wide   = slot_w_wide + cell_gap
	row_px_limit  = step_w * COLS   # wrap rows at this many pixels

	##
	##  Pre-pass: compute (row_num, slot_x, is_wide) for each char

	layout  = []
	row_num = 0
	row_x   = 0
	for c in chars:
		wide    = unicodedata.east_asian_width(c) in ('W', 'F')
		step_px = step_w_wide if wide else step_w
		if row_x > 0 and row_x + step_px > row_px_limit:
			row_num += 1
			row_x = 0
		layout.append((row_num, row_x, wide))
		row_x += step_px
	num_rows = (layout[-1][0] + 1) if layout else 1

	header_h = FONT_LABEL_H if cfg.label else 0
	grid_w   = row_px_limit
	grid_h   = header_h + (slot_h + cell_gap + LABEL_H) * num_rows
	grid     = Image.new('RGB', (grid_w, grid_h), (180, 180, 180))
	gdraw    = ImageDraw.Draw(grid)

	if cfg.label:
		gdraw.rectangle([0, 0, grid_w - 1, header_h - 1], fill=(60, 60, 60))
		gdraw.text((4, 4), cfg.label, fill=(220, 220, 220), font=label_font)

	for i, c in enumerate(chars):
		row_num, slot_x, wide = layout[i]
		code_point = ord(c)
		slot_y     = header_h + row_num * (slot_h + cell_gap + LABEL_H)
		slot_w_px  = slot_w_wide if wide else slot_w

		# Filter checks use standard-width cell so is_missing_glyph comparison stays valid
		fails    = []
		metrics  = None
		if is_emoji_by_metadata(code_point):
			fails.append('EMOJI_META')
		if code_point > 127 and code_point in ascii_confusables:
			fails.append('ASCII_CONFUSABLE')
		std_cell = render_char(c, font, cfg)
		no_glyph = is_missing_glyph(std_cell, missing_pixels)
		if not no_glyph and not fails:
			# For wide chars, re-render in double-width cell for analysis
			if wide:
				acfg = copy(cfg)
				acfg.cell_w = cfg.cell_w_wide
				acfg.edge_margin_h = cfg.edge_margin_h_wide
				acfg.edge_margin_v = cfg.edge_margin_v_wide
				acfg.disconnect_h_gap = cfg.disconnect_h_gap_wide
				acfg.disconnect_any_gap = cfg.disconnect_any_gap_wide
				acfg.max_vert_lines = cfg.max_vert_lines_wide
				analysis_cell = render_char(c, font, acfg)
				grid_ref_ctr = (ref_center[0] + (cfg.cell_w_wide - cfg.cell_w) / 2, ref_center[1]) if ref_center else None
			else:
				acfg = cfg
				analysis_cell = std_cell
				grid_ref_ctr = ref_center
			if has_color_pixels(analysis_cell):
				fails.append('EMOJI_COLOR')
			metrics = analyze_cell(analysis_cell, acfg, ref_center=grid_ref_ctr)
			if metrics['blank']:
				fails.append('BLANK')
			else:
				if metrics.get('touches_edge'):
					fails.append('EDGE')
				if metrics.get('poorly_centered'):
					fails.append('OFFCENTER')
				if metrics.get('disconnected'):
					fails.append('DISCONNECTED')
				if metrics.get('too_many_vert_lines'):
					fails.append('VERT_LINES')

		# Display: render into wide cell if needed (disp_w = slot minus equal border on each side)
		disp_w    = slot_w_px - 2 * BORDER_W
		if DEBUG_OVERLAY:
			# Use render_char positioning (same as analysis) so overlays align accurately
			if wide:
				dcfg = copy(cfg)
				dcfg.cell_w = disp_w
				disp_cell = render_char(c, font, dcfg)
			else:
				disp_cell = render_char(c, font, cfg)
				# render_char uses cfg.cell_w which equals disp_w for non-wide
		else:
			disp_cell = Image.new('RGB', (disp_w, cfg.cell_h), (255, 255, 255))
			ddraw     = ImageDraw.Draw(disp_cell)
			try:
				bbox = font.getbbox(c)
				glyph_width  = bbox[2] - bbox[0]
				glyph_height = bbox[3] - bbox[1]
				ddraw.text(((disp_w - glyph_width) // 2 - bbox[0], (cfg.cell_h - glyph_height) // 2 - bbox[1]),
					c, fill=(0, 0, 0), font=font)
			except Exception:
				pass

		decision, decision_reasons = char_decisions.get(c, ('pass', set()))
		if decision == 'fail_confusable':
			border_color = (0x00, 0x00, 0x00)  # black  = ASCII confusable
		elif decision == 'fail_meta':
			border_color = (0xff, 0x88, 0x00)  # orange = emoji metadata
		elif decision == 'fail_visual':
			this_font_voted_no = any(f not in ('EMOJI_META', 'ASCII_CONFUSABLE') for f in fails)
			# Pick color by most specific fail reason (priority: vert_lines > disconnected > offcenter > generic)
			if 'VERT_LINES' in decision_reasons:
				border_color = (0x80, 0x00, 0xc0) if this_font_voted_no else (0xa0, 0x80, 0xc0)  # purple
			elif 'DISCONNECTED' in decision_reasons:
				border_color = (0x00, 0xc0, 0xc0) if this_font_voted_no else (0x80, 0xc0, 0xc0)  # cyan
			elif 'OFFCENTER' in decision_reasons:
				border_color = (0xff, 0x00, 0xff) if this_font_voted_no else (0xc0, 0x80, 0xc0)  # magenta
			else:
				border_color = (0xff, 0x00, 0x00) if this_font_voted_no else (0xc0, 0x80, 0x80)  # red
		else:
			border_color = (60, 60, 180) if no_glyph else (0, 180, 0)
		gdraw.rectangle([slot_x, slot_y, slot_x + slot_w_px - 1, slot_y + slot_h - 1], fill=border_color)
		grid.paste(disp_cell, (slot_x + BORDER_W, slot_y + BORDER_W))

		##
		## Debug overlays

		if DEBUG_OVERLAY:
			overlay = Image.new('RGBA', (disp_w, cfg.cell_h), (0, 0, 0, 0))
			odraw   = ImageDraw.Draw(overlay)
			# Compute margins matching the analysis cell
			ov_edge_margin_h = cfg.edge_margin_h_wide if wide else cfg.edge_margin_h
			ov_edge_margin_v = cfg.edge_margin_v_wide if wide else cfg.edge_margin_v
			margin_h = round(disp_w    * ov_edge_margin_h)
			margin_v = round(cfg.cell_h * ov_edge_margin_v)
			margin_color = (128, 128, 128, 160)
			# Edge margin bands (left, right, top, bottom)
			if margin_h > 0:
				odraw.rectangle([0, 0, margin_h - 1, cfg.cell_h - 1], fill=margin_color)
				odraw.rectangle([disp_w - margin_h, 0, disp_w - 1, cfg.cell_h - 1], fill=margin_color)
			if margin_v > 0:
				odraw.rectangle([0, 0, disp_w - 1, margin_v - 1], fill=margin_color)
				odraw.rectangle([0, cfg.cell_h - margin_v, disp_w - 1, cfg.cell_h - 1], fill=margin_color)
			# Center tolerance zone (light blue rectangle around reference center)
			ref_pt = ref_center if ref_center else (disp_w / 2, cfg.cell_h / 2)
			if wide and ref_center:
				ref_pt = (ref_center[0] + (cfg.cell_w_wide - cfg.cell_w) / 2, ref_center[1])
			tol_half_w = disp_w    * cfg.center_h_tolerance
			tol_half_h = cfg.cell_h * cfg.center_v_tolerance
			tol_color = (100, 150, 255, 120)
			odraw.rectangle([
				int(ref_pt[0] - tol_half_w), int(ref_pt[1] - tol_half_h),
				int(ref_pt[0] + tol_half_w), int(ref_pt[1] + tol_half_h)
			], fill=tol_color)
			# Crosshair at actual glyph bounding-box center (red)
			if not no_glyph and metrics and not metrics.get('blank'):
				glyph_center_x = metrics.get('center_c')
				glyph_center_y = metrics.get('center_r')
				if glyph_center_x is not None and glyph_center_y is not None:
					cross_color = (255, 0, 0, 100)
					odraw.line([(int(glyph_center_x), 0), (int(glyph_center_x), cfg.cell_h - 1)], fill=cross_color, width=1)
					odraw.line([(0, int(glyph_center_y)), (disp_w - 1, int(glyph_center_y))], fill=cross_color, width=1)
			# Composite overlay onto grid
			cell_x = slot_x + BORDER_W
			cell_y = slot_y + BORDER_W
			region = grid.crop((cell_x, cell_y, cell_x + disp_w, cell_y + cfg.cell_h)).convert('RGBA')
			composited = Image.alpha_composite(region, overlay)
			grid.paste(composited.convert('RGB'), (cell_x, cell_y))
		gdraw.text((slot_x + BORDER_W + 1, slot_y + slot_h + 1), f"{code_point:04X}",
			fill=(60, 60, 60), font=label_font)

	return grid

def composite_images(images):
	"""Arrange images left-to-right, top-to-bottom in the cols×rows layout closest to 16:9,
	   without the composite exceeding 2:1 or 3:4 aspect ratio.
	   Each grid cell is sized to the maximum image width/height across all images.
	"""
	if len(images) == 1:
		return images[0]

	image_count = len(images)
	cell_w = max(img.width  for img in images)
	cell_h = max(img.height for img in images)

	TARGET = 16 / 9   # ideal aspect ratio
	MAX_AR =  2 / 1   # wider than this → excluded
	MIN_AR =  1 / 1   # taller than this → excluded

	best_cols     = None
	best_ar_diff  = float('inf')

	GAP = 16
	for cols in range(1, image_count + 1):
		rows    = (image_count + cols - 1) // cols
		aspect_ratio = (GAP + cols * (cell_w + GAP)) / (GAP + rows * (cell_h + GAP))
		if aspect_ratio > MAX_AR or aspect_ratio < MIN_AR:
			continue
		diff = abs(aspect_ratio - TARGET)
		if diff < best_ar_diff:
			best_ar_diff = diff
			best_cols    = cols

	if best_cols is None:
		# All layouts exceed bounds; pick the one with aspect ratio closest to target anyway
		best_cols    = 1
		best_ar_diff = float('inf')
		for cols in range(1, image_count + 1):
			rows = (image_count + cols - 1) // cols
			aspect_ratio = (GAP + cols * (cell_w + GAP)) / (GAP + rows * (cell_h + GAP))
			diff = abs(aspect_ratio - TARGET)
			if diff < best_ar_diff:
				best_ar_diff = diff
				best_cols    = cols

	cols    = best_cols
	rows    = (image_count + cols - 1) // cols
	GAP     = 16
	total_w = GAP + cols * (cell_w + GAP)
	total_h = GAP + rows * (cell_h + GAP)
	out     = Image.new('RGB', (total_w, total_h), (0, 0, 0))

	for i, img in enumerate(images):
		paste_x = GAP + (i % cols) * (cell_w + GAP)
		paste_y = GAP + (i // cols) * (cell_h + GAP)
		out.paste(img, (paste_x, paste_y))

	return out

def append_legend(img):
	"""Append a color legend bar to the bottom of the image, centered."""
	legend_items = [
		((0, 180, 0),       'Pass'),
		((60, 60, 180),     'No glyph (abstain)'),
		((0x00, 0x00, 0x00),'ASCII confusable'),
		((0xff, 0x88, 0x00),'Emoji / metadata'),
		((0x80, 0x00, 0xc0),'Vertical lines'),
		((0x00, 0xc0, 0xc0),'Disconnected'),
		((0xff, 0x00, 0xff),'Off-center'),
		((0xff, 0x00, 0x00),'Edge'),
		((0xc0, 0x80, 0x80),'Failed (font abstained)'),
	]
	legend_font = ImageFont.truetype(LABEL_FONT_PATH, 15)
	swatch_w = 36
	swatch_h = 36
	padding  = 18
	gap      = 36    # between items

	# Measure total width to center
	total_w = 0
	for color, text in legend_items:
		total_w += swatch_w + 8 + int(legend_font.getlength(text)) + gap
	total_w -= gap  # no trailing gap

	legend_h = swatch_h + 2 * padding
	legend = Image.new('RGB', (img.width, legend_h), (40, 40, 40))
	ldraw  = ImageDraw.Draw(legend)
	cursor_x = max(padding, (img.width - total_w) // 2)
	for color, text in legend_items:
		y_swatch = (legend_h - swatch_h) // 2
		ldraw.rectangle([cursor_x, y_swatch, cursor_x + swatch_w - 1, y_swatch + swatch_h - 1], fill=color)
		text_x = cursor_x + swatch_w + 8
		# Vertically center text with swatch
		text_bbox = legend_font.getbbox(text)
		text_h = text_bbox[3] - text_bbox[1]
		text_y = y_swatch + (swatch_h - text_h) // 2 - text_bbox[1]
		ldraw.text((text_x, text_y), text, fill=(200, 200, 200), font=legend_font)
		text_w = legend_font.getlength(text)
		cursor_x = text_x + int(text_w) + gap
		if cursor_x > img.width - 50:
			break

	out = Image.new('RGB', (img.width, img.height + legend_h), (0, 0, 0))
	out.paste(img, (0, 0))
	out.paste(legend, (0, img.height))
	return out


##
## Core filtering

def _filter_chars(chars):
	"""Core filter: takes a list of unique characters, returns (passed, fail_log).
	   passed:   list of characters that passed all filters.
	   fail_log: list of (code_point, char, 'FAIL:reason+...', name) tuples for failures.
	"""
	ascii_confusables = load_confusables()

	# Load all fonts and compute per-font missing-glyph fingerprints + reference centers
	font_setups = []  # list of (cfg, font, missing_pixels, ref_center)
	for cfg in FONTS:
		font       = ImageFont.truetype(cfg.font_path, cfg.font_size)
		missing_px = get_missing_glyph_pixels(font, cfg)
		ref_ctr    = get_reference_center(font, cfg)
		font_setups.append((cfg, font, missing_px, ref_ctr))

	passed   = []
	fail_log = []

	for c in chars:
		code_point = ord(c)
		# ASCII characters always pass — no filter applies
		if code_point < 128:
			passed.append(c)
			continue
		# Latin-1 Supplement (U+0080–U+00FF) always passes, like ASCII
		if 0x80 <= code_point <= 0xFF:
			passed.append(c)
			continue
		name  = unicodedata.name(c, '')
		fails = []

		## Filter 1: emoji by metadata
		if is_emoji_by_metadata(code_point):
			fails.append('EMOJI_META')

		## Filter 2: ASCII confusable (skip if char is itself ASCII)
		if code_point > 127 and code_point in ascii_confusables:
			fails.append('ASCII_CONFUSABLE')

		## Filters 3-5: per-font pixel checks
		# Each font that can render the glyph casts a pass/fail vote.
		# The character fails only if >= 50% of voting fonts reject it.
		wide = unicodedata.east_asian_width(c) in ('W', 'F')
		if not fails:
			votes_total    = 0
			votes_fail     = 0
			all_font_fails = []
			for cfg, font, missing_px, ref_ctr in font_setups:
				cell = render_char(c, font, cfg)
				if is_missing_glyph(cell, missing_px):
					continue  # this font abstains
				# Re-render wide chars in a double-width cell for accurate analysis
				if wide:
					wcfg = copy(cfg)
					wcfg.cell_w = cfg.cell_w_wide
					wcfg.edge_margin_h = cfg.edge_margin_h_wide
					wcfg.edge_margin_v = cfg.edge_margin_v_wide
					wcfg.disconnect_h_gap = cfg.disconnect_h_gap_wide
					wcfg.disconnect_any_gap = cfg.disconnect_any_gap_wide
					wcfg.max_vert_lines = cfg.max_vert_lines_wide
					cell = render_char(c, font, wcfg)
					wide_ref_ctr = (ref_ctr[0] + (cfg.cell_w_wide - cfg.cell_w) / 2, ref_ctr[1])
				else:
					wcfg = cfg
					wide_ref_ctr = ref_ctr
				votes_total += 1
				font_fails = []
				if has_color_pixels(cell):
					font_fails.append('EMOJI_COLOR')
				metrics = analyze_cell(cell, wcfg, ref_center=wide_ref_ctr)
				if metrics['blank']:
					font_fails.append('BLANK')
				else:
					if metrics.get('touches_edge'):
						font_fails.append('EDGE')
					if metrics.get('poorly_centered'):
						font_fails.append('OFFCENTER')
					if metrics.get('disconnected'):
						font_fails.append('DISCONNECTED')
					if metrics.get('too_many_vert_lines'):
						font_fails.append('VERT_LINES')
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
			fail_log.append((code_point, c, 'FAIL:' + '+'.join(fails), name))

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


##
## Main (CLI)

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

	##
	## Build per-char decision map for debug rendering

	char_decisions = {c: ('pass', set()) for c in passed}
	for _code_point, _c, _result, _name in fail_log:
		_reasons = set(_result.replace('FAIL:', '').split('+'))
		if _reasons <= {'EMOJI_META', 'ASCII_CONFUSABLE'}:
			char_decisions[_c] = ('fail_confusable', _reasons) if 'ASCII_CONFUSABLE' in _reasons else ('fail_meta', _reasons)
		else:
			char_decisions[_c] = ('fail_visual', _reasons)

	##
	## Output

	print(' '.join(passed))

	# Failure summary to stderr
	if fail_log:
		print(f"\nFiltered out {len(fail_log)} characters:", file=sys.stderr)
		col_result_w = max(len(result) for _, _, result, _ in fail_log)
		for code_point, c, result, name in fail_log:
			print(f"  U+{code_point:04X}  {c}  {result:<{col_result_w}}  '{name.lower()}'", file=sys.stderr)

	if debug:
		label_font = ImageFont.truetype(LABEL_FONT_PATH, LABEL_FONT_SIZE)
		grids = []
		for cfg, font, missing_px, ref_ctr in font_setups:
			grid = render_font_grid(chars, font, cfg, label_font, ascii_confusables, missing_px, char_decisions, ref_center=ref_ctr)
			grids.append(grid)
		out_img   = append_legend(composite_images(grids))
		code_points = [ord(c) for c in chars]
		code_point_lo, code_point_hi = min(code_points), max(code_points)
		base_name = f"unicode_visual_debug_{code_point_lo:04X}-{code_point_hi:04X}.png"
		out_dir   = debug_dir if debug_dir else os.path.dirname(os.path.abspath(__file__))
		os.makedirs(out_dir, exist_ok=True)
		out_path  = os.path.join(out_dir, base_name)
		out_img.save(out_path)
		print(f"Debug grid saved to {out_path}", file=sys.stderr)

if __name__ == '__main__':
	main()
