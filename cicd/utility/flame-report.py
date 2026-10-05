#!/usr/bin/env python3

##	Purpose: Summarize the newest convert-base-v2 profiler flamegraph - self-time
##		hot spots, inclusive call buckets, and the caller chain of the top leaves -
##		by parsing the inferno-style SVG that pprof2flame.py writes (its fg:w
##		attribute = raw sample counts). Runs two ways: plain (print the report,
##		meant to run every cicd run) and --check (print only when the newest
##		flamegraph is newer than the one last recorded in a local marker, then
##		record it - meant for session startup so a look is a no-op until there is
##		something new to read).
##	History: At bottom of script.

##	Copyright (c) 2026 Bubbles
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


import argparse
import html
import re
import sys
from pathlib import Path
from typing import NamedTuple, NoReturn

STEP      = 16              # flamegraph row height in the SVG, px (a child sits at parent_y - STEP)
SELF_TOP  = 22             	# self-time leaders to list
INCL_TOP  = 14             	# inclusive-time buckets to list
CHAIN     = 4              	# leaves whose caller chain we walk up to the root
SEEN_FILE = ".flame-seen"  	# marker basename, kept in the profiling dir - outside the git repo

NAME_RE   = re.compile(r"flame_(\d{8}-\d{6})_\w+\.svg$")
FRAME_RE  = re.compile(r"<title>(.*?)</title><rect ([^>]*?)/>", re.S)

##	Subsystem buckets for THIS app, keyed on function-name substrings. The
##	workload drives both hot paths, so self-time splits across: the
##	arbitrary-precision big-number convert (math/big plus our divide and conquer
##	parse and format around it), the O(N) streaming bit-packing/codec path, and
##	Go's GC + allocator (usually just the cost of the allocations the convert
##	paths make - discount unless it dwarfs the actual work). Order matters:
##	first match wins.
BUCKETS = [
	("big-int, math/big convert", ("math/big", ".Convert", "bigConvert", "quoRem",
	                               "dcState", "DCState", "parseDigits", "formatDigits", "wordChunk")),
	("streaming, bit-packing/codec", ("stream", "encodeCodec", "decodeCodec", "bitPack", "packBits", "unpackBits")),
	("GC + allocator (discount)", ("runtime.gc", "mallocgc", "runtime.scan", "runtime.mark", "runtime.sweep",
	                               "memclr", "memmove", "growslice", "typedslicecopy", "runtime.span", "heap")),
	("other runtime / test harness", ("runtime.", "testing.")),
]


class Frame(NamedTuple):
	name: str
	x: float                                     # fg:x, in raw samples
	y: float                                     # px, the root row is at the bottom
	w: float                                     # fg:w, in raw samples


def fSkip(msg: str) -> NoReturn:
	##	2 = environmental skip (no dir / unparseable) - non-fatal, matches the
	##	cicd profiler stage which treats such things as a warning, not a failure.
	sys.stderr.write(f"flame-report: {msg}\n")
	sys.exit(2)


def fNewest(pdir: Path) -> tuple[str, str] | None:
	##	Sort on the timestamp, NOT the role suffix: GFS rotation retags the role
	##	(frequent -> latest -> hour/day/...) as time passes, but the timestamp in
	##	the name is stable.
	best = None
	try:
		names = [p.name for p in pdir.iterdir()]
	except OSError as e:
		fSkip(f"cannot read {pdir}: {e}")
	for name in names:
		m = NAME_RE.match(name)
		if m and (best is None or m.group(1) > best[0]):
			best = (m.group(1), name)
	return best


def fAttr(attrs: str, key: str) -> float | None:
	vm = re.search(re.escape(key) + r'="([\d.]+)"', attrs)
	return float(vm.group(1)) if vm else None


def fParse(path: Path) -> tuple[int, list[Frame]]:
	try:
		text = path.read_text(encoding="utf-8")
	except (OSError, UnicodeDecodeError) as e:
		fSkip(f"cannot read {path}: {e}")
	m = re.search(r'total_samples="(\d+)"', text)
	total = int(m.group(1)) if m else 0
	frames: list[Frame] = []
	for fm in FRAME_RE.finditer(text):
		attrs = fm.group(2)
		y, x, w = fAttr(attrs, "y"), fAttr(attrs, "fg:x"), fAttr(attrs, "fg:w")
		if y is None or x is None or w is None:
			continue
		name = re.sub(r"\s*\(\d[\d,]* samples.*$", "", html.unescape(fm.group(1)))
		frames.append(Frame(name, x, y, w))
	if not total or not frames:
		fSkip(f"could not parse a flamegraph out of {path}")
	return total, frames


def fBucket(name: str) -> str:
	for label, needles in BUCKETS:
		if any(n in name for n in needles):
			return label
	return "other, app code"


