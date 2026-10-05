#!/usr/bin/env python3

##	Purpose: Render an animated demo GIF of a CLI program, without recording a
##		real terminal (no ttyd, no asciinema, no ffmpeg - just Pillow). A TOML
##		scenario file scripts the session; each command is "typed" into a fake
##		terminal window with human timing (slower digits, a beat before flags,
##		the occasional corrected typo), then actually executed so the captured
##		output can never go stale. Motion runs at 50 fps, the fastest a GIF can
##		go: scrolling is pixel-smooth at a constant velocity and the cursor
##		eases between cells rather than teleporting. A step whose output is
##		taller than the window starts on a cleared screen. At the end it holds
##		the last frame still, then
##		hard-cuts to a black frame before repeating - a held black frame is one
##		cheap frame, not a bloaty fade. Frames share one exact master palette,
##		so nothing is ever re-dithered, and gifsicle takes a lossless size pass
##		at the end when it is installed.
##		Project-agnostic - point it at any scenario.
##	Syntax:
##		gen-demo-gif.py --scenario FILE --out FILE [--bin PATH] [--seed N]
##		  --scenario FILE  TOML scenario (see load_scenario for the format)
##		  --out FILE       GIF to write (required)
##		  --bin PATH       program under demo; substituted for {bin} in run=
##		                   ({here} in a run= line is the scenario's own directory)
##		  --seed N         RNG seed; fixed default so reruns are byte-stable
##		  --font NAME      override the scenario's font preference list
##		  --quiet          only errors
##	Exit: 0 wrote the GIF, 2 non-fatal skip (no Pillow, bad scenario, cmd failed).
##	History: At bottom of script.

##	Copyright (c) 2026 Bubbles
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


import argparse
import io
import random
import re
import shlex
import subprocess
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import Any, NamedTuple, NoReturn

try:
	import tomllib
except ImportError:
	sys.stderr.write("gen-demo-gif: needs python 3.11+ (tomllib)\n")
	sys.exit(2)
try:
	from PIL import Image, ImageDraw, ImageFont
except ImportError:
	sys.stderr.write("gen-demo-gif: Pillow not installed\n")
	sys.exit(2)


##	Canvas and window chrome. 960x540 total; the window fills the whole view
##	except a thin black border. Square corners, no shadow.
CANVAS_W, CANVAS_H = 960, 540
MARGIN     = 4        # thin black border around the window
TITLE_H    = 34       # title bar height
PAD        = 12       # text inset inside the terminal area

Rgb = tuple[int, int, int]
Span = tuple[str, str]                   # (text, THEME key)
Step = dict[str, Any]                    # one [[step]] table from the scenario

THEME: dict[str, Rgb] = {
	"outer":    (0, 0, 0),         # thin border around the window
	"border":   (58, 58, 62),      # 1px window outline
	"titlebar": (44, 44, 48),
	"titletxt": (150, 150, 152),
	"bg":       (30, 32, 30),      # terminal background: dark gray, hint of warmth
	"fg":       (166, 227, 161),   # bright pale green
	"gray":     (148, 148, 148),   # prompt punctuation ("standard gray")
	"dim":      (106, 112, 106),   # comments, truncation ellipsis
}
TRAFFIC_LIGHTS: list[Rgb] = [(158, 96, 92), (158, 142, 92), (105, 148, 100)]   # muted
##	user@host tints: dimmer than fg, complementary hues (green sits across from
##	these on the wheel). Two distinct picks per run, seeded.
IDENT_TINTS: list[Rgb] = [
	(196, 148, 108),   # tan
	(160, 136, 200),   # violet
	(112, 178, 196),   # cyan
	(198, 140, 156),   # rose
	(170, 166, 108),   # olive
]
IDENT_USERS = ["mika", "joss", "arlo", "remy", "kai", "nova", "wren", "finn"]
IDENT_HOSTS = ["basalt", "kestrel", "onyx", "lyra", "quartz", "mesa", "flint", "juno"]

##	Typing model. WPM -> ms/char at the usual 5 chars/word.
WPM_LETTERS   = (155, 210)   # per-command draw, then per-char jitter
WPM_DIGITS    = 72           # default; scenario wpm_digits overrides
WPM_NOTES     = (268, 302)   # "# comment" lines fly by
FLAG_PAUSE_MS = (200, 380)   # a beat of thought before a -flag token
TYPO_RATE     = 0.018        # per letter; capped at 2 fixes per command
PASTE_MIN     = 24           # a value at least this long arrives pasted, not typed
BLINK_MS      = 530
##	50 fps. A GIF delay is centiseconds and every browser clamps 0 and 1 cs up to
##	10 cs, so 2 cs is the real floor - there is no smoother GIF than this.
FRAME_MS      = 20           # frame interval while anything is moving
SCROLL_RATE   = 448          # px/s smooth scroll; per-step scrollrate overrides
GLIDE_FRAMES  = 3            # frames the cursor block takes to reach a new cell

QWERTY_ROWS = ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"]
PASTE_RE = re.compile(r"[0-9][0-9.]*")

ANSI_RE = re.compile(r"\x1b(\[[0-9;?]*[ -/]*[@-~]|\][^\x07\x1b]*(\x07|\x1b\\)|.)")


@dataclass(frozen=True)
class EmojiKit:
	pango: ModuleType
	pango_cairo: ModuleType
	cairo: ModuleType
	family: str
	cmap: set[int]                       # codepoints the emoji face covers


