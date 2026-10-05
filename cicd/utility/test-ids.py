#!/usr/bin/env python3

##	Purpose: Test IDs. Every check in cicd/test.bash and every Go Test or Fuzz
##		function has one, so a failure, a backlog item and a commit can all name
##		the same test. An ID is the time the test was written, as milliseconds
##		since 2000-01-01 00:00 UTC, in base 62 (0-9 A-Z a-z, the same as base 62
##		here). Seven characters until the year 2111.
##	Usage:
##		test-ids.py new [EPOCH_MS]  print an ID for now, or for a given time
##		test-ids.py check           fail if a test has no ID, a bad one, or shares one
##		test-ids.py list            every ID with its test, oldest first
##		test-ids.py lookup DIR NAME the ID of Go test NAME in package dir DIR
##		test-ids.py report          read `go test -json` on stdin and print one
##		                            line per top-level test with its ID; exit 1 on
##		                            any failure
##		A Go test's ID sits on the line above its func, as `// Test ID: XXXXXXX`.
##		A harness check takes its ID as the first argument of _pass, _fail,
##		check, _assert and the other reporting helpers.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


import json
import os
import re
import sys
import time
from functools import cache
from pathlib import Path
from typing import NamedTuple

DIGITS   = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
EPOCH_MS = 946684800000  # 2000-01-01 00:00 UTC
ROOT     = Path(__file__).resolve().parent.parent.parent
HARNESS  = ROOT / "cicd" / "test.bash"
SKIP_DIRS = {".git", "shcl", "testdata", "thirdparty", "node_modules", "build", "dist", "bin"}

ID_RE     = re.compile(r"^[0-9A-Za-z]{7}$")
GO_FUNC   = re.compile(r"^func ((?:Test|Fuzz)\w*)\(")
GO_ID     = re.compile(r"^// Test ID: (\S+)\s*$")
GO_MODULE = re.compile(r'^module\s+"?([^"\s]+)', re.M)
## A reporting call starts a statement, possibly after env assignments. A "("
## after "=" opens an array of words, not a subshell, so neither counts.
SH_CALL   = re.compile(r"(?:^|[;&|{]|(?<!=)\(|\bthen|\belse|\bdo)\s*(?:\w+=(?!\()\S*\s+)*"
                       r"(_pass|_fail|_warn|check|_assert|cvec|nvec|pipecheck|fCheckCoverage|fCheckLegacy)\s+(\S+)(?:\s+(\S+))?")
PASSING   = {"_pass", "check", "_assert", "cvec", "nvec", "pipecheck", "fCheckCoverage", "fCheckLegacy"}


class GoTest(NamedTuple):
	tid: str | None
	path: str                                    # relative to ROOT
	line: int


class HarnessCall(NamedTuple):
	line: int
	func: str
	ids: list[str]


def encode(ms: int) -> str:
	if ms <= 0:
		return "0"
	out = ""
	while ms:
		ms, r = divmod(ms, 62)
		out = DIGITS[r] + out
	return out

def decode(tid: str) -> int:
	n = 0
	for c in tid:
		n = n * 62 + DIGITS.index(c)
	return n

def when(tid: str) -> str:
	return time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime((decode(tid) + EPOCH_MS) / 1000))


@cache
def module_path(go_mod: Path) -> str:
	m = GO_MODULE.search(go_mod.read_text(encoding="utf-8"))
	return m.group(1) if m else ""


def import_path(pkg_dir: Path) -> str:
	"""Import path of the package in pkg_dir, the name `go test -json` gives it.

	Two packages can share a last path element, so tests are keyed by this
	and not by the directory name.
	"""
	for mod_dir in (pkg_dir, *pkg_dir.parents):
		go_mod = mod_dir / "go.mod"
		if go_mod.is_file():
			rel = pkg_dir.relative_to(mod_dir).as_posix()
			return module_path(go_mod) if rel == "." else f"{module_path(go_mod)}/{rel}"
	return pkg_dir.as_posix()