def fAnalyze(total: int, frames: list[Frame], top: int) -> None:
	byY: dict[float, list[Frame]] = {}
	for fr in frames:
		byY.setdefault(fr.y, []).append(fr)
	eps = 1e-6

	def kids(fr: Frame) -> list[Frame]:
		return [c for c in byY.get(fr.y - STEP, []) if c.x >= fr.x - eps and c.x + c.w <= fr.x + fr.w + eps]

	def parent(fr: Frame) -> Frame | None:
		for p in byY.get(fr.y + STEP, []):
			if p.x <= fr.x + eps and p.x + p.w >= fr.x + fr.w - eps:
				return p
		return None

	def selfW(fr: Frame) -> float:
		return fr.w - sum(c.w for c in kids(fr))

	selfBy: dict[str, float] = {}
	inclBy: dict[str, float] = {}
	byName: dict[str, list[Frame]] = {}
	attrib: dict[str, float] = {}
	for fr in frames:
		name = fr.name
		byName.setdefault(name, []).append(fr)
		inclBy[name] = inclBy.get(name, 0.0) + fr.w
		s = selfW(fr)
		selfBy[name] = selfBy.get(name, 0.0) + s
		if s > 0:
			attrib[fBucket(name)] = attrib.get(fBucket(name), 0.0) + s

	def pct(v: float) -> str:
		return f"{v / total * 100:5.1f}%"

	print("attribution (self-time):")
	for label, _ in BUCKETS:
		print(f"  {label:.<32}: {pct(attrib.get(label, 0.0))}")
	print(f"  {'other, app code':.<32}: {pct(attrib.get('other, app code', 0.0))}")
	print()

	print("top self-time (where CPU actually burns):")
	for name, v in sorted(selfBy.items(), key=lambda kv: -kv[1])[:top]:
		if v < 1:
			break
		print(f"  {pct(v)} {int(v):4d}  {name}")
	print()

	print("top inclusive (call buckets):")
	for name, v in sorted(inclBy.items(), key=lambda kv: -kv[1])[:INCL_TOP]:
		print(f"  {pct(v)} {int(v):4d}  {name}")
	print()

	print(f"caller chains of the top {CHAIN} leaves:")
	for name, v in sorted(selfBy.items(), key=lambda kv: -kv[1])[:CHAIN]:
		fr = max(byName[name], key=selfW)
		print(f"  {name}  ({pct(v)} self)")
		cur, depth = parent(fr), 0
		while cur and depth < 12:
			print(f"      {cur.name}")
			if cur.name == "all":
				break
			cur, depth = parent(cur), depth + 1


def main() -> None:
	default_dir = Path(__file__).resolve().parent.parent / "artifacts" / "profiling"

	ap = argparse.ArgumentParser(description="Summarize the newest convert-base-v2 profiler flamegraph.")
	ap.add_argument("--dir", type=Path, default=default_dir, help="profiling directory (default: %(default)s)")
	ap.add_argument("--file", type=Path, help="analyze this SVG instead of the newest in --dir")
	ap.add_argument("--top", type=int, default=SELF_TOP, help="self-time leaders to list")
	ap.add_argument("--check", action="store_true",
	                help="startup gate: print only if newer than the local marker, then record it")
	ap.add_argument("--force", action="store_true", help="with --check, report even if already seen")
	ap.add_argument("--no-mark", action="store_true", help="with --check, do not update the marker")
	a = ap.parse_args()

	if a.file:
		path = a.file
		if not path.is_file():
			fSkip(f"no such file: {path}")
		name = path.name
		m = NAME_RE.match(name)
		ts = m.group(1) if m else ""
	else:
		if not a.dir.is_dir():
			fSkip(f"no profiling dir: {a.dir}")
		nb = fNewest(a.dir)
		if not nb:
			fSkip(f"no flamegraphs in {a.dir}")
		ts, name = nb
		path = a.dir / name

	marker = a.dir / SEEN_FILE
	if a.check and not a.force:
		seen = ""
		try:
			seen = marker.read_text().strip()
		except OSError:
			pass
		if ts and seen and ts <= seen:
			print(f"SEEN {name}  (nothing newer than {seen})")
			return

	total, frames = fParse(path)
	print(f"{'NEW' if a.check else 'FLAME'} {name}  ({ts or 'n/a'}, {total} samples)")
	print()
	fAnalyze(total, frames, a.top)

	if a.check and not a.no_mark and ts:
		try:
			marker.write_text(ts + "\n")
		except OSError as e:
			sys.stderr.write(f"flame-report: could not write marker: {e}\n")


if __name__ == "__main__":
	main()


##	History:
##		- 20260709: Created.
##		- 20261004: An unreadable flamegraph is a skip (exit 2). The divide and conquer convert counts as big-int.
##		- 20261004: Type hints, pathlib, and a named record for each frame.
