#!/usr/bin/env python3

##	Purpose: Turn a Go `go test -cpuprofile` profile into an inferno-style
##		flamegraph SVG, with no external flamegraph tool (no perl, no inferno,
##		no go-torch). It folds the stacks straight out of `go tool pprof -raw`
##		- leaf-first sample location lists, locations expanded through their
##		inlined-frame continuation lines - then emits the same fg:x / fg:w /
##		total_samples SVG that flame-report.py reads. The output is a real,
##		viewable flamegraph (warm palette, per-frame tooltips), root at the
##		bottom, hotter/wider frames drawn first.
##	Syntax:
##		pprof2flame.py --prof cpu.prof --out flame.svg [--go go] [--title STR]
##		  --prof FILE   the profile written by `go test -cpuprofile` (required)
##		  --out FILE    SVG to write (required)
##		  --go BIN      go binary to invoke for `go tool pprof -raw` (default: go)
##		  --title STR   title drawn at the top of the SVG
##		  --minwidth PX prune frames narrower than this many px (default 0.1)
##	Exit: 0 wrote the SVG, 2 non-fatal skip (no profile / pprof unparseable).
##	History: At bottom of script.

##	Copyright (c) 2026 Bubbles
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


import argparse
import html
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import NamedTuple, NoReturn

STEP    = 16      # row height in the SVG, px (a child sits at parent_y - STEP)
RECTH   = 15      # drawn rect height, px
WIDTH   = 1200    # image width, px
PADTOP  = 54      # headroom for the title + summary line, px
PADBOT  = 16      # bottom margin, px

Stacks = dict[tuple[str, ...], int]


@dataclass
class Node:
	name: str
	samples: int = 0                             # inclusive
	children: dict[str, "Node"] = field(default_factory=dict)


class Frame(NamedTuple):
	name: str
	xoff: int                                    # in samples
	depth: int
	samples: int


def skip(msg: str) -> NoReturn:
	##	2 = non-fatal skip - matches the cicd profiler stage, which treats a
	##	missing/unparseable profile as a warning, not a failure.
	sys.stderr.write(f"pprof2flame: {msg}\n")
	sys.exit(2)


def fold(prof: str, go: str) -> Stacks:
	##	Parse `go tool pprof -raw` into {(root..leaf): samples}. The raw dump has a
	##	Samples block (each line "<count> <period>: locID locID ...", leaf first)
	##	and a Locations block (each "ID: 0xADDR M=n func file:line s=..", with
	##	indented continuation lines for inlined callers, innermost first).
	if not Path(prof).is_file():
		skip(f"no profile: {prof}")
	try:
		raw = subprocess.run([go, "tool", "pprof", "-raw", prof],
		                     capture_output=True, text=True, check=True).stdout
	except (OSError, subprocess.CalledProcessError) as e:
		skip(f"go tool pprof failed: {e}")

	samples: list[tuple[int, list[str]]] = []    # (count, [locID...])
	locs: dict[str, list[str]] = {}              # locID -> [func, inlined callers...]
	section, cur_id = "", None
	for line in raw.splitlines():
		low = line.strip()
		if low in ("Samples:", "Locations", "Mappings"):
			section = low.rstrip(":")
			continue
		if section == "Samples":
			if ":" not in line or not low[:1].isdigit():
				continue
			head, tail = line.split(":", 1)
			count_text = head.split()[0]
			ids = tail.split()
			if count_text.isdigit() and ids:
				samples.append((int(count_text), ids))
		elif section == "Locations":
			if not low:
				continue
			parts = line.split()
			if line.lstrip().startswith(tuple("0123456789")) and parts[0].endswith(":"):
				cur_id = parts[0][:-1]          # "12:" -> "12"
				# id, addr, M=n, FUNC, file... -> func is the 4th field
				locs[cur_id] = [parts[3]] if len(parts) > 3 else ["?"]
			elif cur_id is not None and parts:
				locs[cur_id].append(parts[0])   # inlined caller (further from the leaf)
		# Mappings ignored

	if not samples:
		skip(f"no samples parsed from {prof}")

	folded: Stacks = {}
	for count, ids in samples:
		frames: list[str] = []                   # leaf first
		for loc_id in ids:
			frames.extend(locs.get(loc_id, ["?"]))
		frames.reverse()                         # root first
		key = tuple(frames)
		folded[key] = folded.get(key, 0) + count
	return folded