def test_binary_package(import_path_field: str) -> str:
	"""The package a build-output event belongs to.

	Its ImportPath names what was compiled, plus the test binary it was
	compiled for: "pkg [pkg.test]".
	"""
	binary = import_path_field.split(" [")[-1].rstrip("]")
	return binary.removesuffix(".test")


def short_name(pkg: str) -> str:
	return pkg.rsplit("/", 1)[-1]


def go_tests() -> dict[tuple[str, str], GoTest]:
	"""(import path, func name) -> the test's ID, file and line."""
	found = {}
	for dirpath, dirs, files in os.walk(ROOT):
		dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
		pkg_dir = Path(dirpath)
		for f in sorted(files):
			if not f.endswith("_test.go"):
				continue
			path = pkg_dir / f
			lines = path.read_text(encoding="utf-8").split("\n")
			for i, line in enumerate(lines):
				m = GO_FUNC.match(line)
				if not m or m.group(1) == "TestMain":
					continue
				idm = GO_ID.match(lines[i - 1]) if i else None
				key = (import_path(pkg_dir), m.group(1))
				found[key] = GoTest(idm.group(1) if idm else None, str(path.relative_to(ROOT)), i + 1)
	return found


def harness_calls() -> list[HarnessCall]:
	calls = []
	with HARNESS.open(encoding="utf-8") as harness:
		for n, line in enumerate(harness, 1):
			if line.lstrip().startswith("#"):
				continue
			for m in SH_CALL.finditer(line):
				if line[m.end(1):].startswith("()"):
					continue
				fn, a1, a2 = m.group(1), m.group(2).strip('"'), (m.group(3) or "").strip('"')
				if fn == "_warn":
					ids = re.findall(r"\S+", line[m.start(2):].split('"')[1]) if m.group(2).startswith('"') else [a1]
				elif fn == "fCheckLegacy":
					ids = [a1, a2]
				else:
					ids = [a1]
				calls.append(HarnessCall(n, fn, ids))
	return calls


def collect() -> tuple[dict[str, str], list[str]]:
	"""All IDs with what they name, plus a list of problems."""
	problems: list[str] = []
	named: dict[str, str] = {}
	passing: dict[str, list[int]] = {}
	warned: list[tuple[int, str]] = []
	for n, fn, ids in harness_calls():
		for tid in ids:
			if re.fullmatch(r"\$\{?\w+\}?", tid):
				continue  # passed in by the caller
			if not ID_RE.match(tid):
				problems.append(f"test.bash:{n}: {fn} has no test ID (got {tid!r})")
				continue
			if fn == "_warn":
				warned.append((n, tid))
				continue
			named.setdefault(tid, f"test.bash:{n}")
			if fn in PASSING:
				passing.setdefault(tid, []).append(n)
	for tid, where in named.items():
		lines = passing.get(tid, [])
		if not lines:
			problems.append(f"{where}: {tid} is only ever a failure; it needs the passing call of its test")
		elif len(lines) > 1:
			problems.append(f"test.bash: {tid} names more than one test, on lines {', '.join(map(str, lines))}")
	for (_, name), test in sorted(go_tests().items()):
		if test.tid is None or not ID_RE.match(test.tid):
			problems.append(f"{test.path}:{test.line}: {name} needs a `// Test ID: XXXXXXX` line above it")
		elif test.tid in named:
			problems.append(f"{test.path}:{test.line}: {test.tid} is already {named[test.tid]}")
		else:
			named[test.tid] = f"{test.path}:{test.line} {name}"
	## A skip may name the Go tests a section runs, too.
	for n, tid in warned:
		if tid not in named:
			problems.append(f"test.bash:{n}: _warn names {tid}, which is no test")
	now = int(time.time() * 1000) - EPOCH_MS + 86400000
	floor = 1672531200000 - EPOCH_MS  # 2023-01-01, before anything here was written
	for tid, where in named.items():
		if not floor <= decode(tid) <= now:
			problems.append(f"{where}: {tid} decodes to {when(tid)}, outside 2023 to now")
	return named, problems