class KeyEvent(NamedTuple):
	action: str                          # "type", "bs" or "pause"
	text: str | None                     # what "type" adds
	delay: float                         # ms


class TypedLine(NamedTuple):
	text: str
	color: str                           # THEME key; "fg" is a command, "dim" a note
	wpm: tuple[float, float]
	typos: bool
	scale: float


def emoji_init() -> EmojiKit | None:
	##	Color emoji are beyond FreeType-via-Pillow now (Noto ships COLRv1), so
	##	glyph tiles come from Pango+cairo instead. Everything here is optional:
	##	if any piece is missing the chars just draw through the monochrome
	##	fallback like before.
	try:
		import gi
		import cairo
		gi.require_version("Pango", "1.0")
		gi.require_version("PangoCairo", "1.0")
		from gi.repository import Pango, PangoCairo
		from fontTools.ttLib import TTFont
	except (ImportError, ValueError):
		return None
	try:
		out = subprocess.run(["fc-match", "-f", "%{file}\t%{family}", "emoji"],
		                     capture_output=True, text=True, timeout=10).stdout
		path, family = (out.split("\t") + [""])[:2]
		if "emoji" not in family.lower():
			return None
		cmap = set(TTFont(path, lazy=True).getBestCmap())
	except Exception:
		return None
	return EmojiKit(Pango, PangoCairo, cairo, family, cmap)


EMOJI = emoji_init()


def optimize_gif(path: Path) -> bool:
	##	Another sixth off, losslessly: gifsicle can mark individual unchanged
	##	pixels transparent per frame, where Pillow only ever writes one changed
	##	rectangle. Pixels and frame delays come out identical, so this is purely
	##	a size pass. Skipped when gifsicle is not installed - the gif is just
	##	bigger, which is why it is a probe and not a requirement.
	tmp = path.with_name(path.name + ".gifsicle")
	try:
		res = subprocess.run(["gifsicle", "-O2", "--no-warnings", path, "-o", tmp],
		                     capture_output=True, text=True, timeout=600)
		if res.returncode == 0 and tmp.stat().st_size > 0:
			tmp.replace(path)
			return True
	except (OSError, subprocess.TimeoutExpired):
		pass
	tmp.unlink(missing_ok=True)
	return False


def skip(msg: str) -> NoReturn:
	##	2 = non-fatal skip, same convention as the other cicd utilities: the
	##	stage warns and the pipeline continues.
	sys.stderr.write(f"gen-demo-gif: {msg}\n")
	sys.exit(2)


def find_font(prefs: list[str], size: int) -> tuple[ImageFont.FreeTypeFont, str]:
	##	Resolve the first available preference via fc-match. fc-match always
	##	answers with its best match, so verify the family before trusting it;
	##	the final fallback takes whatever monospace fontconfig offers.
	for name in prefs + ["monospace"]:
		try:
			out = subprocess.run(
				["fc-match", "-f", "%{file}\t%{family}\t%{style}", name],
				capture_output=True, text=True, timeout=10).stdout
		except OSError:
			break
		path, family, style = (out.split("\t") + ["", ""])[:3]
		want = re.sub(r"[^a-z]", "", name.lower())
		got  = re.sub(r"[^a-z]", "", (family + style).lower())
		if name == "monospace" or (path and want in got):
			try:
				return ImageFont.truetype(path, size), f"{family} {style}".strip()
			except OSError:
				continue
	skip("no usable monospace font found")


def load_scenario(path: str) -> dict[str, Any]:
	##	Scenario format (TOML):
	##	  title = "window title"        prog = "name shown in typed commands"
	##	  font = ["pref1", "pref2"]     seed = 11
	##	  wpm_digits = 42               digit typing speed (numbers-heavy demos: raise it)
	##	  end_hold = 3.0                seconds the final frame holds before the loop
	##	  end_black = 2.0               seconds of black after the hold, then repeat
	##	  [[step]]
	##	  note = "typed as a # comment first"           (optional; a list = one
	##	                                                 comment line per element)
	##	  show = "{prog} 255 16"        the command line as typed (optional: a step
	##	                                with only notes types them and pauses)
	##	  run  = "echo hi | {bin} ..."  what actually executes (default: show)
	##	  pause = 2.6                   read time after the output, seconds
	##	  overflow = "truncate"         or "wrap" for real feature output
	##	  scrollrate = 260              px/s smooth scroll during this step's output
	##	  linems = 26                   ms per output line before scrolling kicks in
	##	  gap = true                    blank line between the command and its output
	##	  paste = true                  long numbers in show= arrive pasted, not typed
	##	  pastepause = 1.0              hesitation before a pasted value lands, seconds
	##	  preenter = 2.0                cursor holds at the end of the command, seconds
	##	  typescale = 1.5               command typing speed multiplier (notes unaffected)
	##	  notepause = 0.5               read time after each note line, seconds
	##	  clear = true                  start on a blank screen (default: output taller
	##	                                than the window clears, shorter output does not)
	try:
		with open(path, "rb") as f:
			sc = tomllib.load(f)
	except (OSError, tomllib.TOMLDecodeError) as e:
		skip(f"scenario: {e}")
	if not sc.get("step"):
		skip("scenario has no [[step]] entries")
	for step in sc["step"]:
		if not step.get("show") and not step_notes(step):
			skip("scenario has a step with neither show= nor note=")
	return sc


