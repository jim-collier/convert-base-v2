#!/usr/bin/env python3

##	Purpose: Generate the README "List of predefined bases" table. One fixed
##		base-10 number is written in every listed base, with its character
##		count and its UTF-8 byte count. Regenerate whenever the set of bases
##		or their alphabets change, and paste the output into README.md.
##	Syntax:
##		gen-bases-table.py [--exe PATH] [--config PATH] [--num N] [--width N]
##		  --exe PATH    convert-base-v2 to run (default: ../lib/convert-base-v2)
##		  --config PATH config to read (default: ../lib/cmd/convert-base-v2/default-config.shcl)
##		  --num N       integer part of the number to show (default below)
##		  --width N     target rendered width of the Output column, in ens
##	Note: the config is pinned to the shipped default rather than the user's, so
##		the table shows what a fresh install has and nothing more. Pass
##		--config /dev/null for built-in bases only.
##	Exit: 0 wrote the table, 1 no usable binary.
##	History: At bottom of script.

##	Copyright (c) 2026 Bubbles
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


import argparse
import math
import os
import shutil
import subprocess
import sys
import unicodedata
from collections.abc import Iterator
from pathlib import Path
from typing import NamedTuple

##	Two forms of the same number. The signed fractional one shows more of what
##	a base can do, but nine of the alphabets use every candidate character as a
##	digit and so carry no negative or decimal marker. Those get the plain
##	positive integer instead of being left out.
NUMBER  = "86434491232548995369"
FRACT   = "314"
WIDTH   = 20    # target rendered width of the Output column


class ListedBase(NamedTuple):
	size: str
	name: str
	alias: str      # the first one, or ""


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##	Rendered width
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••

def char_width(ch: str) -> int:
	"""Rough rendered width of one character, in ens.

	The table renders in a proportional font, so this can only ever be an
	estimate. What it has to get right is the 2:1 split, because an alphabet
	of CJK or emoji digits is twice as wide on screen as its character count
	suggests, and wrapping on character count alone leaves those rows far
	wider than the Latin ones.
	"""
	if unicodedata.combining(ch) or unicodedata.category(ch) in ("Mn", "Me", "Cf"):
		return 0
	if unicodedata.east_asian_width(ch) in ("W", "F"):
		return 2
	# Counting rods and Mayan numerals are not east-asian-wide by property, but
	# nothing common has them, so a browser draws them from a fallback font at
	# a full cell or better. Treat everything above the BMP as wide.
	return 2 if ord(ch) > 0xFFFF else 1


def cell_width(text: str) -> int:
	return sum(char_width(ch) for ch in text)


def wrap_cell(text: str, target: int) -> list[str]:
	"""Split text into lines of roughly equal rendered width, none over target.

	Filling greedily to the target would leave a ragged last line (base 3 at
	target 30 splits 30/10), and the point of the exercise is an even column,
	so the line count is chosen first and the width shared out across it.
	"""
	total = cell_width(text)
	if total <= target:
		return [text]
	line_count = math.ceil(total / target)
	per_line   = math.ceil(total / line_count)
	lines: list[str] = []
	current, current_width = "", 0
	for ch in text:
		width = char_width(ch)
		# Never break ahead of a combining mark - it has to ride its base char.
		if width and current_width + width > per_line and len(lines) < line_count - 1:
			lines.append(current)
			current, current_width = "", 0
		current       += ch
		current_width += width
	lines.append(current)
	return lines


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##	Markdown
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••

def escape_cell(text: str) -> str:
	"""Escape a table cell. The control characters are digits in the keyboard
	base, so they are shown rather than emitted."""
	for find, replace in (("\\", "\\\\"), ("|", "\\|"), ("`", "\\`"),
	                      ("\t", "\\t"), ("\n", "\\n"), ("\r", "\\r")):
		text = text.replace(find, replace)
	return text


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##	The binary
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••

def find_exe(given: str | None) -> str | None:
	if given:
		return given if os.access(given, os.X_OK) else None
	nearby = Path(__file__).resolve().parent.parent / "lib" / "convert-base-v2"
	if os.access(nearby, os.X_OK):
		return str(nearby)
	return shutil.which("convert-base-v2")


def find_config(given: str | None) -> str:
	if given:
		return given
	return str(Path(__file__).resolve().parent.parent / "lib" / "cmd" / "convert-base-v2" / "default-config.shcl")


def run(exe: str, config: str, *args: str) -> str | None:
	result = subprocess.run([exe, "--config", config, *args],
	                        capture_output=True, text=True)
	if result.returncode != 0:
		return None
	return result.stdout.rstrip("\n")


def list_bases(exe: str, config: str) -> Iterator[ListedBase]:
	"""Every base --list shows, header row dropped."""
	listing = run(exe, config, "--list")
	if listing is None:
		sys.exit("--list failed")
	for line in listing.splitlines()[1:]:
		fields = line.split(None, 6)
		if len(fields) < 6:
			continue
		_, name, size = fields[0], fields[1], fields[2]
		aliases = fields[6].split(",") if len(fields) > 6 else []
		yield ListedBase(size, name, aliases[0].strip() if aliases else "")


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##	Main
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••

def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument("--exe")
	parser.add_argument("--config")
	parser.add_argument("--num",   default=NUMBER)
	parser.add_argument("--width", type=int, default=WIDTH)
	opts = parser.parse_args()

	exe = find_exe(opts.exe)
	if not exe:
		sys.exit("convert-base-v2 not found; pass --exe")
	config = find_config(opts.config)

	signed = f"-{opts.num}.{FRACT}"

	print("| Base | Name [arg] | First alias | Char count | UTF-8 byte count | Output")
	print("| --: | :-- | :-- | --: | --: | :--")
	for size, name, alias in list_bases(exe, config):
		# Markerless alphabets reject the signed fractional form, so they fall
		# back to the bare integer rather than dropping out of the table.
		output = run(exe, config, "--from", "10", "--to", name, "--", signed)
		if output is None:
			output = run(exe, config, "--from", "10", "--to", name, "--", opts.num)
		if output is None:
			# bytes is raw only, so it has no text form to show and no counts.
			if name == "bytes":
				print(f"| {size} | {name} | {alias} |  |  | (raw bytes 0x00-0xFF)")
			else:
				print(f"skipped {name}: will not represent the number", file=sys.stderr)
			continue
		cell = "<br>".join(escape_cell(part)
		                   for part in wrap_cell(output, opts.width))
		print(f"| {size} | {name} | {alias} | {len(output)} | "
		      f"{len(output.encode('utf-8'))} | {cell}")


if __name__ == "__main__":
	main()


##	History:
##		20260731 Replaced gen-example-table.bash. Dropped the description and
##			specification columns, added the UTF-8 byte count, and wrapped the
##			output cell on estimated rendered width so the column stops
##			overflowing.
##		20260731 New example number, shown signed and fractional where the
##			alphabet has the markers for it and as a bare integer where it
##			does not.
##		20260731 Narrower output column, above-BMP digits counted as wide, and
##			the shipped config read so its example base is listed too.
##		20261004 PEP 8 names and type hints.