def report() -> int:
	"""One line per top-level Go test, from `go test -json` on stdin."""
	ids = {k: v.tid for k, v in go_tests().items()}
	state: dict[tuple[str, str], str] = {}
	output: dict[tuple[str, str | None], list[str]] = {}
	order: list[tuple[str, str]] = []
	pkgfail: list[str] = []
	for raw in sys.stdin:
		try:
			ev = json.loads(raw)
		except ValueError:
			sys.stdout.write(raw)
			continue
		test, action = ev.get("Test"), ev.get("Action")
		## A compile error comes as build-output, keyed by the test binary.
		if action == "build-output":
			pkg = test_binary_package(ev.get("ImportPath", ""))
			output.setdefault((pkg, None), []).append(ev.get("Output", ""))
			continue
		pkg = ev.get("Package", "")
		if test is None:
			if action == "fail":
				pkgfail.append(pkg)
			if action == "output":
				output.setdefault((pkg, None), []).append(ev["Output"])
			continue
		top = test.split("/")[0]
		key = (pkg, top)
		if action == "output":
			output.setdefault(key, []).append(ev["Output"])
		if action in ("pass", "fail", "skip") and test == top:
			if key not in state:
				order.append(key)
			state[key] = action
	failed = 0
	for key in order:
		tid = ids.get(key) or "-------"
		st = state[key]
		tag = {"pass": "  ok ", "fail": " FAIL", "skip": " SKIP"}[st]
		print(f"{tag} {tid}  {key[1]} ({short_name(key[0])})")
		if st == "fail":
			failed += 1
			for line in output.get(key, [])[-20:]:
				print("       " + line.rstrip())
	for pkg in pkgfail:
		if not any(k[0] == pkg and state[k] == "fail" for k in order):
			failed += 1
			print(f" FAIL -------  {pkg} (package did not build or run)")
			for line in output.get((pkg, None), [])[-20:]:
				print("       " + line.rstrip())
	print(f"  {len(order) - failed}/{len(order)} Go tests passed" if not failed else f"  {failed} Go test(s) failed")
	return 1 if failed or pkgfail else 0


def main(argv: list[str]) -> int:
	cmd = argv[1] if len(argv) > 1 else ""
	if cmd == "new":
		ms = int(argv[2]) if len(argv) > 2 else int(time.time() * 1000)
		print(encode(ms - EPOCH_MS))
		return 0
	if cmd == "check":
		named, problems = collect()
		for p in problems:
			print(p, file=sys.stderr)
		if problems:
			return 1
		print(f"OK: {len(named)} test IDs, all distinct")
		return 0
	if cmd == "list":
		named, problems = collect()
		for tid in sorted(named, key=decode):
			print(f"{tid}  {when(tid)}  {named[tid]}")
		for p in problems:
			print(p, file=sys.stderr)
		return 1 if problems else 0
	if cmd == "lookup" and len(argv) == 4:
		found = go_tests().get((import_path(Path(argv[2]).resolve()), argv[3]))
		lookup_id = found.tid if found else None
		print(lookup_id or "-------")
		return 0 if lookup_id else 1
	if cmd == "report":
		return report()
	print("usage: test-ids.py new [EPOCH_MS] | check | list | lookup DIR NAME | report", file=sys.stderr)
	return 2


if __name__ == "__main__":
	sys.exit(main(sys.argv))


##	Script history:
##		- 2026-10-04 JC: Created.
##		- 2026-10-04 JC: A bash array of words is no test call.
##		- 2026-10-04 JC: Go tests are keyed by import path, not directory name, and a compile error prints under its package. Type hints and named records.