def step_notes(step: Step) -> list[str]:
	##	A step's comment lines: one string, or a list of them.
	note = step.get("note", [])
	return [note] if isinstance(note, str) else list(note)


def run_step(step: Step, binpath: str, here: str) -> list[str]:
	##	Execute the step's command for real; merged stdout+stderr becomes the
	##	demo output, so notes the program prints on stderr show up too.
	if not step.get("show") and not step.get("run"):
		return []                        # a notes-only step has nothing to run
	cmd: str = step["run"] if "run" in step else step["show"]
	cmd = cmd.replace("{bin}", shlex.quote(binpath)).replace("{prog}", shlex.quote(binpath))
	cmd = cmd.replace("{here}", shlex.quote(here))
	try:
		res = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True,
		                     timeout=30, errors="replace")
	except subprocess.TimeoutExpired:
		skip(f"command timed out: {cmd}")
	out = ANSI_RE.sub("", res.stdout + res.stderr)
	return [ln.expandtabs(8).rstrip() for ln in out.rstrip("\n").split("\n")]


def type_events(text: str, rng: random.Random, wpm_range: tuple[float, float],
                typos: bool = True, wpm_digits: float = WPM_DIGITS, paste: bool = False,
                scale: float = 1.0, paste_pre: float = 0.0) -> list[KeyEvent]:
	##	Turn a command string into keystroke events.
	##	Letters ride the per-command WPM draw with per-char jitter, digits get
	##	their own WPM (slow by default, fast for numbers-heavy demos), a -flag
	##	token gets a small hesitation, and a couple of seeded typos get noticed
	##	and backspaced away.
	##	Under paste, a long number arrives in one event. Nobody types a thousand
	##	digits, and at one frame per keystroke it would cost more frames than the
	##	rest of the demo put together.
	wpm = rng.uniform(*wpm_range) * scale
	wpm_digits *= scale
	events: list[KeyEvent] = []
	fixes = 0
	lead_len = len(text.partition(" ")[0])
	for i, ch in type_units(text, paste):
		if len(ch) > 1:
			if paste_pre > 0:
				events.append(KeyEvent("pause", None, paste_pre))   # a beat before it lands
			events.append(KeyEvent("type", ch, rng.uniform(280, 420)))
			continue
		if ch.isdigit():
			delay = 60000.0 / (wpm_digits * 5) * rng.uniform(0.82, 1.22)
		else:
			delay = 60000.0 / (wpm * 5) * rng.uniform(0.70, 1.34)
			if i < lead_len:
				delay *= 0.78        # the leading token is muscle memory
		if ch == "-" and (i == 0 or text[i - 1] == " "):
			delay += rng.uniform(*FLAG_PAUSE_MS)
		if typos and fixes < 2 and ch.isalpha() and rng.random() < TYPO_RATE:
			wrong = neighbor_key(ch, rng)
			events.append(KeyEvent("type", wrong, delay))
			overshoot = None
			if i + 1 < len(text) and text[i + 1].isalpha() and rng.random() < 0.4:
				overshoot = text[i + 1]      # one more char before noticing
				events.append(KeyEvent("type", overshoot, 60000.0 / (wpm * 5)))
			events.append(KeyEvent("pause", None, rng.uniform(320, 640)))
			for _ in range(2 if overshoot else 1):
				events.append(KeyEvent("bs", None, rng.uniform(95, 150)))
			events.append(KeyEvent("type", ch, rng.uniform(140, 260)))
			fixes += 1
			continue
		events.append(KeyEvent("type", ch, delay))
	return events


def type_units(text: str, paste: bool) -> list[tuple[int, str]]:
	##	(index, chunk) pairs to type. A chunk is one character, unless pasting is
	##	on and a long number runs from here, in which case it is the whole number.
	units: list[tuple[int, str]] = []
	i = 0
	while i < len(text):
		m = PASTE_RE.match(text, i) if paste else None
		if m and m.end() - i >= PASTE_MIN:
			units.append((i, m.group(0)))
			i = m.end()
		else:
			units.append((i, text[i]))
			i += 1
	return units


def neighbor_key(ch: str, rng: random.Random) -> str:
	for row in QWERTY_ROWS:
		pos = row.find(ch.lower())
		if pos < 0:
			continue
		near = [row[j] for j in (pos - 1, pos + 1) if 0 <= j < len(row)]
		pick = rng.choice(near)
		return pick.upper() if ch.isupper() else pick
	return ch


##	Palette: one shared 256-entry table for every frame. The text colors carry
##	short blend ramps toward their background so antialiased edges quantize
##	cleanly instead of dithering, and the leftover entries are median-cut from
##	the emoji tiles the scenario actually produces. One global table means no
##	per-frame palette cost.
def build_palette(user_tint: Rgb, host_tint: Rgb, emoji_tiles: list[Image.Image]) -> Image.Image:
	def blend(a: Rgb, b: Rgb, k: float) -> Rgb:
		r, g, bl = (round(a[i] + (b[i] - a[i]) * k) for i in range(3))
		return r, g, bl
	t = THEME
	colors = [(0, 0, 0), t["outer"], t["border"], t["titlebar"],
	          t["titletxt"], t["bg"], t["fg"], t["gray"], t["dim"],
	          user_tint, host_tint] + TRAFFIC_LIGHTS
	for c in (t["fg"], t["gray"], t["dim"], user_tint, host_tint):
		for k in (0.22, 0.45, 0.68, 0.86):
			colors.append(blend(t["bg"], c, k))
	for k in (0.35, 0.7):
		colors.append(blend(t["titlebar"], t["titletxt"], k))
	colors = list(dict.fromkeys(colors))
	if emoji_tiles:
		w = sum(tile.width for tile in emoji_tiles)
		h = max(tile.height for tile in emoji_tiles)
		strip = Image.new("RGB", (max(w, 1), max(h, 1)), t["bg"])
		x = 0
		for tile in emoji_tiles:
			strip.paste(tile, (x, 0), tile)
			x += tile.width
		room = min(256 - len(colors), 220)
		q = strip.quantize(colors=room, method=Image.Quantize.MEDIANCUT)
		qp = q.getpalette() or []
		got = [(qp[i], qp[i + 1], qp[i + 2]) for i in range(0, room * 3, 3)]
		colors = list(dict.fromkeys(colors + got))
	colors = (colors + [(0, 0, 0)] * 256)[:256]
	pal = Image.new("P", (1, 1))
	pal.putpalette([v for c in colors for v in c])
	return pal