def build_tree(folded: Stacks) -> Node:
	##	Merge folded stacks into a tree under a synthetic "all" root.
	root = Node("all")
	for frames, count in folded.items():
		root.samples += count
		node = root
		for name in frames:
			kid = node.children.get(name)
			if kid is None:
				kid = Node(name)
				node.children[name] = kid
			kid.samples += count
			node = kid
	return root


def color(name: str) -> str:
	##	Deterministic warm "hot" palette (red-orange), keyed on the frame name so
	##	a rebuild recolors identically. Mirrors inferno's hot scheme ranges.
	h = 0
	for ch in name:
		h = (h * 31 + ord(ch)) & 0xFFFFFFFF
	r = 205 + h % 50
	g = (h // 50) % 230
	b = (h // 12000) % 55
	return f"rgb({r},{g},{b})"


def layout(root: Node) -> list[Frame]:
	##	Children are laid left to right in name order (stable across runs)
	##	within the parent's sample span.
	frames: list[Frame] = []

	def walk(node: Node, xoff: int, depth: int) -> None:
		frames.append(Frame(node.name, xoff, depth, node.samples))
		cx = xoff
		for name in sorted(node.children):
			kid = node.children[name]
			walk(kid, cx, depth + 1)
			cx += kid.samples

	walk(root, 0, 0)
	return frames


def emit(frames: list[Frame], total: int, title: str, minwidth: float) -> str:
	maxdepth = max(f.depth for f in frames)
	height = PADTOP + (maxdepth + 1) * STEP + PADBOT
	usable = WIDTH - 20                          # 10px side margins
	minfrac = (minwidth / usable) if usable else 0

	out = []
	out.append('<?xml version="1.0" standalone="no"?>')
	out.append('<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">')
	out.append(f'<svg version="1.1" width="{WIDTH}" height="{height}" '
	           f'viewBox="0 0 {WIDTH} {height}" xmlns="http://www.w3.org/2000/svg" '
	           f'xmlns:fg="http://github.com/jonhoo/inferno" total_samples="{total}">')
	out.append('<!--Flame graph stack visualization; fg:w = raw samples. Generated by pprof2flame.py.-->')
	out.append(f'<rect x="0" y="0" width="{WIDTH}" height="{height}" fill="rgb(255,255,255)"/>')
	out.append(f'<text x="{WIDTH/2:.0f}" y="24" font-family="Verdana" font-size="17" '
	           f'text-anchor="middle">{html.escape(title)}</text>')

	for name, xoff, depth, w in frames:
		frac = w / total if total else 0
		if frac < minfrac:
			continue
		x = 10 + xoff / total * usable
		wpx = frac * usable
		y = PADTOP + (maxdepth - depth) * STEP
		pct = frac * 100
		esc = html.escape(name)
		out.append(
			f'<title>{esc} ({int(w)} samples, {pct:.2f}%)</title>'
			f'<rect x="{x/WIDTH*100:.4f}%" y="{y}" width="{wpx/WIDTH*100:.4f}%" '
			f'height="{RECTH}" fill="{color(name)}" fg:x="{int(xoff)}" fg:w="{int(w)}"/>'
		)
	out.append('</svg>')
	return "\n".join(out) + "\n"


def main() -> None:
	ap = argparse.ArgumentParser(description="Fold a Go CPU profile into an inferno-style flamegraph SVG.")
	ap.add_argument("--prof", required=True, help="profile from `go test -cpuprofile`")
	ap.add_argument("--out", required=True, help="SVG path to write")
	ap.add_argument("--go", default="go", help="go binary (default: go)")
	ap.add_argument("--title", default="convert-base-v2 CPU flamegraph", help="SVG title")
	ap.add_argument("--minwidth", type=float, default=0.1, help="prune frames narrower than this many px")
	args = ap.parse_args()

	root = build_tree(fold(args.prof, args.go))
	frames = layout(root)
	svg = emit(frames, root.samples, args.title, args.minwidth)
	try:
		Path(args.out).write_text(svg, encoding="utf-8")
	except OSError as e:
		skip(f"could not write {args.out}: {e}")
	print(f"pprof2flame: wrote {args.out}  ({root.samples} samples, {max(f.depth for f in frames)} deep)")


if __name__ == "__main__":
	main()


##	History:
##		- 20260709: Created.
##		- 20261004: PEP 8 names, type hints, and named records for tree nodes and frames.