class Screen:
	##	The fake terminal: a scrollback of styled lines plus an in-progress
	##	prompt line, viewed through a pixel-scrolled window. render() draws the
	##	full chrome each time and quantizes straight to the master palette.
	def __init__(self, font: ImageFont.FreeTypeFont, font_name: str, title: str,
	             prompt: list[Span], font_size: int) -> None:
		self.font, self.title, self.prompt = font, title, prompt
		self.pal = Image.new("P", (1, 1))  # the real one needs the emoji tiles first
		self.font_size = font_size
		self.show_prompt = True   # hidden while a command's output is scrolling in
		self._glyph_font: dict[str, ImageFont.FreeTypeFont] = {}       # ch -> font that can draw it
		self._fallback_fonts: dict[str, ImageFont.FreeTypeFont] = {}   # font file -> font
		self._emoji_tiles: dict[str, Image.Image | None] = {}         # None if it would not render
		self._notdef = self._glyph_pixels(font, "\U000FFFFD")
		ascent, descent = font.getmetrics()
		self.cw = font.getlength("0")
		self.lh = ascent + descent + 3
		self.win_w = CANVAS_W - 2 * MARGIN
		self.win_h = CANVAS_H - 2 * MARGIN
		self.term_x = MARGIN + PAD
		self.term_y = MARGIN + TITLE_H + PAD
		self.cols = int((self.win_w - 2 * PAD) // self.cw)
		self.rows = int((self.win_h - TITLE_H - 2 * PAD) // self.lh)
		self.view_w = self.win_w - 2 * PAD
		self.view_h = self.rows * self.lh
		self.lines: list[list[Span]] = []   # committed scrollback
		self.typed = ""          # text after the prompt on the live line
		self.scroll = 0.0        # view offset into the content, px
		self.font_name = font_name
		self._live: tuple[str, list[list[Span]]] | None = None   # (typed, wrapped rows)

	def put(self, spans: list[Span]) -> None:
		self.lines.append(spans)

	@staticmethod
	def _glyph_pixels(font: ImageFont.FreeTypeFont, ch: str) -> bytes:
		left, top, right, bottom = font.getbbox(ch)
		img = Image.new("L", (int(right - left), int(bottom - top)))
		ImageDraw.Draw(img).text((-left, -top), ch, font=font, fill=255)
		return img.tobytes()

	def font_for(self, ch: str) -> ImageFont.FreeTypeFont:
		##	The primary font, unless it draws ch as .notdef; then whatever
		##	fontconfig says covers that codepoint (e.g. a CJK face for the
		##	Kanji/Hanzi base aliases). Cached hard - fc-match is not cheap.
		if ord(ch) < 0x80:
			return self.font
		hit = self._glyph_font.get(ch)
		if hit:
			return hit
		use = self.font
		if self._glyph_pixels(self.font, ch) == self._notdef:
			try:
				path = subprocess.run(
					["fc-match", "-f", "%{file}", f":charset={ord(ch):x}"],
					capture_output=True, text=True, timeout=10).stdout.strip()
			except OSError:
				path = ""
			if path:
				if path not in self._fallback_fonts:
					try:
						self._fallback_fonts[path] = ImageFont.truetype(path, self.font_size)
					except OSError:
						self._fallback_fonts[path] = self.font
				use = self._fallback_fonts[path]
		self._glyph_font[ch] = use
		return use

	def is_emoji(self, ch: str) -> bool:
		##	Only chars the emoji face covers, and only from the emoji blocks -
		##	CJK and friends stay on the monochrome fallback fonts.
		return EMOJI is not None and ord(ch) >= 0x2600 and ord(ch) in EMOJI.cmap

	def emoji_tile(self, ch: str) -> Image.Image | None:
		##	Rasterize one emoji via Pango+cairo at 4x, then shrink into the cell
		##	box (two columns wide, like a terminal). Cached; None = unrenderable.
		if ch in self._emoji_tiles:
			return self._emoji_tiles[ch]
		kit = EMOJI
		if kit is None:
			return None
		px = self.lh * 4
		surf = kit.cairo.ImageSurface(kit.cairo.FORMAT_ARGB32, px * 2, px * 2)
		ctx = kit.cairo.Context(surf)
		layout = kit.pango_cairo.create_layout(ctx)
		desc = kit.pango.FontDescription(kit.family)
		desc.set_absolute_size(px * kit.pango.SCALE)
		layout.set_font_description(desc)
		layout.set_text(ch, -1)
		kit.pango_cairo.show_layout(ctx, layout)
		surf.flush()
		img = Image.frombuffer("RGBA", (px * 2, px * 2), bytes(surf.get_data()),
		                       "raw", "BGRa", surf.get_stride())
		box = img.getbbox()
		tile = None
		if box:
			glyph = img.crop(box)
			s = min((2 * self.cw - 1) / glyph.width, (self.lh - 2) / glyph.height)
			tile = glyph.resize((max(1, round(glyph.width * s)),
			                     max(1, round(glyph.height * s))), Image.LANCZOS)
		self._emoji_tiles[ch] = tile
		return tile

	def draw_text(self, d: ImageDraw.ImageDraw, img: Image.Image, x: float, y: float,
	              text: str, fill: Rgb) -> float:
		##	Draw in runs of a single font, so fallback glyphs slot inline. Emoji
		##	go down as color tiles pasted on two terminal cells.
		i = 0
		while i < len(text):
			ch = text[i]
			if self.is_emoji(ch):
				tile = self.emoji_tile(ch)
				if tile:
					img.paste(tile, (round(x + (2 * self.cw - tile.width) / 2),
					                 round(y + (self.lh - 2 - tile.height) / 2) + 1), tile)
					x += 2 * self.cw
					i += 1
					continue
			f = self.font_for(ch)
			j = i + 1
			##	Combining marks ride the run of their base char, else shaping
			##	splits and a Devanagari matra draws as dotted-circle + box.
			while j < len(text) and not self.is_emoji(text[j]) \
					and (unicodedata.category(text[j]).startswith("M")
					     or self.font_for(text[j]) is f):
				j += 1
			d.text((x, y), text[i:j], font=f, fill=fill)
			x += d.textlength(text[i:j], font=f)
			i = j
		return x

	def cells(self, ch: str) -> int:
		##	Terminal cell count: emoji and East-Asian wide chars take two.
		if self.is_emoji(ch) or unicodedata.east_asian_width(ch) in ("W", "F"):
			return 2
		return 1

	def wrap(self, text: str, colorkey: str = "fg", overflow: str = "truncate") -> list[list[Span]]:
		##	One output line -> the screen lines it occupies. Split on terminal
		##	cell widths, not char counts, so wide glyphs (emoji, CJK) don't push
		##	a line past the window edge. Returning them instead of committing
		##	them lets the caller feed them in against the scroll.
		out: list[list[Span]] = []
		while True:
			used, cut = 0, len(text)
			for i, ch in enumerate(text):
				used += self.cells(ch)
				if used > self.cols:
					cut = i
					break
			if overflow == "truncate" and cut < len(text):
				out.append([(text[: max(0, cut - 1)], colorkey), ("…", "dim")])
				return out
			out.append([(text[:cut], colorkey)])
			text = text[cut:]
			if not text:
				return out

	def wrap_spans(self, spans: list[Span]) -> list[list[Span]]:
		##	Wrap a styled line onto screen rows, keeping each character's color.
		##	The live prompt line needs this: a pasted value runs well past the
		##	window edge, and a real terminal wraps it rather than hiding it.
		rows: list[list[list[str]]] = []
		row: list[list[str]] = []        # [text, key] pairs, grown in place
		used = 0
		for text, key in spans:
			for ch in text:
				w = self.cells(ch)
				if used + w > self.cols and row:
					rows.append(row)
					row, used = [], 0
				if row and row[-1][1] == key:
					row[-1][0] += ch
				else:
					row.append([ch, key])
				used += w
		rows.append(row)
		return [[(t, k) for t, k in r] for r in rows]

	def live_rows(self) -> list[list[Span]]:
		##	The prompt line as wrapped rows, recomputed only when the text changes.
		if self._live is None or self._live[0] != self.typed:
			self._live = (self.typed,
			              self.wrap_spans(self.prompt + [(self.typed, "fg")]))
		return self._live[1]

	def clear(self) -> None:
		##	Reset the screen the way a full-screen tool would, with no `clear`
		##	typed at the prompt.
		self.lines = []
		self.scroll = 0.0

	def text_width(self, text: str) -> float:
		##	Pixel width with the same runs draw_text uses.
		w, i = 0.0, 0
		while i < len(text):
			if self.is_emoji(text[i]) and self.emoji_tile(text[i]):
				w += 2 * self.cw
				i += 1
				continue
			f = self.font_for(text[i])
			j = i + 1
			while j < len(text) and not self.is_emoji(text[j]) \
					and (unicodedata.category(text[j]).startswith("M")
					     or self.font_for(text[j]) is f):
				j += 1
			w += f.getlength(text[i:j])
			i = j
		return w

	def rest_scroll(self) -> float:
		##	Where the view settles: content bottom (incl. the live line when the
		##	prompt is showing) on the grid.
		rows = len(self.lines) + (len(self.live_rows()) if self.show_prompt else 0)
		return max(0.0, rows * self.lh - self.view_h)

	def cursor_target(self) -> tuple[float, float]:
		##	Cursor cell at the end of the live line, in view (layer) px at current
		##	scroll - which is the last of its wrapped rows, not the first.
		live = self.live_rows()
		x = self.text_width("".join(t for t, _ in live[-1]))
		return x, (len(self.lines) + len(live) - 1) * self.lh - self.scroll

	def render(self, cursor: tuple[float, float] | None, ident_colors: dict[str, Rgb]) -> Image.Image:
		##	cursor: None = hidden, else (x, y) view px of the block's top-left.
		img = Image.new("RGB", (CANVAS_W, CANVAS_H), THEME["outer"])
		d = ImageDraw.Draw(img)
		x0, y0 = MARGIN, MARGIN
		d.rectangle([x0, y0, x0 + self.win_w, y0 + self.win_h],
		            fill=THEME["bg"], outline=THEME["border"])
		d.rectangle([x0, y0, x0 + self.win_w, y0 + TITLE_H],
		            fill=THEME["titlebar"])
		for i, c in enumerate(TRAFFIC_LIGHTS):
			dot_x = x0 + 18 + i * 20
			d.ellipse([dot_x, y0 + 12, dot_x + 11, y0 + 23], fill=c)
		tw = d.textlength(self.title, font=self.font)
		self.draw_text(d, img, x0 + (self.win_w - tw) / 2,
		               y0 + (TITLE_H - self.lh) / 2 + 1, self.title, THEME["titletxt"])

		##	Text: content lines at their scrolled offsets, drawn on a layer the
		##	size of the view so partial lines clip cleanly at the edges.
		colors = dict(THEME, **ident_colors)
		layer = Image.new("RGB", (self.view_w, self.view_h), THEME["bg"])
		ld = ImageDraw.Draw(layer)
		content = self.lines + (self.live_rows() if self.show_prompt else [])
		first = max(0, int(self.scroll // self.lh))
		last = min(len(content), int((self.scroll + self.view_h) // self.lh) + 2)
		for i in range(first, last):
			x: float = 0
			y = round(i * self.lh - self.scroll)
			for text, key in content[i]:
				x = self.draw_text(ld, layer, x, y, text, colors[key])
		if cursor is not None:
			cx, cy = cursor
			ld.rectangle([cx + 1, cy + 1, cx + self.cw, cy + self.lh - 3],
			             fill=THEME["fg"])
		img.paste(layer, (self.term_x, self.term_y))
		return img.quantize(palette=self.pal, dither=Image.Dither.NONE)


def after_first_image(gif: bytes) -> int:
	##	Offset just past the first image in a GIF: header and global table, any
	##	extensions, then the image descriptor, its local table and its data.
	pos = 13
	if gif[10] & 0x80:
		pos += 3 << ((gif[10] & 7) + 1)
	while gif[pos] == 0x21:
		pos += 2
		while gif[pos]:
			pos += gif[pos] + 1
		pos += 1
	if gif[pos] != 0x2C:
		raise ValueError("no image in encoded batch")
	flags = gif[pos + 9]
	pos += 10
	if flags & 0x80:
		pos += 3 << ((flags & 7) + 1)
	pos += 1
	while gif[pos]:
		pos += gif[pos] + 1
	return pos + 1


class Movie:
	##	Ordered (frame, duration) list. Identical consecutive frames merge into
	##	one longer frame; GIF timing is centisecond-quantized, so bank the
	##	remainder instead of rounding it away every keystroke.
	##	Frames are encoded a batch at a time as they come in. Held raw until the
	##	save, 3000-odd frames came to 1.6 GB, and Pillow's save copied them all
	##	again. A delta frame depends only on the frame before it, so each batch
	##	is saved behind the previous batch's last frame, and that leading frame
	##	and the header are cut off again. The bytes match a single save.
	BATCH = 32

	def __init__(self) -> None:
		self.durs: list[int] = []
		self._rem = 0.0
		self._pending: list[Image.Image] = []   # not yet encoded; the last may still grow
		self._last_bytes: bytes | None = None
		self._lead: Image.Image | None = None   # last encoded frame, the base for the next batch
		self._done = 0           # frames encoded so far
		self._gif: list[bytes] = []             # encoded batches, header in the first only

	def add(self, img: Image.Image, ms: float) -> None:
		ms += self._rem
		dur = max(20, int(round(ms / 10.0)) * 10)
		self._rem = ms - dur if ms > 20 else 0.0
		raw = img.tobytes()
		if raw == self._last_bytes:
			self.durs[-1] += dur
			return
		self._last_bytes = raw
		if len(self._pending) >= self.BATCH:
			self._encode()                   # every pending duration is final now
		self._pending.append(img)
		self.durs.append(dur)

	def _encode(self) -> None:
		frames = self._pending
		durs = self.durs[self._done:self._done + len(frames)]
		if self._lead is not None:
			frames = [self._lead] + frames
			durs = [self.durs[self._done - 1]] + durs
		buf = io.BytesIO()
		frames[0].save(buf, format="GIF", save_all=True, append_images=frames[1:],
		               duration=durs, loop=0, optimize=False)
		gif = buf.getvalue()
		cut = after_first_image(gif) if self._lead is not None else 0
		self._gif.append(gif[cut:-1])        # the trailer goes on once, at the end
		self._done += len(self._pending)
		self._lead = self._pending[-1]
		self._pending = []

	def save(self, path: Path) -> None:
		if self._pending:
			self._encode()
		with open(path, "wb") as f:
			f.writelines(self._gif)
			f.write(b";")


def main() -> None:
	ap = argparse.ArgumentParser(add_help=True)
	ap.add_argument("--scenario", required=True)
	ap.add_argument("--out", required=True)
	ap.add_argument("--bin", default="")
	ap.add_argument("--seed", type=int, default=None)
	ap.add_argument("--font", default="")
	ap.add_argument("--quiet", action="store_true")
	args = ap.parse_args()

	sc = load_scenario(args.scenario)
	rng = random.Random(args.seed if args.seed is not None else sc.get("seed", 11))
	prog = sc.get("prog", "prog")
	binpath = args.bin or sc.get("bin", prog)

	prefs = [args.font] if args.font else sc.get("font", [])
	prefs = prefs + ["Monaspace Argon SemiBold", "JetBrains Mono",
	                 "Cascadia Mono", "DejaVu Sans Mono"]
	font, font_name = find_font([p for p in prefs if p], sc.get("fontsize", 15))

	user_tint, host_tint = rng.sample(IDENT_TINTS, 2)
	user = rng.choice(IDENT_USERS)
	host = rng.choice(IDENT_HOSTS)
	prompt = [(user, "user"), ("@", "gray"), (host, "host"), (":", "gray"),
	          ("~", "gray"), ("$ ", "gray")]
	ident_colors = {"user": user_tint, "host": host_tint}

	scr = Screen(font, font_name, sc.get("title", prog), prompt, sc.get("fontsize", 15))

	##	Run every command up front: the outputs feed the demo AND tell the
	##	palette which emoji it must carry before the first frame renders.
	here = str(Path(args.scenario).resolve().parent)
	step_out = [run_step(step, binpath, here) for step in sc["step"]]
	emoji_set = sorted({ch for lines in step_out for ln in lines for ch in ln
	                    if scr.is_emoji(ch)})
	tiles = [t for t in (scr.emoji_tile(ch) for ch in emoji_set) if t is not None]
	scr.pal = build_palette(user_tint, host_tint, tiles)

	mov = Movie()
	wpm_digits = sc.get("wpm_digits", WPM_DIGITS)
	shown = list(scr.cursor_target())    # displayed cursor; glides toward its cell

	def snap(ms: float, cursor: bool = True) -> None:
		mov.add(scr.render((shown[0], shown[1]) if cursor else None, ident_colors), ms)

	def glide_cursor(ms: float) -> None:
		##	Ease the block toward its cell, then hold still for whatever is left
		##	of the keystroke. The glide never overruns the keystroke's own time,
		##	so a fast digit still gets a frame and the typing keeps its pace.
		tx, ty = scr.cursor_target()
		x0, y0 = shown
		steps = max(1, min(int(ms // FRAME_MS), GLIDE_FRAMES))
		glide_ms: float = steps * FRAME_MS
		rest = ms - glide_ms
		if rest < FRAME_MS:      # too little left to be its own frame - stretch the glide
			glide_ms, rest = ms, 0.0
		for s in range(1, steps + 1):
			k = s / steps
			k = k * k * (3.0 - 2.0 * k)      # smoothstep: soft leave, soft landing
			shown[0] = x0 + (tx - x0) * k
			shown[1] = y0 + (ty - y0) * k
			snap(glide_ms / steps)
		shown[0], shown[1] = tx, ty
		if rest:
			snap(rest)

	def settle(rate: float, cursor: bool = True) -> None:
		##	Smooth-scroll the view to rest; the cursor rides along on its line.
		step = rate * FRAME_MS / 1000.0
		while abs(scr.rest_scroll() - scr.scroll) >= 0.5:
			d = scr.rest_scroll() - scr.scroll
			scr.scroll += (1 if d > 0 else -1) * min(abs(d), step)
			shown[:] = scr.cursor_target()
			snap(FRAME_MS, cursor)
		scr.scroll = scr.rest_scroll()
		shown[:] = scr.cursor_target()

	def emit(out_lines: list[str], rate: float, line_ms: float, overflow: str) -> None:
		##	Feed the output in against the scroll instead of appending a line and
		##	settling to rest before the next one. Settling per line restarts the
		##	scroll at every line boundary, which costs a fraction of a frame each
		##	time and reads as judder once the frame rate is high enough to see it.
		##	Committing the next line the moment the view catches up keeps the
		##	velocity dead constant and carries the sub-pixel remainder forward.
		step = rate * FRAME_MS / 1000.0
		pending = [ln for text in out_lines for ln in scr.wrap(text, "fg", overflow)]
		while True:
			##	Commit the next line as soon as the view is within one frame of
			##	catching up, never after. Waiting for an exact landing forces a
			##	short frame at every line boundary; releasing a frame early lets
			##	the sub-pixel remainder carry into the next line instead.
			if pending and scr.rest_scroll() - scr.scroll <= step + 0.5:
				scr.put(pending.pop(0))
				if scr.rest_scroll() - scr.scroll <= 0.5:
					snap(line_ms, cursor=False)     # view not full yet: nothing to scroll
					continue
			d = scr.rest_scroll() - scr.scroll
			if d <= 0.5:
				break
			scr.scroll += min(d, step)
			snap(FRAME_MS, cursor=False)
		scr.scroll = scr.rest_scroll()

	def blink_pause(total_ms: float) -> None:
		##	Idle at the prompt: block cursor blinking at the usual cadence.
		on = True
		left = total_ms
		while left > 0:
			step = min(BLINK_MS, left)
			snap(step, cursor=on)
			on = not on
			left -= step

	snap(700)                                        # opening frame = loop-in target
	for step_idx, step in enumerate(sc["step"]):
		rate = float(step.get("scrollrate", SCROLL_RATE))
		line_ms = float(step.get("linems", 26))
		##	Output taller than the window starts on a clean screen, so a long
		##	list scrolls through once instead of first chasing the previous
		##	step's output off the top. Nothing types `clear`; the screen just
		##	resets, the way a full-screen tool would leave it.
		if step.get("clear", len(step_out[step_idx]) > scr.rows) and scr.lines:
			scr.clear()
			shown[:] = scr.cursor_target()
			snap(260)
		typing = [TypedLine("# " + n, "dim", WPM_NOTES, False, 1.0) for n in step_notes(step)]
		if step.get("show"):
			typing.append(TypedLine(step["show"].replace("{prog}", prog).replace("{bin}", prog),
			                        "fg", WPM_LETTERS, True, float(step.get("typescale", 1.0))))
		for note_or_cmd, key, wpm, typos, scale in typing:
			for event in type_events(
					note_or_cmd, rng, wpm, typos, wpm_digits,
					key == "fg" and step.get("paste", False), scale,
					1000 * float(step.get("pastepause", 0.0))):
				if event.action == "type" and event.text:
					scr.typed += event.text
				elif event.action == "bs":
					scr.typed = scr.typed[:-1]
				glide_cursor(event.delay)
			snap(rng.uniform(260, 480) if key == "fg" else 130)   # beat before Enter
			if key == "fg" and step.get("preenter"):
				blink_pause(1000 * float(step["preenter"]))
			for row in scr.wrap_spans(scr.prompt + [(scr.typed, key)]):
				scr.put(row)
			scr.typed = ""
			if key == "dim":                         # notes: no output to run
				if scr.rest_scroll() > scr.scroll + 0.5:
					settle(rate)
				else:
					glide_cursor(130)                 # cursor hop onto the new line
				snap(140)
				if step.get("notepause"):
					blink_pause(1000 * float(step["notepause"]))
				continue
			##	Prompt stays hidden until the command's output is fully in, the
			##	way a real shell does it.
			scr.show_prompt = False
			if scr.rest_scroll() > scr.scroll + 0.5:
				settle(rate, cursor=False)
			##	A blank line between the command and its output, for a step whose
			##	output wraps: without it the two run together as one block.
			out_lines = ([""] if step.get("gap") else []) + step_out[step_idx]
			emit(out_lines, rate, line_ms, step.get("overflow", "truncate"))
			##	Blank line and the returning prompt scroll in as one move - two
			##	back-to-back settles would put a seam right where the eye rests.
			if out_lines and out_lines[-1].strip():
				scr.put([("", "fg")])               # breathe before the next prompt
			scr.show_prompt = True
			shown[:] = scr.cursor_target()
			if scr.rest_scroll() > scr.scroll + 0.5:
				settle(rate)
			snap(60)
			blink_pause(1000 * float(step.get("pause", 2.6)))
		if not step.get("show"):                     # notes with nothing to run
			blink_pause(1000 * float(step.get("pause", 2.6)))

	##	Tail: hold the last frame dead still, then a hard cut to black before the
	##	loop repeats. The black is one held frame (a cut, not a fade), so it costs
	##	almost nothing.
	hold_ms  = 1000 * float(sc.get("end_hold", 3.0))
	black_ms = 1000 * float(sc.get("end_black", 2.0))
	if hold_ms > 0:
		snap(hold_ms)
	if black_ms > 0:
		black = Image.new("RGB", (CANVAS_W, CANVAS_H), (0, 0, 0)).quantize(
			palette=scr.pal, dither=Image.Dither.NONE)
		mov.add(black, black_ms)

	out = Path(args.out)
	out.resolve().parent.mkdir(parents=True, exist_ok=True)
	mov.save(out)
	squeezed = optimize_gif(out)
	if not args.quiet:
		secs = sum(mov.durs) / 1000.0
		kb = out.stat().st_size // 1024
		print(f"gen-demo-gif: {args.out}: {len(mov.durs)} frames, "
		      f"{secs:.1f}s loop, {kb} KiB"
		      f"{'' if squeezed else ' (no gifsicle)'}, font: {font_name}, "
		      f"{scr.cols}x{scr.rows} cells, ident: {user}@{host}")


if __name__ == "__main__":
	main()


##	History:
##		- 20261004: PEP 8 names and type hints. A one-word command types its
##			first word at muscle-memory speed like any other command. The
##			missing-glyph check no longer reaches into Pillow's internals.
##		- 20261004: Frames are encoded in batches as they come in, instead of
##			held raw until the save. Peak memory 3.2 GB -> 180 MB, same bytes.
##		- 20260801: Typing 15% faster, smooth scrolling 25% faster. Scenario
##			gained pastepause, preenter, typescale, notepause.
##		- 20260801: The live prompt line wraps instead of running off the edge.
##			Scenario gained note lists, notes-only steps, gap=, paste=, {here}.
##		- 20260731: Motion runs at 50 fps. Constant-velocity scroll (output feeds
##			in against it rather than settling per line), eased cursor glide,
##			scrolling 10% faster, and tall output starts on a cleared screen.
##			Lossless gifsicle pass at the end, when it is installed.
##		- 20260713: End of loop holds the final frame (end_hold, 3s) then hard-
##			cuts to black (end_black, 2s) before repeating.
##		- 20260711: v1.2. Antialiased text again (ramped 256 palette), color
##			emoji tiles, prompt hidden until output lands, faster typing and
##			scrolling, cell-width wrap.
##		- 20260711: v1.1. Pixel-smooth scrolling and cursor glide; scenario
##			knobs wpm_digits, scrollrate, linems.
##		- 20260711: v1.0. Scenario-driven typing/render/fade engine.
