#!/usr/bin/env bash

#  shellcheck disable=1091  ## 'source is valid here, but shellcheck doesn't know the path to it.'
#  shellcheck disable=2001  ## 'See if you can use ${variable//search/replace} instead.' Complains about good uses of sed.
#  shellcheck disable=2015  ## 'A && B || C is not if-then-else.' The one-line check form. _pass only fails if printing fails, and then _fail counts it too.
#  shellcheck disable=2016  ## 'Expressions don't expand in single quotes, use double quotes for that.' I know, and I often want an explicit '$'.
#  shellcheck disable=2034  ## 'variable appears unused.' Complains about valid use of variable indirection (e.g. later use of local -n var=$1)
#  shellcheck disable=2046  ## 'Quote to prevent word-splitting.' (OK for integers.)
#  shellcheck disable=2059  ## 'Variables in the printf format.' The \U escapes are built into the format on purpose, so printf expands them.
#  shellcheck disable=2086  ## 'Double quote to prevent globbing and word splitting.' (OK for integers.)
#  shellcheck disable=2155  ## 'Declare and assign separately to avoid masking return values.' Cumbersome and unnecessary.
#  shellcheck disable=2162  ## 'read without -r will mangle backslashes.'
#  shellcheck disable=2154  ## 'referenced but not assigned.' False hit on trap strings that assign the var they use (rc=$?).
#  shellcheck disable=2181  ## 'Check exit code directly, not indirectly with $?.'
#  shellcheck disable=2207  ## 'Prefer mapfile or read -a to split command output.'
#  shellcheck disable=2317  ## 'Can't reach.' (an 'exit' used for debugging makes a visual mess.)
#  shellcheck disable=2329  ## 'Never invoked.' False hit on cleanup, which the EXIT trap runs.

##	Purpose:
##		- Exhaustive, CI-friendly test harness for convert-base-v2. Exits non-zero if any check fails.
##		- Table-driven so cases are cheap to add: a check is one line (ID, mode, label, expected, then the argv).
##		- Coverage:
##			- CLI surface (version, help, examples, list).
##			- Deterministic conversions, base-name aliases, negatives, fractionals, precision, lower, raw.
##			- Custom symbol specs, including neg/dec markers.
##			- Errors and robustness: bad bases, bad digits, malformed input, shell-metachar input, oversized input.
##			- Binary/streaming: bit-perfect raw round-trips through every raw-capable base (power-of-2 via bit-packing, plus the base45/ascii85/z85/base91 codecs), fixed spec vectors for each codec, the byte-alignment guard, wrapped-input decoding, and a check that non-codec bases refuse raw binary. The base lists come from --list, so a base that is added or renamed is covered with no edit here.
##			- Performance and profiling (unless --quick): streaming throughput, a peak-memory ceiling on every power-of-2 base, and a codec throughput guard.
##			- Fuzz: random values round-tripped through every defined base (bases enumerated from the binary itself).
##			- Full-coverage symbol fuzz: for every base, a random-length string of its own random symbols is carried through a random target base and back. Base names and alphabets are read from the binary, so all bases are covered.
##			- Interop against the published implementations of the four big bases (qntm's base2048/base32768/base65536 and LLFourn's base2048), unpacked verbatim under utility/interop/thirdparty. Randomized bytes are encoded by both sides and compared, and each side reads the other's output back. Skips with a warning where node or cargo is missing; fails outright if a vendored reference no longer matches its manifest.
##			- Release and helper scripts: package.bash and make clean empty only a dir a build made, and the release, install and pin scripts print their own errors. install.ps1 installs from a stand-in release and refuses a tampered checksum, and the PowerShell files are ASCII. The packaged Windows exes and installers have the icon and the version they were built as. The benchmark and screenshot scripts run their commands clean, and stop when one fails.
##			- CI engine: cicd.bash, run from a copy with fake tools. The fuzz deadline and a real find, the knobs handed to this harness, what --quick runs and skips, the leak checks, -q, the dogfood copy, and the shellcheck, ruff and PSScriptAnalyzer gates.
##			- The harness itself: a run against a program that refuses everything, with Go off the PATH, counts each failure and reaches its summary.
##			- Cross-check against the bundled convert-base-v1 and convert-base-v1b scripts: a base both tools share is checked against both, a base only one has is checked against that one. Every output base each tool offers is either mapped or listed as excused, so a gap can't go unnoticed. A missing script skips its suite with a warning that the summary repeats.
##		- Knobs (env):
##			- CICDTEST_EXE ..........: path to the binary under test (default: ../lib/bin/convert-base-v2).
##			- CICDTEST_DO_LONGTEST ..: 1 for the exhaustive run (more fuzz iterations, larger inputs). cicd.bash sets it unless --quick, or with --long.
##			- CICDTEST_DO_PERF ......: 1 to run the performance section. cicd.bash sets it unless --quick.
##			- CICDTEST_QUICK ........: 1 to skip the packaging rebuild check. cicd.bash sets it under --quick.
##			- CICDTEST_FUZZ_ITERS ...: override the fuzz iteration count.
##			- CICDTEST_SELFCHECK ....: 1 in the run the harness makes of itself, which skips that self-check.
##			- CICD_NO_SKIP ..........: 1 where every tool is installed, as in the container. A skip the run
##			                           didn't ask for, such as a missing node, then fails the run.
##	History: At bottom of script.

##	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail
export LANG="C.UTF-8" LC_ALL="C.UTF-8"

meDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

## Binary under test, and the optional legacy binaries for back-compat cross-checks.
EXE="${CICDTEST_EXE:-${meDir}/../lib/bin/convert-base-v2}"
EXE_V1="${meDir}/utility/convert-base-v1"
EXE_V1B="${meDir}/utility/convert-base-v1b"
doLong=0; [[ "${CICDTEST_DO_LONGTEST:-0}" == "1" ]] && doLong=1
## Performance section runs on any long run, or whenever the engine asks for it
## (it does so unless --quick was passed). A long run always includes it.
doPerf=0; { ((doLong)) || [[ "${CICDTEST_DO_PERF:-0}" == "1" ]]; } && doPerf=1
doQuick=0; [[ "${CICDTEST_QUICK:-0}" == "1" ]] && doQuick=1

## Guard against hangs: a check that doesn't return quickly is a failure, not a wait.
TIMEOUT=(); command -v timeout >/dev/null 2>&1 && TIMEOUT=(timeout 60)

## Colors + counters.
b=$'\e[1m'; dim=$'\e[2m'; grn=$'\e[32m'; red=$'\e[31m'; ylw=$'\e[33m'; rst=$'\e[0m'
declare -i TOTAL=0 PASS=0 FAIL=0
declare -a FAILURES=() WARNINGS=() UNASKED=()

CBT_OUT="$(mktemp)"; CBT_ERR="$(mktemp)"; CBT_TMP="$(mktemp -d)"
cleanup(){ rm -rf "${CBT_OUT}" "${CBT_ERR}" "${CBT_TMP}"; }
trap cleanup EXIT

## Sandbox the user config: the binary writes a default one on its first run,
## and that must land here, not in whoever's home is running the tests. The
## warm-up run does the creating, so no later check sees the one-time note.
export XDG_CONFIG_HOME="${CBT_TMP}/xdg"
"${TIMEOUT[@]}" "${EXE}" --get-index-count >/dev/null 2>&1 || true
## Inside $( ) or <( ) a non-zero status is often the answer: cmp and diff on a
## difference, a conversion that was refused. Ending the subshell there only cut
## the output short, so the status is left to whatever reads it.
trap 'rc=$?; ((BASH_SUBSHELL)) || { printf "\n%sHARNESS ABORTED (exit %s) at line %s: %s%s\n" "${red}" "$rc" "$LINENO" "$BASH_COMMAND" "${rst}" >&2; exit $rc; }' ERR

section(){ printf '\n%s>>> %s%s\n' "${b}" "$*" "${rst}"; }

## _run ARGS...           : run EXE with ARGS (argv, never a shell string), capture _out/_err/_rc.
## _run_in FILE ARGS...   : same, but feed FILE on stdin.
## A bare x="$(...)" that runs the program ends the whole run when a conversion
## is refused. A single run goes through these instead, and a pipeline ends in
## "|| true". Either way the check after it judges what came out.
_run(){    _rc=0; "${TIMEOUT[@]}" "${EXE}" "$@"        >"${CBT_OUT}" 2>"${CBT_ERR}" || _rc=$?; _out="$(<"${CBT_OUT}")"; _err="$(<"${CBT_ERR}")"; }
_run_in(){ local f="$1"; shift; _rc=0; "${TIMEOUT[@]}" "${EXE}" "$@" <"$f" >"${CBT_OUT}" 2>"${CBT_ERR}" || _rc=$?; _out="$(<"${CBT_OUT}")"; _err="$(<"${CBT_ERR}")"; }

## Every check has an ID, the first argument here: when the test was written,
## as milliseconds since 2000-01-01 UTC in base 62. `utility/test-ids.py new`
## makes one, and `test-ids.py check` refuses a check without one or two tests
## sharing one. Loops share their site's ID, and the label tells the runs apart.
## A bad ID fails the check, so a function handed an empty one shows up.
_pass(){
	[[ "$1" =~ ^[0-9A-Za-z]{7}$ ]] || { _fail "$1" "$2" "bad test ID"; return; }
	PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); printf '%s  ok  %s  %s%s\n' "${dim}" "$1" "$2" "${rst}"
}
_fail(){ FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); printf '%s FAIL %-7s  %s%s\n       %s\n' "${red}" "$1" "$2" "${rst}" "$3"; FAILURES+=("$1 $2 :: $3"); }
## A suite that did not run at all. Not a failure, but it must not read as one
## more quiet line either, so the summary repeats every one of these. IDS is a
## space-separated list of the checks that were skipped, one line each. A third
## argument of "asked" marks a skip the run asked for, like --quick's.
_warn(){
	local wid
	for wid in $1; do
		printf '%s SKIP %s  %s%s\n' "${ylw}" "$wid" "$2" "${rst}"
		if [[ "${3:-}" != "asked" ]]; then UNASKED+=("$wid"); fi
	done
	WARNINGS+=("$2 ($1)")
}

## Assert against the last _run/_run_in result.
##   _assert ID MODE LABEL EXPECTED
##   MODE: eq | ne | ok | err | errmsg  (errmsg checks stderr contains EXPECTED)
_assert(){
	local id="$1" mode="$2" label="$3" expected="${4:-}"
	if ((_rc == 124)); then _fail "$id" "$label" "timed out"; return; fi
	case "$mode" in
		eq)     { ((_rc == 0)) && [[ "$_out" == "$expected" ]]; } && _pass "$id" "$label" || _fail "$id" "$label" "rc=$_rc out=[$_out] want=[$expected] err=[$_err]" ;;
		ne)     { ((_rc == 0)) && [[ "$_out" != "$expected" ]]; } && _pass "$id" "$label" || _fail "$id" "$label" "rc=$_rc out=[$_out] should-differ-from=[$expected]" ;;
		ok)     ((_rc == 0)) && _pass "$id" "$label" || _fail "$id" "$label" "expected success, rc=$_rc err=[$_err]" ;;
		err)    ((_rc != 0)) && _pass "$id" "$label" || _fail "$id" "$label" "expected failure, got rc=0 out=[$_out]" ;;
		errmsg) { ((_rc != 0)) && [[ "$_err" == *"$expected"* ]]; } && _pass "$id" "$label" || _fail "$id" "$label" "rc=$_rc err=[$_err] want-substr=[$expected]" ;;
		*)      _fail "$id" "$label" "unknown assert mode '$mode'" ;;
	esac
}

## check ID MODE LABEL EXPECTED -- ARGS...   (ARGS go straight to the binary as argv)
check(){ local id="$1" mode="$2" label="$3" expected="$4"; shift 4; [[ "${1:-}" == "--" ]] && shift; _run "$@"; _assert "$id" "$mode" "$label" "$expected"; }

## Random numbers come from $SRANDOM, which costs no fork.
[[ -n "${SRANDOM:-}" ]] || { printf 'test.bash needs bash 5.1 or later, for $SRANDOM. This is %s.\n' "${BASH_VERSION}" >&2; exit 1; }

## Random base-10 integer, 1..maxlen digits, no leading zeros.
_rand_int(){
	local -i maxlen="$1"
	local -i len=$(( 1 + SRANDOM % maxlen ))
	local digits="" chunk
	while (( ${#digits} < len )); do printf -v chunk '%09d' $(( SRANDOM % 1000000000 )); digits+="$chunk"; done
	digits="${digits:0:len}"
	digits="${digits#"${digits%%[!0]*}"}"
	[[ -z "$digits" ]] && digits="0"
	printf '%s' "$digits"
}


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## CLI surface
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "CLI surface"
_run --version
{ ((_rc == 0)) && [[ "$_out" == "convert-base-v2 v"* ]]; } && _pass EizUJDc "--version prints a version" || _fail EizUJDc "--version prints a version" "rc=$_rc out=[$_out]"
for _vflag in -v -V; do
	_run "$_vflag"
	{ ((_rc == 0)) && [[ "$_out" == "convert-base-v2 v"* ]]; } && _pass ErgVwO8 "$_vflag prints a version" || _fail ErgVwO8 "$_vflag prints a version" "rc=$_rc out=[$_out]"
done
## The library's lib/vX.Y.Z tags sit on the command's release commits, and a
## build from a clone once stamped the library's version on the command.
_run --version
{ ((_rc == 0)) && [[ "$_out" == "convert-base-v2 v"[1-9]* ]]; } && _pass ErkSf4k "--version: command tag" || _fail ErkSf4k "--version: command tag" "out=[$_out]"
## Still one line for scripts: the name, the version, then the build number when
## the build was stamped, with no space at either end. Crockford base32, lower
## case, so no i, l, o or u. A build between releases ends with its date.
_run --version
{ ((_rc == 0)) && [[ "$_out" =~ ^convert-base-v2\ v[^[:space:]]+( build [0-9a-hjkmnp-tv-z]+( \([0-9]{4}-[0-9]{2}-[0-9]{2}\))?)?$ ]]; } && _pass ErlL5dx "--version one-line format" || _fail ErlL5dx "--version one-line format" "out=[$_out]"
## make stamps the commit's time, never the clock, so a release rebuilds to its checksums.
cbEpoch="$(git -C "${meDir}" log -1 --format=%ct 2>/dev/null || true)"
if [[ -z "${cbEpoch}" ]] || ! command -v make >/dev/null 2>&1; then
	_warn ErlL5eT "make build stamp not checked (needs git and make)"
else
	cbMake="$(make -n -C "${meDir}/../lib" local debug wasm release 2>/dev/null || true)"
	{ (($(grep -cF -- "-X main.buildEpoch=${cbEpoch}" <<<"$cbMake") == 3)) && grep -qF -- "--build-epoch '${cbEpoch}'" <<<"$cbMake"; } && _pass ErlL5eT "make build-epoch stamp" || _fail ErlL5eT "make build-epoch stamp" "want ${cbEpoch} in local, debug, wasm and release: [$cbMake]"
fi
check EizUJDd ok  "--help exits 0"          -   --help
check EizUJDe ok  "-h exits 0"              -   -h
check EizUJDf ok  "--examples exits 0"      -   --examples
## Explicit --help/--examples go to stdout so they can be piped (BxZNl-18).
_run --help
{ ((_rc == 0)) && [[ -n "$_out" ]] && [[ "$_out" == *Usage* ]]; } && _pass Eje9ui0 "--help writes to stdout" || _fail Eje9ui0 "--help writes to stdout" "rc=$_rc outlen=${#_out}"
_run --examples
{ ((_rc == 0)) && [[ -n "$_out" ]] && [[ "$_out" == *Examples* ]]; } && _pass Eje9ui1 "--examples writes to stdout" || _fail Eje9ui1 "--examples writes to stdout" "rc=$_rc outlen=${#_out}"
_run --version; cbVer="$_out"
_run --about
{ ((_rc == 0)) && [[ "$_out" == "${cbVer}"$'\n'* ]] && [[ "$_out" == *"Copyright ©"* ]] && [[ "$_out" == *GPL-2.0-or-later* ]] && [[ "$_out" == *"https://github.com/jim-collier/convert-base-v2"* ]]; } && _pass Erfqe2C "--about names version, copyright, license, home" || _fail Erfqe2C "--about names version, copyright, license, home" "rc=$_rc out=[$_out]"
_run --donate
{ ((_rc == 0)) && [[ "$_out" == *"https://github.com/sponsors/jim-collier"* ]] && [[ "$_out" == *"https://ko-fi.com/jimcollier"* ]]; } && _pass Erfqe2D "--donate lists both support links" || _fail Erfqe2D "--donate lists both support links" "rc=$_rc out=[$_out]"
## Several informational flags each print once, in the order given.
_run --donate --version
{ ((_rc == 0)) && [[ "$_out" == "convert-base-v2 is free"* ]] && [[ "$_out" == *$'\n\n'"${cbVer}" ]]; } && _pass Erfqe2E "--donate --version prints both, in order" || _fail Erfqe2E "--donate --version prints both, in order" "rc=$_rc out=[$_out]"
_run --version --donate
{ ((_rc == 0)) && [[ "$_out" == "${cbVer}"$'\n\n'"convert-base-v2 is free"* ]]; } && _pass Erfqe2F "--version --donate prints both, in order" || _fail Erfqe2F "--version --donate prints both, in order" "rc=$_rc out=[$_out]"
_run --help --donate --help
{ ((_rc == 0)) && [[ "$_out" == "${cbVer}"* ]] && [[ "$_out" == *"https://ko-fi.com/jimcollier"* ]] && (($(grep -c '^Usage:' <<<"$_out") == 1)); } && _pass Erfqe2G "--help --donate --help prints help once, then donate" || _fail Erfqe2G "--help --donate --help prints help once, then donate" "rc=$_rc out=[$_out]"
## --about opens with the version line, so --version adds nothing to it.
_run --about --version
{ ((_rc == 0)) && (($(grep -cxF -- "${cbVer}" <<<"$_out") == 1)); } && _pass Erfqe2H "--about covers --version" || _fail Erfqe2H "--about covers --version" "rc=$_rc out=[$_out]"
## No-args error path keeps help on stderr, exit 2, stdout empty.
_run
{ ((_rc == 2)) && [[ -z "$_out" ]] && [[ -n "$_err" ]]; } && _pass Eje9ui2 "no-args help stays on stderr" || _fail Eje9ui2 "no-args help stays on stderr" "rc=$_rc outlen=${#_out} errlen=${#_err}"
_run --list
{ ((_rc == 0)) && [[ "$_out" == *NAME* ]]; } && _pass EizUJDg "--list lists bases" || _fail EizUJDg "--list lists bases" "rc=$_rc"
## --list has an INDEX column, and row 0's name matches --by-index=0 (BxZNl-19).
_run --list
{ ((_rc == 0)) && [[ "$_out" == *INDEX* ]]; } && _pass EjeBOHQ "--list has an INDEX column" || _fail EjeBOHQ "--list has an INDEX column" "rc=$_rc"
## awk consumes the whole stream (NR==2 is the first data row) to avoid a SIGPIPE.
list_idx0="$("${EXE}" --list 2>/dev/null | awk 'NR==2{print $2}' || true)"
_run --get-base-name --by-index=0; byidx0="$_out"
[[ "$list_idx0" == "$byidx0" && -n "$byidx0" ]] && _pass EjeBOHR "--list INDEX 0 matches --by-index=0" || _fail EjeBOHR "--list INDEX 0 matches --by-index=0" "list=[$list_idx0] byidx=[$byidx0]"
## --list-compat shows only the v1/v1b compatibility bases, --list only the rest,
## and the two together cover every index exactly once. A compat base must still
## be reachable by name, it just isn't advertised in the everyday listing.
list_n="$("${EXE}" --list 2>/dev/null | awk '$1 ~ /^[0-9]+$/' | wc -l || true)"
compat_n="$("${EXE}" --list-compat 2>/dev/null | awk '$1 ~ /^[0-9]+$/' | wc -l || true)"
_run --get-index-count; total_n="$_out"
(( compat_n > 0 )) && _pass ElG9gVM "--list-compat lists compatibility bases (${compat_n})" || _fail ElG9gVM "--list-compat lists compatibility bases" "got ${compat_n}"
(( list_n + compat_n == total_n )) && _pass ElG9gVN "--list plus --list-compat covers every index" || _fail ElG9gVN "--list plus --list-compat covers every index" "list=${list_n} compat=${compat_n} total=${total_n}"
_run --list
{ ((_rc == 0)) && [[ "$_out" != *_compat_* ]]; } && _pass ElG9gVO "--list hides compatibility bases" || _fail ElG9gVO "--list hides compatibility bases" "rc=$_rc"
check ElG9gVP eq  "compat base still resolves" 128_compat_v1 -- --get-base-name 128v1compat
## The byte base gave up these names to the --binary flag.
oldnames=""
for oldname in binary bin raw; do "${EXE}" --get-base-name "$oldname" >/dev/null 2>&1 && oldnames+=" $oldname"; done
[[ -z "$oldnames" ]] && _pass ErkSf4p "retired byte-base names gone" || _fail ErkSf4p "retired byte-base names gone" "still resolve:${oldnames}"
## The ALIASES column lists the other names only. Columns: INDEX NAME SIZE NEG DEC RAW ALIASES
aliasdup="$("${EXE}" --list --list-compat 2>/dev/null | awk '$1 ~ /^[0-9]+$/ { for (i = 7; i <= NF; i++) { a = $i; sub(/,$/, "", a); if (a == $2) print $2 } }' || true)"
[[ -z "$aliasdup" ]] && _pass ErkSf4s "--list alias/name dupes" || _fail ErkSf4s "--list alias/name dupes" "repeated on: ${aliasdup}"
## A dash digit can't double as the negative marker, so those bases use "~" or
## none. Every base is checked. One already on "~" or off can't break the rule,
## so its digits aren't read.
dashneg=""
while read -r dnidx dnname _ dnneg _; do
	[[ "$dnidx" =~ ^[0-9]+$ ]] || continue
	[[ "$dnneg" == "~" || "$dnneg" == "(off)" ]] && continue
	dnsyms="$("${EXE}" --show-symbols-0 "$dnname" 2>/dev/null | tr '\0' '\n' || true)"
	[[ $'\n'"${dnsyms}"$'\n' == *$'\n-\n'* ]] || continue
	dashneg+=" ${dnname}=${dnneg}"
done < <("${EXE}" --list --list-compat 2>/dev/null)
[[ -z "$dashneg" ]] && _pass ErkSf4r "dash digit vs neg marker" || _fail ErkSf4r "dash digit vs neg marker" "bases:${dashneg}"
## The README bases table is generated from the binary, so a renamed base leaves
## it pointing at a name that no longer exists. Nothing else notices that.
README_MD="${meDir}/../README.md"
if [[ -r "${README_MD}" ]]; then
	## Names and aliases from one listing. A README name that is neither still
	## gets the program's own lookup, which also takes a prefix or other case.
	declare -A readme_known=()
	while read -r rkidx rkname _ _ _ _ rkaliases; do
		[[ "$rkidx" =~ ^[0-9]+$ ]] || continue
		readme_known["$rkname"]=1
		read -ra rkalias <<<"${rkaliases//,/ }"
		for rka in "${rkalias[@]}"; do readme_known["$rka"]=1; done
	done < <("${EXE}" --list --list-compat 2>/dev/null)
	readme_stale=""; readme_n=0
	while read -r rname; do
		readme_n=$((readme_n + 1))
		[[ -n "${readme_known["$rname"]:-}" ]] && continue
		"${TIMEOUT[@]}" "${EXE}" --get-base-name "$rname" >/dev/null 2>&1 || readme_stale+=" ${rname}"
	done < <(grep -oP '^\| *[0-9]+ \| *\K[^ |]+' "${README_MD}" | sort -u)
	{ (( readme_n >= 20 )) && [[ -z "$readme_stale" ]]; } \
		&& _pass ElWMN5U "README bases table resolves (${readme_n} names)" \
		|| _fail ElWMN5U "README bases table resolves" "scraped=${readme_n} stale:${readme_stale:- none}"
else
	_warn ElWMN5U "README bases table not checked: no readable file at ${README_MD}"
fi
## The Go example in the library doc has to build against this tree and give
## the command's answer. It's the first ~~~go block there, run as main's body.
GODOC_MD="${meDir}/../use_in_your_code.md"
GODOC_DIR="${CBT_TMP}/godoc"
if ! go env GOVERSION >/dev/null 2>&1; then
	_warn EsifL7e "Go doc example skipped: needs a Go toolchain"
elif ! gdBody="$(awk '/^~~~go$/ {on = 1; next} on && /^~~~$/ {exit} on' "${GODOC_MD}" 2>/dev/null)" || [[ -z "$gdBody" ]]; then
	_fail EsifL7e "Go doc example" "no ~~~go block in ${GODOC_MD}"
else
	mkdir -p "${GODOC_DIR}"
	printf 'module godoc\n\ngo 1.21\n\nrequire github.com/jim-collier/convert-base-v2/lib v0.0.0\n\nreplace github.com/jim-collier/convert-base-v2/lib => %s\n' \
		"$(cd "${meDir}/../lib" && pwd)" >"${GODOC_DIR}/go.mod"
	{
		printf 'package main\n\nimport (\n\t"fmt"\n\n\t"github.com/jim-collier/convert-base-v2/lib/convertbase"\n)\n\nfunc main() {\n'
		printf '%s\n' "$gdBody"
		printf '\tif err != nil {\n\t\tpanic(err)\n\t}\n\tfmt.Println(out)\n}\n'
	} >"${GODOC_DIR}/main.go"
	gdWant="$("${EXE}" --from 10 --to 62 86434491232548995369 2>/dev/null || true)"
	if gdGot="$(cd "${GODOC_DIR}" && GOFLAGS=-mod=mod GOPROXY=off go run . 2>"${CBT_ERR}")" && [[ -n "$gdWant" && "$gdGot" == "$gdWant" ]]; then
		_pass EsifL7e "Go doc example builds and matches the command"
	else
		_fail EsifL7e "Go doc example builds and matches the command" "want=[$gdWant] got=[${gdGot:-}] $(tail -2 "${CBT_ERR}" | tr '\n' ' ')"
	fi
fi
## --by-index outside a query mode is ignored, with a stderr note. The note
## reads like every other unused flag's since 2026100516265602, so the wording
## checked changed from "--by-index is ignored".
_run --by-index 3 255 16
{ ((_rc == 0)) && [[ "$_out" == FF ]] && [[ "$_err" == *"--by-index does nothing"* ]]; } && _pass EjeBOHS "--by-index note in conversion mode" || _fail EjeBOHS "--by-index note in conversion mode" "rc=$_rc out=[$_out] err=[$_err]"

## Base-introspection query flags (used by the full-coverage fuzz below).
_run --get-index-count
{ ((_rc == 0)) && [[ "$_out" =~ ^[0-9]+$ ]] && ((_out > 0)); } && _pass Ej1HnoG "--get-index-count prints a count" || _fail Ej1HnoG "--get-index-count prints a count" "rc=$_rc out=[$_out]"
check Ej1HnoH eq     "--get-base-name --by-index=0" 2               -- --get-base-name --by-index=0
check Ej1HnoI eq     "--get-base-name alias hex"    16              -- --get-base-name hex
check Ej1HnoJ errmsg "--by-index out of range"      'out of range'  -- --get-base-name --by-index=999999
check Ej1HnoK errmsg "query needs a selector"       'select a base' -- --get-base-name
_run --show-symbols 16
{ ((_rc == 0)) && [[ "$_out" == "0123456789ABCDEF" ]]; } && _pass EjUH4Lo "--show-symbols 16 concatenates 16 symbols" || _fail EjUH4Lo "--show-symbols 16 concatenates 16 symbols" "rc=$_rc out=[$_out]"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Basic conversions and aliases
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Basic conversions and aliases"
check EizUJDh eq  "255 -> 16"               FF        -- 255 16
check EizUJDi eq  "255 -> 8"                377       -- 255 8
check EizUJDj eq  "255 -> 2"                11111111  -- 255 2
check EizUJDk eq  "hex FF -> 10"            255       -- --from 16 FF
check EizUJDl eq  "bin 11111111 -> 10"     255       -- --from 2 11111111
check EizUJDm eq  "alias hex -> 10"         255       -- --from hex FF
check EizUJDn eq  "alias octal out"         377       -- 255 octal
check EizUJDo eq  "alias decimal in"        2A        -- --from decimal 42 16
check EizUJDp eq  "leading zeros ignored"   FF        -- 000255 16
check EizUJDq eq  "--to flag beats posn"    FF        -- --to 16 255 10
## "base"/"base-"/"base_"/"base " prefix on any name or alias.
check EjUSzQO eq  "base16 prefix"           FF        -- 255 base16
check EjUSzQP eq  "base-16 prefix"          FF        -- 255 base-16
check EjUSzQQ eq  "base_16 prefix"          FF        -- 255 base_16
check EjUSzQR eq  "base hex prefix"         FF        -- 255 "base hex"
check EjUSzQS eq  "base-hex prefix in"      255       -- --from base-hex FF
check EjUSzQT eq  "base_ prefix on alias"   255       -- --from base_hex FF
## Crockford base32 is asymmetric: reads O as 0, I/L as 1 (case-insensitive),
## but never emits them. O1=1, I1=L1=33, LO=32; output for 24 stays R (no O/I/L).
check Eje5hGK eq  "32c decode O->0"          1         -- --from 32c --to 10 -- O1
check Eje5hGL eq  "32c decode o->0"          1         -- --from 32c --to 10 -- o1
check Eje5hGM eq  "32c decode I->1"          33        -- --from 32c --to 10 -- I1
check Eje5hGN eq  "32c decode L->1"          33        -- --from 32c --to 10 -- L1
check Eje5hGO eq  "32c decode l->1"          33        -- --from 32c --to 10 -- l1
check Eje5hGP eq  "32c encode stays strict"  r         -- --from 10 --to 32c -- 24


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Negatives, fractionals, precision, lower, raw
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Negatives, fractionals, precision, lower, raw"
check EizUJDr eq  "negative -- guard"       -1E240    -- -- -123456 16
check EizUJDs eq  "fractional 1.5 -> 16"    1.8       -- 1.5 16
## 1.5 -> base3 is 1.1111...; at precision 2 it rounds half-up (0.111.. -> "12"3), not truncates.
check EjYV8Gm eq  "fractional rounding"     1.12      -- --precision 2 1.5 3
## More fixed fractional pins (fuzz only does integers, so the frac path needs
## its own coverage): signed fractions, a clean power-of-two fraction, and the
## imprecise 0.1 tail rounded to precision.
check EjeFbj6 eq  "fraction 0.5 -> 16"       0.8       -- --number 0.5 16
check EjeFbj7 eq  "neg fraction -0.5 -> 2"   -0.1      -- --number --precision 6 -- -0.5 2
check EjeFbj8 eq  "neg mixed -255.5 -> 16"   -FF.8     -- --number -- -255.5 16
check EjeFbj9 eq  "fraction 255.5 -> 16"     FF.8      -- --number 255.5 16
check EjeFbjA eq  "fraction 0.1 -> 16 p6"     0.19999A -- --number --precision 6 0.1 16
## Auto precision (the default): output frac length tracks the input's scaled by
## base size, so a short decimal input does not grow an invented tail. Weird
## corners: widening (dec->bin), narrowing (hex->dec), an odd base ratio, a
## terminating value that trims, and a big base down to a small one.
check Ejlud4y eq  "auto 0.1 -> 16"            0.1A      -- --number 0.1 16
check Ejlud4z eq  "auto 0.1 -> 2"             0.00011   -- --number 0.1 2
check Ejlud50 eq  "auto 0.1 -> 3"             0.0022    -- --number 0.1 3
check Ejlud51 eq  "auto FF.8 -> 10"           255.5     -- --from 16 --to 10 FF.8
check Ejlud52 eq  "auto 0.5 -> 2 (trims)"     0.1       -- --number 0.5 2
check Ejlud53 eq  "auto 0.9 -> 2 (round up)"  0.11101   -- --number 0.9 2
check Ejlud54 eq  "auto 288 -> 10"            0.0035    -- --from 288j1 --to 10 0.1
check Ejlud55 eq  "auto tiny 0.000001 -> 16"  0.000011  -- --number 0.000001 16
## Independent (non-round-trip) known-value pins for bases that otherwise only
## get self-round-trip fuzz, so a bug mirrored in encode+decode can't hide.
check ElG9gVQ eq  "pin 1000000 -> 60tc"      4cmf      -- --number 1000000 60tc
check ElG9gVR eq  "pin 65535 -> 60tc"        JCF       -- --number 65535 60tc
check EjeFbjB eq  "pin 1000000 -> 62"        4C92      -- --number 1000000 62
check EjeFbjC eq  "pin 1000000 -> 36"        LFLS      -- --number 1000000 36
check EjeFbjD eq  "pin 1000000 -> 85ipv6"    1rYy      -- --number 1000000 85ipv6
check EjeFbjE eq  "pin 65535 -> 62"          H31       -- --number 65535 62
check EizUJDt eq  "--lower on hex"          ff        -- --lower 255 16
check EizUJDu errmsg "--lower on mixed-case" "--lower is invalid for mixed-case" -- --lower 9 62
check ErkSf4m eq  "--upper on 32c"          R         -- --upper --to 32c 24
check ErkSf4n errmsg "--upper on mixed-case" "--upper is invalid for mixed-case" -- --upper 255 62
check ErkSf4o errmsg "--upper with --lower"  'not both' -- --upper --lower 255 16
## The case flags apply to digits only. A marker is not a digit, so recasing it
## yields a value the same base cannot read back - and no output would show it.
check Em1DQ5Y eq  "--lower keeps neg marker" "Nff"    -- --lower --to 16 --to-neg N -- -255
check Em1DQ5Z eq  "--upper keeps dec marker" "FF.8"   -- --upper --to 16 --to-dec . -- 255.5
check Em1DQ5a eq  "--lower keeps both"       "Nff.8"  -- --lower --to 16 --to-neg N -- -255.5
## Precision is bounded, the same way the browser and reactor builds bound it:
## the scale factor is one power of the output base, so a mistyped value asks
## for gigabytes before it asks for anything else.
check Em1DQ5b errmsg "precision upper bound" 'at most' -- --precision 100000000 0.1 16
check Em1DQ5c ok  "precision at the bound"   -         -- --precision 100000 0.1 16
## --no-newline: exact bytes, no trailing newline.
_run --no-newline 255 16
{ ((_rc == 0)) && [[ "$(wc -c <"${CBT_OUT}")" == "2" ]]; } && _pass EjTpGMi "--no-newline has no trailing newline" || _fail EjTpGMi "--no-newline has no trailing newline" "bytes=$(wc -c <"${CBT_OUT}")"
## --raw was this flag's old name, and it overlapped the raw-byte base.
check ErkSf4q errmsg "--raw is not a flag"   'unknown flag' -- --raw 255 16


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Custom symbol specs
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Custom symbol specs"
check EizUJDv eq  "custom in, fractional"   148.25    -- --from-symbols ABCD --to 10 CBBA.B
check EizUJDw eq  "custom out, neg+dec"     -9FCC.8M6 -- --from-symbols "aeiouy.-_0" --from-neg "~" --from-dec "/" --to 20ws "~y0-._/ooo"
## Markers are separate from the symbols. The retired in-string tokens must be an
## error, never silently absorbed as a digit.
check El4bQKu errmsg "retired neg= token"   'no longer part of the symbol spec' -- --from-symbols "0123456789 neg=~" --to 10 5
check El4bQKv errmsg "retired dec= token"   'no longer part of the symbol spec' -- --from-symbols "0123456789 dec=," --to 10 5
check El4bQKw errmsg "retired pad= token"   'no longer part of the symbol spec' -- --from-symbols "0123456789 pad==" --to 10 5
## Markers apply to named bases too, not just custom alphabets.
check El4bQKx eq  "marker on named base"    -255      -- --from 16 --from-neg "~" --to 10 "~ff"
check El4bQKy eq  "marker on output base"   "~FF"     -- --from 10 --to 16 --to-neg "~" -- -255
check El4bQKz errmsg "marker collides"      'is also a digit' -- --from 16 --from-neg "a" --to 10 ff
check El4bQL0 errmsg "markers vs bytes"     'is raw bytes' -- --from bytes --from-neg "~" --to 16 5
check EizUJDx ok  "custom both sides"       -         -- --from-symbols ABCD --to-symbols 0123 CBBA
check EizUJDy errmsg "one-symbol spec fails" 'at least 2 symbols' -- --from-symbols A 5 16
## Spec parser edge cases: multi-token comma split makes a base-4 alphabet
## (decimal 3 stays a single digit "3"; the old bug made it base-3); escaped
## space is a literal-space digit; a digit that contains a marker is rejected.
check EjeFbjF eq  "spec comma-split -> base4"  3        -- --number --from 10 --to-symbols "0,1 2 3" 3
check EjeFbjG eq  "spec escaped-space digit"   2        -- --from-symbols 'a\ b' --to 10 -- b
check EjeFbjH err "spec marker-in-digit"       -        -- --from-symbols "a b a.b" --to 10 -- a.b
## 85ps carries a literal comma and backslash as their own digits; its alphabet
## must stay exactly 85 symbols (regression pin for the escape/comma-split bug).
sym85=$("${EXE}" --show-symbols-0 85ps 2>/dev/null | tr '\0' '\n' | grep -c . || true)
[[ "$sym85" == 85 ]] && _pass EjeFbjI "85ps has exactly 85 symbols" || _fail EjeFbjI "85ps has exactly 85 symbols" "got=$sym85"

#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Config file loading (a user-defined base via --config)
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Config file"
cfg="${CBT_TMP}/bases.shcl"
{
	printf 'base: myb\n\taliases: mybase, mb\n\tsymbols: "z y x w"\n\n'
	printf 'base: u12\n\tsymbols: "0123456789-_"\n\tnegative: N\n\n'
	printf 'base: nodec\n\tsymbols: 0123456789\n\tdecimal:\n\n'
	printf 'base: fruit4\n\tsymbols:\n\t\t* 🍎\n\t\t* 🍊\n\t\t* 🍋\n\t\t* 🍌\n\n'
	printf 'base: spacey\n\tsymbols: "a b", c, d, e\n'
} >"$cfg"
## The custom 4-symbol base "myb" resolves only when the config is loaded.
check EjeFbjJ eq  "config base loads"        yx        -- --config "$cfg" --from 10 --to myb 6
check EjeFbjK errmsg "config base absent otherwise" 'unknown base' -- --from 10 --to myb 6
check EjeFbjL errmsg "explicit missing config errors" 'no such file' -- --config "${CBT_TMP}/nope.shcl" 255 16
## Extra names from the aliases field; the "base:" line stays canonical.
check ElHp3yS eq  "config alias resolves"    yx        -- --config "$cfg" --from 10 --to mb 6
check ElHp3yT eq  "config canonical name"    myb       -- --config "$cfg" --get-base-name mybase
## A marker set, and a marker switched off on purpose by leaving it empty.
check ElHp3yU eq  "config negative marker"   N11       -- --config "$cfg" --from 10 --to u12 -- -13
check ElHp3yV errmsg "config empty marker disables" 'no decimal marker' -- --config "$cfg" --from 10 --to nodec 12.5
## Both list spellings: stacked one per line, and inline with a symbol that
## carries a space of its own.
check ElHp3yW eq  "config stacked list"      '🍊🍋'    -- --config "$cfg" --from 10 --to fruit4 6
spacesym=$("${EXE}" --config "$cfg" --show-symbols-0 spacey 2>/dev/null | tr '\0' '|' || true)
[[ "$spacesym" == 'a b|c|d|e' ]] && _pass ElHp3yX "config symbol with a space" || _fail ElHp3yX "config symbol with a space" "got='$spacesym'"
## A typo has to fail loudly: silently dropping a field means the wrong alphabet.
printf 'base: x\n\tsybmols: abc\n' >"${CBT_TMP}/typo.shcl"
check ElHp3yY errmsg "config typo rejected"  'unknown field' -- --config "${CBT_TMP}/typo.shcl" 255 16
## A quoted name is a typo too, and it used to slip past the check unseen.
printf 'base: x\n\tsymbols: abc\n\t"weird.field": 1\n' >"${CBT_TMP}/quoted.shcl"
check Em1008u errmsg "config quoted typo rejected" 'unknown field' -- --config "${CBT_TMP}/quoted.shcl" 255 16
## A field written twice reads back as nothing, so the base would quietly get a
## default instead of what the file says.
printf 'base: x\n\tsymbols: abc\n\tnegative: A\n\tnegative: B\n' >"${CBT_TMP}/twice.shcl"
check Em1008v errmsg "config repeated field rejected" 'more than once' -- --config "${CBT_TMP}/twice.shcl" 255 16
## A field indented under another one was never read, and the empty field above
## it switched its marker off.
printf 'base: x\n\tsymbols: abc\n\tnegative:\n\t\tdecimal: X\n' >"${CBT_TMP}/nested.shcl"
check Erg4X7I errmsg "config nested field rejected" 'line 4: base "x": "decimal" is nested under negative' -- --config "${CBT_TMP}/nested.shcl" 255 16
printf 'base: x\n\tsymbols: abc\n  bogus indent\n' >"${CBT_TMP}/bad.shcl"
check ElHp3yZ errmsg "config bad line rejected" 'line 3'          -- --config "${CBT_TMP}/bad.shcl" 255 16
## --help goes on past a config that won't load and says why in its config
## section. It used to stop at the error, and called an unreadable file loaded.
_run --config "${CBT_TMP}/bad.shcl" --help
{ ((_rc == 0)) && [[ "$_out" == *Usage:* ]] && grep -qF "bad.shcl" <<<"$_out" && grep -qF "[not loaded]" <<<"$_out" && grep -qF "line 3:" <<<"$_out" && [[ "$_out" == *"(optional user-specified flags)"* ]]; } && _pass ErmufTF "--help shows a config error and prints the rest" || _fail ErmufTF "--help shows a config error and prints the rest" "rc=$_rc err=[$_err] out=[$_out]"
## Both the default user path, which a normal run skips when it won't open, and
## a typed one, which a normal run refuses.
lockedcfg="${CBT_TMP}/xdg-locked/convert-base-v2/convert-base-v2.shcl"
mkdir -p "${lockedcfg%/*}"
printf 'base: lockd\n\tsymbols: abcd\n##    Format   3\n' >"$lockedcfg"; chmod 000 "$lockedcfg"
if [[ -r "$lockedcfg" ]]; then
	_warn ErmufUW "--help unreadable config not checked (running as root)"
else
	for lockedhow in default typed; do
		if [[ "$lockedhow" == default ]]; then XDG_CONFIG_HOME="${CBT_TMP}/xdg-locked" _run --help; else _run --config "$lockedcfg" --help; fi
		{ ((_rc == 0)) && grep -qF "[unreadable]" <<<"$_out" && ! grep -qF "[loaded]" <<<"$_out"; } && _pass ErmufUW "--help unreadable config ($lockedhow path)" || _fail ErmufUW "--help unreadable config ($lockedhow path)" "rc=$_rc err=[$_err] out=[$_out]"
	done
fi
chmod 600 "$lockedcfg"
## SHCL leaves a bare backslash alone, so the symbol spec's own escape still
## puts a space inside a digit. In double quotes an unknown escape is refused.
## Both files name the current format, since one without it is read the old
## way (see the migration section).
printf 'base: bs\n\tsymbols: a\\ b c\n##    Format   3\n' >"${CBT_TMP}/bslash.shcl"
bssym=$("${EXE}" --config "${CBT_TMP}/bslash.shcl" --show-symbols-0 bs 2>/dev/null | tr '\0' '|' || true)
[[ "$bssym" == 'a b|c' ]] && _pass Erg0gYy "config bare backslash escape" || _fail Erg0gYy "config bare backslash escape" "got='$bssym'"
printf 'base: bs\n\tsymbols: "a\\ b c"\n##    Format   3\n' >"${CBT_TMP}/bslashq.shcl"
check Erg0gYz errmsg "config bad escape rejected" 'line 2'     -- --config "${CBT_TMP}/bslashq.shcl" 255 16
## A raw block under symbols used to be reported as missing symbols, and under
## most other fields it was dropped. Rows of digits are ambiguous, so it's refused.
printf 'base: rb\n\tsymbols:\n\t\t~~~\n\t\tABCD\n\t\tEFGH\n\t\t~~~\n' >"${CBT_TMP}/rawsym.shcl"
check ErgbjuS errmsg "config raw block symbols rejected" 'line 2: base "rb": symbols takes a one-line value, not a raw block' -- --config "${CBT_TMP}/rawsym.shcl" 255 16
printf 'base: rb\n\tsymbols: 01\n\taliases:\n\t\t~~~\n\t\trbx\n\t\t~~~\n' >"${CBT_TMP}/rawalias.shcl"
check Erg6SWW errmsg "config raw block alias rejected" 'line 3: base "rb": aliases takes a one-line value, not a raw block' -- --config "${CBT_TMP}/rawalias.shcl" 255 16
## First run writes the default config, and 10emoji comes from it rather than
## from the built-in set. XDG_CONFIG_HOME was sandboxed at the top of the run.
usercfg="${XDG_CONFIG_HOME}/convert-base-v2/convert-base-v2.shcl"
[[ -s "$usercfg" ]] && _pass ElHp3ya "first run creates the user config" || _fail ElHp3ya "first run creates the user config" "missing $usercfg"
## It names its SHCL format, so a later version can tell it from an older file.
grep -Eq '^##    Format   [0-9]+$' "$usercfg" && _pass Erg0gZ0 "user config names its format" || _fail Erg0gZ0 "user config names its format" "no Format line in $usercfg"
check ElczR2W eq  "10emoji comes from config"  '😑😔😘😜' -- --from 10 --to 10emoji 1234
check ElczR2X eq  "10emoji keeps its old name" '😑😔😘😜' -- --from 10 --to emoji10 1234


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Config files written for an older SHCL format
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Config migration"
## An old file as the SHCL 1.x releases wrote one, with no Format line. Under
## the current rules the bare \t is two characters, so oldtab would be one
## digit, and the \# marker would be a backslash.
oldcfg="${CBT_TMP}/oldcfg.shcl"
{
	printf '# my bases\n'
	printf 'base: oldtab\n\tsymbols: 0\\t1\\t2\\t3\n\n'
	printf 'base: oldq\n\taliases: oq\n\tsymbols: "a\\ b"\n\tnegative: \\#\n'
} >"$oldcfg"
## A fresh config dir holding FILE as its user config. Prints the dir.
fMigDir(){ local d="${CBT_TMP}/$1"; mkdir -p "${d}/convert-base-v2"; cp "$2" "${d}/convert-base-v2/convert-base-v2.shcl"; printf '%s' "$d"; }
## How many backups sit beside a user config.
fBackups(){ local -a found=("$1"/convert-base-v2/convert-base-v2_backup_[0-9]*-[0-9]*_format-v1.shcl); [[ -e "${found[0]}" ]] && printf '%s' "${#found[@]}" || printf '0'; }

migdir="$(fMigDir mig1 "$oldcfg")"; migcfg="${migdir}/convert-base-v2/convert-base-v2.shcl"
XDG_CONFIG_HOME="$migdir" _run --from 10 --to oldtab 6
_assert ErgDzU8 eq "old config converts and reads the old way" '12'
[[ "$_err" == *"note: converted ${migcfg}"*"_format-v1.shcl"* ]] && _pass ErgDzU9 "conversion note names the backup" || _fail ErgDzU9 "conversion note names the backup" "err=[$_err]"
nbak="$(fBackups "$migdir")"
if [[ "$nbak" == "1" ]]; then
	bak=("${migdir}"/convert-base-v2/convert-base-v2_backup_*_format-v1.shcl)
	cmp -s "${bak[0]}" "$oldcfg" && _pass ErgDzUA "backup holds the original bytes" || _fail ErgDzUA "backup holds the original bytes" "${bak[0]} differs"
else
	_fail ErgDzUA "backup holds the original bytes" "found ${nbak} backups"
fi
grep -q '^##    Format   3$' "$migcfg" && _pass ErgDzUB "converted config names format 3" || _fail ErgDzUB "converted config names format 3" "no Format line in $migcfg"
grep -q '^# my bases$' "$migcfg" && _pass ErgDzUC "converted config keeps its comments" || _fail ErgDzUC "converted config keeps its comments" "comment gone from $migcfg"
migsym=$(XDG_CONFIG_HOME="$migdir" "${EXE}" --show-symbols-0 oldtab 2>/dev/null | tr '\0' '|' || true)
[[ "$migsym" == '0|1|2|3' ]] && _pass ErgDzUD "converted config resolves the same alphabet" || _fail ErgDzUD "converted config resolves the same alphabet" "got='$migsym'"
XDG_CONFIG_HOME="$migdir" check ErgDzUE eq "converted config keeps the old marker" '\#ba' -- --from 10 --to oq -- -6
cp "$migcfg" "${CBT_TMP}/mig1-after.shcl"
XDG_CONFIG_HOME="$migdir" _run --from 10 --to oldtab 6
{ ((_rc == 0)) && [[ -z "$_err" ]] && [[ "$(fBackups "$migdir")" == "1" ]] && cmp -s "$migcfg" "${CBT_TMP}/mig1-after.shcl"; } \
	&& _pass ErgDzUF "second run changes nothing" || _fail ErgDzUF "second run changes nothing" "rc=$_rc err=[$_err] backups=$(fBackups "$migdir")"

## The same file under the old rules, from v3.0.0, the last release on SHCL 1.x.
## It is built from the tag, so it needs the git history.
repoTop="$(git -C "${meDir}" rev-parse --show-toplevel 2>/dev/null || true)"
oldExe="${CBT_TMP}/convert-base-v2-v3.0.0"
if [[ -z "$repoTop" ]] || ! command -v go >/dev/null 2>&1 || ! git -C "$repoTop" rev-parse -q --verify 'v3.0.0^{commit}' >/dev/null 2>&1; then
	_warn "ErgDzUG ErgDzUH" "config migration vs v3.0.0 (needs go and the v3.0.0 tag)"
elif ! { mkdir -p "${CBT_TMP}/v3src" && git -C "$repoTop" archive v3.0.0 lib | tar -x -C "${CBT_TMP}/v3src" \
	&& (cd "${CBT_TMP}/v3src/lib" && go build -o "$oldExe" ./cmd/convert-base-v2); } >"${CBT_ERR}" 2>&1; then
	_fail ErgDzUG "build v3.0.0 for the migration check" "$(head -c 400 "${CBT_ERR}")"
else
	for mb in oldtab oldq; do
		want=$(XDG_CONFIG_HOME="${CBT_TMP}/xdg" "$oldExe" --config "$oldcfg" --show-symbols-0 "$mb" 2>&1 | tr '\0' '|' || true)
		got=$("${EXE}" --config "${CBT_TMP}/mig1-after.shcl" --show-symbols-0 "$mb" 2>&1 | tr '\0' '|' || true)
		[[ -n "$want" && "$got" == "$want" ]] && _pass ErgDzUG "converted $mb matches v3.0.0 on the original" || _fail ErgDzUG "converted $mb matches v3.0.0 on the original" "v3.0.0='$want' now='$got'"
	done
	want=$(XDG_CONFIG_HOME="${CBT_TMP}/xdg" "$oldExe" --config "$oldcfg" --from 10 --to oq -- -6 2>&1 || true)
	got=$("${EXE}" --config "${CBT_TMP}/mig1-after.shcl" --from 10 --to oq -- -6 2>&1 || true)
	[[ "$got" == "$want" ]] && _pass ErgDzUH "converted marker matches v3.0.0" || _fail ErgDzUH "converted marker matches v3.0.0" "v3.0.0='$want' now='$got'"
fi

## The old rules read [ab] with an error, and the conversion would turn it into
## a value that loads. It has to stay refused, and stay untouched.
printf 'base: x\n\tsymbols: [ab]\n' >"${CBT_TMP}/oldbad.shcl"
migdir="$(fMigDir mig2 "${CBT_TMP}/oldbad.shcl")"
XDG_CONFIG_HOME="$migdir" _run 255 16
_assert ErgDzUI errmsg "unconvertible old config refused" "can't be converted"
{ cmp -s "${migdir}/convert-base-v2/convert-base-v2.shcl" "${CBT_TMP}/oldbad.shcl" && [[ "$(fBackups "$migdir")" == "0" ]]; } \
	&& _pass ErgDzUJ "unconvertible old config left alone" || _fail ErgDzUJ "unconvertible old config left alone" "changed, or backups=$(fBackups "$migdir")"

## A directory that cannot be written loses nothing, and the run goes on.
if [[ "$(id -u)" == "0" ]]; then
	_warn "ErgDzUK ErgDzUL ErgDzUM" "config migration in a read-only dir (root writes through it)"
else
	migdir="$(fMigDir mig3 "$oldcfg")"
	chmod 555 "${migdir}/convert-base-v2"
	XDG_CONFIG_HOME="$migdir" _run --from 10 --to oldtab 6
	_assert ErgDzUK eq "read-only config dir still reads the old way" '12'
	[[ "$_err" == *"couldn't be converted"* ]] && _pass ErgDzUL "read-only config dir says so" || _fail ErgDzUL "read-only config dir says so" "err=[$_err]"
	{ cmp -s "${migdir}/convert-base-v2/convert-base-v2.shcl" "$oldcfg" && [[ "$(fBackups "$migdir")" == "0" ]]; } \
		&& _pass ErgDzUM "read-only config dir loses nothing" || _fail ErgDzUM "read-only config dir loses nothing" "changed, or backups=$(fBackups "$migdir")"
	chmod 755 "${migdir}/convert-base-v2"
fi

## A file named with --config is never rewritten. It is read the old way.
migdir="$(fMigDir mig4 "$oldcfg")"
_run --config "${migdir}/convert-base-v2/convert-base-v2.shcl" --from 10 --to oldtab 6
_assert ErgDzUN eq "explicit old config reads the old way" '12'
[[ "$_err" == *"shcl migrate --write"* ]] && _pass ErgDzUO "explicit old config says how to convert it" || _fail ErgDzUO "explicit old config says how to convert it" "err=[$_err]"
{ cmp -s "${migdir}/convert-base-v2/convert-base-v2.shcl" "$oldcfg" && [[ "$(fBackups "$migdir")" == "0" ]]; } \
	&& _pass ErgDzUP "explicit old config left alone" || _fail ErgDzUP "explicit old config left alone" "changed, or backups=$(fBackups "$migdir")"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Errors and robustness (security by construction: input is argv, never eval'd)
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Errors and robustness"
check EizUJDz errmsg "unknown base"         'unknown base'                       -- 10 nope
## Friendlier stumble messages (BxZNl-16).
check Eje7f0i errmsg "unknown base near-match" 'did you mean "hex"'              -- 255 hexx
check Eje7f0j errmsg "unknown base to --list"  'see --list'                      -- 255 nope
check Eje7f0k errmsg "flags after number"      'flags must come before'          -- 255 16 --lower
check Eje7f0l errmsg "neg number without --"   'a "--" separator'                -- -123 16
check Eje7f0m errmsg "unknown flag hint"       'unknown flag'                    -- --lowr 255 16
check EizUJE0 errmsg "bad digit for base"   'not in base'                        -- --from 2 9
check EizUJE1 errmsg "extra positional"     'unexpected extra positional'        -- 1 2 3
check EizUJE2 errmsg "precision < 0"        'non-negative integer or'            -- --precision -1 1
check Ejlud56 errmsg "precision bad word"   'non-negative integer or'            -- --precision foo 1 16
check EizUJE3 errmsg "empty input"          'empty input'                        -- "" 16
check EizUJE4 err   "multiple decimals"     -                                     -- --from 10 1.2.3 16
check EizUJE5 err   "double negative"       -                                     -- -- --5 16
## A decimal marker with no digits on either side is not zero.
for nd in . -.; do check ErlzAd6 errmsg "no digits: '${nd}'" 'no digits in input' -- --from 10 --to 16 -- "$nd"; done
## A flag typed after the NUMBER is named as one, not read as OUTBASE or as an
## extra argument. "-" and a digit is a negative number, so it gets no flag hint,
## and a config base whose name starts with "-" still works as OUTBASE.
for fa in "255 --lower" "255 --about" "ff --from hex" "255 16 --lower"; do
	read -ra faArgs <<<"$fa"
	check ErssdCS errmsg "flag after number: ${fa}" 'flags must come before' -- "${faArgs[@]}"
done
check ErssdD7 errmsg "negative-looking OUTBASE is a base" 'unknown base' -- 255 -5
printf 'base: dashy\n\taliases: -x\n\tsymbols: A B C D\n##    Format   3\n' >"${CBT_TMP}/dashy.shcl"
check ErsskLV eq "config base named -x is no flag" CB -- --config "${CBT_TMP}/dashy.shcl" 9 -x

## A command line that can't be parsed exits 2. Input that won't convert exits 1.
for ua in "--lowr 255 16" "255 --lower" "ff --from hex" "1 2 3" "-123 16" "--by-index x --show-symbols" "--show-symbols"; do
	read -ra uaArgs <<<"$ua"; _run "${uaArgs[@]}"
	{ ((_rc == 2)) && [[ "$_err" == error:* ]]; } && _pass ErssdDk "usage error exits 2: ${ua}" || _fail ErssdDk "usage error exits 2: ${ua}" "rc=$_rc err=[$_err]"
done
for ca in "255 nope" "255 -5" "--from 2 9" "--from 16 --to 64 --binary FFF"; do
	read -ra caArgs <<<"$ca"; _run "${caArgs[@]}"
	((_rc == 1)) && _pass ErssdER "failed conversion exits 1: ${ca}" || _fail ErssdER "failed conversion exits 1: ${ca}" "rc=$_rc err=[$_err]"
done

## Flags that can't go together, or that the mode refuses, are usage errors too.
## So is an argument a query has no use for, which used to be dropped.
for ua in "--precision foo 255" "--binary --number --from 16 --to 64 dead" "--lower --upper 255" "--escape-controls --binary --from 16 --to 64 dead" \
	"--show-symbols hex --lower" "--list foo" "--get-index-count 3" "--by-index 3 --show-symbols hex"; do
	read -ra uaArgs <<<"$ua"; _run "${uaArgs[@]}"
	{ ((_rc == 2)) && [[ "$_err" == error:* ]]; } && _pass ErsveGw "refused flags exit 2: ${ua}" || _fail ErsveGw "refused flags exit 2: ${ua}" "rc=$_rc out=[$_out] err=[$_err]"
done
## A value the chosen base can't take stays exit 1, as an unknown base does.
printf 'hi' >"${CBT_TMP}/idle_in"
for ca in "--lower --to 62 255" "--to-pad = --to 10 255" "--from bytes --from-neg x --to 64 -"; do
	read -ra caArgs <<<"$ca"; _run_in "${CBT_TMP}/idle_in" "${caArgs[@]}"
	((_rc == 1)) && _pass ErswASw "base refuses the flag, exit 1: ${ca}" || _fail ErswASw "base refuses the flag, exit 1: ${ca}" "rc=$_rc err=[$_err]"
done

## A flag that does nothing in the run gets one note on stderr, and the output
## is what it is without the flag (design.md, "Flags by mode").
for ic in "--precision 5|--binary --from 16 --to 64 dead" "--to-neg ~|--binary --from 16 --to 64 dead" "--from-dec ,|--binary --from 16 --to 64 dead" \
	"--to-pad =|--to 64 255" "--to-tail=|--to 2048tz 255" "--number|--from bytes --to 64 -" "--no-newline|--binary --from 16 dead" \
	"--by-index 3|255 16" "--lower|--show-symbols hex" "--escape-controls|--get-base-name keyboard" "--from 16|--get-index-count" "--get-base-name|--list"; do
	read -ra icFlag <<<"${ic%%|*}"; read -ra icArgs <<<"${ic#*|}"
	_run_in "${CBT_TMP}/idle_in" "${icArgs[@]}"; icWant="$_out"; icErr="$_err"
	_run_in "${CBT_TMP}/idle_in" "${icFlag[@]}" "${icArgs[@]}"
	{ ((_rc == 0)) && [[ -z "$icErr" ]] && [[ "$_out" == "$icWant" ]] && [[ "$_err" == "note: ${icFlag[0]%%=*} does nothing "* ]] && [[ "$_err" != *$'\n'* ]]; } \
		&& _pass ErswATd "unused flag gets one note: ${ic%%|*} with ${ic#*|}" \
		|| _fail ErswATd "unused flag gets one note: ${ic%%|*} with ${ic#*|}" "rc=$_rc out=[$_out] want=[$icWant] err=[$_err] err-without=[$icErr]"
done
## The notes print before the stream starts, once each, and leave it alone.
head -c 3000000 /dev/urandom >"${CBT_TMP}/idle_big"
"${TIMEOUT[@]}" "${EXE}" --from bytes --to 64 <"${CBT_TMP}/idle_big" >"${CBT_TMP}/idle_plain" 2>/dev/null || true
_rc=0; "${TIMEOUT[@]}" "${EXE}" --precision 3 --to-neg '~' --to-neg '~' --from bytes --to 64 <"${CBT_TMP}/idle_big" >"${CBT_TMP}/idle_noted" 2>"${CBT_ERR}" || _rc=$?
{ ((_rc == 0)) && cmp -s "${CBT_TMP}/idle_plain" "${CBT_TMP}/idle_noted" && [[ "$(<"${CBT_ERR}")" == $'note: --to-neg does nothing in byte mode\nnote: --precision does nothing in byte mode' ]]; } \
	&& _pass ErswAUX "unused flags vs stream output" \
	|| _fail ErswAUX "unused flags vs stream output" "rc=$_rc err=[$(<"${CBT_ERR}")]"
## Every stderr note starts with "note:", the number-or-bytes one included.
_run --from 16 --to 64 deadbeef
[[ "$_err" == "note: "* ]] && _pass ErswAVN "number-or-bytes note starts with note:" || _fail ErswAVN "number-or-bytes note starts with note:" "err=[$_err]"

## Conflicting base selectors: still convert, but emit a stderr note (BxZNl-17).
_run --to 16 255 8
{ ((_rc == 0)) && [[ "$_out" == FF ]] && [[ "$_err" == *"overrides positional output base"* ]]; } && _pass Eje8sS8 "conflict note: --to over positional" || _fail Eje8sS8 "conflict note: --to over positional" "rc=$_rc out=[$_out] err=[$_err]"
_run --from 16 --from-symbols 01 10 10
{ ((_rc == 0)) && [[ "$_out" == 2 ]] && [[ "$_err" == *"--from-symbols overrides --from"* ]]; } && _pass Eje8sS9 "conflict note: --from-symbols over --from" || _fail Eje8sS9 "conflict note: --from-symbols over --from" "rc=$_rc out=[$_out] err=[$_err]"
_run --to 16 255 hex
{ ((_rc == 0)) && [[ "$_out" == FF ]] && [[ -z "$_err" ]]; } && _pass Eje8sSA "no conflict note when --to and positional agree" || _fail Eje8sSA "no conflict note when --to and positional agree" "rc=$_rc out=[$_out] err=[$_err]"
## `echo 255 | prog 16` reads 16 as the NUMBER and leaves the pipe alone. With
## a base name as the only argument and a pipe on stdin, a note says to use -.
pnout="$(printf '255' | "${TIMEOUT[@]}" "${EXE}" 16 2>"${CBT_ERR}")" || true
{ [[ "$pnout" == 16 ]] && grep -qF 'stdin (piped) was ignored' "${CBT_ERR}"; } && _pass ErkSf4l "pipe + base-name NUMBER note" || _fail ErkSf4l "pipe + base-name NUMBER note" "out=[$pnout] err=[$(<"${CBT_ERR}")]"
pnout="$(printf '255' | "${TIMEOUT[@]}" "${EXE}" 255 16 2>"${CBT_ERR}")" || true
{ [[ "$pnout" == FF ]] && [[ ! -s "${CBT_ERR}" ]]; } && _pass ErkSf4t "no pipe note, NUMBER and base given" || _fail ErkSf4t "no pipe note, NUMBER and base given" "out=[$pnout] err=[$(<"${CBT_ERR}")]"

## Shell-metachar / injection strings are just invalid digits: must error, never execute.
sentinel="${CBT_TMP}/PWNED"
check EizUJE6 err "injection: command sub"  -   -- '$(touch '"${sentinel}"')' 16
check EizUJE7 err "injection: backticks"    -   -- '`touch '"${sentinel}"'`' 16
check EizUJE8 err "injection: semicolon"    -   -- 'touch '"${sentinel}"'; echo' 16
[[ ! -e "$sentinel" ]] && _pass EizUJE9 "injection created no file" || _fail EizUJE9 "injection created no file" "sentinel exists: $sentinel"

## Oversized input stays bounded and correct (round-trips, does not hang or crash).
biglen=2000; ((doLong)) && biglen=8000
big="$(_rand_int "$biglen")"
_run --from 10 --to 62 -- "$big"; enc="$_out"
if ((_rc == 0)); then
	_run --from 62 --to 10 -- "$enc"
	{ ((_rc == 0)) && [[ "$_out" == "$big" ]]; } && _pass EizUJEA "oversized input round-trips (${#big} digits)" || _fail EizUJEA "oversized input round-trips" "mismatch or rc=$_rc"
else
	_fail EizUJEA "oversized input round-trips" "encode rc=$_rc err=[$_err]"
fi

## Invalid UTF-8 on stdin must fail gracefully (no hang, no crash).
printf '\xff\xfe\x00\x9c' >"${CBT_TMP}/badutf8"
_run_in "${CBT_TMP}/badutf8" --from 2048qntm -
((_rc != 0 && _rc != 124)) && _pass EizUJEB "invalid UTF-8 stdin errors gracefully" || _fail EizUJEB "invalid UTF-8 stdin errors gracefully" "rc=$_rc"

## Every way of printing a result fails the run when stdout can't take it.
## Each case is INPUT:ARGS, where INPUT is null, a number, or raw bytes.
if [[ -w /dev/full ]]; then
	printf '255' >"${CBT_TMP}/full_num"; printf 'ab' >"${CBT_TMP}/full_raw"; : >"${CBT_TMP}/full_null"
	for fcase in "null:255 16" "null:-n 255 16" "null:--version" "null:--help" "null:--list" "null:--list --list-compat" \
		"null:--get-index-count" "null:--get-base-name hex" "null:--show-symbols hex" "null:--show-symbols-0 hex" \
		"num:- 16" "raw:--from bytes --to hex -" "raw:-n --from bytes --to hex -"; do
		read -ra fargs <<<"${fcase#*:}"; frc=0
		"${TIMEOUT[@]}" "${EXE}" "${fargs[@]}" <"${CBT_TMP}/full_${fcase%%:*}" >/dev/full 2>"${CBT_ERR}" || frc=$?
		{ ((frc != 0 && frc != 124)) && grep -qF 'no space left' "${CBT_ERR}"; } && _pass Erm02E7 "full stdout fails: ${fargs[*]}" || _fail Erm02E7 "full stdout fails: ${fargs[*]}" "rc=$frc err=[$(<"${CBT_ERR}")]"
	done
else
	_warn Erm02E7 "write-failure checks skipped: no /dev/full"
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Binary / streaming: bit-perfect round-trips + the byte-alignment guard
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Binary / streaming"
## Every raw-capable base comes from the RAW column of --list, so a base that is
## added or renamed is covered with no edit here. Both listings are scraped: the
## compatibility bases carry raw bytes like the rest, and the index filter drops
## the header rows. The power-of-2 bases are split out because they convert by
## bit-packing; what is left is the binary-to-text codecs.
## Columns: INDEX NAME SIZE NEG DEC RAW ALIASES
declare -a RAW_BASES=() POW2_BASES=()
while read -r idx bname bsize _ _ rawcol _; do
	[[ "$idx" =~ ^[0-9]+$ ]] || continue
	[[ "$rawcol" == "yes" && "$bname" != "bytes" ]] || continue
	RAW_BASES+=("$bname")
	(( (bsize & (bsize - 1)) == 0 )) && POW2_BASES+=("$bname")
done < <("${EXE}" --list --list-compat 2>/dev/null)
## Guard the scrapes themselves: if the --list format ever shifts and these parse
## nothing, every loop below passes vacuously. Assert a floor on each.
(( ${#RAW_BASES[@]} >= 8 ))   && _pass EjeFbjM "raw-base scrape found bases (${#RAW_BASES[@]})"          || _fail EjeFbjM "raw-base scrape found bases" "only ${#RAW_BASES[@]} scraped (--list format changed?)"
(( ${#POW2_BASES[@]} >= 20 )) && _pass ElWMN5V "power-of-2 scrape found bases (${#POW2_BASES[@]})" || _fail ElWMN5V "power-of-2 scrape found bases" "only ${#POW2_BASES[@]} scraped (--list format changed?)"

## Every power-of-2 base round-trips raw bytes at every input length: the small
## ones through the bit-packed path, the ones above 8 bits per digit through
## native chunking and a tail. Odd lengths are the ones a zero-padded tail used
## to corrupt, and the last blob is big enough to cross the streaming buffer.
for base in "${POW2_BASES[@]}"; do
	p2fail=0; p2detail=""
	for n in 0 1 2 3 4 5 7 8 15 16 17 31 32 33 64 333 777; do
		src="${CBT_TMP}/bp_src"; mid="${CBT_TMP}/bp_mid"; out="${CBT_TMP}/bp_out"
		head -c "$n" /dev/urandom >"$src"
		rc1=0; rc2=0
		"${TIMEOUT[@]}" "${EXE}" --from bytes --to "$base" <"$src" >"$mid" 2>"${CBT_ERR}" || rc1=$?
		"${TIMEOUT[@]}" "${EXE}" --from "$base" --to bytes <"$mid" >"$out" 2>"${CBT_ERR}" || rc2=$?
		{ ((rc1 == 0 && rc2 == 0)) && cmp -s "$src" "$out"; } || { p2fail=$((p2fail+1)); p2detail="n=${n} rc1=${rc1} rc2=${rc2} err=[$(<"${CBT_ERR}")]"; }
	done
	((p2fail == 0)) && _pass ElWMN5W "binary round-trip via ${base} (all lengths, bit-perfect)" || _fail ElWMN5W "binary round-trip via ${base}" "${p2fail} lengths mismatched, last: ${p2detail}"
done
## Raw binary round-trips through every base the tool advertises as a codec (the
## RAW column of --list): power-of-2 bases via bit-packing, plus base45, ascii85,
## z85, and base91 via their own schemes. Blob lengths force partial final chunks
## so padding/tail handling is exercised; Z85 requires 4-aligned input, so its
## lengths are rounded down. --no-newline both ways stays byte-exact for bases that carry
## newline as a digit.
raw_all_fail=0; raw_all_n=0
for base in "${RAW_BASES[@]}"; do
	for n in 1 2 3 4 5 7 8 11 13 16 17 31 63 100 255 257 $(( 1 + SRANDOM % 512 )); do
		len=$n
		[[ "$base" == "85z" ]] && len=$(( (n / 4) * 4 )) # Z85: multiple of 4 only
		src="${CBT_TMP}/ra_src"; mid="${CBT_TMP}/ra_mid"; out="${CBT_TMP}/ra_out"
		head -c "$len" /dev/urandom >"$src"
		rc1=0; rc2=0
		"${TIMEOUT[@]}" "${EXE}" --from bytes --to "$base" --no-newline <"$src" >"$mid" 2>"${CBT_ERR}" || rc1=$?
		"${TIMEOUT[@]}" "${EXE}" --from "$base" --to bytes --no-newline <"$mid" >"$out" 2>"${CBT_ERR}" || rc2=$?
		raw_all_n=$((raw_all_n + 1))
		{ ((rc1 == 0 && rc2 == 0)) && cmp -s "$src" "$out"; } || { raw_all_fail=$((raw_all_fail+1)); _fail EjK8KIi "raw round-trip ${base} n=${len}" "rc1=$rc1 rc2=$rc2 err=[$(<"${CBT_ERR}")]"; }
	done
done
((raw_all_fail == 0)) && _pass EjK8KIi "raw round-trip, all codec bases (${#RAW_BASES[@]} bases, ${raw_all_n} blobs)" || printf '  %s%d raw round-trip failures above%s\n' "${red}" "$raw_all_fail" "${rst}"

## Wrapped output must decode back, on both the piped and the argv path, at wrap
## widths that land inside a multi-byte digit. Line breaks have to be dropped
## before the bytes are read as characters, or a split digit looks like bad UTF-8.
## Every raw base is swept, so a codec that quietly stops tolerating wraps shows
## up here. 300 bytes keeps Z85 on its 4-byte boundary. The argv leg needs "--":
## several of these bases carry "-" as a digit, so an encoding can start with one
## and would otherwise be read as a flag.
for base in "${RAW_BASES[@]}"; do
	wrapfail=0
	src="${CBT_TMP}/wr_src"; enc="${CBT_TMP}/wr_enc"; out="${CBT_TMP}/wr_out"
	head -c 300 /dev/urandom >"$src"
	"${TIMEOUT[@]}" "${EXE}" --from bytes --to "$base" --no-newline <"$src" >"$enc" 2>"${CBT_ERR}" || wrapfail=$((wrapfail+1))
	for width in 7 13 40; do
		fold -w "$width" <"$enc" | "${TIMEOUT[@]}" "${EXE}" --from "$base" --to bytes >"$out" 2>"${CBT_ERR}" || wrapfail=$((wrapfail+1))
		cmp -s "$src" "$out" || wrapfail=$((wrapfail+1))
		"${TIMEOUT[@]}" "${EXE}" --from "$base" --to bytes -- "$(fold -w "$width" <"$enc")" >"$out" 2>"${CBT_ERR}" || wrapfail=$((wrapfail+1))
		cmp -s "$src" "$out" || wrapfail=$((wrapfail+1))
	done
	((wrapfail == 0)) && _pass El5P4dk "wrapped input decodes via ${base}" || _fail El5P4dk "wrapped input decodes via ${base}" "${wrapfail} failures"
done

## A base the tool does NOT advertise as a codec (RAW column "-") must refuse raw
## binary, not silently mis-handle it. Spot-check a spread, including the two
## whole-value base-N encoding (base85-RFC1924) that deliberately doesn't stream.
for base in 10 62 keyboard 60tc 85ipv6 26 36; do
	rc=0; printf 'hi' | "${TIMEOUT[@]}" "${EXE}" --from bytes --to "$base" >/dev/null 2>"${CBT_ERR}" || rc=$?
	((rc != 0)) && _pass EjK8KIj "non-codec base ${base} refuses raw binary" || _fail EjK8KIj "non-codec base ${base} refuses raw binary" "expected error, got rc=0"
done

## Fixed vectors for the binary-to-text codecs, straight from each official spec
## (RFC 9285, Adobe Ascii85, ZeroMQ RFC 32, basE91). Exact bytes -> exact text,
## so a codec regression is caught precisely, not just as a round-trip drift.
cvec(){ # ID LABEL BASE INPUT_HEX EXPECTED_TEXT
	local id="$1" label="$2" base="$3" hex="$4" want="$5" src got
	src="${CBT_TMP}/cv_src"
	printf '%b' "$(printf '%s' "$hex" | sed 's/../\\x&/g')" >"$src"
	_run_in "$src" --from bytes --to "$base" --no-newline; got="$_out"
	[[ "$got" == "$want" ]] && _pass "$id" "codec vector ${label}" || _fail "$id" "codec vector ${label}" "want=[$want] got=[$got]"
}
cvec EjK8KIk "base45 AB"       45   4142             "BB8"
cvec EjK8KIl "base45 ietf!"    45   6965746621       "QED8WEX0"
cvec EjK8KIm "ascii85 sure."   85ps 737572652e       "F*2M7/c"
cvec EjK8KIn "ascii85 zeros"   85ps 00000000         "z"
cvec EjK8KIo "z85 helloworld"  85z  864fd26fb559f75b "HelloWorld"
cvec EjK8KIp "base91 test"     91hk 74657374         "fPNKd"
## basE91's reference decoder skips junk. Here it is refused, the same way from
## a pipe as from an argument.
b91pipe="$(printf 'fPN-Kd' | "${TIMEOUT[@]}" "${EXE}" --from 91hk --to bytes 2>&1)" && b91pipe="rc=0 [$b91pipe]"
_run --from 91hk --to bytes -- 'fPN-Kd'
{ ((_rc != 0)) && [[ "$_err" == *"isn't a base-91 symbol"* ]] && [[ "$b91pipe" == *"isn't a base-91 symbol"* ]]; } && _pass ErkSf4e "base91 refuses junk, argv and pipe" || _fail ErkSf4e "base91 refuses junk, argv and pipe" "argv rc=$_rc err=[$_err] pipe=[$b91pipe]"
## The four big bases match the published third-party layouts byte-for-byte.
## These fixed vectors (input bytes -> exact output code points) guard that
## interop; they come straight from the reference implementations. Each pins the
## tail/secondary-block handling, and for 65536 the little-endian byte order.
nvec(){ # ID LABEL BASE INPUT_HEX EXPECTED_CODEPOINTS(space-separated hex)
	local id="$1" label="$2" base="$3" hex="$4" cps="$5" src exp="" got cp ch
	src="${CBT_TMP}/nv_src"
	printf '%b' "$(printf '%s' "$hex" | sed 's/../\\x&/g')" >"$src"
	for cp in $cps; do printf -v ch '\\U%08x' "0x${cp}"; printf -v ch "$ch"; exp+="$ch"; done
	_run_in "$src" --from bytes --to "$base"; got="$_out"
	[[ "$got" == "$exp" ]] && _pass "$id" "native vector ${label}" \
		|| _fail "$id" "native vector ${label}" "want=[$cps] got=[$(printf '%s' "$got" | od -An -tx1 | tr -d '\n')]"
}
nvec EjGTP6O "65536 lone byte"   65536qntm   00         1500
nvec EjGTP6P "65536 byte order"  65536qntm   0102       3601
nvec EjGTP6Q "65536 pair+tail"   65536qntm   010203     "3601 1503"
nvec EjGTP6R "65536 high block"  65536qntm   ffff       285FF
nvec EjGTP6S "65536 Hello"       65536qntm   48656c6c6f "9A48 A36C 156F"
nvec EjGTP6T "32768 one byte"    32768qntm   00         06BF
nvec EjGTP6U "32768 two bytes"   32768qntm   0000       "04A0 025F"
nvec EjGTP6V "32768 short tail"  32768qntm   000000000000 "04A0 04A0 04A0 018F"
nvec EjGTP6W "2048 one byte"     2048qntm 00         0046
nvec EjGTP6X "2048 two bytes"    2048qntm 0000       "0038 0110"
nvec EjGTP6Y "2048 three-bit tail" 2048qntm 010203   "0047 01B7 0037"
nvec EjGTP6Z "rust one byte"     2048llfourn    00         00D8
nvec EjGTP6a "rust tail zero"    2048llfourn    000000     "00D8 00D8 0F0D"
nvec EjGTP6b "rust tail three"   2048llfourn    010203     "00C5 0140 0F10"

## RFC 4648 padding: every RFC variant (base64 s4, base32 s6, and the URL/hex
## variants 64u/64h/32h) emits '=' padding to the group boundary in codec mode
## (vectors from RFC 4648 s10). Number-mode output is never padded. Decode is
## lenient: padded or unpadded input both accepted.
pipecheck(){ # ID LABEL FROM TO INPUT EXPECTED
	local id="$1" label="$2" f="$3" t="$4" in="$5" want="$6" got
	_run_in <(printf '%s' "$in") --from "$f" --to "$t"; got="$_out"
	[[ "$got" == "$want" ]] && _pass "$id" "$label" || _fail "$id" "$label" "in='$in' want='$want' got='$got'"
}
pipecheck EjGXlOS "rfc64 pad f"        bytes 64  "f"        "Zg=="
pipecheck EjGXlOT "rfc64 pad fo"       bytes 64  "fo"       "Zm8="
pipecheck EjGXlOU "rfc64 pad foobar"   bytes 64  "foobar"   "Zm9vYmFy"
pipecheck EjGXlOV "rfc32 pad f"        bytes 32  "f"        "MY======"
pipecheck EjGXlOW "rfc32 pad foob"     bytes 32  "foob"     "MZXW6YQ="
pipecheck EjGXlOX "rfc32 pad foobar"   bytes 32  "foobar"   "MZXW6YTBOI======"
pipecheck EjeCdXk "base64url pad foob" bytes 64u "foob"     "Zm9vYg=="
pipecheck EjeCdXl "base64hex pad foob" bytes 64h "foob"     "PczlOW=="
pipecheck EjeCdXm "base32hex pad f"    bytes 32h "f"        "CO======"
pipecheck EjGXlOY "base64 strips pad"  64  bytes "Zm9vYmFy" "foobar"
pipecheck EjGXlOZ "base64url takes pad" 64u bytes "Zm9vYg==" "foob"
## Decode still accepts UNPADDED input on the now-padded variants.
pipecheck EjeCdXn "base64url takes unpadded" 64u bytes "Zm9vYg" "foob"
## Number-mode output is never padded, even for the RFC variants.
pipecheck EjeCdXo "base64url number unpadded" 10 64u "255" "D_"

## Custom (user-defined) bases can opt into the same padding with --to-pad.
## This custom alphabet mirrors RFC 4648 base32, so its padded output must match.
B32C="ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
_run_in <(printf 'A') --from bytes --to-symbols "$B32C" --to-pad "="; padgot="$_out"
[[ "$padgot" == "IE======" ]] && _pass EjGkfrU "custom base32 emits pad" || _fail EjGkfrU "custom base32 emits pad" "got='$padgot'"
padrt=$(printf 'A' | "${TIMEOUT[@]}" "${EXE}" --from bytes --to-symbols "$B32C" --to-pad "=" 2>/dev/null | "${TIMEOUT[@]}" "${EXE}" --from-symbols "$B32C" --from-pad "=" --to bytes 2>"${CBT_ERR}" || true)
[[ "$padrt" == "A" ]] && _pass EjGkfrV "custom pad round-trips" || _fail EjGkfrV "custom pad round-trips" "got='$padrt'"
_run_in <(printf 'IE') --from-symbols "$B32C" --from-pad "=" --to bytes; padun="$_out"
[[ "$padun" == "A" ]] && _pass EjGkfrW "custom pad decode takes unpadded" || _fail EjGkfrW "custom pad decode takes unpadded" "got='$padun'"
check EjGkfrX errmsg "pad collides with digit" 'is also a digit' -- --from-symbols "0123456789ABCDEF" --from-pad "A" --to 10 5
## Padding is a trailing run and nothing else. Both routes must say so the same
## way: the argv one used to name the character instead of the mistake.
check Em1DQ5d errmsg "interior pad, argv" 'data after padding' -- --binary --from 64rfc --to bytes "A=BC"
printf 'A=BC' >"${CBT_TMP}/interior-pad"
_run_in "${CBT_TMP}/interior-pad" --binary --from 64rfc --to bytes
_assert Em1DQ5e errmsg "interior pad, pipe" 'data after padding'
## A pad is only ever applied on the bit-packed path, one character at a time.
## Definitions that could never take effect are rejected where they are written.
check El51s2C errmsg "multi-char pad rejected" 'must be a single character' -- --from bytes --to 64 --to-pad "==" 5
check El51s2D errmsg "pad above 8 bits rejected" 'at most 256 symbols' -- --from bytes --to 512tt --to-pad "=" 5
check El51s2E errmsg "pad on non-2^N rejected" 'at most 256 symbols' -- --from bytes --to 45 --to-pad "=" 5

## A user-defined base above 8 bits streams only once it declares a tail. Without
## one the packing writes a leading length, which can't be known while streaming.
SYM512=""; for ((cp=0x4E00; cp<0x5000; cp++)); do printf -v ch '\\U%08x' "$cp"; printf -v ch "$ch"; SYM512+="${ch} "; done
tailrt=$(head -c 37 /bin/cat | "${TIMEOUT[@]}" "${EXE}" --from bytes --to-symbols "$SYM512" --to-tail "⸐ ⸑" -n 2>/dev/null \
	| "${TIMEOUT[@]}" "${EXE}" --from-symbols "$SYM512" --from-tail "⸐ ⸑" --to bytes -n 2>"${CBT_ERR}" | md5sum | cut -d' ' -f1 || true)
tailwant=$(head -c 37 /bin/cat | md5sum | cut -d' ' -f1)
[[ "$tailrt" == "$tailwant" ]] && _pass El5mcJk "custom tail round-trips" || _fail El5mcJk "custom tail round-trips" "got='$tailrt'"
## The same base with no tail still round-trips, on the length-prefixed layout.
ntrt=$(head -c 37 /bin/cat | "${TIMEOUT[@]}" "${EXE}" --from bytes --to-symbols "$SYM512" -n 2>/dev/null \
	| "${TIMEOUT[@]}" "${EXE}" --from-symbols "$SYM512" --to bytes -n 2>"${CBT_ERR}" | md5sum | cut -d' ' -f1 || true)
[[ "$ntrt" == "$tailwant" ]] && _pass El5mcJl "custom no-tail round-trips" || _fail El5mcJl "custom no-tail round-trips" "got='$ntrt'"
## A tail that could never be used is rejected where it is declared.
check El5mcJm errmsg "tail below 8 bits rejected" 'above 256 symbols' -- --from bytes --to 64 --to-tail "⸐ ⸑" 5
check El5mcJn errmsg "tail not power of 2 rejected" 'power of 2' -- --from bytes --to-symbols "$SYM512" --to-tail "⸐ ⸑ ⸒" 5
check El5mcJo errmsg "tail too narrow rejected" 'must be between' -- --from bytes --to 1024tz --to-tail "⸐ ⸑" 5
check El5mcJp errmsg "tail on bytes rejected" "don't apply" -- --from bytes --to 16 --from-tail "⸐ ⸑" 5
## Binary decode of a tail base reads one character per digit, so a tail on a
## base of longer digits used to encode bytes it could not decode.
SYM2048W=""; for ((cp=0; cp<2048; cp++)); do printf -v ch '\\U%08x\\U%08x' $((0x4E00 + cp / 64)) $((0x5000 + cp % 64)); printf -v ch "$ch"; SYM2048W+="${ch} "; done
check Erm5wxB errmsg "tail on two-character digits rejected" 'single character' -- --from bytes --to-symbols "$SYM2048W" --to-tail "⸐ ⸑ ⸒ ⸓ ⸔ ⸕ ⸖ ⸗" 5
printf -- 'base: wide2048\n\tsymbols: "%s"\n\ttail: "⸐ ⸑ ⸒ ⸓ ⸔ ⸕ ⸖ ⸗"\n' "$SYM2048W" >"${CBT_TMP}/tail-wide.shcl"
check Erm5wxg errmsg "config tail on two-character digits rejected" '"wide2048": a tail needs every digit to be a single character' -- --config "${CBT_TMP}/tail-wide.shcl" --from bytes --to 16 5
## A tail of only commas parses to no symbols, and the tail layout without a
## tail decoded some lengths to the wrong bytes.
## Off since 2026100417280514: the spec parser now refuses a comma-only tail
## first, naming the flag rather than the base and layout. ErmufVw pins it.
## check ErmULmv errmsg "comma-only tail rejected" '"2048qntm": binary scheme "qntm" needs tail symbols' -- --from bytes --to 2048qntm --to-tail ',' 5
check ErmufVw errmsg "comma-only tail names the flag" '--to-tail: symbol spec has only commas' -- --from bytes --to 2048qntm --to-tail ',' 5
check ErmufXE errmsg "comma-only symbols names the flag" '--to-symbols: symbol spec has only commas' -- --to-symbols ',' 5
printf -- 'base: cfgcomma\n\tsymbols: 0123456789abcdef\n\ttail: ","\n##    Format   3\n' >"${CBT_TMP}/tail-comma.shcl"
check ErmufYc errmsg "config comma-only tail names the field" 'line 3: base "cfgcomma": tail: symbol spec has only commas' -- --config "${CBT_TMP}/tail-comma.shcl" 5 16
## A digit that isn't valid UTF-8 used to stream out text the same base's
## streaming decode refused.
printf 'hi' >"${CBT_TMP}/hi.bin"
_run_in "${CBT_TMP}/hi.bin" --from bytes --to-symbols $'\x80 \x81 \xc3\xa9 \xc3\xa8'
_assert Erq3i2u errmsg "invalid UTF-8 digit refused" 'base "custom(4)": digit "\x80" at index 0 '"isn't valid UTF-8"
printf -- 'base: cfgbadutf\n\tsymbols: "\xff a b c"\n##    Format   3\n' >"${CBT_TMP}/bad-utf8.shcl"
check Erq3i3e errmsg "config invalid UTF-8 digit refused" 'base "cfgbadutf": digit "\xff" at index 0 '"isn't valid UTF-8" -- --config "${CBT_TMP}/bad-utf8.shcl" 5 16
## A stray byte later in the quotes made shcl skip the closing quote (E017).
printf -- 'base: cfgbadutf\n\tsymbols: "a b \x80 c"\n##    Format   3\n' >"${CBT_TMP}/bad-utf8-mid.shcl"
check ErsoOAv errmsg "config invalid UTF-8 digit mid-quote refused" 'base "cfgbadutf": digit "\x80" at index 2 '"isn't valid UTF-8" -- --config "${CBT_TMP}/bad-utf8-mid.shcl" 5 16

## Same tail declared in a config file rather than on the command line.
tailcfg="${CBT_TMP}/tail.shcl"
printf -- 'base: cfgtail\n\tsymbols: "%s"\n\ttail: "⸐ ⸑"\n' "$SYM512" >"$tailcfg"
cfgrt=$(head -c 37 /bin/cat | "${TIMEOUT[@]}" "${EXE}" --config "$tailcfg" --from bytes --to cfgtail -n 2>/dev/null \
	| "${TIMEOUT[@]}" "${EXE}" --config "$tailcfg" --from cfgtail --to bytes -n 2>"${CBT_ERR}" | md5sum | cut -d' ' -f1 || true)
[[ "$cfgrt" == "$tailwant" ]] && _pass El5mcJq "config tail round-trips" || _fail El5mcJq "config tail round-trips" "got='$cfgrt'"

## Odd-length hex has no whole-byte representation: decoding to binary must error.
check EizUJEC errmsg "odd hex -> binary guarded" "can't decode to binary" -- --from 16 --to bytes ABC

## --lower/--upper on piped input give the same bytes as recasing the plain
## encode afterward, on the byte path, the --binary route and the wide path.
## The Greek base is one 2-byte rune per digit, so it would take the wide path,
## but it's refused before reading since 2026100519520001.
csrc="${CBT_TMP}/case_src"; c64="${CBT_TMP}/case_64"; cout="${CBT_TMP}/case_out"; cwant="${CBT_TMP}/case_want"
head -c 300001 /dev/urandom >"$csrc"
"${TIMEOUT[@]}" "${EXE}" --from bytes --to 64 -n <"$csrc" >"$c64" 2>/dev/null || true
GREEK_UP="Α Β Γ Δ Ε Ζ Η Θ Ι Κ Λ Μ Ν Ξ Ο Π"
for ccase in hex-lower 32c-upper binary-lower greek-lower; do
	rc1=0; crefuse=0
	case "$ccase" in
		hex-lower)
			"${EXE}" --from bytes --to hex -n <"$csrc" 2>/dev/null | tr 'A-F' 'a-f' >"$cwant" || true
			"${TIMEOUT[@]}" "${EXE}" --from bytes --to hex --lower -n <"$csrc" >"$cout" 2>"${CBT_ERR}" || rc1=$? ;;
		32c-upper)
			"${EXE}" --from bytes --to 32c -n <"$csrc" 2>/dev/null | tr '[:lower:]' '[:upper:]' >"$cwant" || true
			"${TIMEOUT[@]}" "${EXE}" --from bytes --to 32c --upper -n <"$csrc" >"$cout" 2>"${CBT_ERR}" || rc1=$? ;;
		binary-lower)
			"${EXE}" --from bytes --to hex -n <"$csrc" 2>/dev/null | tr 'A-F' 'a-f' >"$cwant" || true
			"${TIMEOUT[@]}" "${EXE}" --binary --from 64 --to hex --lower -n <"$c64" >"$cout" 2>"${CBT_ERR}" || rc1=$? ;;
		greek-lower)
			## Refused now: lower-case Greek doesn't read back as these digits (2026100519520001).
			crefuse=1
			"${TIMEOUT[@]}" "${EXE}" --from bytes --to-symbols "$GREEK_UP" --lower -n <"$csrc" >"$cout" 2>"${CBT_ERR}" || rc1=$? ;;
	esac
	if ((crefuse)); then
		cok=0; { ((rc1 == 1)) && [[ ! -s "$cout" ]] && grep -qF "can't read back" "${CBT_ERR}"; } && cok=1
	else
		cok=0; { ((rc1 == 0)) && [[ -s "$cwant" ]] && cmp -s "$cwant" "$cout"; } && cok=1
	fi
	clabel="case flag on a stream matches recased output (${ccase})"; ((crefuse)) && clabel="case flag on a stream refused (${ccase})"
	((cok)) && _pass Ersmg3G "$clabel" || _fail Ersmg3G "$clabel" "rc=${rc1} err=[$(<"${CBT_ERR}")]"
done

## The case flags used to drop to the buffered path, about 5 times the input in
## memory, with the right output, so only a memory ceiling sees it.
if [[ -x /usr/bin/time ]]; then
	cprof="${CBT_TMP}/case_prof"; case_mib=32; case_ceiling=65536 # KiB
	for cflags in "--from bytes --to hex --lower" "--from bytes --to 32c --upper" "--binary --from 64 --to hex --lower"; do
		cpeak=""
		if [[ "$cflags" == --binary* ]]; then
			head -c "$((case_mib * 1024 * 1024))" /dev/zero | "${EXE}" --from bytes --to 64 -n 2>/dev/null \
				| /usr/bin/time -o "$cprof" -f '%M' "${EXE}" $cflags >/dev/null 2>&1 || true
		else
			head -c "$((case_mib * 1024 * 1024))" /dev/zero | /usr/bin/time -o "$cprof" -f '%M' "${EXE}" $cflags >/dev/null 2>&1 || true
		fi
		[[ -s "$cprof" ]] && cpeak=$(tail -1 "$cprof")
		{ [[ "$cpeak" =~ ^[0-9]+$ ]] && ((cpeak < case_ceiling)); } && _pass Ersmg45 "case flag streams in constant memory (${cflags}, peak ${cpeak} KiB)" || _fail Ersmg45 "case flag streams in constant memory (${cflags})" "${case_mib} MiB in, peak ${cpeak:-?} KiB, ceiling ${case_ceiling}"
		: >"$cprof"
	done
else
	_warn "Ersmg45" "case flag memory ceiling: no /usr/bin/time"
fi

## --lower/--upper recase digits only. A pad or tail symbol stays as the base
## spells it, piped or on argv, or the same base can't read the output back.
## The answer is the plain encode through a base whose digits are already
## recased, with the same pad or tail. CJK has no case, so only the tail can
## change there. Greek is refused since 2026100519520001, since upper-case Greek
## doesn't read back as the lower-case digits.
LATIN32="0 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O Q R S T U V W"
GREEK8_LO="α β γ δ ε ζ η θ"; GREEK8_UP="Α Β Γ Δ Ε Ζ Η Θ"
for kcase in latin-pad latin-pad-dec greek-pad cjk-tail; do
	kin="a"; kread=(); krefuse=0; kback=""; kback2=""
	case "$kcase" in
		latin-pad)     kflags=(--to-symbols "$LATIN32" --to-pad P --lower); kref=(--to-symbols "${LATIN32,,}" --to-pad P)
		               kread=(--from-symbols "$LATIN32" --from-pad P) ;;
		latin-pad-dec) kflags=(--to-symbols "$LATIN32" --to-pad P --to-dec P --lower); kref=(--to-symbols "${LATIN32,,}" --to-pad P --to-dec P)
		               kread=(--from-symbols "$LATIN32" --from-pad P --from-dec P) ;;
		greek-pad)     krefuse=1; kflags=(--to-symbols "$GREEK8_LO" --to-pad ω --upper) ;;
		cjk-tail)      kin="abcdefgh"; kflags=(--to-symbols "$SYM512" --to-tail "x y" --upper); kref=(--to-symbols "$SYM512" --to-tail "x y")
		               kread=(--from-symbols "$SYM512" --from-tail "x y") ;;
	esac
	kpipe=$(printf '%s' "$kin" | "${TIMEOUT[@]}" "${EXE}" --from bytes "${kflags[@]}" 2>"${CBT_ERR}" || true)
	kargv=$("${TIMEOUT[@]}" "${EXE}" --from bytes "${kflags[@]}" "$kin" 2>>"${CBT_ERR}" || true)
	kok=0
	if ((krefuse)); then
		kwant="refused"
		[[ -z "$kpipe" && -z "$kargv" && "$(grep -cF "can't read back" "${CBT_ERR}" || true)" == 2 ]] && kok=1
	else
		kwant=$("${EXE}" --from bytes "${kref[@]}" "$kin" 2>/dev/null || true)
		## Read back through the base itself where its digits take either case, and
		## through the recased base everywhere.
		kback=$(printf '%s' "$kpipe" | "${TIMEOUT[@]}" "${EXE}" "${kref[@]/--to/--from}" --to bytes -n 2>>"${CBT_ERR}" || true)
		if ((${#kread[@]})); then
			kback2=$(printf '%s' "$kargv" | "${TIMEOUT[@]}" "${EXE}" "${kread[@]}" --to bytes -n 2>>"${CBT_ERR}" || true)
		else
			kback2="$kin"
		fi
		[[ -n "$kwant" && "$kpipe" == "$kwant" && "$kargv" == "$kwant" && "$kback" == "$kin" && "$kback2" == "$kin" ]] && kok=1
	fi
	klabel="case flag leaves pad and tail alone (${kcase})"; ((krefuse)) && klabel="case flag refused (${kcase})"
	((kok)) && _pass ErsqAZ3 "$klabel" || _fail ErsqAZ3 "$klabel" "want='${kwant}' pipe='${kpipe}' argv='${kargv}' back='${kback}' back2='${kback2}' err=[$(<"${CBT_ERR}")]"
done
## A digit that recases into the pad, a tail symbol or a marker would read back
## as that instead, so the flag is refused, the same as for mixed-case digits.
for kcase in pad tail marker; do
	case "$kcase" in
		pad)    kwant='padding symbol';  kflags=(--from bytes --to-symbols "$GREEK8_LO" --to-pad Α --upper a) ;;
		tail)   kwant='tail symbol';     kflags=(--from bytes --to-symbols "${SYM512/一 /ж }" --to-tail "Ж y" --upper abcdefgh) ;;
		marker) kwant='negative marker'; kflags=(--to-symbols "$GREEK8_UP" --to-neg β --lower -- -9) ;;
	esac
	check ErsqAZh errmsg "case flag refused when a digit recases into the ${kcase}" "$kwant" -- "${kflags[@]}"
done
## Input takes the other case only for one-letter ASCII digits, so recasing a
## longer digit or one from another script writes what the same base can't read
## back, or reads as some other digit (long s uppercases to S). Refused with
## exit 1 before any input is read (2026100519520001).
printf 'hi' >"${CBT_TMP}/rb_in"
for rcase in multi-letter greek greek-pipe long-s; do
	case "$rcase" in
		multi-letter) rwant='--lower is invalid for output base "custom(4)": lowercasing digit "Ab" gives "ab"'; rargs=(--to-symbols "Ab Cd Ef Gh" --lower 9) ;;
		greek)        rwant='--upper is invalid for output base "custom(4)": uppercasing digit "α" gives "Α"';  rargs=(--to-symbols "α β γ δ" --upper 9) ;;
		greek-pipe)   rwant='--lower is invalid for output base "custom(16)": lowercasing digit "Α" gives "α"'; rargs=(--from bytes --to-symbols "$GREEK_UP" --lower) ;;
		long-s)       rwant='--upper is invalid for output base "custom(2)": uppercasing digit "ſ" gives "S"';  rargs=(--to-symbols "s ſ" --upper 3) ;;
	esac
	_run_in "${CBT_TMP}/rb_in" "${rargs[@]}"
	{ ((_rc == 1)) && [[ -z "$_out" && "$_err" == *"$rwant"* ]]; } && _pass ErvpHV2 "case flag refused (${rcase})" \
		|| _fail ErvpHV2 "case flag refused (${rcase})" "rc=$_rc out=[$_out] err=[$_err] want-substr=[$rwant]"
done
## A digit the flag leaves as it is doesn't count: uncased multi-letter digits,
## CJK, and CJK beside one-letter ASCII digits all still recase and read back.
for rsyms in "0! 1! 2! 3!" "一 二 三 四" "a b 一 二"; do
	rout=$("${TIMEOUT[@]}" "${EXE}" --to-symbols "$rsyms" --upper 9 2>"${CBT_ERR}" || true)
	rback=$("${TIMEOUT[@]}" "${EXE}" --from-symbols "$rsyms" --to 10 "${rout:-x}" 2>>"${CBT_ERR}" || true)
	[[ -n "$rout" && "$rback" == 9 ]] && _pass ErvpHVf "case flag ok (${rsyms})" \
		|| _fail ErvpHVf "case flag ok (${rsyms})" "out='${rout}' back='${rback}' err=[$(<"${CBT_ERR}")]"
done


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## --binary: byte re-encoding between two text bases (like basenc)
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Without a mode flag, two power-of-2 text bases convert numerically (leading
## zeros dropped) and a note goes to stderr. --binary routes through the bytes
## base so the result matches the two-stage pipe and basenc byte-for-byte.
section "--binary byte mode"

## Known vector: the four bytes 0xDE 0xAD 0xBE 0xEF as base64.
_run --binary --from 16 --to 64 deadbeef; bm="$_out"
[[ "$bm" == "3q2+7w==" ]] && _pass EjU6h0i "--binary hex->64 (argv)" || _fail EjU6h0i "--binary hex->64 (argv)" "got='$bm'"

## Streaming (stdin) must match the argv result.
_run_in <(printf 'deadbeef') --binary --from 16 --to 64; bms="$_out"
[[ "$bms" == "3q2+7w==" ]] && _pass EjU6h0j "--binary hex->64 (stream)" || _fail EjU6h0j "--binary hex->64 (stream)" "got='$bms'"

## --binary must equal the explicit two-stage route through the bytes base.
bmp=$(printf 'deadbeef' | "${TIMEOUT[@]}" "${EXE}" --from 16 --to bytes 2>/dev/null | "${TIMEOUT[@]}" "${EXE}" --from bytes --to 32 2>/dev/null || true)
_run --binary --from 16 --to 32 deadbeef; bm32="$_out"
[[ "$bm32" == "$bmp" ]] && _pass EjU6h0k "--binary == pipe-through-bytes (hex->32)" || _fail EjU6h0k "--binary == pipe-through-bytes" "flag='$bm32' pipe='$bmp'"

## Aliases -b and --bin behave the same.
_run_in <(printf 'deadbeef') -b --from 16 --to 64; bmb="$_out"
_run_in <(printf 'deadbeef') --bin --from 16 --to 64; bmbin="$_out"
{ [[ "$bmb" == "3q2+7w==" ]] && [[ "$bmbin" == "3q2+7w==" ]]; } && _pass EjU6h0l "--binary aliases -b/--bin" || _fail EjU6h0l "--binary aliases -b/--bin" "b='$bmb' bin='$bmbin'"

## Round-trip through byte mode restores the bytes (case normalizes to base-16 canonical).
bmrt=$(printf 'deadbeef' | "${TIMEOUT[@]}" "${EXE}" -b --from 16 --to 64 2>/dev/null | "${TIMEOUT[@]}" "${EXE}" -b --from 64 --to 16 2>/dev/null || true)
[[ "$bmrt" == "DEADBEEF" ]] && _pass EjU6h0m "--binary round-trip 16<->64" || _fail EjU6h0m "--binary round-trip 16<->64" "got='$bmrt'"

## A non-power-of-2 base has no byte encoding: --binary must error.
check EjU6h0n errmsg "--binary rejects non-pow2" 'byte mode requires a power-of-2' -- --binary --from 10 --to 64 255

## --binary and --number are mutually exclusive.
check EjU6h0o errmsg "--binary + --number conflict" 'not both' -- --binary --number --from 16 --to 64 dead

## The ambiguity note: fires on pow2->pow2 with no mode flag, on stderr only, and
## stdout still carries the numeric result.
_run --from 16 --to 64 deadbeef
{ ((_rc == 0)) && [[ "$_out" == "Derb7v" ]] && [[ "$_err" == *"--binary"* ]]; } && _pass EjU6h0p "pow2->pow2 note on stderr" || _fail EjU6h0p "pow2->pow2 note on stderr" "out='$_out' err='$_err'"

## --number asserts numeric intent and silences the note.
_run --number --from 16 --to 64 deadbeef
{ ((_rc == 0)) && [[ "$_out" == "Derb7v" ]] && [[ -z "$_err" ]]; } && _pass EjU6h0q "--number silences note" || _fail EjU6h0q "--number silences note" "out='$_out' err='$_err'"

## -N alias silences too.
_run -N --from 16 --to 64 deadbeef
[[ -z "$_err" ]] && _pass EjU6h0r "-N alias silences note" || _fail EjU6h0r "-N alias silences note" "err='$_err'"

## No note when a non-power-of-2 base is involved (no byte ambiguity).
_run --from 10 --to 16 255
[[ -z "$_err" ]] && _pass EjU6h0s "no note for non-pow2 conversion" || _fail EjU6h0s "no note for non-pow2 conversion" "err='$_err'"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Keyboard (text) base: a plain-text document is valid input as-is
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Every printable keyboard character plus tab/newline/return is a digit, so
## source code, prose, JSON, and the like convert with no escaping. Like binary
## it holds newline as a digit, so it needs --no-newline output and file-based checks.
## Round-trips are exact except a leading zero-digit (tab), which vanishes like
## any leading zero, so the samples start on a non-tab byte.
section "Keyboard (text) base"
ksrc="${CBT_TMP}/kb_src"; kmid="${CBT_TMP}/kb_mid"; kout="${CBT_TMP}/kb_out"
printf 'def f(x):\n\treturn {"k": [1, 2], "s": "a+b/c=d"}  # note\n' >"$ksrc"
kfail=0
for tb in 16 10; do
	if "${TIMEOUT[@]}" "${EXE}" --from keyboard --to "$tb" <"$ksrc" >"$kmid" 2>"${CBT_ERR}" \
		&& "${TIMEOUT[@]}" "${EXE}" --from "$tb" --to keyboard --no-newline <"$kmid" >"$kout" 2>"${CBT_ERR}" \
		&& cmp -s "$ksrc" "$kout"; then :; else kfail=$((kfail+1)); fi
done
((kfail == 0)) && _pass EjGqhx2 "keyboard sample round-trips (base 16 and 10)" || _fail EjGqhx2 "keyboard sample round-trips" "${kfail} of 2 failed"
## Random text blobs of only valid keyboard bytes, forced to start on a non-tab
## byte so no leading digit is lost.
krand_fail=0
for len in 1 2 5 33 200 1500; do
	{ printf '#'; head -c "$((len * 8 + 64))" /dev/urandom | LC_ALL=C tr -cd '\11\12\15\40-\176' | head -c "$len"; } >"$ksrc" || true
	if "${TIMEOUT[@]}" "${EXE}" --from keyboard --to 16 <"$ksrc" >"$kmid" 2>"${CBT_ERR}" \
		&& "${TIMEOUT[@]}" "${EXE}" --from 16 --to keyboard --no-newline <"$kmid" >"$kout" 2>"${CBT_ERR}" \
		&& cmp -s "$ksrc" "$kout"; then :; else krand_fail=$((krand_fail+1)); fi
done
((krand_fail == 0)) && _pass EjGqhx3 "keyboard random text round-trips (6 blobs)" || _fail EjGqhx3 "keyboard random text round-trips" "${krand_fail} lengths mismatched"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Control-character escapes
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Tab, newline and return are digits of the keyboard base, so they can also be
## written as a name. Input takes raw and escaped forms mixed, always; output
## writes them only when asked. The pins are literal on both sides, so a change
## to either direction shows up here rather than cancelling itself out.
section "Control-character escapes"
kesc_lf=$'A\nB'
check Elotfai eq "escape LF reads as the raw character"   "102225" -- --from keyboard --to 10 -n 'A⊳LFB'
check Elotfaj eq "raw LF reads the same"                  "102225" -- --from keyboard --to 10 -n "$kesc_lf"
check Elotfak eq "lowercase name"                         "102225" -- --from keyboard --to 10 -n 'A⊳lfB'
check Elotfal eq "NEWLINE alias"                          "102225" -- --from keyboard --to 10 -n 'A⊳NEWLINEB'
check Elotfam eq "hex form"                               "102225" -- --from keyboard --to 10 -n 'A⊳x0AB'
check Elotfan eq "escaped output"                         'A⊳LFB'  -- --from 10 --to keyboard --escape-controls -n 102225
check Elotfao eq "output stays raw without the flag"      "$kesc_lf" -- --from 10 --to keyboard -n 102225
## Raw and escaped in one value, and the same value written the other way.
check Elotfap eq "raw and escaped mixed"      "52830726402316" -- --from keyboard --to 10 -n 'x⊳HTy⊳CRz⊳LFw'
check Elotfaq eq "all three escaped on output" 'x⊳HTy⊳CRz⊳LFw' -- --from 10 --to keyboard --escape-controls -n 52830726402316
## A base with no control digits never grows an escape.
check Elotfar eq "no escapes where there are no controls" '!4' -- --from 10 --to keyboard --escape-controls -n 6472
## --show-symbols is where the alphabet is actually legible.
_run --show-symbols --escape-controls keyboard
{ ((_rc == 0)) && [[ "$_out" == *'⊳HT⊳LF⊳CR'* ]]; } \
	&& _pass Elotfas "--show-symbols escapes the control digits" \
	|| _fail Elotfas "--show-symbols escapes the control digits" "rc=$_rc out=[$_out]"
## Guards.
check Elotfat errmsg "unrecognized escape is an error"    "unrecognized escape" -- --from keyboard --to 10 -n 'A⊳ZZZB'
check Elotfau errmsg "escape the base cannot carry"       "not in base"         -- --from 16 --to 10 -n '⊳LF'
check Elotfav errmsg "escaping is refused in byte mode"   "number conversions only" -- --from 10 --to 16 --binary --escape-controls -n 65
## The marker is not a digit of any built-in base, so it is never mistaken for one.
check Elotfaw err "a bare marker is not a digit"          "" -- --from keyboard --to 10 -n 'A⊳'


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Fuzz: random values round-tripped through every defined base
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Fuzz round-trips (all bases)"
## Column 2 is NAME (column 1 is the INDEX). Both listings, so the compatibility
## bases get fuzzed too; the index filter drops the header rows.
mapfile -t BASE_NAMES < <("${EXE}" --list --list-compat 2>/dev/null | awk '$1 ~ /^[0-9]+$/ {print $2}')
## Floor check so a --list format change can't silently empty the fuzz set.
(( ${#BASE_NAMES[@]} >= 50 )) && _pass EjeFbjN "base-name scrape found bases (${#BASE_NAMES[@]})" || _fail EjeFbjN "base-name scrape found bases" "only ${#BASE_NAMES[@]} scraped (--list format changed?)"
declare -a FUZZ_BASES=()
## bytes and keyboard both carry newline as a digit, so their output can't
## survive $(...) capture (it strips trailing newlines). Both get their own
## file-based, --no-newline round-trip sections instead.
for n in "${BASE_NAMES[@]}"; do
	case "$n" in bytes|98keyboard) continue ;; esac
	FUZZ_BASES+=("$n")
done
printf '  %s%d bases under fuzz%s\n' "${dim}" "${#FUZZ_BASES[@]}" "${rst}"

## Deterministic matrix: a few fixed values through every base (fast, always on).
matrix_fail=0; matrix_n=0
for base in "${FUZZ_BASES[@]}"; do
	for val in 0 1 255 1000000 987654321000055555555550000123456789; do
		_run --from 10 --to "$base" -- "$val"; enc="$_out"; ((_rc == 0)) || { matrix_fail=$((matrix_fail+1)); continue; }
		_run --from "$base" --to 10 -- "$enc"; matrix_n=$((matrix_n + 1))
		{ ((_rc == 0)) && [[ "$_out" == "$val" ]]; } || matrix_fail=$((matrix_fail+1))
	done
done
((matrix_fail == 0)) && _pass EizUJED "all-base matrix round-trip (${matrix_n} conversions)" || _fail EizUJED "all-base matrix round-trip" "${matrix_fail} of ${matrix_n} failed"

## Randomized fuzz: random base, random large value.
iters="${CICDTEST_FUZZ_ITERS:-60}"; ((doLong)) && iters="${CICDTEST_FUZZ_ITERS:-800}"
maxlen=48; ((doLong)) && maxlen=160
fuzz_fail=0
## An empty scrape has already failed above, and a modulo by its size would end the run.
for ((i=0; i<iters && ${#FUZZ_BASES[@]} > 0; i++)); do
	idx=$(( SRANDOM % ${#FUZZ_BASES[@]} ))
	base="${FUZZ_BASES[idx]}"
	val="$(_rand_int "$maxlen")"
	_run --from 10 --to "$base" -- "$val"; enc="$_out"; ((_rc == 0)) || { fuzz_fail=$((fuzz_fail+1)); _fail EizUJEE "fuzz enc base=$base val-len=${#val}" "rc=$_rc err=[$_err]"; continue; }
	## A lone "-" output (a base whose single digit is "-", e.g. hostname value 36)
	## is the read-stdin sentinel as a positional, so it can't round-trip via argv.
	[[ "$enc" == "-" ]] && continue
	_run --from "$base" --to 10 -- "$enc"
	{ ((_rc == 0)) && [[ "$_out" == "$val" ]]; } || { fuzz_fail=$((fuzz_fail+1)); _fail EizUJEE "fuzz round-trip base=$base" "val=[$val] enc=[$enc] got=[$_out] rc=$_rc"; }
done
((fuzz_fail == 0)) && _pass EizUJEE "randomized fuzz round-trip (${iters} iterations, maxlen ${maxlen})" || printf '  %s%d fuzz failures above%s\n' "${red}" "$fuzz_fail" "${rst}"

## Full-coverage symbol round-trip: for every base (not just a handful), build a
## random-length string from its own randomly chosen symbols, carry it through a
## random target base, and bring it back. Bases, names, and symbol alphabets all
## come from the binary itself (--get-index-count, --get-base-name, --show-symbols-0),
## so every defined base is exercised with no hand-maintained tables. The first
## symbol is kept off the zero digit so the source string is already canonical and
## a clean string compare is a valid round-trip check. The bytes base (raw bytes)
## is the one left out; it is covered bit-perfectly in its own section above.
_run --get-index-count; n_bases="$_out"
## Names by index from one listing. An index it leaves out gets a name no base
## has, so its round trips fail. An empty one would read as base 10 and pass.
declare -a IDX_NAME=()
while read -r lidx lname _; do
	[[ "$lidx" =~ ^[0-9]+$ ]] || continue
	IDX_NAME[lidx]="$lname"
done < <("${EXE}" --list --list-compat 2>/dev/null)
declare -a ELIGIBLE=()
for ((i=0; i<n_bases; i++)); do
	IDX_NAME[i]="${IDX_NAME[i]:-unlisted-index-${i}}"
	case "${IDX_NAME[i]}" in bytes|98keyboard) continue ;; esac
	ELIGIBLE+=("$i")
done

## Symbols are loaded once per base, on first use, into a per-index array.
declare -A SYM_LOADED=()
_load_syms(){
	local idx="$1"
	[[ -n "${SYM_LOADED[$idx]:-}" ]] && return
	mapfile -d '' -t "SYMS_${idx}" < <("${EXE}" --show-symbols-0 --by-index="$idx")
	SYM_LOADED[$idx]=1
}

## Random string of `1..maxlen` symbols from base at index $1. First symbol is a
## non-zero digit (index 1..size-1) so there is no leading-zero ambiguity.
_rand_symbols(){
	local -n syms="SYMS_$1"
	local -i size=${#syms[@]}
	local -i len=$(( 1 + SRANDOM % maxlen ))
	local out=""; local -i j rand_val idx
	for ((j = 0; j < len; j++)); do
		rand_val=SRANDOM
		if ((j == 0)); then idx=$(( 1 + rand_val % (size - 1) )); else idx=$(( rand_val % size )); fi
		out+="${syms[idx]}"
	done
	printf '%s' "$out"
}

symfuzz_fail=0; symfuzz_n=0
for ((i = 0; i < iters && ${#ELIGIBLE[@]} > 0; i++)); do
	src_idx="${ELIGIBLE[$(( SRANDOM % ${#ELIGIBLE[@]} ))]}"
	tgt_idx="${ELIGIBLE[$(( SRANDOM % ${#ELIGIBLE[@]} ))]}"
	_load_syms "$src_idx"
	src_name="${IDX_NAME[src_idx]}"; tgt_name="${IDX_NAME[tgt_idx]}"
	src_str="$(_rand_symbols "$src_idx")"
	## A lone "-" as a positional value is the read-stdin sentinel, not a digit,
	## so a base that carries "-" in its alphabet (hostname, username, ...) can't
	## pass the single-digit "-" through argv. Skip just that one string on either
	## side; any longer value that merely contains "-" is unambiguous and fine.
	[[ "$src_str" == "-" ]] && continue
	_run --from "$src_name" --to "$tgt_name" -- "$src_str"; encoded="$_out"; ((_rc == 0)) || { symfuzz_fail=$((symfuzz_fail+1)); _fail Ej1HnoL "symbol fuzz enc $src_name->$tgt_name" "src=[$src_str] rc=$_rc err=[$_err]"; continue; }
	[[ "$encoded" == "-" ]] && continue
	_run --from "$tgt_name" --to "$src_name" -- "$encoded"; symfuzz_n=$((symfuzz_n + 1))
	{ ((_rc == 0)) && [[ "$_out" == "$src_str" ]]; } || { symfuzz_fail=$((symfuzz_fail+1)); _fail Ej1HnoL "symbol fuzz round-trip $src_name<->$tgt_name" "src=[$src_str] enc=[$encoded] got=[$_out] rc=$_rc"; }
done
((symfuzz_fail == 0)) && _pass Ej1HnoL "full-coverage symbol round-trip (${symfuzz_n} iterations, ${#ELIGIBLE[@]} bases, maxlen ${maxlen})" || printf '  %s%d symbol-fuzz failures above%s\n' "${red}" "$symfuzz_fail" "${rst}"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Back-compat against the bundled v1 and v1b binaries (gating, byte-for-byte)
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Each entry is "v2-base:legacy-base[:extra-v2-flag]". For a shared base, v2 must
## reproduce the legacy output byte-for-byte (encode side), and must read that
## output back to the original (decode side). The legacy tools only accept base 10
## (among a few) as input, so the tests feed base-10 values.
##
## v1 and v1b disagree on several alphabets, which is what the compatibility bases
## exist for, so each legacy binary gets its own map.
## A base both tools share is listed in both maps, so it is checked against both.
## A base only one tool has is listed only there.
V1_MAP=(
	2:2  8:8  10:10  16:16  26:26  36:36  52:52  62:62
	32rfc:32  32hex:32h  32crock:32c:--upper  32ws:32w
	64hex:64u  64code:64j1u
	38hostname:38ho
	48ws_compat_v1:48j1  64ws_compat_v1:64j1uw  128_compat_v1:128j1
	256_compat_v1:256j1  288_compat_v1:288j1
)
V1B_MAP=(
	2:2  8:8  10:10  16:16  26:26  36:36  52:52  62:62
	32rfc:32  32hex:32h  32crock:32c:--upper  32ws:32w
	64rfc:64  64url:64u  64hex:64h  64code:64jc1
	38hostname:38ho  39username:39us  45email:45em
	48ws_compat_v1:48v1compat  64ws_compat_v1:64v1compat  128_compat_v1:128v1compat
	48ws_compat_v1b:48jc1ws  64ws_compat_v1b:64jc1ws  128ws_compat_v1b:128jc1ws
	128_compat_v1b:128jc1  256_compat_v1:256jc1  288_compat_v1:288jc1
)
## Every output base each tool offers, one entry per distinct alphabet (the tools
## take several spellings of each; these are the canonical ones). The coverage
## check below fails on anything here that neither the map nor the excused list
## accounts for, so a v2 base that could close a gap gets noticed.
V1_BASES=(2 8 10 16 26 32 32h 32c 32w 36 38us 38ho 48j1 52 62 64 64u 64j1u 64j1uw 128j1 256j1 288j1)
V1B_BASES=(2 8 10 16 26 32 32h 32c 32w 36 38ho 39us 45em 48jc1ws 48v1compat 52 62 64 64u 64h
           64jc1 64jc1ws 64v1compat 128jc1 128jc1ws 128v1compat 256jc1 288jc1)
## Excused: a legacy base with no v2 counterpart to compare against. Both were
## confirmed by walking each alphabet symbol by symbol against every v2 base, not
## assumed, and both are permanent - neither is a gap waiting to be closed. So
## they are simply excused, with no warning to sit in the output forever.
##   - v1 "38us" is 38 symbols (0-9 a-z - _). v2's username is 39, adding ".",
##     which v1b's "39us" already did. v2 carries the v1b alphabet, not v1's.
##   - v1 "64" is hex-ordered (0-9 A-Z a-z + /), which is neither RFC 4648 §4 nor
##     any v2 base. v1b fixed it to the RFC order. v1's "64u" is the one that does
##     match a v2 base, and it is v2's 64h.
## Everything else either tool offers has a v2 counterpart and is mapped above, so
## the v1b side excuses nothing.
V1_EXCUSED=(38us 64)
V1B_EXCUSED=()
## v2 base-45 is RFC 9285, a different alphabet than the legacy "45em"; neither
## legacy tool has a plain base-45.
##
## 32c encodes with --upper: v2 emits Crockford's alphabet in lower case for
## legibility, and both legacy tools emit upper case. Same digits, same order.

## fCheckCoverage ID LABEL MAPVAR ALLVAR EXCUSEDVAR
## A legacy base that no map reaches is a silent hole, and a map entry naming a
## base the tool doesn't have is a stale entry, so both directions are checked.
fCheckCoverage(){
	local id="$1" label="$2"; local -n _map="$3" _all="$4" _excused="$5"
	local pair tok missing="" stale=""
	local -A covered=()
	for pair in "${_map[@]}"; do tok="${pair#*:}"; covered["${tok%%:*}"]=1; done
	for tok in "${_all[@]}"; do
		[[ -n "${covered[$tok]:-}" ]] && continue
		[[ " ${_excused[*]} " == *" ${tok} "* ]] || missing+=" ${tok}"
	done
	for tok in "${!covered[@]}"; do
		[[ " ${_all[*]} " == *" ${tok} "* ]] || stale+=" ${tok}"
	done
	## Name the excused ones in the pass line: they are a deliberate, permanent
	## part of the coverage, not something to go hunting through comments for.
	local note="none"; ((${#_excused[@]})) && note="${_excused[*]}"
	{ [[ -z "$missing" ]] && [[ -z "$stale" ]]; } \
		&& _pass "$id" "${label} base coverage (${#_all[@]} bases, excused: ${note})" \
		|| _fail "$id" "${label} base coverage" "unmapped:${missing:- none} stale:${stale:- none}"
}

## fCheckLegacy ENCODE_ID ROUNDTRIP_ID BINARY LABEL MAP...
fCheckLegacy(){
	local encid="$1" rtid="$2" exe="$3" label="$4"; shift 4
	local pair v2n lgn extra enc_fail rt_fail detail val o2 o1 back r
	local reps=3; ((doLong)) && reps=20
	for pair in "$@"; do
		v2n="${pair%%:*}"; lgn="${pair#*:}"; extra="${lgn#*:}"; lgn="${lgn%%:*}"
		[[ "$extra" == "$lgn" ]] && extra=""
		## A renamed v2 base would otherwise read as a byte mismatch on every
		## single value, which says nothing about what actually went wrong.
		if ! "${TIMEOUT[@]}" "${EXE}" --get-base-name "$v2n" >/dev/null 2>&1; then
			_fail "$encid" "v2 base ${v2n} exists (mapped to ${label} ${lgn})" "unknown base - renamed or removed?"
			continue
		fi
		enc_fail=0; rt_fail=0; detail=""
		for ((r=0; r<reps; r++)); do
			val="$(_rand_int 30)"
			o2="$("${EXE}" ${extra} --from 10 --to "$v2n" -- "$val" 2>/dev/null || true)"
			o1="$("${exe}" --ibase 10 "$val" "$lgn"                 2>/dev/null || true)"
			if [[ -z "$o1" || "$o2" != "$o1" ]]; then enc_fail=1; detail="val=[$val] v2=[$o2] ${label}=[$o1]"; fi
			## A lone "-" encoding (hostname value 36, and others carrying "-" as
			## a digit) is the read-stdin sentinel as a positional, so it can't be
			## fed back through argv. Skip just that one value; anything longer is
			## unambiguous. Same guard the fuzz loops use.
			[[ "$o1" == "-" ]] && continue
			back="$("${EXE}" --from "$v2n" --to 10 -- "$o1" 2>/dev/null || true)"
			[[ -n "$o1" && "$back" == "$val" ]] || { rt_fail=1; detail="val=[$val] ${label}enc=[$o1] v2dec=[$back]"; }
		done
		((enc_fail == 0)) && _pass "$encid" "v2==${label} encode: ${v2n} (== ${label} ${lgn})" || _fail "$encid" "v2==${label} encode: ${v2n} (== ${label} ${lgn})" "$detail"
		((rt_fail == 0))  && _pass "$rtid" "${label}->v2 round-trip: ${v2n} (from ${label} ${lgn})" || _fail "$rtid" "${label}->v2 round-trip: ${v2n} (from ${label} ${lgn})" "$detail"
	done
}

## Don't skip silently: a missing legacy script means that back-compat suite did
## not run, which is easy to mistake for "passed". The summary repeats it.
section "Back-compat vs v1 (byte-for-byte + round-trip)"
if [[ -x "${EXE_V1}" ]]; then
	fCheckCoverage ElWMN5X v1 V1_MAP V1_BASES V1_EXCUSED
	fCheckLegacy ElG9gVS ElG9gVT "${EXE_V1}" v1 "${V1_MAP[@]}"
else
	_warn "ElWMN5X ElG9gVS ElG9gVT" "v1 back-compat skipped: script not found at ${EXE_V1}"
fi

section "Back-compat vs v1b (byte-for-byte + round-trip)"
if [[ -x "${EXE_V1B}" ]]; then
	fCheckCoverage ElWMN5Y v1b V1B_MAP V1B_BASES V1B_EXCUSED
	fCheckLegacy Ej0q2ga Ej0q2gb "${EXE_V1B}" v1b "${V1B_MAP[@]}"
else
	_warn "ElWMN5Y Ej0q2ga Ej0q2gb" "v1b back-compat skipped: script not found at ${EXE_V1B}"
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Interop: the four big bases against the implementations that defined them
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The fixed vectors earlier pin a handful of known inputs, copied down by hand.
## These run randomized bytes through the published implementations themselves -
## qntm's three npm packages and LLFourn's Rust crate, unpacked verbatim under
## utility/interop/thirdparty - and check all three directions:
##   encode  : our output equals theirs, byte for byte
##   decode  : we read back what they wrote
##   xdecode : they read back what we wrote
## Encode alone would not be enough. A shared misreading of the tail rules can
## survive it, and only feeding each side the other's output catches that.
##
## Lengths start at zero and run up consecutively before going random, because
## every disagreement these bases have ever had was about the final partial
## chunk. The widths are 11, 15 and 16 bits, so the byte-boundary cycle closes
## at 11, 15 and 2 bytes respectively - well inside the consecutive run.
INTEROP_DIR="${meDir}/utility/interop"
INTEROP_QNTM="${INTEROP_DIR}/drivers/qntm.mjs"
INTEROP_RSBIN="${INTEROP_DIR}/build/release/llfourn2048"
nSamples=40; ((doLong)) && nSamples=200

## fInteropSamples FILE COUNT -> one lowercase hex string per line, no separators.
fInteropSamples(){
	local file="$1"; local -i count="$2" i len
	: >"$file"
	for ((i = 0; i < count; i++)); do
		if ((i <= 24)); then len=$i; else len=$(( 1 + SRANDOM % 4096 )); fi
		((len)) && head -c "$len" /dev/urandom | od -An -tx1 -v | tr -d ' \n' >>"$file"
		echo >>"$file"
	done
}

## Name the sample that broke, not just the fact that something did. A tail bug
## shows up at one specific length and that length is the whole diagnosis.
fFirstDiff(){ # OURS THEIRS
	local a="$1" b="$2" n
	n="$(cmp "$a" "$b" 2>&1 | sed -n 's/.*line \([0-9][0-9]*\).*/\1/p' | head -1)"
	[[ -n "$n" ]] || n=1
	## The two line counts are part of the diagnosis: unequal means one side gave
	## up early, and then the named sample is the last one they agreed on.
	printf 'sample %s of %s/%s: ours=[%.60s] ref=[%.60s]' \
		"$n" "$(wc -l <"$a")" "$(wc -l <"$b")" "$(sed -n "${n}p" "$a")" "$(sed -n "${n}p" "$b")"
}

## fCheckInterop V2BASE LABEL REF...   (REF is an adapter taking encode|decode)
fCheckInterop(){
	local v2base="$1" label="$2"; shift 2
	local samples="${CBT_TMP}/io_samples" theirs="${CBT_TMP}/io_theirs" ours="${CBT_TMP}/io_ours"
	local ourdec="${CBT_TMP}/io_ourdec" theirdec="${CBT_TMP}/io_theirdec" bin="${CBT_TMP}/io_bin"
	local hex enc

	fInteropSamples "$samples" "$nSamples"
	if ! "$@" encode <"$samples" >"$theirs" 2>"${CBT_ERR}"; then
		_fail EleGcFU "interop ${label}" "reference adapter would not run: $(head -2 "${CBT_ERR}")"
		return
	fi

	while IFS= read -r hex; do
		printf '%b' "$(printf '%s' "$hex" | sed 's/../\\x&/g')" >"$bin"
		"${TIMEOUT[@]}" "${EXE}" --from bytes --to "$v2base" --no-newline <"$bin" 2>/dev/null || true
		echo
	done <"$samples" >"$ours"
	cmp -s "$ours" "$theirs" \
		&& _pass EleGcFU "interop encode == ${label} (${nSamples} samples)" \
		|| _fail EleGcFU "interop encode == ${label}" "$(fFirstDiff "$ours" "$theirs")"

	while IFS= read -r enc; do
		printf '%s' "$enc" >"$bin"
		"${TIMEOUT[@]}" "${EXE}" --from "$v2base" --to bytes <"$bin" 2>/dev/null | od -An -tx1 -v | tr -d ' \n' || true
		echo
	done <"$theirs" >"$ourdec"
	cmp -s "$ourdec" "$samples" \
		&& _pass EleGcFV "interop decode of ${label} output (${nSamples} samples)" \
		|| _fail EleGcFV "interop decode of ${label} output" "$(fFirstDiff "$ourdec" "$samples")"

	if ! "$@" decode <"$ours" >"$theirdec" 2>"${CBT_ERR}"; then
		_fail EleGcFW "interop ${label} reads our output" "reference adapter would not run: $(head -2 "${CBT_ERR}")"
		return
	fi
	cmp -s "$theirdec" "$samples" \
		&& _pass EleGcFW "interop ${label} reads our output (${nSamples} samples)" \
		|| _fail EleGcFW "interop ${label} reads our output" "$(fFirstDiff "$theirdec" "$samples")"
}

section "Interop vs the published reference implementations"
if [[ ! -d "${INTEROP_DIR}/thirdparty" ]]; then
	_warn "EleGcFX EleGcFU EleGcFV EleGcFW" "interop skipped: no vendored references at ${INTEROP_DIR}/thirdparty (utility/interop/fetch.bash --refresh)"
else
	## Pinned versions, so a pass line says which release we agree with.
	declare -A INTEROP_VER=()
	# shellcheck disable=1091  ## 'Not following.' The pin file is data, next to the suite it describes.
	source "${INTEROP_DIR}/pins.env"
	for pin in "${INTEROP_PINS[@]}"; do
		IFS='|' read -r ipName ipVer _rest <<< "${pin}"
		INTEROP_VER["${ipName}"]="${ipVer}"
	done

	## An edited reference is worse than no reference: every check would still
	## pass, against something nobody published. So this one fails, never skips.
	if "${INTEROP_DIR}/fetch.bash" --verify >/dev/null 2>&1; then
		_pass EleGcFX "interop references verbatim (${#INTEROP_PINS[@]} pinned packages)"
	else
		_fail EleGcFX "interop references verbatim" "$("${INTEROP_DIR}/fetch.bash" --verify 2>&1 | tail -2)"
	fi

	if command -v node >/dev/null 2>&1; then
		fCheckInterop 2048qntm  "qntm base2048 ${INTEROP_VER[base2048-qntm]}"   node "${INTEROP_QNTM}" 2048
		fCheckInterop 32768qntm "qntm base32768 ${INTEROP_VER[base32768-qntm]}" node "${INTEROP_QNTM}" 32768
		fCheckInterop 65536qntm "qntm base65536 ${INTEROP_VER[base65536-qntm]}" node "${INTEROP_QNTM}" 65536
	else
		_warn "EleGcFU EleGcFV EleGcFW" "interop vs qntm base2048/base32768/base65536 skipped: node not installed"
	fi

	## The crate is a library, so the adapter around it has to be compiled. It
	## builds offline from the vendored source in a few seconds and is cached
	## after that, so this is not a per-run cost.
	if command -v cargo >/dev/null 2>&1; then
		CARGO_TARGET_DIR="${INTEROP_DIR}/build" cargo build --release --offline --quiet \
			--manifest-path "${INTEROP_DIR}/drivers/llfourn2048/Cargo.toml" >/dev/null 2>&1 || true
	fi
	if [[ -x "${INTEROP_RSBIN}" ]]; then
		fCheckInterop 2048llfourn "llfourn base2048 ${INTEROP_VER[base2048-llfourn]}" "${INTEROP_RSBIN}"
	else
		_warn "EleGcFU EleGcFV EleGcFW" "interop vs llfourn base2048 skipped: no adapter binary and cargo could not build one"
	fi
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Reactor module: the callable WebAssembly library, driven from a host
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Builds the wasip1 reactor and exercises the whole ABI from a wazero host:
## exports present and _start absent, conversions against known answers, base
## metadata, the error codes, stale-pointer and double-free detection, and a
## work loop that must end with zero outstanding regions. The host program has
## its own module so the library keeps zero dependencies; fetching wazero needs
## the network once, so an uncached offline build skips with a warning. The
## reactor build itself needs Go 1.24+ (wasmexport landed there); an older
## toolchain skips rather than failing with a confusing compiler error.
section "Reactor module"
REACTOR_HOST_DIR="${meDir}/utility/reactor-host"
REACTOR_WASM="${CBT_TMP}/convert-base-reactor.wasm"
goMinor="$(go env GOVERSION 2>/dev/null | sed -E 's/^go1\.([0-9]+).*$/\1/' || true)"
if [[ ! "${goMinor}" =~ ^[0-9]+$ ]] || ((goMinor < 24)); then
	_warn "Elmd2Y4 Ern7YaC" "reactor module skipped: needs a Go 1.24+ toolchain (have $(go env GOVERSION 2>/dev/null || echo none))"
elif ! (cd "${meDir}/../lib" && GOOS=wasip1 GOARCH=wasm go build -trimpath -buildmode=c-shared -o "${REACTOR_WASM}" ./reactor) >"${CBT_ERR}" 2>&1; then
	_fail Elmd2Y4 "reactor module build" "$(tail -2 "${CBT_ERR}")"
elif ! (cd "${REACTOR_HOST_DIR}" && go build -o "${CBT_TMP}/reactor-host" .) >"${CBT_ERR}" 2>&1; then
	_warn "Elmd2Y4 Ern7YaC" "reactor ABI skipped: host harness would not build (wazero not cached and offline?): $(tail -1 "${CBT_ERR}")"
elif "${CBT_TMP}/reactor-host" "${REACTOR_WASM}" >"${CBT_OUT}" 2>"${CBT_ERR}"; then
	_pass Elmd2Y4 "reactor ABI (exports, conversions, metadata, streams, errors, leak loops)"
	## A call's cost must not grow with the regions a host holds open.
	if "${CBT_TMP}/reactor-host" --regions "${REACTOR_WASM}" >"${CBT_OUT}" 2>"${CBT_ERR}"; then
		_pass Ern7YaC "reactor call cost with 10,000 regions open"
	else
		_fail Ern7YaC "reactor call cost with 10,000 regions open" "$(tail -1 "${CBT_ERR}")"
	fi
else
	_fail Elmd2Y4 "reactor ABI" "$(tail -1 "${CBT_ERR}")"
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## WASI command: the whole command as a WASI module, under wazero
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Same build as make wasm, run through reactor-host --wasi with no env and no
## dirs, like a bare wasmtime run. Stdout and exit status have to match the
## native command for numbers, errors and a binary stream both ways. No config
## reaches the module, so no case uses a config base.
section "WASI command"
WASI_WASM="${CBT_TMP}/convert-base-v2.wasm"
WASI_HOST="${CBT_TMP}/reactor-host"
if ! go env GOVERSION >/dev/null 2>&1; then
	_warn "EsifL4h EsifL63" "WASI command skipped: needs a Go toolchain"
elif ! (cd "${meDir}/../lib" && GOOS=wasip1 GOARCH=wasm go build -trimpath -o "${WASI_WASM}" ./cmd/convert-base-v2) >"${CBT_ERR}" 2>&1; then
	_fail EsifL4h "WASI command build" "$(tail -2 "${CBT_ERR}")"
elif [[ ! -x "${WASI_HOST}" ]] && ! (cd "${REACTOR_HOST_DIR}" && go build -o "${WASI_HOST}" .) >"${CBT_ERR}" 2>&1; then
	_warn "EsifL4h EsifL63" "WASI command skipped: host would not build (wazero not cached and offline?): $(tail -1 "${CBT_ERR}")"
else
	wasiBad=""; wasiN=0
	## wasi_case STDIN ARGS...
	wasi_case() {
		local in="$1" wrc=0 nrc=0
		shift
		"${WASI_HOST}" --wasi "${WASI_WASM}" "$@" <"$in" >"${CBT_TMP}/wasi_w" 2>/dev/null || wrc=$?
		"${EXE}" "$@" <"$in" >"${CBT_TMP}/wasi_n" 2>/dev/null || nrc=$?
		wasiN=$((wasiN + 1))
		if [[ "$wrc" != "$nrc" ]] || ! cmp -s "${CBT_TMP}/wasi_w" "${CBT_TMP}/wasi_n"; then
			wasiBad+=" [$* rc ${wrc}/${nrc}]"
		fi
		return 0
	}
	wasi_case /dev/null --from hex --to 10 ff
	wasi_case /dev/null --to 64emoji -- -62831853.0717958647692528676655
	wasi_case /dev/null --to 2048qntm 86434491232548995369
	wasi_case /dev/null --from 36 --to 10 --precision 40 zz.zz
	wasi_case /dev/null --from hex nope
	wasi_case /dev/null --bogus
	printf 'hi\nthere' >"${CBT_TMP}/wasi_text"
	wasi_case "${CBT_TMP}/wasi_text" --from keyboard --to 10 -
	(( ${#wasiBad} == 0 && wasiN == 7 )) && _pass EsifL4h "WASI command matches the native one (${wasiN} cases)" || _fail EsifL4h "WASI command matches the native one" "differs:${wasiBad}"

	wasiBad=""; wasiN=0
	head -c 30000 /dev/urandom >"${CBT_TMP}/wasi_raw"
	for wb in 64rfc 91hk 32768qntm; do
		wasi_case "${CBT_TMP}/wasi_raw" --binary --to "$wb"
		cp "${CBT_TMP}/wasi_n" "${CBT_TMP}/wasi_enc"
		wasi_case "${CBT_TMP}/wasi_enc" --binary --from "$wb" --to bytes
		cmp -s "${CBT_TMP}/wasi_w" "${CBT_TMP}/wasi_raw" || wasiBad+=" [${wb} round trip]"
	done
	(( ${#wasiBad} == 0 )) && _pass EsifL63 "WASI command streams binary both ways (${wasiN} cases)" || _fail EsifL63 "WASI command streams binary both ways" "differs:${wasiBad}"
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Browser module: the js/wasm build's own tests, run under node
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Go's wasm runner hands node the whole environment, and node refuses one
## over about 8K. So the tests get a short one, with the job counts cicd set,
## less GOMAXPROCS: the wasm program gets it too, and dies over 1 (newosproc).
## Each prints its own line and ID.
section "Browser module"
goRoot="$(go env GOROOT 2>/dev/null || true)"
wasmExec="${goRoot}/lib/wasm/go_js_wasm_exec"
[[ -x "$wasmExec" ]] || wasmExec="${goRoot}/misc/wasm/go_js_wasm_exec"
if ! command -v node >/dev/null 2>&1 || [[ ! -x "$wasmExec" ]]; then
	_warn "ErkSf4j ErkSf4h ErkSf4i Ert2MSr" "browser module tests skipped: needs node and Go's go_js_wasm_exec"
else
	bwrc=0; bwJobs=()
	for bwVar in GOFLAGS GO19CONCURRENTCOMPILATION; do [[ -z "${!bwVar:-}" ]] || bwJobs+=("${bwVar}=${!bwVar}"); done
	(cd "${meDir}/../lib" && env -i PATH="$PATH" HOME="$HOME" GOCACHE="$(go env GOCACHE)" GOMODCACHE="$(go env GOMODCACHE)" "${bwJobs[@]}" \
		GOOS=js GOARCH=wasm go test -json -count=1 -exec "$wasmExec" ./wasm) 2>&1 | python3 "${meDir}/utility/test-ids.py" report || bwrc=$?
	((bwrc == 0)) && _pass ErkSf4j "browser module tests" || _fail ErkSf4j "browser module tests" "exit ${bwrc}, see the lines above"
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Frontend parity: the Go module, the reactor and the browser module against the command
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Conversion behavior lives in the library, but each frontend has its own
## resolve-and-call plumbing, so the same requests run through all three: the
## command, the module natively (utility/module-driver), and the reactor
## (reactor-host --batch), and the answers must agree byte for byte. Every
## listed base, compat included, gets an integer both directions plus a signed
## fractional value; a base that can't represent one must refuse it in all
## three places, so agreement covers the error cases too. The compat and
## interop suites stay on the command alone on purpose: parity here extends
## what they establish to the other frontends transitively. The browser
## module joins at the end, and is held to the reactor's error codes as well.
section "Frontend parity"
MODDRV_DIR="${meDir}/utility/module-driver"
MODDRV="${CBT_TMP}/module-driver"
RHOST="${CBT_TMP}/reactor-host"
if ! go env GOVERSION >/dev/null 2>&1; then
	_warn "EloQXv6 EloQXv7 EloQXv8 EloQXv9 Ert30AN Ert2MTh" "frontend parity skipped: needs a Go toolchain"
elif ! (cd "${MODDRV_DIR}" && go build -o "${MODDRV}" .) >"${CBT_ERR}" 2>&1; then
	_fail EloQXv6 "module driver build" "$(tail -2 "${CBT_ERR}")"
else
	preq="${CBT_TMP}/parity_req"; pcli="${CBT_TMP}/parity_cli"; pout="${CBT_TMP}/parity_out"
	: >"$preq"; : >"$pcli"
	pn=0
	## parity_case FROM TO PRECISION VALUE: append the request in the driver
	## protocol, run the command on it, and append the command's answer. The
	## command's trailing newline is stripped by the head; values travel as hex
	## so digits carrying tabs or newlines (the keyboard base) survive intact.
	## --config /dev/null pins the command to the built-in bases: the module
	## and the reactor load no config, so the sandbox's worked example
	## (10emoji) exists only on the command's side. Config loading has its own
	## checks above.
	parity_case() {
		local from="$1" to="$2" prec="$3" val="$4" rc=0 hexv hexo
		hexv="$(printf '%s' "$val" | xxd -p | tr -d '\n')"
		printf '%s\t%s\t%s\t%s\n' "$from" "$to" "$prec" "$hexv" >>"$preq"
		local args=(--config /dev/null --from "$from" --to "$to")
		((prec >= 0)) && args+=(--precision "$prec")
		"${TIMEOUT[@]}" "${EXE}" "${args[@]}" -- "$val" >"${CBT_OUT}" 2>/dev/null || rc=$?
		if ((rc == 0)); then
			hexo="$(head -c -1 "${CBT_OUT}" | xxd -p | tr -d '\n')"
			printf 'ok\t%s\n' "$hexo" >>"$pcli"
		else
			printf 'err\n' >>"$pcli"
		fi
		pn=$((pn + 1))
	}
	declare -a PARITY_BASES=()
	while read -r pidx pname _; do
		[[ "$pidx" =~ ^[0-9]+$ ]] || continue
		[[ "$pname" == "bytes" ]] && continue
		PARITY_BASES+=("$pname")
	done < <("${EXE}" --config /dev/null --list --list-compat 2>/dev/null)
	(( ${#PARITY_BASES[@]} >= 30 )) && _pass EloQXv7 "parity scrape found bases (${#PARITY_BASES[@]})" || _fail EloQXv7 "parity scrape found bases" "only ${#PARITY_BASES[@]} scraped (--list format changed?)"
	for pname in "${PARITY_BASES[@]}"; do
		parity_case 10 "$pname" -1 "12345678901234567890"
		if [[ "$(tail -1 "$pcli")" == ok* ]]; then
			pfwd="$(tail -1 "$pcli" | cut -f2 | xxd -r -p)"
			parity_case "$pname" 10 -1 "$pfwd"
		fi
		parity_case 10 "$pname" 8 "-255.755"
	done
	parity_case 10 16 -1 "."
	parity_case 10 16 -1 "-."
	if "${MODDRV}" <"$preq" >"$pout" 2>"${CBT_ERR}"; then
		cmp -s "$pcli" "$pout" && _pass EloQXv6 "module answers match the command (${pn} cases)" || _fail EloQXv6 "module answers match the command" "first diff: $(diff "$pcli" "$pout" | head -3 | tr '\n' ' ')"
	else
		_fail EloQXv6 "module driver run" "$(tail -1 "${CBT_ERR}")"
	fi
	if [[ -x "$RHOST" && -s "$REACTOR_WASM" ]]; then
		if "$RHOST" --batch "$REACTOR_WASM" <"$preq" >"$pout" 2>"${CBT_ERR}"; then
			cmp -s "$pcli" "$pout" && _pass EloQXv8 "reactor answers match the command (${pn} cases)" || _fail EloQXv8 "reactor answers match the command" "first diff: $(diff "$pcli" "$pout" | head -3 | tr '\n' ' ')"
		else
			_fail EloQXv8 "reactor batch run" "$(tail -1 "${CBT_ERR}")"
		fi
		## Stream parity: one raw payload through the command's pipe and the
		## reactor's push streams, both directions, over every raw-capable
		## base. Deliberately odd chunk sizes so digit groups straddle the
		## write boundaries; the length is a multiple of 4 so z85 is legal.
		psrc="${CBT_TMP}/parity_src"
		head -c 3332 /dev/urandom >"$psrc"
		for pname in "${RAW_BASES[@]}"; do
			sfail=""; rc1=0; rc2=0; rc3=0; rc4=0
			"${TIMEOUT[@]}" "${EXE}" -n --from bytes --to "$pname" <"$psrc" >"${CBT_TMP}/ps_cli" 2>/dev/null || rc1=$?
			"$RHOST" --stream "$REACTOR_WASM" bytes "$pname" 7 <"$psrc" >"${CBT_TMP}/ps_rea" 2>/dev/null || rc2=$?
			if ((rc1 == 0 && rc2 == 0)); then
				cmp -s "${CBT_TMP}/ps_cli" "${CBT_TMP}/ps_rea" || sfail="encode mismatch"
				"${TIMEOUT[@]}" "${EXE}" -n --from "$pname" --to bytes <"${CBT_TMP}/ps_cli" >"${CBT_TMP}/ps_dcli" 2>/dev/null || rc3=$?
				"$RHOST" --stream "$REACTOR_WASM" "$pname" bytes 11 <"${CBT_TMP}/ps_cli" >"${CBT_TMP}/ps_drea" 2>/dev/null || rc4=$?
				{ ((rc3 == 0 && rc4 == 0)) && cmp -s "${CBT_TMP}/ps_dcli" "${CBT_TMP}/ps_drea" && cmp -s "$psrc" "${CBT_TMP}/ps_drea"; } || sfail="${sfail:+$sfail, }decode mismatch rc=${rc3}/${rc4}"
			else
				sfail="encode rc=${rc1}/${rc2}"
			fi
			[[ -z "$sfail" ]] && _pass EloQXv9 "stream parity via ${pname}" || _fail EloQXv9 "stream parity via ${pname}" "$sfail"
		done
	else
		_warn "EloQXv8 EloQXv9" "reactor parity skipped: reactor module or host not built"
	fi
	## Browser parity: the same requests through convertBase.convert(), the
	## call a page makes, under node. Its answers must match the command's, and
	## its answers and error codes the reactor's. A few failures the reactor can
	## also be given are added, so each code they reach is compared. Codes 3
	## and 4 need a symbol spec, which the reactor doesn't take; the browser
	## module's own tests (Ert2MSr) cover those.
	BROWSER_WASM="${CBT_TMP}/convert-base.wasm"
	wasmExecJs="${goRoot}/lib/wasm/wasm_exec.js"
	[[ -f "$wasmExecJs" ]] || wasmExecJs="${goRoot}/misc/wasm/wasm_exec.js"
	if ! command -v node >/dev/null 2>&1 || [[ ! -f "$wasmExecJs" ]]; then
		_warn "Ert30AN Ert2MTh" "browser parity skipped: needs node and Go's wasm_exec.js"
	elif ! (cd "${meDir}/../lib" && GOOS=js GOARCH=wasm go build -trimpath -o "${BROWSER_WASM}" ./wasm) >"${CBT_ERR}" 2>&1; then
		_fail Ert30AN "browser module build" "$(tail -2 "${CBT_ERR}")"
	else
		pcreq="${CBT_TMP}/parity_creq"; pbro="${CBT_TMP}/parity_bro"; prea="${CBT_TMP}/parity_rea"
		cp "$preq" "$pcreq"
		for pcase in "hexx|16|-1|1" "10|hexx|-1|1" "10|38hostname|-1|-5" "10|16|-1|12z" "10|16|-1|" "10|16|100001|1" "|16|-1|1"; do
			IFS='|' read -r pfrom pto pprec pval <<<"$pcase"
			printf '%s\t%s\t%s\t%s\n' "$pfrom" "$pto" "$pprec" "$(printf '%s' "$pval" | xxd -p | tr -d '\n')" >>"$pcreq"
		done
		if ! node "${meDir}/utility/browser-driver.js" "$wasmExecJs" "${BROWSER_WASM}" <"$pcreq" >"$pbro" 2>"${CBT_ERR}"; then
			_fail Ert30AN "browser driver run" "$(tail -1 "${CBT_ERR}")"
		else
			## The command gives no code, so the browser's are dropped for this one.
			head -n "$pn" "$pbro" | sed -E 's/^err\t.*$/err/' | cmp -s "$pcli" - && _pass Ert30AN "browser answers match the command (${pn} cases)" || _fail Ert30AN "browser answers match the command" "first diff: $(head -n "$pn" "$pbro" | sed -E 's/^err\t.*$/err/' | diff "$pcli" - | head -3 | tr '\n' ' ')"
			if [[ ! -x "$RHOST" || ! -s "$REACTOR_WASM" ]]; then
				_warn "Ert2MTh" "browser error code parity skipped: reactor module or host not built"
			elif ! "$RHOST" --batch-codes "$REACTOR_WASM" <"$pcreq" >"$prea" 2>"${CBT_ERR}"; then
				_fail Ert2MTh "reactor batch-codes run" "$(tail -1 "${CBT_ERR}")"
			else
				## A missing code kind means the added cases stopped reaching it,
				## and the comparison would pass without looking at it.
				pkinds="$(awk -F'\t' '$1 == "err" { print $2 }' "$prea" | sort -un | tr '\n' ' ')"
				if ! cmp -s "$prea" "$pbro"; then
					_fail Ert2MTh "browser answers and error codes match the reactor" "first diff: $(diff "$prea" "$pbro" | head -3 | tr '\n' ' ')"
				elif [[ "$pkinds" != "1 2 5 6 " ]]; then
					_fail Ert2MTh "browser answers and error codes match the reactor" "codes reached: ${pkinds:-none}, want 1 2 5 6"
				else
					_pass Ert2MTh "browser answers and error codes match the reactor ($(wc -l <"$pcreq") cases, codes ${pkinds% })"
				fi
			fi
		fi
	fi
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The macOS universal binary is joined here, not by lipo, and there is no Mac
## to run it on. Its tests check the fat layout against hand-made slices and
## against the real command cross-built for both Macs.
section "macOS universal binary"
## Each Go test there prints its own line and ID. This check is the suite.
if ! go env GOVERSION >/dev/null 2>&1; then
	_warn "ErftBA8 ErftBA9 ErftBAA ErftBAB ErftBAC ErftBAD" "macOS universal binary tests skipped: needs a Go toolchain"
else
	mfrc=0
	(cd "${meDir}/utility/macho-fat" && go test -json -count=1 .) 2>&1 | python3 "${meDir}/utility/test-ids.py" report || mfrc=$?
	((mfrc == 0)) && _pass ErftBA8 "macho-fat tests" || _fail ErftBA8 "macho-fat tests" "exit ${mfrc}, see the lines above"
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Release notes. The downloads table is built from the asset names package.bash
## writes, so these fixtures use the same names. Every bare unix binary is a stub
## that answers --version, so the build line is checked on any host.
section "Release notes"
rnDir="${CBT_TMP}/rn"; rnDist="${rnDir}/dist"; mkdir -p "${rnDist}"
for rnName in checksums.txt convert-base-v2.wasm notes.txt \
	convert-base-v2_9.9.9~beta1_amd64.deb convert-base-v2_9.9.9~beta1_arm64.deb \
	convert-base-v2-9.9.9~beta1-1.x86_64.rpm convert-base-v2-9.9.9~beta1-1.aarch64.rpm \
	convert-base-v2-{linux,darwin,freebsd}-{x86_64,arm64}{,.tgz} convert-base-v2-darwin-universal{,.tgz} \
	convert-base-v2-windows-{x86_64,arm64}{.exe,.zip,-setup.exe}; do
	if [[ "${rnName}" =~ ^convert-base-v2-(linux|darwin|freebsd)-[a-z0-9_]+$ ]]; then
		printf '#!/bin/sh\necho "convert-base-v2 v9.9.9-beta1 build abcde"\n' >"${rnDist}/${rnName}"; chmod +x "${rnDist}/${rnName}"
	else
		: >"${rnDist}/${rnName}"
	fi
done
printf '%s\n' '## vNEXT - DATE' '' '## v9.9.9-beta1 - 2026-10-04' '' '### Added' '' '- Something new.' '' '## v9.9.8 - 2026-10-01' '' '- Older.' >"${rnDir}/changelog.md"
rnU="https://github.com/o/r/releases/download/v9.9.9-beta1"
rnWant="$(cat <<EOF
### Added

- Something new.

### Downloads

| OS | x86_64 | arm64 | Universal
| :--- | :--- | :--- | :---
| Linux | [binary](${rnU}/convert-base-v2-linux-x86_64), [.tgz](${rnU}/convert-base-v2-linux-x86_64.tgz), [.deb](${rnU}/convert-base-v2_9.9.9.beta1_amd64.deb), [.rpm](${rnU}/convert-base-v2-9.9.9.beta1-1.x86_64.rpm) | [binary](${rnU}/convert-base-v2-linux-arm64), [.tgz](${rnU}/convert-base-v2-linux-arm64.tgz), [.deb](${rnU}/convert-base-v2_9.9.9.beta1_arm64.deb), [.rpm](${rnU}/convert-base-v2-9.9.9.beta1-1.aarch64.rpm) |
| macOS | [binary](${rnU}/convert-base-v2-darwin-x86_64), [.tgz](${rnU}/convert-base-v2-darwin-x86_64.tgz) | [binary](${rnU}/convert-base-v2-darwin-arm64), [.tgz](${rnU}/convert-base-v2-darwin-arm64.tgz) | [binary](${rnU}/convert-base-v2-darwin-universal), [.tgz](${rnU}/convert-base-v2-darwin-universal.tgz)
| Windows | [.exe](${rnU}/convert-base-v2-windows-x86_64.exe), [.zip](${rnU}/convert-base-v2-windows-x86_64.zip), [installer](${rnU}/convert-base-v2-windows-x86_64-setup.exe) | [.exe](${rnU}/convert-base-v2-windows-arm64.exe), [.zip](${rnU}/convert-base-v2-windows-arm64.zip), [installer](${rnU}/convert-base-v2-windows-arm64-setup.exe) |
| FreeBSD | [binary](${rnU}/convert-base-v2-freebsd-x86_64), [.tgz](${rnU}/convert-base-v2-freebsd-x86_64.tgz) | [binary](${rnU}/convert-base-v2-freebsd-arm64), [.tgz](${rnU}/convert-base-v2-freebsd-arm64.tgz) |
| WebAssembly (WASI) |  |  | [.wasm](${rnU}/convert-base-v2.wasm)

Also: [notes.txt](${rnU}/notes.txt)

Checksums for every file: [checksums.txt](${rnU}/checksums.txt)

---

convert-base-v2 v9.9.9-beta1 build abcde
EOF
)"
rnrc=0; rnGot="$(bash "${meDir}/utility/release-notes.bash" --version v9.9.9-beta1 --dist "${rnDist}" --repo o/r --changelog "${rnDir}/changelog.md" 2>"${CBT_ERR}")" || rnrc=$?
{ ((rnrc == 0)) && [[ "${rnGot}" == "${rnWant}" ]]; } && _pass ErlN8Nk "release notes: changelog, downloads table, build line" || _fail ErlN8Nk "release notes: changelog, downloads table, build line" "rc=${rnrc} diff: $(diff <(printf '%s\n' "${rnWant}") <(printf '%s\n' "${rnGot}") || true)"
grep -qF "not a known asset, listed under the table: notes.txt" "${CBT_ERR}" && _pass ErlN8OJ "release notes: unknown asset warning" || _fail ErlN8OJ "release notes: unknown asset warning" "stderr=[$(<"${CBT_ERR}")]"
## A --no-arm run, and a build that says another version: only the column that
## has something, and no build line rather than a wrong one.
rnDist2="${rnDir}/dist2"; mkdir -p "${rnDist2}"
cp -p "${rnDist}"/convert-base-v2-linux-x86_64{,.tgz} "${rnDist}"/convert-base-v2-windows-x86_64.zip "${rnDist2}/"
rnGot="$(bash "${meDir}/utility/release-notes.bash" --version v9.9.9 --dist "${rnDist2}" --repo o/r --changelog "${rnDir}/changelog.md" 2>"${CBT_ERR}" || true)"
rnU="https://github.com/o/r/releases/download/v9.9.9"
rnWant="$(printf '%s\n' 'See changelog.md.' '' '### Downloads' '' '| OS | x86_64' '| :--- | :---' "| Linux | [binary](${rnU}/convert-base-v2-linux-x86_64), [.tgz](${rnU}/convert-base-v2-linux-x86_64.tgz)" "| Windows | [.zip](${rnU}/convert-base-v2-windows-x86_64.zip)")"
{ [[ "${rnGot}" == "${rnWant}" ]] && grep -qF "so the notes name no build number" "${CBT_ERR}"; } && _pass ErlN8Oq "release notes: sparse table, no build line" || _fail ErlN8Oq "release notes: sparse table, no build line" "got=[${rnGot}] stderr=[$(<"${CBT_ERR}")]"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Release packaging, as a prerelease, twice. The second run has another umask
## and time zone and comes seconds later, so anything taken from the clock or
## the host shows up as a changed checksum.
section "Release packaging"
## --out is cleared only when a build made it. The go here always fails, so
## each run stops right after the clearing and builds nothing.
pgDir="${CBT_TMP}/pg"; pgBin="${pgDir}/bin"; pgMark=".convert-base-v2-dist"
mkdir -p "${pgBin}" "${pgDir}/theirs" "${pgDir}/empty"
printf '#!/bin/sh\nexit 1\n' >"${pgBin}/go"; chmod +x "${pgBin}/go"
echo keep >"${pgDir}/theirs/notes.txt"
## What a dir holds, for a failure message.
fNames(){ find "$1" -mindepth 1 -maxdepth 1 -printf '%f ' 2>&1 || true; }
fPgRun(){ PATH="${pgBin}:${PATH}" bash "${meDir}/utility/package.bash" --version v9.9.9 --build-epoch 1700000000 --out "$1" >/dev/null 2>"${CBT_ERR}"; }
pgrc=0; fPgRun "${pgDir}/theirs" || pgrc=$?
{ ((pgrc != 0)) && [[ -f "${pgDir}/theirs/notes.txt" ]] && grep -qF "no sign a build made them" "${CBT_ERR}"; } && _pass Erm3Sws "package.bash: foreign --out kept" \
	|| _fail Erm3Sws "package.bash: foreign --out kept" "rc=${pgrc} left: [$(fNames "${pgDir}/theirs")] err=[$(<"${CBT_ERR}")]"
fPgRun "${pgDir}/ours" || true
mkdir -p "${pgDir}/ours/sub"; echo old >"${pgDir}/ours/old.tgz"
fPgRun "${pgDir}/ours" || true
fPgRun "${pgDir}/empty" || true
{ [[ -f "${pgDir}/ours/${pgMark}" && -f "${pgDir}/empty/${pgMark}" && ! -e "${pgDir}/ours/old.tgz" && ! -e "${pgDir}/ours/sub" ]]; } && _pass Erm3SxT "package.bash: own or empty --out" \
	|| _fail Erm3SxT "package.bash: own or empty --out" "ours: [$(fNames "${pgDir}/ours")] empty: [$(fNames "${pgDir}/empty")]"
## make clean takes the same rule. BINARY is pointed away from lib/'s own build.
mkdir -p "${pgDir}/mc-theirs" "${pgDir}/mc-ours"; echo keep >"${pgDir}/mc-theirs/notes.txt"; : >"${pgDir}/mc-ours/${pgMark}"; : >"${pgDir}/mc-ours/old.tgz"
mcrc=0; make -s -C "${meDir}/../lib" clean BINARY="${pgDir}/no-binary" DIST="${pgDir}/mc-theirs" >/dev/null 2>&1 || mcrc=$?
make -s -C "${meDir}/../lib" clean BINARY="${pgDir}/no-binary" DIST="${pgDir}/mc-ours" >/dev/null 2>&1 || true
{ ((mcrc != 0)) && [[ -f "${pgDir}/mc-theirs/notes.txt" && ! -e "${pgDir}/mc-ours" ]]; } && _pass Erm3Syv "make clean: own dist only" \
	|| _fail Erm3Syv "make clean: own dist only" "rc=${mcrc} theirs: [$(fNames "${pgDir}/mc-theirs")] ours: [$(fNames "${pgDir}/mc-ours")]"
## The two full packaging runs take several seconds each, so --quick skips them.
if ((doQuick)); then
	_warn "ErlP6B8 Erm3SyD EtAjZOv EtAjy1j ErlP6Bg ErlP6CE Et9pfRW Et9pfS9" "packaging rebuild checks skipped: --quick" asked
else
	pkDir="${CBT_TMP}/pk"; pkrc=0
	pkArgs=(--version v9.9.9-beta1 --build-epoch 1700000000)
	bash "${meDir}/utility/package.bash" "${pkArgs[@]}" --out "${pkDir}/a" >/dev/null 2>"${CBT_ERR}" || pkrc=$?
	## A stray GOAMD64 must not change the bytes either.
	( umask 077; TZ=Pacific/Kiritimati GOAMD64=v3 bash "${meDir}/utility/package.bash" "${pkArgs[@]}" --out "${pkDir}/b" >/dev/null 2>>"${CBT_ERR}" ) || pkrc=$?
	pkSums="${pkDir}/a/checksums.txt"
	if ((pkrc != 0)) || [[ ! -s "${pkSums}" ]]; then
		_fail ErlP6B8 "release assets rebuild to the same bytes" "package.bash exit ${pkrc}: $(tail -5 "${CBT_ERR}")"
	else
		pkDiff="$(diff "${pkSums}" "${pkDir}/b/checksums.txt" | sed -n 's/^> [0-9a-f]* *//p' | tr '\n' ' ' || true)"
		[[ -z "${pkDiff}" ]] && _pass ErlP6B8 "release assets rebuild to the same bytes" || _fail ErlP6B8 "release assets rebuild to the same bytes" "differ: ${pkDiff}"
	fi
	## Plain x86-64, so a Core 2 Duo or a Phenom II can run them.
	pkLevels=""
	for pkBin in "${pkDir}"/b/convert-base-v2-{linux,freebsd,darwin}-x86_64 "${pkDir}/b/convert-base-v2-windows-x86_64.exe"; do
		pkLevels+="$(go version -m "${pkBin}" 2>/dev/null | sed -n 's/^[[:space:]]*build[[:space:]]*GOAMD64=//p' || true),"
	done
	[[ "${pkLevels}" == "v1,v1,v1,v1," ]] && _pass EtAjZOv "x86_64 release builds target plain x86-64" \
		|| _fail EtAjZOv "x86_64 release builds target plain x86-64" "GOAMD64 by linux,freebsd,darwin,windows: [${pkLevels}]"
	## And it runs on an emulated Penryn, the last Core 2 Duo, and a Phenom II.
	## A v2 build is the control, since Go refuses to start on either.
	if ! command -v qemu-x86_64 >/dev/null 2>&1; then
		_warn "EtAjy1j" "old CPU check skipped: needs qemu-x86_64, from qemu-user"
	else
		pkV2="${pkDir}/convert-base-v2-v2"
		(cd "${meDir}/../lib" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GOAMD64=v2 go build -trimpath -o "${pkV2}" ./cmd/convert-base-v2) >"${CBT_ERR}" 2>&1 || true
		## Big enough for math/big, which picks its own code by CPU.
		pkNum="$(printf '9%.0s' {1..120})"
		pkWant="$("${pkDir}/b/convert-base-v2-linux-x86_64" "${pkNum}" 62 2>&1 || true)"
		pkCpus=""
		for pkModel in Penryn phenom; do
			pkGot="$("${TIMEOUT[@]}" qemu-x86_64 -cpu "${pkModel}" "${pkDir}/b/convert-base-v2-linux-x86_64" "${pkNum}" 62 2>&1 || true)"
			pkCtl=0; "${TIMEOUT[@]}" qemu-x86_64 -cpu "${pkModel}" "${pkV2}" 255 16 >/dev/null 2>&1 || pkCtl=$?
			pkCpus+="${pkModel}:$([[ -n "${pkWant}" && "${pkGot}" == "${pkWant}" ]] && echo same || echo "[${pkGot:0:80}]"):$((pkCtl != 0 && pkCtl != 124));"
		done
		[[ "${pkCpus}" == "Penryn:same:1;phenom:same:1;" && -x "${pkV2}" ]] && _pass EtAjy1j "x86_64 release build runs on a Core 2 Duo and a Phenom II" \
			|| _fail EtAjy1j "x86_64 release build runs on a Core 2 Duo and a Phenom II" "model:output:control-refused [${pkCpus}] v2 build: $([[ -x "${pkV2}" ]] && echo ok || head -c 300 "${CBT_ERR}")"
	fi
	## The mark stays out of checksums.txt, which lists what gets uploaded.
	{ [[ -s "${pkSums}" && -f "${pkDir}/a/${pgMark}" ]] && ! grep -qF -- "${pgMark}" "${pkSums}"; } && _pass Erm3SyD "dist mark is not a release asset" \
		|| _fail Erm3SyD "dist mark is not a release asset" "mark: $([[ -f "${pkDir}/a/${pgMark}" ]] && echo yes || echo no), sums: $(grep -cF -- "${pgMark}" "${pkSums}" 2>/dev/null || true)"
	## Explorer's icon and Details tab. The fixed version is four numbers, and a
	## beta is flagged prerelease (0x2) in the exe. The installer gets the same
	## icon and version, less the flag. The resource is gone from the source dir
	## after, so no later build picks up a stale one.
	pkWant=(icon_groups=1 "icon_sizes=16,32,48,64,128,256" fixed_file_version=9.9.9.0 fixed_product_version=9.9.9.0
		string.FileVersion=9.9.9-beta1 string.ProductVersion=9.9.9-beta1 "string.CompanyName=Jim Collier")
	## Prints what's missing, if anything. No ID marker in LegalCopyright, since Explorer shows it.
	fPeHas(){
		local file="$1" want got; shift
		got="$(python3 -I "${meDir}/utility/pe-resources.py" "${file}" 2>&1 || true)"
		for want in "$@"; do grep -qxF -- "${want}" <<<"${got}" || { printf 'missing [%s] in: %s' "${want}" "$(tr '\n' ' ' <<<"${got}")"; return 1; }; done
		grep -qE '^string\.LegalCopyright=Copyright © [0-9-]+ Jim Collier\.' <<<"${got}" || { printf 'LegalCopyright: [%s]' "$(grep -F LegalCopyright <<<"${got}" || true)"; return 1; }
	}
	if ! command -v goversioninfo >/dev/null 2>&1; then
		_warn "Et9pfRW Et9pfS9" "Windows resource checks skipped: goversioninfo not installed"
	else
		for pkExe in convert-base-v2-windows-x86_64.exe convert-base-v2-windows-arm64.exe; do
			pkWhy="$(fPeHas "${pkDir}/a/${pkExe}" "${pkWant[@]}" fixed_flags=0x2 string.OriginalFilename=convert-base-v2.exe)" \
				&& [[ -z "$(find "${meDir}/../lib/cmd/convert-base-v2" -name '*.syso')" ]] \
				&& _pass Et9pfRW "Windows exe icon and version: ${pkExe}" || _fail Et9pfRW "Windows exe icon and version: ${pkExe}" "${pkWhy:-a .syso was left in lib/cmd/convert-base-v2}"
		done
		if ! command -v makensis >/dev/null 2>&1; then
			_warn Et9pfS9 "installer resource check skipped: makensis not installed"
		else
			for pkExe in convert-base-v2-windows-x86_64-setup.exe convert-base-v2-windows-arm64-setup.exe; do
				pkWhy="$(fPeHas "${pkDir}/a/${pkExe}" "${pkWant[@]}")" \
					&& _pass Et9pfS9 "installer icon and version: ${pkExe}" || _fail Et9pfS9 "installer icon and version: ${pkExe}" "${pkWhy}"
			done
		fi
	fi
	if ! command -v nfpm >/dev/null 2>&1; then
		_warn "ErlP6Bg ErlP6CE" "prerelease package checks skipped: nfpm not installed"
	elif [[ -s "${pkSums}" ]]; then
		## GitHub turns any character outside [A-Za-z0-9._-] into a dot on upload.
		pkBad="$(awk '{ sub(/^\*/, "", $2); if ($2 !~ /^[A-Za-z0-9._-]+$/) printf "%s ", $2 }' "${pkSums}")"
		pkCheck="$(cd "${pkDir}/a" && sha256sum -c --quiet checksums.txt 2>&1 || true)"
		pkDebs="$(find "${pkDir}/a" -maxdepth 1 -type f \( -name '*.deb' -o -name '*.rpm' \) | wc -l)"
		{ [[ -z "${pkBad}" && -z "${pkCheck}" ]] && ((pkDebs == 4)); } && _pass ErlP6Bg "prerelease asset names" \
			|| _fail ErlP6Bg "prerelease asset names" "renamed on upload: [${pkBad}] check: [${pkCheck}] packages: ${pkDebs}"
		## The version inside keeps the ~, so a beta sorts below its final.
		pkVers=""
		command -v dpkg-deb >/dev/null 2>&1 && pkVers+="$(dpkg-deb -f "${pkDir}"/a/*_amd64.deb Version 2>&1 || true) "
		command -v rpm >/dev/null 2>&1 && pkVers+="$(rpm -qp --qf '%{VERSION}' "${pkDir}"/a/*.x86_64.rpm 2>/dev/null || true) "
		if [[ -z "${pkVers}" ]]; then
			_warn ErlP6CE "package version check skipped: neither dpkg-deb nor rpm installed"
		else
			[[ "${pkVers}" =~ ^(9\.9\.9~beta1 )+$ ]] && _pass ErlP6CE "prerelease package version keeps its ~" || _fail ErlP6CE "prerelease package version keeps its ~" "got [${pkVers}]"
		fi
	fi
fi


## Where every packager should be installed, a missing one stops the run before
## the cross builds, not a minute in.
pnDir="${CBT_TMP}/pn"; mkdir -p "${pnDir}/bin"; ln -s "$(command -v dirname)" "${pnDir}/bin/dirname"
pnrc=0; pnOut="$(CICD_NO_SKIP=1 PATH="${pnDir}/bin" "${BASH}" "${meDir}/utility/package.bash" --out "${pnDir}/out" 2>&1)" || pnrc=$?
{ ((pnrc == 1)) && [[ "${pnOut}" == *"ERROR: nfpm missing"* && ! -e "${pnDir}/out" ]]; } && _pass EsJjVzI "package.bash missing nfpm, NO_SKIP" \
	|| _fail EsJjVzI "package.bash missing nfpm, NO_SKIP" "rc=${pnrc} out=[${pnOut}]"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Release and helper scripts. A failed lookup prints the script's own message
## instead of ending it at exit 1, and a pipeline still works when the tool in
## front writes more than a pipe holds. Fake tools stand in for the real ones.
section "Release and helper scripts"
crDir="${CBT_TMP}/cr"
mkdir -p "${crDir}/repo/lib/cmd/convert-base-v2" "${crDir}/norepo/lib/cmd/convert-base-v2" "${crDir}/nofile"
for crRoot in repo norepo; do
	printf 'package main\n\nvar version = "v9.9.9"\n' >"${crDir}/${crRoot}/lib/cmd/convert-base-v2/main.go"
	printf '# x\n\nNo badge here.\n' >"${crDir}/${crRoot}/README.md"
done
git -C "${crDir}/repo" init -q >/dev/null 2>&1 || true
for crCase in "nofile|no 'var version'" "norepo|could not list the tags" "repo|no Lifecycle badge found"; do
	crRoot="${crCase%%|*}"; crWant="${crCase#*|}"; crrc=0
	bash "${meDir}/utility/check-release.bash" --repo "${crDir}/${crRoot}" >/dev/null 2>"${CBT_ERR}" || crrc=$?
	{ ((crrc == 1)) && grep -qF -- "${crWant}" "${CBT_ERR}"; } && _pass Erm3Szg "check-release says why: ${crWant}" \
		|| _fail Erm3Szg "check-release says why: ${crWant}" "rc=${crrc} err=[$(<"${CBT_ERR}")]"
done

inDir="${CBT_TMP}/in"; mkdir -p "${inDir}/bin" "${inDir}/home"
cat >"${inDir}/bin/curl" <<'EOF'
#!/bin/sh
out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac; done
case "$url" in
	*api.github.com*) cat "$FAKE_RELEASE" ;;
	*/checksums.txt) echo "0000  convert-base-v2-other" >"$out" ;;
	*) echo bin >"$out" ;;
esac
EOF
chmod +x "${inDir}/bin/curl"
## The API lists releases one field per line, as GitHub serves it.
fInList(){ local t; printf '[\n'; for t in "$@"; do printf '  {\n    "tag_name": "%s",\n    "draft": %s,\n    "prerelease": %s\n  },\n' "${t%%:*}" "$( [[ "${t}" == *:draft ]] && echo true || echo false)" "$( [[ "${t}" == *:pre* ]] && echo true || echo false)"; done; printf ']\n'; }
fInRun(){ inrc=0; HOME="${inDir}/home" FAKE_RELEASE="${inDir}/release.json" PATH="${inDir}/bin:${PATH}" bash "${meDir}/../install.bash" "$@" </dev/null >"${CBT_OUT}" 2>"${CBT_ERR}" || inrc=$?; inOut="$(<"${CBT_OUT}")"; }
for inCase in '{"message": "Not Found"}|'"couldn't determine the stable release tag" 'v9.9.9|no checksum for convert-base-v2-'; do
	if [[ "${inCase}" == v* ]]; then fInList "${inCase%%|*}" >"${inDir}/release.json"; else printf '%s\n' "${inCase%%|*}" >"${inDir}/release.json"; fi
	inWant="${inCase#*|}"; fInRun -y
	{ ((inrc == 1)) && grep -qF -- "${inWant}" "${CBT_ERR}"; } && _pass Erm3T0M "install.bash says why: ${inWant}" \
		|| _fail Erm3T0M "install.bash says why: ${inWant}" "rc=${inrc} err=[$(<"${CBT_ERR}")]"
done
## Newest by version, not by listing order: a pre-release sorts below its
## final, beta10 above beta9, and a draft never counts.
fInList v3.0.0 v3.1.0-beta2:pre v99.0.0:draft v3.1.0-beta10:pre v3.1.0-beta9:pre v2.0.0 v3.0.1-rc1:pre >"${inDir}/release.json"
fInRun -y; inStable="${inOut}"
fInRun -y --release=dev; inDev="${inOut}"
fInRun -y --release dev; inDev2="${inOut}"
{ [[ "${inStable}" == *"Release: v3.0.0 (stable)"* && "${inDev}" == *"Release: v3.1.0-beta10 (dev)"* && "${inDev2}" == *"Release: v3.1.0-beta10 (dev)"* ]]; } && _pass EshY04X "install.bash picks newest version" \
	|| _fail EshY04X "install.bash picks newest version" "stable=[${inStable}] dev=[${inDev}]"
## No stable release yet: stable takes the newest pre-release, and says so.
fInList v1.0.0-rc2:pre v1.0.0-rc10:pre >"${inDir}/release.json"
fInRun -y
{ [[ "${inOut}" == *"No stable release yet"* && "${inOut}" == *"Release: v1.0.0-rc10 (stable)"* ]]; } && _pass EshY05J "install.bash, pre-releases only" \
	|| _fail EshY05J "install.bash, pre-releases only" "rc=${inrc} out=[${inOut}]"
## --version, no --arch, and a closed stdin at the prompt is a no.
inOk=""
fInRun --version; [[ "${inrc}" == 0 && "${inOut}" =~ ^convert-base-v2\ installer\ v[0-9]+\.[0-9]+\.[0-9]+$ ]] && inOk+="version "
fInRun --arch x86_64; [[ "${inrc}" == 1 ]] && grep -qF 'unknown option: --arch' "${CBT_ERR}" && inOk+="arch "
fInRun; [[ "${inrc}" == 1 && "${inOut}" == *"aborted; nothing was touched"* && ! -e "${inDir}/home/.local/bin/convert-base-v2" ]] && inOk+="prompt"
[[ "${inOk}" == "version arch prompt" ]] && _pass EshY061 "install.bash options" \
	|| _fail EshY061 "install.bash options" "passed=[${inOk}] last rc=${inrc} out=[${inOut}]"
## Already current, read from the installed build's --version, with the name in
## front as now, or without it as before 3.0.1.
fInList v3.0.0 >"${inDir}/release.json"; mkdir -p "${inDir}/home/.local/bin"
for inLine in "convert-base-v2 v3.0.0 build abcde" "v3.0.0 build abcde" "v3.0.0"; do
	printf '#!/bin/sh\necho "%s"\n' "${inLine}" >"${inDir}/home/.local/bin/convert-base-v2"; chmod +x "${inDir}/home/.local/bin/convert-base-v2"
	fInRun -y
	{ ((inrc == 0)) && [[ "${inOut}" == *"is already v3.0.0; nothing to do"* ]]; } && _pass Esj2Pos "install.bash sees it's current: ${inLine}" \
		|| _fail Esj2Pos "install.bash sees it's current: ${inLine}" "rc=${inrc} out=[${inOut}]"
done
rm -f "${inDir}/home/.local/bin/convert-base-v2"

## PowerShell files stay ASCII. The one-liner reads install.ps1 through irm,
## which keeps a byte-order mark, and the parse then fails. With no mark,
## Windows PowerShell 5.1 reads anything else in the ANSI code page.
psFiles="$(git -C "${meDir}/.." ls-files -- '*.ps1' '*.psm1' '*.psd1' 2>/dev/null || true)"; psBad=""
while IFS= read -r psF; do
	[[ -n "${psF}" && -f "${meDir}/../${psF}" ]] || continue
	[[ -z "$(LC_ALL=C tr -d '\000-\177' <"${meDir}/../${psF}" | head -c1)" ]] || psBad+="${psF} "
done <<<"${psFiles}"
{ [[ -z "${psBad}" ]] && grep -qx 'install.ps1' <<<"${psFiles}"; } && _pass Et9uoIr "PowerShell files are ASCII" \
	|| _fail Et9uoIr "PowerShell files are ASCII" "non-ASCII: [${psBad}] tracked: [$(tr '\n' ' ' <<<"${psFiles}")]"

## install.ps1 gets the same checks, plus a real install from a release with a
## real checksums.txt, a tampered one, a read-only folder, and the prompt. The
## two web cmdlets are stood in for by functions defined before it runs. Most
## runs use the README's one-liner form, where an exit would close the caller's
## shell. A file run is what gives an exit code.
psIds="Et9uoJX Et9uoKF Et9uoKx Et9uoLd Et9uoMI Et9uoMw Et9uoNc Et9uoOI Et9uoOx Et9uoPc"
if ! command -v pwsh >/dev/null 2>&1; then
	_warn "${psIds}" "install.ps1 checks skipped: pwsh not installed"
else
	psDir="${CBT_TMP}/ps"; psFix="${psDir}/fix"; psHome="${psDir}/home"; psBin="${psDir}/home/.local/bin/convert-base-v2"
	mkdir -p "${psFix}/dist" "${psHome}" "${psDir}/tmp"
	psRaw="$(CBV_PS1="${meDir}/../install.ps1" pwsh -NoProfile -NonInteractive -Command '$t = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($env:CBV_PS1)); $e = $null; $null = [System.Management.Automation.Language.Parser]::ParseInput($t, [ref]$null, [ref]$e); $e.Count' 2>&1 </dev/null)" || true
	[[ "${psRaw}" == 0 ]] && _pass Et9uoJX "install.ps1 parses from its raw bytes" || _fail Et9uoJX "install.ps1 parses from its raw bytes" "errors=[${psRaw}]"
	cat >"${psDir}/run.ps1" <<'EOF'
function Invoke-RestMethod {
	[CmdletBinding()]
	param([string]$Uri, [switch]$UseBasicParsing)
	Add-Content -LiteralPath (Join-Path -Path $env:CBV_FIX -ChildPath 'urls.log') -Value $Uri
	$json = Join-Path -Path $env:CBV_FIX -ChildPath 'release.json'
	if (-not (Test-Path -LiteralPath $json)) { throw 'No such host is known.' }
	Get-Content -Raw -LiteralPath $json | ConvertFrom-Json
}
function Invoke-WebRequest {
	[CmdletBinding()]
	param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing)
	Add-Content -LiteralPath (Join-Path -Path $env:CBV_FIX -ChildPath 'urls.log') -Value $Uri
	$src = Join-Path -Path (Join-Path -Path $env:CBV_FIX -ChildPath 'dist') -ChildPath ($Uri -replace '^.*/', '')
	if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw 'Response status code does not indicate success: 404 (Not Found).' }
	Copy-Item -LiteralPath $src -Destination $OutFile
}
$mode = $args[0]
$rest = @(if ($args.Count -gt 1) { $args[1..($args.Count - 1)] })
if ($mode -eq 'file') {
	& $env:CBV_PS1 @rest
	exit $LASTEXITCODE
}
& ([scriptblock]::Create([IO.File]::ReadAllText($env:CBV_PS1))) @rest
## Strict mode left on would throw at the unset variable.
"caller still here, EAP=$ErrorActionPreference, unset=$($null -eq $notSetAnywhere)"
EOF
	psOs="$(uname -s | tr '[:upper:]' '[:lower:]')"; psArch="$(uname -m)"
	case "${psArch}" in amd64) psArch=x86_64 ;; aarch64) psArch=arm64 ;; esac
	psAsset="convert-base-v2-${psOs}-${psArch}"
	## The release the packaging checks made, when they ran, so the asset asked
	## for has a name package.bash writes. Otherwise a stub that answers
	## --version the same way, with an archive whose name starts with the
	## asset's listed first in checksums.txt.
	if [[ -s "${pkDir:-}/a/checksums.txt" && -f "${pkDir:-}/a/${psAsset}" ]]; then
		cp "${pkDir}/a/${psAsset}" "${pkDir}/a/checksums.txt" "${psFix}/dist/"; psFrom="packaged"
	else
		printf '#!/bin/sh\necho "convert-base-v2 v9.9.9-beta1 build abcde"\n' >"${psFix}/dist/${psAsset}"; echo decoy >"${psFix}/dist/${psAsset}.tgz"
		(cd "${psFix}/dist" && sha256sum "${psAsset}.tgz" "${psAsset}" >checksums.txt); psFrom="stub"
	fi
	chmod +x "${psFix}/dist/${psAsset}"; cp "${psFix}/dist/checksums.txt" "${psDir}/checksums.good"
	psVerLine="$("${psFix}/dist/${psAsset}" --version 2>/dev/null || true)"; psTag="${psVerLine#convert-base-v2 }"; psTag="${psTag%% *}"
	## fPsRun STDIN MODE ARGS...: block is the one-liner form, file runs the file.
	fPsRun(){
		local psIn="$1"; shift; psRc=0
		printf '%s' "${psIn}" >"${psDir}/stdin"; : >"${psFix}/urls.log"
		env -u DISPLAY NO_COLOR=1 HOME="${psHome}" TMPDIR="${psDir}/tmp" CBV_FIX="${psFix}" CBV_PS1="${meDir}/../install.ps1" \
			"${TIMEOUT[@]}" pwsh -NoProfile -File "${psDir}/run.ps1" "$@" <"${psDir}/stdin" >"${CBT_OUT}" 2>"${CBT_ERR}" || psRc=$?
		psOut="$(<"${CBT_OUT}")"; psErr="$(<"${CBT_ERR}")"
	}
	fPsTail(){ printf 'rc=%s out=[%s] err=[%s]' "${psRc}" "$(tail -4 <<<"${psOut}")" "$(head -c 400 <<<"${psErr}")"; }
	## Nothing written, nothing left in the temp dir, and only the lookup fetched.
	fPsUntouched(){ [[ ! -e "${psBin}" && ! -e "${psHome}/.local/bin/.convert-base-v2.new" && -z "$(ls -A "${psDir}/tmp")" ]] && [[ "$(<"${psFix}/urls.log")" == *"/releases?per_page=100" ]]; }

	psOk=""
	fPsRun "" file -Version; [[ "${psRc}" == 0 && "${psOut}" =~ ^convert-base-v2\ installer\ v[0-9]+\.[0-9]+\.[0-9]+$ ]] && psOk+="version "
	fPsRun "" block -Help; [[ "${psRc}" == 0 && "${psOut}" == *"-Release stable|dev"* && "${psOut}" == *"-Target user|system"* ]] && psOk+="help "
	fPsRun "" file -Arch x86_64; grep -qF "'Arch'" "${CBT_ERR}" && [[ ! -s "${psFix}/urls.log" ]] && psOk+="arch"
	[[ "${psOk}" == "version help arch" ]] && _pass Et9uoKF "install.ps1 options" || _fail Et9uoKF "install.ps1 options" "passed=[${psOk}] $(fPsTail)"

	fInList v3.0.0 v3.1.0-beta2:pre v99.0.0:draft v3.1.0-beta10:pre v3.1.0-beta9:pre v2.0.0 v3.0.1-rc1:pre >"${psFix}/release.json"
	fPsRun n block; psStable="${psOut}"
	fPsRun n block -Release dev
	{ [[ "${psStable}" == *"Release: v3.0.0 (stable)"* && "${psOut}" == *"Release: v3.1.0-beta10 (dev)"* ]]; } && _pass Et9uoKx "install.ps1 picks newest version" \
		|| _fail Et9uoKx "install.ps1 picks newest version" "stable=[${psStable}] dev=[${psOut}]"
	fInList v1.0.0-rc2:pre v1.0.0-rc10:pre >"${psFix}/release.json"
	fPsRun n block
	{ [[ "${psOut}" == *"No stable release yet"* && "${psOut}" == *"Release: v1.0.0-rc10 (stable)"* ]]; } && _pass Et9uoLd "install.ps1, pre-releases only" \
		|| _fail Et9uoLd "install.ps1, pre-releases only" "$(fPsTail)"

	## A real install, in the one-liner form. The shell that ran it keeps its
	## preferences, has no strict mode, and is still there afterward.
	fInList "${psTag}" >"${psFix}/release.json"
	fPsRun "" block -Yes
	psUrls="$(tr '\n' ' ' <"${psFix}/urls.log")"; psU="https://github.com/jim-collier/convert-base-v2/releases/download/${psTag}"
	{ ((psRc == 0)) && [[ -n "${psTag}" && -x "${psBin}" && "$("${psBin}" --version 2>&1)" == "${psVerLine}" && "${psOut}" == *"[ Installed: ${psVerLine} ]"* ]] \
		&& [[ "${psUrls}" == *"/releases?per_page=100 ${psU}/${psAsset} ${psU}/checksums.txt " && "${psOut}" == *"caller still here, EAP=Continue, unset=True"* ]] \
		&& [[ ! -e "${psHome}/.local/bin/.convert-base-v2.new" && -z "$(ls -A "${psDir}/tmp")" ]]; } && _pass Et9uoMI "install.ps1 installs, ${psFrom} release" \
		|| _fail Et9uoMI "install.ps1 installs, ${psFrom} release" "tag=[${psTag}] urls=[${psUrls}] $(fPsTail)"
	mkdir -p "${psHome}/.local/bin"
	for psLine in "convert-base-v2 ${psTag} build abcde" "${psTag} build abcde" "${psTag}"; do
		printf '#!/bin/sh\necho "%s"\n' "${psLine}" >"${psBin}"; chmod +x "${psBin}"
		fPsRun "" file -Yes
		{ ((psRc == 0)) && [[ "${psOut}" == *"is already ${psTag}; nothing to do"* ]]; } && _pass Et9uoMw "install.ps1 sees it's current: ${psLine}" \
			|| _fail Et9uoMw "install.ps1 sees it's current: ${psLine}" "$(fPsTail)"
	done
	rm -f "${psBin}"

	## One changed digit in the asset's checksum.
	awk -v a="${psAsset}" '$2 == a { $1 = (substr($1, 1, 1) == "0" ? "1" : "0") substr($1, 2); print $1 "  " $2; next } { print }' "${psDir}/checksums.good" >"${psFix}/dist/checksums.txt"
	fPsRun "" file -Yes
	{ ((psRc == 1)) && [[ "${psErr}" == *"checksum mismatch"* && ! -e "${psBin}" && ! -e "${psHome}/.local/bin/.convert-base-v2.new" && -z "$(ls -A "${psDir}/tmp")" ]]; } && _pass Et9uoNc "install.ps1 refuses a tampered checksum" \
		|| _fail Et9uoNc "install.ps1 refuses a tampered checksum" "$(fPsTail)"
	cp "${psDir}/checksums.good" "${psFix}/dist/checksums.txt"; rm -f "${psBin}"

	## Refused before any download, with the folder named.
	mkdir -p "${psHome}/.local/bin"; chmod 555 "${psHome}/.local/bin"
	fPsRun "" file -Yes
	chmod 755 "${psHome}/.local/bin"; rm -f "${psBin}"
	{ ((psRc == 1)) && [[ "${psErr}" == *"can't write to ${psHome}/.local/bin - permission denied"* ]] && fPsUntouched; } && _pass Et9uoOI "install.ps1, read-only folder" \
		|| _fail Et9uoOI "install.ps1, read-only folder" "urls=[$(tr '\n' ' ' <"${psFix}/urls.log")] $(fPsTail)"

	## No, a closed stdin, then yes.
	psOk=""
	fPsRun $'n\n' file; { ((psRc == 1)) && [[ "${psOut}" == *"aborted; nothing was touched"* ]] && fPsUntouched; } && psOk+="no "
	fPsRun "" file; { ((psRc == 1)) && [[ "${psOut}" == *"aborted; nothing was touched"* ]] && fPsUntouched; } && psOk+="closed "
	fPsRun $'y\n' file; { ((psRc == 0)) && [[ -x "${psBin}" ]]; } && psOk+="yes"
	[[ "${psOk}" == "no closed yes" ]] && _pass Et9uoOx "install.ps1 prompt" || _fail Et9uoOx "install.ps1 prompt" "passed=[${psOk}] $(fPsTail)"
	rm -f "${psBin}"

	for psCase in "offline|couldn't reach the GitHub API" "notfound|couldn't determine the stable release tag" "nosum|no checksum for ${psAsset} in checksums.txt"; do
		case "${psCase%%|*}" in
			offline) rm -f "${psFix}/release.json" ;;
			notfound) printf '%s\n' '{"message": "Not Found"}' >"${psFix}/release.json" ;;
			nosum) fInList "${psTag}" >"${psFix}/release.json"; grep -v " ${psAsset}\$" "${psDir}/checksums.good" >"${psFix}/dist/checksums.txt" || true ;;
		esac
		fPsRun "" file -Yes
		{ ((psRc == 1)) && [[ "${psErr}" == *"${psCase#*|}"* && ! -e "${psBin}" ]]; } && _pass Et9uoPc "install.ps1 says why: ${psCase#*|}" \
			|| _fail Et9uoPc "install.ps1 says why: ${psCase#*|}" "$(fPsTail)"
	done
	cp "${psDir}/checksums.good" "${psFix}/dist/checksums.txt"
fi

## magick lists pango first, then more than a pipe holds. Any other call
## exits 42, which shows the pango probe passed.
gsDir="${CBT_TMP}/gs"; mkdir -p "${gsDir}/bin" "${gsDir}/repo/lib"
printf '%s\n' '#!/bin/sh' '[ "$1" = -list ] || exit 42' 'echo "PANGO* PANGO r-- Pango Markup Language"' "head -c 1000000 /dev/zero | tr '\\0' x" >"${gsDir}/bin/magick"
printf '%s\n' '#!/bin/sh' 'exit 0' >"${gsDir}/bin/fc-match"
printf '%s\n' '#!/bin/sh' 'echo 0' >"${gsDir}/bin/cbv"
chmod +x "${gsDir}/bin/magick" "${gsDir}/bin/fc-match" "${gsDir}/bin/cbv"
gsrc=0; PATH="${gsDir}/bin:${PATH}" bash "${meDir}/../utility/gen-screenshots.bash" "${gsDir}/repo" "${gsDir}/bin/cbv" >/dev/null 2>"${CBT_ERR}" || gsrc=$?
{ ((gsrc == 42)) && ! grep -qF "lacks the pango delegate" "${CBT_ERR}"; } && _pass Erm3T0v "gen-screenshots pango probe" \
	|| _fail Erm3T0v "gen-screenshots pango probe" "rc=${gsrc} err=[$(tail -3 "${CBT_ERR}")]"

## go version -m names the pinned nfpm, then writes more than a pipe holds.
ptDir="${CBT_TMP}/pt"; mkdir -p "${ptDir}/bin" "${ptDir}/home"
cat >"${ptDir}/bin/go" <<'EOF'
#!/bin/sh
[ "$1" = version ] || exit 0
printf 'nfpm: go1.0\n\tpath\tx\n\tmod\tgithub.com/goreleaser/nfpm/v2\t%s\th1:x\n' "$FAKE_MOD"
head -c 1000000 /dev/zero | tr '\0' x
EOF
printf '%s\n' '#!/bin/sh' >"${ptDir}/bin/nfpm"
chmod +x "${ptDir}/bin/go" "${ptDir}/bin/nfpm"
ptWant="$(sed -n 's/^NFPM_VERSION=//p' "${meDir}/tool-versions.env")"
ptrc=0; ptOut="$(HOME="${ptDir}/home" FAKE_MOD="${ptWant}" PATH="${ptDir}/bin:${PATH}" bash "${meDir}/utility/pin-tools.bash" 2>&1)" || ptrc=$?
{ ((ptrc == 0)) && [[ -n "${ptWant}" && "${ptOut}" != *"installing nfpm"* ]]; } && _pass Erm3T1Z "pin-tools nfpm version" \
	|| _fail Erm3T1Z "pin-tools nfpm version" "rc=${ptrc} want=${ptWant} out=[${ptOut}]"
## shellcheck and ruff are only compared. A version that merely starts with
## the pinned one is a different version.
ptSc="$(sed -n 's/^SHELLCHECK_VERSION=//p' "${meDir}/tool-versions.env")"; ptRuff="$(sed -n 's/^RUFF_VERSION=//p' "${meDir}/tool-versions.env")"
printf '%s\n' '#!/bin/sh' "printf 'ShellCheck\\nversion: ${ptSc}\\nlicense: x\\n'" >"${ptDir}/bin/shellcheck"
printf '%s\n' '#!/bin/sh' "echo 'ruff ${ptRuff}1'" >"${ptDir}/bin/ruff"
chmod +x "${ptDir}/bin/shellcheck" "${ptDir}/bin/ruff"
ptrc=0; ptOut="$(HOME="${ptDir}/home" FAKE_MOD="${ptWant}" PATH="${ptDir}/bin:${PATH}" bash "${meDir}/utility/pin-tools.bash" 2>&1)" || ptrc=$?
{ ((ptrc == 0)) && [[ -n "${ptSc}" && -n "${ptRuff}" && "${ptOut}" == *"WARNING: ruff is not the pinned ${ptRuff}"* && "${ptOut}" != *"shellcheck is not"* ]]; } && _pass Ermt58H "pin-tools: unpinned shellcheck/ruff" \
	|| _fail Ermt58H "pin-tools: unpinned shellcheck/ruff" "rc=${ptrc} out=[${ptOut}]"

## awk -v would read the backslash as an escape and miss the heading.
rbDir="${CBT_TMP}/rb"; mkdir -p "${rbDir}/dist"; rbVer='v9.9.9-b\q'
printf '%s\n' "## ${rbVer} - 2026-10-04" '' '- Backslash.' >"${rbDir}/changelog.md"
rbGot="$(bash "${meDir}/utility/release-notes.bash" --version "${rbVer}" --dist "${rbDir}/dist" --repo o/r --changelog "${rbDir}/changelog.md" 2>/dev/null || true)"
[[ "${rbGot%%$'\n'*}" == "- Backslash." ]] && _pass Erm3T2D "release notes backslash version" \
	|| _fail Erm3T2D "release notes backslash version" "got=[${rbGot%%$'\n'*}]"

## A pin with an empty name. Unchecked, that is a remove of all of thirdparty/.
feDir="${CBT_TMP}/fe"; mkdir -p "${feDir}/bin" "${feDir}/src/pkg" "${feDir}/thirdparty/keep"
echo keep >"${feDir}/thirdparty/keep/file"; echo x >"${feDir}/src/pkg/file"
tar czf "${feDir}/pkg.tgz" -C "${feDir}/src" pkg || true
cp "${meDir}/utility/interop/fetch.bash" "${feDir}/"
printf 'INTEROP_PINS=("|1.0|https://example.invalid/pkg.tgz|%s|example.invalid/pkg")\n' "$(sha256sum "${feDir}/pkg.tgz" | cut -d' ' -f1)" >"${feDir}/pins.env"
printf '%s\n' '#!/bin/sh' 'while [ $# -gt 0 ]; do [ "$1" = -o ] && { cp "$FAKE_TGZ" "$2"; exit 0; }; shift; done' 'exit 7' >"${feDir}/bin/curl"
chmod +x "${feDir}/bin/curl"
ferc=0; FAKE_TGZ="${feDir}/pkg.tgz" PATH="${feDir}/bin:${PATH}" bash "${feDir}/fetch.bash" --refresh >/dev/null 2>"${CBT_ERR}" || ferc=$?
{ ((ferc != 0)) && [[ -f "${feDir}/thirdparty/keep/file" ]] && grep -qF "not a plain directory name" "${CBT_ERR}"; } && _pass Erm3T2q "interop refresh bad pin name" \
	|| _fail Erm3T2q "interop refresh bad pin name" "rc=${ferc} left: [$(fNames "${feDir}/thirdparty")] err=[$(<"${CBT_ERR}")]"

## The benchmark times only runs that worked. A 1 MiB blob and one run keep
## each of these to about a second.
bnFail="${CBT_TMP}/bn-fail"; printf '%s\n' '#!/bin/sh' 'echo "unknown base" >&2' 'exit 1' >"${bnFail}"; chmod +x "${bnFail}"
bnrc=0; BENCH_SIZE_MIB=1 BENCH_RUNS=1 bash "${meDir}/../utility/bench-encoders.bash" "${bnFail}" >/dev/null 2>"${CBT_ERR}" || bnrc=$?
{ ((bnrc != 0)) && grep -qF "bench-encoders: failed:" "${CBT_ERR}"; } && _pass ErmCp2M "bench-encoders failed conversion" \
	|| _fail ErmCp2M "bench-encoders failed conversion" "rc=${bnrc} err=[$(tail -3 "${CBT_ERR}")]"
bnrc=0; BENCH_SIZE_MIB=1 BENCH_RUNS=1 bash "${meDir}/../utility/bench-encoders.bash" "${EXE}" >"${CBT_OUT}" 2>"${CBT_ERR}" || bnrc=$?
{ ((bnrc == 0)) && ! grep -qF "failed:" "${CBT_ERR}" && (($(grep -cE '^\| convert-base-v2 +\|' "${CBT_OUT}" || true) == 3)); } && _pass ErmCp2N "bench-encoders rows" \
	|| _fail ErmCp2N "bench-encoders rows" "rc=${bnrc} err=[$(tail -3 "${CBT_ERR}")]"

## The screenshot script against the real binary, with a magick that draws
## nothing and notes each picture it was asked for.
ssDir="${CBT_TMP}/ss"; mkdir -p "${ssDir}/bin" "${ssDir}/repo/lib"
printf '%s\n' '#!/bin/sh' '[ "$1" = -list ] && { echo "PANGO* PANGO r-- Pango Markup Language"; exit 0; }' 'echo draw >>"$SS_DRAWN"' >"${ssDir}/bin/magick"
printf '%s\n' '#!/bin/sh' 'exit 0' >"${ssDir}/bin/fc-match"
chmod +x "${ssDir}/bin/magick" "${ssDir}/bin/fc-match"
ssrc=0; SS_DRAWN="${ssDir}/drawn" PATH="${ssDir}/bin:${PATH}" bash "${meDir}/../utility/gen-screenshots.bash" "${ssDir}/repo" "${EXE}" >/dev/null 2>"${CBT_ERR}" || ssrc=$?
{ ((ssrc == 0)) && [[ ! -s "${CBT_ERR}" ]]; } && _pass ErmCp2O "gen-screenshots scenes" \
	|| _fail ErmCp2O "gen-screenshots scenes" "rc=${ssrc} err=[$(head -3 "${CBT_ERR}")]"
: >"${ssDir}/drawn"
ssrc=0; SS_DRAWN="${ssDir}/drawn" PATH="${ssDir}/bin:${PATH}" bash "${meDir}/../utility/gen-screenshots.bash" "${ssDir}/repo" "${bnFail}" >/dev/null 2>"${CBT_ERR}" || ssrc=$?
{ ((ssrc != 0)) && [[ ! -s "${ssDir}/drawn" ]]; } && _pass ErmCp2P "gen-screenshots stops on failure" \
	|| _fail ErmCp2P "gen-screenshots stops on failure" "rc=${ssrc} drawn: $(wc -l <"${ssDir}/drawn")"

## The demo gif encodes frames in batches as they come. A real render takes over
## a minute, so its Movie is fed made-up frames: small ones across many batch
## edges against one Pillow save of the same frames, then 400 full-size ones
## whose peak memory must stay under half of what holding them all would take.
## A one-word command types at the same pace as the first word of a longer one.
dgDir="${CBT_TMP}/dg"; mkdir -p "${dgDir}"
dgrc=0; python3 -B - "${meDir}/utility/gen-demo-gif.py" "${dgDir}" >"${CBT_OUT}" 2>"${CBT_ERR}" <<'EOF' || dgrc=$?
import importlib.util, random, resource, sys
spec = importlib.util.spec_from_file_location("gendemogif", sys.argv[1])
gd = importlib.util.module_from_spec(spec)
try:
	spec.loader.exec_module(gd)
except SystemExit:
	sys.exit(3)
from PIL import Image, ImageDraw
outDir = sys.argv[2]
pal = gd.build_palette((196, 148, 108), (160, 136, 200), []).getpalette()

def fCanvas(w, h):
	img = Image.new("P", (w, h), 5)
	img.putpalette(pal)
	return img

try:
	w, h, n = gd.CANVAS_W, gd.CANVAS_H, 400
	canvas = fCanvas(w, h)
	before = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
	mov = gd.Movie()
	for i in range(n):
		ImageDraw.Draw(canvas).rectangle([i * 2, 100, i * 2 + 9, 120], fill=6)
		mov.add(canvas.copy(), 20)
	mov.save(f"{outDir}/mem.gif")
	grewMiB = (resource.getrusage(resource.RUSAGE_SELF).ru_maxrss - before) / 1024
	heldMiB = n * w * h / 2**20
	print(f"memory {'ok' if grewMiB < heldMiB / 2 else 'FAIL'} grew {grewMiB:.0f} MiB, all frames {heldMiB:.0f} MiB")
except Exception as e:
	print(f"memory FAIL {e!r}")

class OldMovie:
	##	The single-save Movie from before batching, as the reference.
	def __init__(self):
		self.frames, self.durs, self._rem = [], [], 0.0
	def add(self, img, ms):
		ms += self._rem
		dur = max(20, int(round(ms / 10.0)) * 10)
		self._rem = ms - dur if ms > 20 else 0.0
		if self.frames and img.tobytes() == self.frames[-1].tobytes():
			self.durs[-1] += dur
		else:
			self.frames.append(img)
			self.durs.append(dur)

try:
	rng, bad = random.Random(7), []
	for n in (1, 2, 3, 4, 5, 7, 8, 60):
		canvas, mov, old = fCanvas(64, 48), gd.Movie(), OldMovie()
		mov.BATCH = 3
		for i in range(n):
			if i == 0 or rng.random() > 0.2:
				x, y = rng.randrange(64), rng.randrange(48)
				ImageDraw.Draw(canvas).rectangle([x, y, x + rng.randrange(1, 40), y + rng.randrange(1, 30)], fill=rng.randrange(40))
			ms = rng.uniform(5, 700)
			mov.add(canvas.copy(), ms)
			old.add(canvas.copy(), ms)
		mov.save(f"{outDir}/new{n}.gif")
		old.frames[0].save(f"{outDir}/old{n}.gif", format="GIF", save_all=True, append_images=old.frames[1:], duration=old.durs, loop=0, optimize=False)
		with open(f"{outDir}/new{n}.gif", "rb") as f1, open(f"{outDir}/old{n}.gif", "rb") as f2:
			if f1.read() != f2.read() or mov.durs != old.durs:
				bad.append(n)
	print(f"identity {'ok' if not bad else 'FAIL'} {bad or ''}")
except Exception as e:
	print(f"identity FAIL {e!r}")

try:
	alone = [e.delay for e in gd.type_events("cat", random.Random(5), (180, 180), typos=False)]
	first = [e.delay for e in gd.type_events("cat x", random.Random(5), (180, 180), typos=False)][:3]
	print(f"leadword {'ok' if alone == first else 'FAIL'} {alone} {first}")
except Exception as e:
	print(f"leadword FAIL {e!r}")
EOF
if ((dgrc == 3)); then
	_warn "ErmYENq ErmYEP0 ErnEi9h" "demo gif checks: no Pillow"
else
	grep -q "^identity ok" "${CBT_OUT}" && _pass ErmYENq "demo gif batches match one Pillow save" \
		|| _fail ErmYENq "demo gif batches match one Pillow save" "rc=${dgrc} out=[$(<"${CBT_OUT}")] err=[$(tail -3 "${CBT_ERR}")]"
	grep -q "^memory ok" "${CBT_OUT}" && _pass ErmYEP0 "demo gif frame memory" \
		|| _fail ErmYEP0 "demo gif frame memory" "rc=${dgrc} out=[$(<"${CBT_OUT}")] err=[$(tail -3 "${CBT_ERR}")]"
	grep -q "^leadword ok" "${CBT_OUT}" && _pass ErnEi9h "demo gif one-word typing" \
		|| _fail ErnEi9h "demo gif one-word typing" "rc=${dgrc} out=[$(<"${CBT_OUT}")] err=[$(tail -3 "${CBT_ERR}")]"
fi

## Demo commands run in a home of their own, after the scenario's setup=, so the
## gif never shows the config of whoever renders it. The setup only passes in a
## private home, and the step leaves a mark in the real one only if it saw the
## setup's file. The private home is gone afterward.
dhDir="${CBT_TMP}/dh"; mkdir -p "${dhDir}/home" "${dhDir}/tmp"
cat >"${dhDir}/sc.toml" <<'EOF'
end_hold = 0.1
end_black = 0.1
setup = '[ "$HOME" != "$DH_REAL" ] && [ "$XDG_CONFIG_HOME" = "$HOME/.config" ] && mkdir -p "$XDG_CONFIG_HOME" && touch "$XDG_CONFIG_HOME/made"'
[[step]]
show = "true"
run = '[ -e "$XDG_CONFIG_HOME/made" ] && touch "$DH_REAL/step-saw-setup"'
EOF
if ((dgrc == 3)); then
	_warn "EsJpWap EsKCVWy" "demo gif private home and missing glyphs: no Pillow"
else
	dhrc=0; HOME="${dhDir}/home" DH_REAL="${dhDir}/home" TMPDIR="${dhDir}/tmp" python3 -B "${meDir}/utility/gen-demo-gif.py" --quiet \
		--scenario "${dhDir}/sc.toml" --out "${dhDir}/out.gif" --bin true >"${CBT_OUT}" 2>&1 || dhrc=$?
	{ ((dhrc == 0)) && [[ -e "${dhDir}/home/step-saw-setup" && ! -e "${dhDir}/home/.config" && -z "$(ls -A "${dhDir}/tmp")" ]]; } && _pass EsJpWap "demo gif private home, after setup=" \
		|| _fail EsJpWap "demo gif private home, after setup=" "rc=${dhrc} home=[$(ls -A "${dhDir}/home")] tmp=[$(ls -A "${dhDir}/tmp")] out=[$(tail -2 "${CBT_OUT}")]"
	## A char no font has would show as a box, so it fails before anything renders.
	printf '%s\n' 'end_hold = 0.1' 'end_black = 0.1' '[[step]]' 'show = "true"' 'run = "printf \"a\\U0010FFFDb\""' >"${dhDir}/nofont.toml"
	dhrc=0; TMPDIR="${dhDir}/tmp" python3 -B "${meDir}/utility/gen-demo-gif.py" --quiet \
		--scenario "${dhDir}/nofont.toml" --out "${dhDir}/nofont.gif" --bin true >"${CBT_OUT}" 2>&1 || dhrc=$?
	{ ((dhrc == 1)) && grep -qF 'no font draws U+10FFFD' "${CBT_OUT}" && [[ ! -e "${dhDir}/nofont.gif" ]]; } && _pass EsKCVWy "demo gif missing glyph" \
		|| _fail EsKCVWy "demo gif missing glyph" "rc=${dhrc} out=[$(tail -2 "${CBT_OUT}")]"
fi

## flame-report.py is the startup gate's reader. A flamegraph it can't read is
## a skip, exit 2, never a traceback. Root reads a mode-000 file anyway, so
## that case only runs where the mode holds.
frDir="${CBT_TMP}/fr"; mkdir -p "${frDir}"
printf '<svg total_samples="9">\xff\xfe</svg>\n' >"${frDir}/flame_20260101-000000_latest.svg"
printf '<svg total_samples="9"></svg>\n' >"${frDir}/locked.svg"; chmod 000 "${frDir}/locked.svg"
frCases=("${frDir}/flame_20260101-000000_latest.svg")
[[ -r "${frDir}/locked.svg" ]] || frCases+=("${frDir}/locked.svg")
for frFile in "${frCases[@]}"; do
	frrc=0; python3 "${meDir}/utility/flame-report.py" --file "${frFile}" >/dev/null 2>"${CBT_ERR}" || frrc=$?
	{ ((frrc == 2)) && ! grep -qF "Traceback" "${CBT_ERR}"; } && _pass Ermz79l "flame-report unreadable svg: ${frFile##*/}" \
		|| _fail Ermz79l "flame-report unreadable svg: ${frFile##*/}" "rc=${frrc} err=[$(tail -2 "${CBT_ERR}")]"
done
chmod 600 "${frDir}/locked.svg"
## The divide and conquer parse and format, and what they call, are big-int
## time. Every frame here has self time only in those.
frPkg="github.com/jim-collier/convert-base-v2/lib/convertbase"
{
	printf '<svg total_samples="100">\n'
	for frFrame in "all 100 0 100" "${frPkg}.parseDigits 84 0 40" "${frPkg}.newDCState 68 0 10" "${frPkg}.wordChunk 52 0 10" \
		"${frPkg}.(*dcState).parse 68 10 30" "${frPkg}.(*dcState).parseLeaf 52 10 30" "${frPkg}.formatDigits 84 40 60" \
		"${frPkg}.(*dcState).growPows 68 40 10" "${frPkg}.(*dcState).format 68 50 50" "${frPkg}.(*dcState).formatLeaf 52 50 50"; do
		read -r frName frY frX frW <<<"${frFrame}"
		printf '<g><title>%s (%s samples)</title><rect x="0" y="%s" width="1" height="15" fg:x="%s" fg:w="%s"/></g>\n' "${frName}" "${frW}" "${frY}" "${frX}" "${frW}"
	done
	printf '</svg>\n'
} >"${frDir}/flame_20260101-000001_latest.svg"
frrc=0; python3 "${meDir}/utility/flame-report.py" --file "${frDir}/flame_20260101-000001_latest.svg" >"${CBT_OUT}" 2>"${CBT_ERR}" || frrc=$?
{ ((frrc == 0)) && grep -qE '^  big-int, math/big convert\.*: 100\.0%$' "${CBT_OUT}"; } && _pass Ermz7AQ "flame-report big-int bucket" \
	|| _fail Ermz7AQ "flame-report big-int bucket" "rc=${frrc} out=[$(head -8 "${CBT_OUT}" | tr '\n' ' ')] err=[$(tail -2 "${CBT_ERR}")]"

## test-ids.py reads test.bash by pattern. An array of command words is not a
## test call, while a call inside a subshell still is. It runs from a copy, so
## the fixture can stand in for test.bash.
tiDir="${CBT_TMP}/ti"; mkdir -p "${tiDir}/cicd/utility"
cp "${meDir}/utility/test-ids.py" "${tiDir}/cicd/utility/"
{
	printf '%s\n' 'RUFF_CMD=(ruff check .)' 'scCmd=(check -x)' 'lintArgs+=(_fail --quiet)' '_pass Ermz7B4 "kept"'
	printf '%s _pass Ermz7B5 "kept in a subshell" )\n' '('
} >"${tiDir}/cicd/test.bash"
tirc=0; tiOut="$(python3 "${tiDir}/cicd/utility/test-ids.py" check 2>&1)" || tirc=$?
{ ((tirc == 0)) && [[ "${tiOut}" == "OK: 2 test IDs, all distinct" ]]; } && _pass Ermz7B5 "test-ids bash array" \
	|| _fail Ermz7B5 "test-ids bash array" "rc=${tirc} out=[${tiOut}]"

## Go tests are keyed by import path, since two packages can share a directory
## name. A compile error prints under the package it broke.
tgDir="${CBT_TMP}/tg"; mkdir -p "${tgDir}/cicd/utility" "${tgDir}/a/util" "${tgDir}/b/util"
cp "${meDir}/utility/test-ids.py" "${tgDir}/cicd/utility/"
printf '%s\n' '_pass Ermz7B4 "kept"' >"${tgDir}/cicd/test.bash"
printf 'module example.com/m\n' >"${tgDir}/go.mod"
printf '%s\n' 'package util' '' '// Test ID: Ermz7Ba' 'func TestSame(t *testing.T) {}' >"${tgDir}/a/util/x_test.go"
printf '%s\n' 'package util' '' '// Test ID: Ermz7Bb' 'func TestSame(t *testing.T) {}' >"${tgDir}/b/util/x_test.go"
tgrc=0; tgOut="$(python3 "${tgDir}/cicd/utility/test-ids.py" check 2>&1)" || tgrc=$?
tgRep="$(printf '%s\n' '{"Action":"pass","Package":"example.com/m/a/util","Test":"TestSame"}' '{"Action":"pass","Package":"example.com/m/b/util","Test":"TestSame"}' \
	| python3 "${tgDir}/cicd/utility/test-ids.py" report 2>&1 || true)"
{ ((tgrc == 0)) && [[ "${tgOut}" == "OK: 3 test IDs, all distinct" ]] && grep -qF "Ermz7Ba  TestSame (util)" <<<"${tgRep}" && grep -qF "Ermz7Bb  TestSame (util)" <<<"${tgRep}"; } \
	&& _pass ErnEiAv "test-ids same-name packages" \
	|| _fail ErnEiAv "test-ids same-name packages" "rc=${tgrc} check=[${tgOut}] report=[$(tr '\n' ' ' <<<"${tgRep}")]"
tgRep="$(printf '%s\n' '{"ImportPath":"example.com/m/a/util [example.com/m/a/util.test]","Action":"build-output","Output":"a/util/x_test.go:4:1: undefined: oops\n"}' \
	'{"ImportPath":"example.com/m/a/util [example.com/m/a/util.test]","Action":"build-fail"}' '{"Action":"fail","Package":"example.com/m/a/util"}' \
	| python3 "${tgDir}/cicd/utility/test-ids.py" report 2>&1 || true)"
grep -qF "undefined: oops" <<<"${tgRep}" && _pass ErnEiCC "test-ids compile error" \
	|| _fail ErnEiCC "test-ids compile error" "report=[$(tr '\n' ' ' <<<"${tgRep}")]"
## A race report is longer than the usual tail, and its top says where the race
## is, so it shows from there. The same goes for goleak's list after the tests.
tgRep="$( {
	printf '%s\n' '{"Action":"output","Package":"example.com/m/a/util","Test":"TestSame","Output":"WARNING: DATA RACE\n"}' \
		'{"Action":"output","Package":"example.com/m/a/util","Test":"TestSame","Output":"Write at 0x00c by goroutine 7:\n"}'
	for i in $(seq 30); do printf '{"Action":"output","Package":"example.com/m/a/util","Test":"TestSame","Output":"  frame %s\\n"}\n' "$i"; done
	printf '%s\n' '{"Action":"fail","Package":"example.com/m/a/util","Test":"TestSame"}' \
		'{"Action":"output","Package":"example.com/m/b/util","Output":"goleak: Errors on successful test run: found unexpected goroutines:\n"}'
	for i in $(seq 30); do printf '{"Action":"output","Package":"example.com/m/b/util","Output":"  leaked %s\\n"}\n' "$i"; done
	printf '%s\n' '{"Action":"fail","Package":"example.com/m/b/util"}'
} | python3 "${tgDir}/cicd/utility/test-ids.py" report 2>&1 || true)"
{ grep -qF "Write at 0x00c by goroutine 7" <<<"${tgRep}" && grep -qF "frame 30" <<<"${tgRep}" && grep -qF "goleak: Errors on successful test run" <<<"${tgRep}"; } \
	&& _pass Et9WfaT "test-ids race and leak reports from the top" \
	|| _fail Et9WfaT "test-ids race and leak reports from the top" "report=[$(tr '\n' ' ' <<<"${tgRep}")]"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## CI engine. cicd.bash runs from a copy with a stub config, so every stage is
## off or fake. The fake harness writes down the knobs it was handed, the fake
## go fuzzes as FAKE_FUZZ says, and cp fails for anything under CE_CPFAIL.
section "CI engine"
ceDir="${CBT_TMP}/ce"; ceRepo="${ceDir}/repo"; ceBin="${ceDir}/bin"
mkdir -p "${ceRepo}/cicd/utility/include" "${ceRepo}/lib" "${ceBin}" "${ceDir}/home/bin" "${ceDir}/sys" "${ceDir}/tmp"
cp "${meDir}/cicd.bash" "${ceRepo}/cicd/"; cp "${meDir}/utility/include/gfs-rotate.bash" "${meDir}/utility/include/machine-use.bash" "${ceRepo}/cicd/utility/include/"
printf '%s\n' '#!/bin/sh' 'echo v0.0.0' >"${ceRepo}/lib/out"; chmod +x "${ceRepo}/lib/out"
cat >"${ceRepo}/cicd/config.bash" <<'EOF'
APP_NAME="cbv-test"; EXE_NAME="cbv-test"; SRC_DIR="lib"
FMT_CMD=(); NATIVE_BUILD_CMD=(true); NATIVE_BUILD_OUT="lib/out"; STAGED_BIN="lib/bin/cbv-test"; RELEASE_BUILD_CMD=()
PIN_TOOLS_CMD=(); VENDOR_CHECK_CMD=(); INTEROP_CHECK_CMD=(); VET_CMD=(); LINT_CMD=(); STATICCHECK_CMD=()
UNIT_TEST_CMD=(true); TEST_ID_CMD=(); TEST_CMD=(sh -c 'env | grep "^CICDTEST_" | sort >"$CE_KNOBS"')
GO_TEST_PKG="."; FUZZ_ENABLE=1; FUZZ_TIME="1s"; FUZZ_TIME_QUICK="1s"; FUZZ_MINIMIZE_TIME="1s"; FUZZ_MINIMIZE_TIME_QUICK="1s"
VULN_PROBE=(false); VULN_CMD=(${CE_VULN:+true}); PROFILE_ENABLE=0; PROFILE_OUT_DIR="prof"; LINT_LOG_DIR=""; BUILD_CROSS=${CE_CROSS:-0}; RELEASE_ARTIFACT_DIR="dist"
RELEASE_CMD=(sh -c 'mkdir -p dist && echo "win $$" >dist/cbv-test-windows-x86_64.exe && echo "mac $$" >dist/cbv-test-darwin-universal')
CONTAINER_DIR="cicd/container"; CONTAINER_IMAGE="cbv-test-cicd"; CONTAINER_VOLUME="cbv-test-cache"; CONTAINER_MOUNTS=("demos" "nowhere")
CONTAINER_DEFAULT=${CE_CONTAINER_DEFAULT:-0}; CONTAINER_CONTEXTS=("ctx=${CE_CTX:-ctxdir}"); CONTAINER_CONTEXT_MISSING=(--no-demogif)
DOGFOOD_FIXED_DESTS=(${CE_DEST:+"${CE_DEST}"}); DOGFOOD_CROSS=(); DOGFOOD_LOCAL="${CE_LOCAL:-}"
DO_SCREENSHOTS=0; SCREENSHOT_CMD=(none); DO_DEMOGIF=${CE_GIF:-0}; DEMOGIF_CMD=(gif.py); DEMOGIF_OUT="gif/demo.gif"; DEMOGIF_ARCHIVE_DIR="gif/old"; DEMOGIF_CONTAINER_ONLY=1
PREPUBLISH_HOOK=""; GIT_PUBLISH=(); PUBLISH_AUTO_MESSAGE=""
[[ -z "${CE_NET:-}" ]] || { VENDOR_CHECK_CMD=(echo vendor-net); INTEROP_CHECK_CMD=(echo interop-net); VULN_PROBE=(true); VULN_CMD=(echo vuln-net); }
RACE_PROBE=("${CE_RACE_PROBE:-true}"); RACE_TEST_CMD=(echo race-ran); SOAK_CMD=(sh -c 'echo "soak-ran $CICD_SOAK_OUT"'); SOAK_OUT_DIR="soak"
CODEQL_PROBE=("${CE_CODEQL_PROBE:-true}"); CODEQL_CMD=(sh -c 'echo "codeql-ran $1"; exit "${CE_CODEQL_RC:-0}"' sh); CODEQL_OUT_DIR="codeql"
## Each stand-in writes down the job counts it was handed. The harness can make
## the box busy partway, for the steps after it.
if [[ -n "${CE_JOBS:-}" ]]; then
	TEST_CMD=(sh -c 'echo "harness GOMAXPROCS=$GOMAXPROCS GOFLAGS=$GOFLAGS CARGO_BUILD_JOBS=$CARGO_BUILD_JOBS RAYON_NUM_THREADS=$RAYON_NUM_THREADS CPU_CAP=$CPU_CAP GO19CONCURRENTCOMPILATION=$GO19CONCURRENTCOMPILATION" >>"$CE_JOBS"
		echo "nice=$(nice) io=$(ionice -p $$ 2>/dev/null || echo none)" >>"$CE_JOBS"
		if [ -n "${CE_LOAD_LATER:-}" ]; then echo "$CE_LOAD_LATER 1.00 1.00 1/100 1" >"$CICD_LOADAVG_FILE"; fi')
	VET_CMD=(true); LINT_PROBE=(true); LINT_CMD=(sh -c 'echo "lint $*" >>"$CE_JOBS"' sh); LINT_JOBS_FLAG="--concurrency"
	RACE_TEST_CMD=(sh -c 'echo "race GOMAXPROCS=$GOMAXPROCS GOFLAGS=$GOFLAGS" >>"$CE_JOBS"')
	SOAK_CMD=(sh -c 'echo "soak GOMAXPROCS=$GOMAXPROCS" >>"$CE_JOBS"')
	CODEQL_CMD=(sh -c 'echo "codeql GOMAXPROCS=$GOMAXPROCS" >>"$CE_JOBS"' sh)
	BUILD_CROSS=1; RELEASE_CMD=(sh -c 'echo "cross GOMAXPROCS=$GOMAXPROCS" >>"$CE_JOBS"; mkdir -p dist && echo x >dist/cbv-test-windows-x86_64.exe')
fi
EOF
cat >"${ceBin}/go" <<'EOF'
#!/bin/sh
case "$*" in
	*-list*) echo FuzzA ;;
	*-fuzz*)
		if [ -n "${CE_JOBS:-}" ]; then echo "fuzz GOMAXPROCS=$GOMAXPROCS $*" >>"$CE_JOBS"; fi
		echo "--- FAIL: FuzzA"
		case "${FAKE_FUZZ:-}" in
			deadline) echo "    context deadline exceeded"; exit 1 ;;
			find) echo "    Failing input written to testdata/fuzz/FuzzA/0123"; exit 1 ;;
		esac ;;
esac
exit 0
EOF
printf '%s\n' '#!/bin/sh' 'for a; do last="$a"; done' \
	'if [ -n "${CE_CPFAIL:-}" ]; then case "$last" in "$CE_CPFAIL"/*) echo "cp: fake failure" >&2; exit 1 ;; esac; fi' \
	"exec $(command -v cp) \"\$@\"" >"${ceBin}/cp"
printf '%s\n' '#!/bin/sh' 'echo "$*" >>"$CE_SUDO_LOG"' 'exit 1' >"${ceBin}/sudo"
## Three older tags of the image, a dangling image and a container of the run,
## all as if labeled, for the cleanup to find.
cat >"${ceBin}/docker" <<'EOF'
#!/bin/sh
echo "$*" >>"$CE_DOCKER_LOG"
case "$1 $2" in
	version*) exit "${CE_DAEMON_RC:-0}" ;;
	"image inspect")
		case "$*" in
			*LastTagTime*) case "$*" in *0ld0ld*) echo 100 ;; *pr3v10us*) echo 200 ;; *zzz*) echo 50 ;; *) echo 300 ;; esac ;;
			*) [ -n "${CE_HAVE_IMAGE:-}" ]; exit $? ;;
		esac ;;
	"image ls")
		case "$*" in
			*dangling=true*) echo d4ngl3d4ngl3 ;;
			*--format*) printf '%s\n' cbv-test-cicd:0ld0ld0ld0ld cbv-test-cicd:zzz000000000 cbv-test-cicd:pr3v10us0000 ;;
		esac ;;
	"ps -aq") echo c0ffeec0ffee ;;
	"ps -a") echo cbv-test-kept ;;
	"volume inspect")
		[ -n "${CE_HAVE_VOL:-}" ] || exit 1
		case "$*" in *--format*) echo "${CE_VOL_PROJ:-}" ;; esac ;;
	"system df") case "$*" in *" -v "*) echo "cbv-test-cache ${CE_VOL_SIZE:-1.5GB}" ;; *) printf '%s\n' 1GB 2.5GB ;; esac ;;
	"builder prune") printf 'Total:\t12.5MB\n' ;;
	build*)
		if [ -n "${CE_BUILD_SIGINT:-}" ]; then kill -INT "$PPID"; exit 1; fi
		exit "${CE_BUILD_RC:-0}" ;;
	run*)
		## Ctrl+C reaches the pipeline and this, its foreground child. The real
		## one passes it to the container and exits 130 when that does.
		case "${CE_RUN_SIGINT:-}" in
			self) kill -INT "$PPID"; kill -INT $$ ;;
			proxy) kill -INT "$PPID"; exit 130 ;;
		esac
		echo "inner run"; exit "${CE_RUN_RC:-0}" ;;
esac
exit 0
EOF
## A pipeline killed by Ctrl+C would take this harness down with it, the way
## bash treats a child that died of SIGINT, so that run goes through this.
printf '%s\n' 'import subprocess, sys' 'rc = subprocess.run(sys.argv[1:]).returncode' 'sys.exit(128 - rc if rc < 0 else rc)' >"${ceBin}/nosig.py"
chmod +x "${ceBin}/go" "${ceBin}/cp" "${ceBin}/sudo" "${ceBin}/docker"
mkdir -p "${ceRepo}/cicd/container" "${ceDir}/demos-real"
printf '%s\n' 'FROM scratch' >"${ceRepo}/cicd/container/Dockerfile"
printf '%s\n' '## pins' 'FOO_VERSION=1.2' >"${ceRepo}/cicd/tool-versions.env"
ln -s "${ceDir}/demos-real" "${ceRepo}/demos"
mkdir -p "${ceRepo}/ctxdir"; : >"${ceRepo}/ctxdir/font.ttf"
## Stands in for the gif tool, run as python3 gif.py --out OUT --bin BIN.
printf '%s\n' 'import sys' 'open(sys.argv[sys.argv.index("--out") + 1], "w").write("gif")' >"${ceRepo}/gif.py"
mkdir -p "${ceRepo}/gif"
## Knobs from whatever runs this harness must not leak into the copy.
fCeRun(){
	: >"${ceDir}/knobs"; : >"${ceDir}/sudo.log"; : >"${ceDir}/docker.log"; ceRc=0
	local -a ceWrap=(); if [[ -n "${CE_WRAP:-}" ]]; then ceWrap=(python3 "${ceBin}/nosig.py"); fi
	## nproc takes its count from OMP_NUM_THREADS when that's set.
	local -a ceMachine=()
	if [[ -n "${CE_NPROC:-}" ]]; then ceMachine+=("OMP_NUM_THREADS=${CE_NPROC}"); fi
	if [[ -n "${CE_LOADAVG:-}" ]]; then ceMachine+=("CICD_LOADAVG_FILE=${CE_LOADAVG}"); fi
	if [[ -n "${CE_JOBS_MAX:-}" ]]; then ceMachine+=("CICD_JOBS_MAX=${CE_JOBS_MAX}"); fi
	if [[ -n "${CE_GOFLAGS:-}" ]]; then ceMachine+=("GOFLAGS=${CE_GOFLAGS}"); fi
	( cd "${ceDir}" && env -u CICDTEST_EXE -u CICDTEST_DO_LONGTEST -u CICDTEST_DO_PERF -u CICDTEST_QUICK \
		-u OMP_NUM_THREADS -u CICD_LOADAVG_FILE -u CICD_JOBS_MAX -u GOFLAGS -u CPU_CAP "${ceMachine[@]}" \
		HOME="${ceDir}/home" TMPDIR="${ceDir}/tmp" PATH="${ceBin}:${PATH}" CE_KNOBS="${ceDir}/knobs" CE_SUDO_LOG="${ceDir}/sudo.log" \
		CICD_NO_SKIP="${CE_NO_SKIP:-0}" CICD_IN_CONTAINER="${CE_INSIDE:-0}" CICD_DOCKER="${CE_DOCKER:-${ceBin}/docker}" CE_DOCKER_LOG="${ceDir}/docker.log" \
		CICD_IMAGE_PREBUILT="${CE_PREBUILT:-0}" "${ceWrap[@]}" bash "${ceRepo}/cicd/cicd.bash" "$@" </dev/null >"${CBT_OUT}" 2>&1 ) || ceRc=$?
	ceOut="$(<"${CBT_OUT}")"; ceKnobs="$(<"${ceDir}/knobs")"; ceSudo="$(<"${ceDir}/sudo.log")"; ceTmp="$(ls -A "${ceDir}/tmp")"
	ceDocker="$(<"${ceDir}/docker.log")"
}
fCeTail(){ printf 'rc=%s tmp=[%s] out=[%s]' "${ceRc}" "${ceTmp}" "$(tail -4 "${CBT_OUT}" | tr '\n' ' ')"; }

## Go reports its own -fuzztime deadline as a failure (G18): that passes with a
## note, and a real find fails the stage with its own message.
FAKE_FUZZ=deadline fCeRun -y
{ ((ceRc == 0)) && [[ "${ceOut}" == *"NOTE: fuzz FuzzA reported the -fuzztime deadline"* && -z "${ceTmp}" ]]; } && _pass ErmCp2E "fuzz deadline note" \
	|| _fail ErmCp2E "fuzz deadline note" "$(fCeTail)"
FAKE_FUZZ="find" fCeRun -y
{ ((ceRc == 1)) && [[ "${ceOut}" == *"FAILED: fuzz FuzzA found a failure"* && "${ceOut}" != *"CICD ABORTED"* && -z "${ceTmp}" ]]; } && _pass ErmCp2F "fuzz find fails stage" \
	|| _fail ErmCp2F "fuzz find fails stage" "$(fCeTail)"

## The harness runs its perf section, and skips the packaging rebuilds, as
## --quick says. A plain -y run also keeps its plan and progress lines; -q drops them.
fCeRun -y; ceKnobsFull="${ceKnobs}"; ceOutFull="${ceOut}"
fCeRun -y --quick; ceKnobsQuick="${ceKnobs}"
for ceName in Full Quick; do
	ceVar="ceKnobs${ceName}"; ceWant=1; [[ "${ceName}" == Quick ]] && ceWant=0
	grep -qxF "CICDTEST_DO_PERF=${ceWant}" <<<"${!ceVar}" && _pass ErmCp2G "harness perf section asked for: ${ceName} run, ${ceWant}" \
		|| _fail ErmCp2G "harness perf section asked for: ${ceName} run, ${ceWant}" "knobs=[${!ceVar}]"
done
{ grep -qxF "CICDTEST_QUICK=1" <<<"${ceKnobsQuick}" && grep -qxF "CICDTEST_QUICK=0" <<<"${ceKnobsFull}"; } && _pass ErmCp2H "--quick reaches the harness" \
	|| _fail ErmCp2H "--quick reaches the harness" "full=[${ceKnobsFull}] quick=[${ceKnobsQuick}]"
## A plain run has the long tests, and --quick leaves them out unless --long
## is named too, before or after it.
ceLong=""
for ceArgs in "-y" "-y --quick" "-y --quick --long" "-y --long --quick"; do
	fCeRun ${ceArgs}; ceLong+="$(grep -oxE 'CICDTEST_DO_LONGTEST=[01]' <<<"${ceKnobs}" || echo none);"
done
[[ "${ceLong}" == "CICDTEST_DO_LONGTEST=1;CICDTEST_DO_LONGTEST=0;CICDTEST_DO_LONGTEST=1;CICDTEST_DO_LONGTEST=1;" ]] && _pass Et9RcGQ "long tests: plain on, --quick off, --long back on" \
	|| _fail Et9RcGQ "long tests: plain on, --quick off, --long back on" "got=[${ceLong}]"

## --quick still cross-compiles, and --no-cross wins in either order.
rm -rf "${ceRepo}/dist"; CE_CROSS=1 fCeRun -y --quick; ceQuickCross=0
{ ((ceRc == 0)) && [[ -f "${ceRepo}/dist/cbv-test-windows-x86_64.exe" && "${ceOut}" == *"OK: release artifacts"* ]]; } && ceQuickCross=1
rm -rf "${ceRepo}/dist"; CE_CROSS=1 fCeRun -y --no-cross --quick; ceNoCross="${ceRc}"
CE_CROSS=1 fCeRun -y --quick --no-cross
{ ((ceQuickCross && ceNoCross == 0 && ceRc == 0)) && [[ ! -e "${ceRepo}/dist" && "${ceOut}" == *"cross + package skipped"* ]]; } && _pass Et9RcH7 "--quick cross-compiles, --no-cross wins" \
	|| _fail Et9RcH7 "--quick cross-compiles, --no-cross wins" "quick made it: ${ceQuickCross}; $(fCeTail)"
rm -rf "${ceRepo}/dist"

## A plain run has the leak checks, -q included, and --quick leaves them out unless
## --leakcheck is named too, before or after it. The gate never runs them.
ceLeak=""
for ceArgs in "-y" "-q" "-y --quick" "-y --quick --leakcheck" "-y --leakcheck --quick" "--gate"; do
	fCeRun ${ceArgs}; ceLeak+="$(grep -cxE "race-ran|soak-ran ${ceRepo}/soak|codeql-ran ${ceRepo}/codeql/codeql_[0-9]{8}-[0-9]{6}\.sarif" <<<"${ceOut}" || true);"
done
{ [[ "${ceLeak}" == "3;3;0;3;3;0;" && -d "${ceRepo}/soak" && -d "${ceRepo}/codeql" ]]; } && _pass Et9VxXX "leak checks: plain on, --quick off, --leakcheck back on, not in the gate" \
	|| _fail Et9VxXX "leak checks: plain on, --quick off, --leakcheck back on, not in the gate" "got=[${ceLeak}] $(fCeTail)"
## --no-leakcheck drops them from a full run, and the last of the pair wins.
ceNoLeak=""
for ceArgs in "-y --no-leakcheck" "-y --leakcheck --no-leakcheck" "-y --no-leakcheck --leakcheck"; do
	fCeRun ${ceArgs}; ceNoLeak+="${ceRc}:$(grep -cxE "race-ran|soak-ran ${ceRepo}/soak|codeql-ran ${ceRepo}/codeql/codeql_[0-9]{8}-[0-9]{6}\.sarif" <<<"${ceOut}" || true);"
done
[[ "${ceNoLeak}" == "0:0;0:0;0:3;" ]] && _pass EtAaLOQ "--no-leakcheck skips the leak checks, last flag wins" \
	|| _fail EtAaLOQ "--no-leakcheck skips the leak checks, last flag wins" "got=[${ceNoLeak}] $(fCeTail)"
## -race needs cgo. Without it the race run warns and the soak test still runs,
## except where every tool must be there.
CE_RACE_PROBE=false fCeRun -y --quick --leakcheck; ceNoCgo=0
{ ((ceRc == 0)) && [[ "${ceOut}" == *"WARNING: race detector skipped"* ]] && grep -q '^soak-ran ' <<<"${ceOut}" && ! grep -qx 'race-ran' <<<"${ceOut}"; } && ceNoCgo=1
CE_RACE_PROBE=false CE_NO_SKIP=1 fCeRun -y --quick --leakcheck
{ ((ceNoCgo && ceRc == 1)) && [[ "${ceOut}" == *"FAILED: race detector skipped"* ]]; } && _pass Et9VxYy "race detector without cgo" \
	|| _fail Et9VxYy "race detector without cgo" "warned=${ceNoCgo} $(fCeTail)"
## CodeQL is a leak check too: --quick drops it and --leakcheck brings it back,
## with the SARIF going to its own artifact dir.
fCeRun -y --quick; ceCqQuick="${ceOut}"
fCeRun -y --quick --leakcheck
{ ((ceRc == 0)) && ! grep -q '^codeql-ran' <<<"${ceCqQuick}" && grep -qE "^codeql-ran ${ceRepo}/codeql/codeql_[0-9-]+\.sarif$" <<<"${ceOut}" \
	&& [[ "${ceOut}" == *"OK: CodeQL clean, SARIF in codeql/"* ]]; } && _pass Et9ZqiY "CodeQL runs under --leakcheck, not under --quick" \
	|| _fail Et9ZqiY "CodeQL runs under --leakcheck, not under --quick" "$(fCeTail)"
## Any CodeQL result fails the stage, with its own message.
CE_CODEQL_RC=1 fCeRun -y --quick --leakcheck
{ ((ceRc == 1)) && [[ "${ceOut}" == *"FAILED: CodeQL found something"* && "${ceOut}" != *"CICD ABORTED"* ]]; } && _pass Et9ZqjD "CodeQL result fails the stage" \
	|| _fail Et9ZqjD "CodeQL result fails the stage" "$(fCeTail)"
## It's only in the image, so a host run warns and goes on, and the container fails.
CE_CODEQL_PROBE=false fCeRun -y --quick --leakcheck; ceNoCq=0
{ ((ceRc == 0)) && [[ "${ceOut}" == *"WARNING: CodeQL skipped"* ]] && ! grep -q '^codeql-ran' <<<"${ceOut}"; } && ceNoCq=1
CE_CODEQL_PROBE=false CE_NO_SKIP=1 fCeRun -y --quick --leakcheck
{ ((ceNoCq && ceRc == 1)) && [[ "${ceOut}" == *"FAILED: CodeQL skipped"* ]]; } && _pass Et9Zqjy "CodeQL missing: warns here, fails in the container" \
	|| _fail Et9Zqjy "CodeQL missing: warns here, fails in the container" "warned=${ceNoCq} $(fCeTail)"

## The vendor and interop pin checks and govulncheck reach another host, so
## --quick leaves them out.
CE_NET=1 fCeRun -y; ceNetFull="$(grep -oE '^(vendor|interop|vuln)-net$' <<<"${ceOut}" | tr '\n' ' ' || true)"
CE_NET=1 fCeRun -y --quick; ceNetQuick="$(grep -oE '^(vendor|interop|vuln)-net$' <<<"${ceOut}" | tr '\n' ' ' || true)"
{ ((ceRc == 0)) && [[ "${ceNetFull}" == "vendor-net interop-net vuln-net " && -z "${ceNetQuick}" ]]; } && _pass Et9RcHq "--quick skips checks that reach another host" \
	|| _fail Et9RcHq "--quick skips checks that reach another host" "full=[${ceNetFull}] quick=[${ceNetQuick}] $(fCeTail)"

fCeRun -q
{ ((ceRc == 0)) && [[ "${ceOutFull}" == *"Repo root ..."* && "${ceOutFull}" == *"format skipped"* && "${ceOut}" != *"Repo root ..."* && "${ceOut}" != *"format skipped"* \
	&& "${ceOut}" == *"1/8  Format"* && "${ceOut}" == *"OK: integration harness"* ]]; } && _pass ErmCp2I "-q output" \
	|| _fail ErmCp2I "-q output" "$(fCeTail)"

## Machine use. Half the CPUs, a quarter when the 1-minute load is over half the
## CPU count, a quarter for the heavy steps either way, and never under 1.
mjGot=""
for mjCase in "32 10.00 16 8 0" "32 16.00 16 8 0" "32 16.01 8 8 1" "32 16 16 8 0" "16 8.009 8 4 0" "7 0.5 3 1 0" \
	"4 3 1 1 1" "2 0 1 1 0" "1 0.51 1 1 1" "1 0.50 1 1 0" "0 0 1 1 0" "x y 1 1 0" "08 09.08 2 2 1" "32 1.5.3 16 8 0"; do
	read -r mjCpus mjLoad mjWant <<<"${mjCase}"
	mjGot="$( source "${meDir}/utility/include/machine-use.bash"; fMachineJobs "${mjCpus}" "${mjLoad}"; echo "${machineJobs} ${machineJobsHeavy} ${machineBusy}" )"
	[[ "${mjGot}" == "${mjWant}" ]] && _pass EtixvQc "job counts: ${mjCpus} CPUs, load ${mjLoad}" \
		|| _fail EtixvQc "job counts: ${mjCpus} CPUs, load ${mjLoad}" "want=[${mjWant}] got=[${mjGot}]"
done
## A run on 16 CPUs at load 2 that stays that way: every step at nice 19 and
## idle I/O, the harness and lint at 8, and the heavy steps at 4 anyway.
ceLoad="${ceDir}/loadavg"; mjLog="${ceDir}/jobs.log"
echo "2.00 1.00 1.00 1/100 1" >"${ceLoad}"; : >"${mjLog}"
CE_JOBS="${mjLog}" CE_NPROC=16 CE_LOADAVG="${ceLoad}" CE_GOFLAGS="-mod=mod -p=99 -parallel=99" fCeRun -y
mjJobs="$(<"${mjLog}")"; mjIo="none"; if command -v ionice >/dev/null 2>&1; then mjIo="idle"; fi
grep -qxF "nice=19 io=${mjIo}" <<<"${mjJobs}" && _pass EtixvQd "the run is at nice 19 and idle I/O" \
	|| _fail EtixvQd "the run is at nice 19 and idle I/O" "jobs=[${mjJobs}] $(fCeTail)"
{ ((ceRc == 0)) && grep -qxF "harness GOMAXPROCS=8 GOFLAGS=-mod=mod -p=8 -parallel=8 CARGO_BUILD_JOBS=8 RAYON_NUM_THREADS=8 CPU_CAP=8 GO19CONCURRENTCOMPILATION=0" <<<"${mjJobs}" \
	&& grep -qxF "lint --concurrency=8" <<<"${mjJobs}" && grep -qxF "cross GOMAXPROCS=8" <<<"${mjJobs}" \
	&& [[ "${ceOut}" == *"Jobs ................: 8 jobs, 4 for the heavy steps (load 2.00 on 16 CPUs)"* && "${ceOut}" != *"jobs now"* ]]; } \
	&& _pass EtixvQe "half the CPUs for a step on a quiet box" \
	|| _fail EtixvQe "half the CPUs for a step on a quiet box" "jobs=[${mjJobs}] $(fCeTail)"
{ grep -qE '^fuzz GOMAXPROCS=4 .* -parallel 4 \.$' <<<"${mjJobs}" && grep -qxF "race GOMAXPROCS=4 GOFLAGS=-mod=mod -p=4 -parallel=4" <<<"${mjJobs}" \
	&& grep -qxF "soak GOMAXPROCS=4" <<<"${mjJobs}" && grep -qxF "codeql GOMAXPROCS=4" <<<"${mjJobs}"; } \
	&& _pass EtixvQf "a quarter for fuzz, race, soak and CodeQL on a quiet box" \
	|| _fail EtixvQf "a quarter for fuzz, race, soak and CodeQL on a quiet box" "jobs=[${mjJobs}]"
## The box gets busy during the tests, so the next step drops to a quarter.
echo "2.00 1.00 1.00 1/100 1" >"${ceLoad}"; : >"${mjLog}"
CE_JOBS="${mjLog}" CE_NPROC=16 CE_LOADAVG="${ceLoad}" CE_LOAD_LATER="12.00" fCeRun -y
mjJobs="$(<"${mjLog}")"
{ ((ceRc == 0)) && grep -qE '^harness GOMAXPROCS=8 ' <<<"${mjJobs}" && grep -qxF "cross GOMAXPROCS=4" <<<"${mjJobs}" \
	&& [[ "${ceOut}" == *"jobs now 4 jobs, 4 for the heavy steps (load 12.00 on 16 CPUs, busy)"* ]]; } \
	&& _pass EtixvQg "load checked again before each step" \
	|| _fail EtixvQg "load checked again before each step" "jobs=[${mjJobs}] $(fCeTail)"
## In a container nproc counts the host's CPUs, so the --cpus it got is the most.
for mjCase in "2 2 2" "6 6 4" "99 8 4"; do
	read -r mjMax mjWant mjWantHeavy <<<"${mjCase}"
	echo "2.00 1.00 1.00 1/100 1" >"${ceLoad}"; : >"${mjLog}"
	CE_JOBS="${mjLog}" CE_NPROC=16 CE_LOADAVG="${ceLoad}" CE_INSIDE=1 CE_JOBS_MAX="${mjMax}" fCeRun -y
	mjJobs="$(<"${mjLog}")"
	{ ((ceRc == 0)) && grep -qE "^harness GOMAXPROCS=${mjWant} " <<<"${mjJobs}" && grep -qE "^race GOMAXPROCS=${mjWantHeavy} " <<<"${mjJobs}" \
		&& [[ "${ceOut}" == *"at most ${mjMax} in this container)"* ]]; } \
		&& _pass EtiyAAx "in a container, at most its --cpus: ${mjMax}" \
		|| _fail EtiyAAx "in a container, at most its --cpus: ${mjMax}" "jobs=[${mjJobs}] $(fCeTail)"
done
rm -rf "${ceRepo}/dist"

## Dogfood: a copy that fails is an error, and sudo is tried only as sudo -n,
## and only when someone is there.
CE_DEST="${ceDir}/home/bin" fCeRun -y
ceOk=0; { ((ceRc == 0)) && [[ -f "${ceDir}/home/bin/cbv-test" && "${ceOut}" == *"OK: installed -> "* ]]; } && ceOk=1
CE_DEST="${ceDir}/home/bin" CE_CPFAIL="${ceDir}/home/bin" fCeRun -y
{ ((ceOk && ceRc == 1)) && [[ "${ceOut}" == *"could not install"* && "${ceOut}" != *"OK: installed"* && -z "${ceSudo}" ]]; } && _pass ErmCp2J "dogfood: failed copy under HOME" \
	|| _fail ErmCp2J "dogfood: failed copy under HOME" "good copy ok=${ceOk}; sudo=[${ceSudo}] $(fCeTail)"
CE_DEST="${ceDir}/sys" CE_CPFAIL="${ceDir}/sys" fCeRun -y
{ ((ceRc == 1)) && [[ -z "${ceSudo}" && "${ceOut}" != *"OK: installed"* ]]; } && _pass ErmCp2K "dogfood: unattended, no sudo" \
	|| _fail ErmCp2K "dogfood: unattended, no sudo" "sudo=[${ceSudo}] $(fCeTail)"
CE_DEST="${ceDir}/sys" CE_CPFAIL="${ceDir}/sys" fCeRun
{ ((ceRc == 1)) && [[ "${ceSudo}" == "-n cp -f "* && "${ceOut}" == *"even with sudo -n"* ]]; } && _pass ErmCp2L "dogfood: attended, sudo -n only" \
	|| _fail ErmCp2L "dogfood: attended, sudo -n only" "sudo=[${ceSudo}] $(fCeTail)"

## The cross builds, with dirs from a file outside the repo: each goes to the
## first dir that exists, under its own name, and only when stage 6 made it this
## run. --no-dogfood drops the file's lists too.
mkdir -p "${ceDir}/priv" "${ceDir}/home/win" "${ceDir}/home/mac"
cat >"${ceDir}/priv/dogfood.bash" <<EOF
DOGFOOD_CROSS=(
	"cbv-test-windows-x86_64.exe|cbv-test.exe|${ceDir}/home/nope|${ceDir}/home/win"
	"cbv-test-darwin-universal|cbv-test|${ceDir}/home/mac"
)
EOF
fCeCrossClean(){ rm -rf "${ceDir}/home/win" "${ceDir}/home/mac" "${ceRepo}/dist"; mkdir -p "${ceDir}/home/win" "${ceDir}/home/mac"; }
fCeCrossNone(){ [[ -z "$(ls -A "${ceDir}/home/win")$(ls -A "${ceDir}/home/mac")" ]]; }
fCeCrossClean; CE_CROSS=1 CE_LOCAL="../priv/dogfood.bash" fCeRun -y
{ ((ceRc == 0)) && cmp -s "${ceRepo}/dist/cbv-test-windows-x86_64.exe" "${ceDir}/home/win/cbv-test.exe" && cmp -s "${ceRepo}/dist/cbv-test-darwin-universal" "${ceDir}/home/mac/cbv-test" \
	&& [[ "${ceOut}" == *"OK: installed -> ${ceDir}/home/win/cbv-test.exe"* && ! -e "${ceDir}/home/nope" ]]; } && _pass Esj2PpU "dogfood: cross builds to the local file's dirs" \
	|| _fail Esj2PpU "dogfood: cross builds to the local file's dirs" "$(fCeTail)"
fCeCrossClean; mkdir -p "${ceRepo}/dist"; echo stale >"${ceRepo}/dist/cbv-test-windows-x86_64.exe"
CE_LOCAL="../priv/dogfood.bash" fCeRun -y
{ ((ceRc == 0)) && fCeCrossNone && [[ "${ceOut}" == *"stage 6 didn't run"* ]]; } && _pass Esj2Pq1 "dogfood: no cross copy without stage 6" \
	|| _fail Esj2Pq1 "dogfood: no cross copy without stage 6" "$(fCeTail)"
fCeCrossClean; CE_CROSS=1 CE_LOCAL="../priv/dogfood.bash" fCeRun -y --no-dogfood
{ ((ceRc == 0)) && [[ -f "${ceRepo}/dist/cbv-test-windows-x86_64.exe" ]] && fCeCrossNone; } && _pass Esj2PqY "dogfood: --no-dogfood skips the cross builds" \
	|| _fail Esj2PqY "dogfood: --no-dogfood skips the cross builds" "$(fCeTail)"
rm -rf "${ceRepo}/dist"
## The public config names no personal dir.
if grep -nE '/synced/|/Dropbox/|/mnt/zfs/' "${meDir}/config.bash" >"${CBT_OUT}"; then _fail Esj2Pr6 "config.bash names no personal dir" "$(tr '\n' ' ' <"${CBT_OUT}")"
else _pass Esj2Pr6 "config.bash names no personal dir"; fi

## A missing tool warns, except under CICD_NO_SKIP, where it fails the run.
CE_VULN=1 fCeRun -y; ceWarned=0
{ ((ceRc == 0)) && [[ "${ceOut}" == *"WARNING: govulncheck skipped"* ]]; } && ceWarned=1
CE_VULN=1 CE_NO_SKIP=1 fCeRun -y
{ ((ceWarned && ceRc == 1)) && [[ "${ceOut}" == *"FAILED: govulncheck skipped"* && "${ceOut}" != *"OK: tests passed"* ]]; } && _pass EsJjVtL "missing tool under NO_SKIP" \
	|| _fail EsJjVtL "missing tool under NO_SKIP" "warned=${ceWarned} $(fCeTail)"

## --container, against a docker that logs what it's asked. The image is
## tagged by a hash, built when missing with the pins as build args and the
## contexts by real path, and the one it replaces is removed. The run inside
## gets this user, the repo and extra mounts at the same paths, and the flags
## that leave the profiler, dogfood and publish to the host.
fCeTag(){ sed -n 's/^image inspect //p' <<<"${ceDocker}" | head -1; }
## Cross builds are on, and would fail here, so the host must leave stage 6 alone too.
echo "2.00 1.00 1.00 1/100 1" >"${ceLoad}"
CE_NPROC=16 CE_LOADAVG="${ceLoad}" CE_CROSS=1 CE_DEST="${ceDir}/home/bin" fCeRun -y --container --long
ceTag="$(fCeTag)"
## Retired 2026-10-25 by the container reset items: the build and run lines
## now have labels and a name, and old tags go only after a pass, at the end.
## Etil6xK and Etil6xL check the same things.
#{ ((ceRc == 0)) && [[ "${ceTag}" =~ ^cbv-test-cicd:[0-9a-f]{12}$ ]] \
#	&& grep -qxF "build -t ${ceTag} --build-arg FOO_VERSION=1.2 --build-context ctx=$(readlink -f "${ceRepo}/ctxdir") ${ceRepo}/cicd/container" <<<"${ceDocker}" \
#	&& grep -qxF "rmi cbv-test-cicd:0ld0ld0ld0ld" <<<"${ceDocker}"; } && _pass EsJjVuH "--container image rebuild" \
#	|| _fail EsJjVuH "--container image rebuild" "docker=[${ceDocker}] $(fCeTail)"
ceTz=""; [[ -e /etc/localtime ]] && ceTz=" -v /etc/localtime:/etc/localtime:ro"
#ceRunWant="run --rm --init --user $(id -u):$(id -g) -v ${ceRepo}:${ceRepo} -v cbv-test-cache:/cache${ceTz} -v $(readlink -f "${ceDir}/demos-real"):${ceRepo}/demos -w ${ceRepo} ${ceTag} bash ${ceRepo}/cicd/cicd.bash -y --no-profile --no-dogfood --no-publish --long"
#grep -qxF "${ceRunWant}" <<<"${ceDocker}" && _pass EsJjVvF "--container user and repo path" \
#	|| _fail EsJjVvF "--container user and repo path" "want=[${ceRunWant}] docker=[${ceDocker}]"
## Everything the run makes in docker has the project and run labels, and the
## container a name from both.
ceRunName="$(sed -n 's/^build .*--label dev\.run=\([^ ]*\) .*/\1/p' <<<"${ceDocker}")"
ceLabels="--label dev.project=cbv-test --label dev.run=${ceRunName}"
## Retired 2026-10-25 by the CPU and priority reset item: the run line now
## has a CPU limit. EtixvQh checks the same things, and the limit.
#ceRunWant="run --rm --init -e TINI_KILL_PROCESS_GROUP=1 --name cbv-test-${ceRunName}-stages ${ceLabels} --user $(id -u):$(id -g) -v ${ceRepo}:${ceRepo} -v cbv-test-cache:/cache${ceTz} -v $(readlink -f "${ceDir}/demos-real"):${ceRepo}/demos -w ${ceRepo} ${ceTag} bash ${ceRepo}/cicd/cicd.bash -y --no-profile --no-dogfood --no-publish --long"
#{ ((ceRc == 0)) && [[ "${ceTag}" =~ ^cbv-test-cicd:[0-9a-f]{12}$ && "${ceRunName}" == cicd-run.* ]] \
#	&& grep -qxF "build -t ${ceTag} ${ceLabels} --build-arg FOO_VERSION=1.2 --build-context ctx=$(readlink -f "${ceRepo}/ctxdir") ${ceRepo}/cicd/container" <<<"${ceDocker}" \
#	&& grep -qxF "volume create ${ceLabels} cbv-test-cache" <<<"${ceDocker}" && grep -qxF "${ceRunWant}" <<<"${ceDocker}"; } \
#	&& _pass Etil6xK "--container build, volume and run are labeled" \
#	|| _fail Etil6xK "--container build, volume and run are labeled" "run=[${ceRunName}] docker=[${ceDocker}] $(fCeTail)"
## The container also gets the run's job count, 8 of 16 CPUs here, as its CPU
## limit and a low share, since nice on the docker client stops there.
ceRunWant="run --rm --init -e TINI_KILL_PROCESS_GROUP=1 --name cbv-test-${ceRunName}-stages ${ceLabels} --cpus 8 --cpu-shares 256 -e CICD_JOBS_MAX=8 --user $(id -u):$(id -g) -v ${ceRepo}:${ceRepo} -v cbv-test-cache:/cache${ceTz} -v $(readlink -f "${ceDir}/demos-real"):${ceRepo}/demos -w ${ceRepo} ${ceTag} bash ${ceRepo}/cicd/cicd.bash -y --no-profile --no-dogfood --no-publish --long"
{ ((ceRc == 0)) && [[ "${ceTag}" =~ ^cbv-test-cicd:[0-9a-f]{12}$ && "${ceRunName}" == cicd-run.* ]] \
	&& grep -qxF "build -t ${ceTag} ${ceLabels} --build-arg FOO_VERSION=1.2 --build-context ctx=$(readlink -f "${ceRepo}/ctxdir") ${ceRepo}/cicd/container" <<<"${ceDocker}" \
	&& grep -qxF "volume create ${ceLabels} cbv-test-cache" <<<"${ceDocker}" && grep -qxF "${ceRunWant}" <<<"${ceDocker}"; } \
	&& _pass EtixvQh "--container build, volume and run are labeled, and the run has a CPU limit" \
	|| _fail EtixvQh "--container build, volume and run are labeled, and the run has a CPU limit" "run=[${ceRunName}] docker=[${ceDocker}] $(fCeTail)"
## After a pass: the run's containers, then the dangling images and every older
## tag but the newest, then the week-old build cache. Each lookup is by label,
## and nothing is forced or pruned system-wide.
ceGone="$(grep -E '^(rm|rmi|volume rm|builder|system prune)' <<<"${ceDocker}" | tr '\n' ';' || true)"
{ ((ceRc == 0)) && [[ "${ceGone}" == "rm -f c0ffeec0ffee;rmi d4ngl3d4ngl3;rmi cbv-test-cicd:0ld0ld0ld0ld;rmi cbv-test-cicd:zzz000000000;builder prune -f --filter until=168h;" ]] \
	&& grep -qxF "ps -aq --filter label=dev.project=cbv-test --filter label=dev.run=${ceRunName}" <<<"${ceDocker}" \
	&& grep -qxF "image ls -q --filter dangling=true --filter label=dev.project=cbv-test" <<<"${ceDocker}" \
	&& grep -qxF "image ls cbv-test-cicd --filter label=dev.project=cbv-test --format {{.Repository}}:{{.Tag}}" <<<"${ceDocker}" \
	&& [[ "${ceOut}" == *"[ docker cleanup: removed 1 container(s), 3 image(s), build cache older than a week (12.5MB); about 0.0 GB freed ]"* ]] \
	&& [[ "$(grep -n 'docker cleanup' <<<"${ceOut}" | cut -d: -f1)" -lt "$(grep -n 'CI/CD: done' <<<"${ceOut}" | cut -d: -f1)" ]]; } \
	&& _pass Etil6xL "docker cleanup after a pass" \
	|| _fail Etil6xL "docker cleanup after a pass" "gone=[${ceGone}] docker=[${ceDocker}] $(fCeTail)"
{ ((ceRc == 0)) && [[ "${ceOut}" == *"inner run"* && "${ceOut}" == *"OK: stages 1 to 4 and 6 passed in the container"* && "${ceOut}" == *"OK: installed -> "* \
	&& "${ceOut}" != *"1/8  Format"* && "${ceOut}" != *"OK: integration harness"* && "${ceOut}" != *"6/8  Cross"* ]]; } && _pass EsJjVwL "--container host stages" \
	|| _fail EsJjVwL "--container host stages" "$(fCeTail)"
CE_HAVE_IMAGE=1 CE_RUN_RC=1 CE_DEST="${ceDir}/home/bin" fCeRun -y --container
{ ((ceRc == 1)) && [[ "${ceOut}" == *"the run in the container failed"* && "${ceOut}" != *"OK: installed"* && "${ceDocker}" != *"build "* ]]; } && _pass EsJjVxK "--container inner failure" \
	|| _fail EsJjVxK "--container inner failure" "docker=[${ceDocker}] $(fCeTail)"
## A failed run cleans up too, but keeps the older tags, since nothing newer passed.
ceGone="$(grep -E '^(rm|rmi|volume rm|builder|system prune)' <<<"${ceDocker}" | tr '\n' ';' || true)"
{ ((ceRc == 1)) && [[ "${ceGone}" == "rm -f c0ffeec0ffee;rmi d4ngl3d4ngl3;builder prune -f --filter until=168h;" && "${ceOut}" == *"docker cleanup: removed"* ]]; } \
	&& _pass Etil6xM "docker cleanup after a failure" \
	|| _fail Etil6xM "docker cleanup after a failure" "gone=[${ceGone}] $(fCeTail)"
## So does Ctrl+C in the middle of the container run or the image build, and
## it stops the run rather than go on to the host stages.
for ceSig in self proxy build; do
	case "${ceSig}" in
		build) CE_BUILD_SIGINT=1 CE_WRAP=1 CE_DEST="${ceDir}/home/bin" fCeRun -y --container ;;
		*) CE_HAVE_IMAGE=1 CE_RUN_SIGINT="${ceSig}" CE_WRAP=1 CE_DEST="${ceDir}/home/bin" fCeRun -y --container ;;
	esac
	ceGone="$(grep -E '^(rm|rmi|volume rm|builder|system prune)' <<<"${ceDocker}" | tr '\n' ';' || true)"
	{ ((ceRc == 130)) && [[ "${ceGone}" == "rm -f c0ffeec0ffee;rmi d4ngl3d4ngl3;builder prune -f --filter until=168h;" && -z "${ceTmp}" ]] \
		&& [[ "${ceOut}" == *"STOPPED: Ctrl+C"* && "${ceOut}" != *"inner run"* && "${ceOut}" != *"OK: installed"* && "${ceOut}" != *"1/8  Format"* && "${ceOut}" != *"7/8  Dogfood"* ]]; } \
		&& _pass Etil6xN "docker cleanup after Ctrl+C: ${ceSig}" \
		|| _fail Etil6xN "docker cleanup after Ctrl+C: ${ceSig}" "gone=[${ceGone}] $(fCeTail)"
done
## --keep-temp keeps the run's containers, and says which.
CE_HAVE_IMAGE=1 fCeRun -y --container --keep-temp
ceGone="$(grep -E '^(rm|rmi|volume rm|builder|system prune)' <<<"${ceDocker}" | tr '\n' ';' || true)"
{ ((ceRc == 0)) && grep -qE '^run --init -e TINI_KILL_PROCESS_GROUP=1 --name cbv-test-cicd-run\.[^ ]+-stages ' <<<"${ceDocker}" && [[ "${ceGone}" != *"rm -f"* && "${ceGone}" == *"builder prune"* ]] \
	&& [[ "${ceOut}" == *"[ kept container cbv-test-kept (--keep-temp) ]"* ]]; } && _pass Etil6xO "--keep-temp keeps the containers" \
	|| _fail Etil6xO "--keep-temp keeps the containers" "gone=[${ceGone}] docker=[${ceDocker}] $(fCeTail)"
## The cache volume goes once it's over the cap, and only when it's labeled ours.
ceVol=""
for ceCase in "cbv-test 2.5GB" "cbv-test 1.5GB" "other 9GB" " 9GB"; do
	read -r ceProj ceSize <<<"${ceCase}"; [[ "${ceCase}" == " "* ]] && { ceSize="${ceProj}"; ceProj=""; }
	CE_HAVE_IMAGE=1 CE_HAVE_VOL=1 CE_VOL_PROJ="${ceProj}" CE_VOL_SIZE="${ceSize}" fCeRun -y --container
	ceVol+="${ceRc}:$(grep -c '^volume rm cbv-test-cache$' <<<"${ceDocker}" || true):$(grep -c '^volume create' <<<"${ceDocker}" || true):$(grep -c 'has no dev.project=cbv-test label' <<<"${ceOut}" || true);"
done
[[ "${ceVol}" == "0:1:0:0;0:0:0:0;0:0:0:1;0:0:0:1;" ]] && _pass Etil6xP "cache volume emptied over the cap, ours only" \
	|| _fail Etil6xP "cache volume emptied over the cap, ours only" "got=[${ceVol}] $(fCeTail)"
## The gif's fallback fonts are pinned only in the container, so a host run
## leaves it alone rather than flip it back and forth.
rm -f "${ceRepo}/gif/demo.gif"; CE_GIF=1 fCeRun -y; ceGifHost=0; [[ -e "${ceRepo}/gif/demo.gif" ]] && ceGifHost=1
CE_GIF=1 CE_INSIDE=1 fCeRun -y
{ ((ceRc == 0 && ! ceGifHost)) && [[ -s "${ceRepo}/gif/demo.gif" ]]; } && _pass EsJpWaD "demo gif container-only" \
	|| _fail EsJpWaD "demo gif container-only" "host made it: ${ceGifHost}; $(fCeTail)"
## --leakcheck goes to the run inside, as --long does.
CE_HAVE_IMAGE=1 fCeRun -y --container --quick --leakcheck
{ ((ceRc == 0)) && grep -qE '^run .* --no-publish --quick --leakcheck$' <<<"${ceDocker}"; } && _pass Et9VxYE "--leakcheck reaches the container run" \
	|| _fail Et9VxYE "--leakcheck reaches the container run" "docker=[${ceDocker}] $(fCeTail)"
CE_HAVE_IMAGE=1 fCeRun -y --container --no-leakcheck
{ ((ceRc == 0)) && grep -qE '^run .* --no-publish --no-leakcheck$' <<<"${ceDocker}"; } && _pass EtAaQDY "--no-leakcheck reaches the container run" \
	|| _fail EtAaQDY "--no-leakcheck reaches the container run" "docker=[${ceDocker}] $(fCeTail)"
CE_INSIDE=1 fCeRun -y --container
{ ((ceRc == 2)) && [[ "${ceOut}" == *"--container is for the host"* && -z "${ceDocker}" ]]; } && _pass EsJjVyJ "--container is refused inside the container" \
	|| _fail EsJjVyJ "--container is refused inside the container" "docker=[${ceDocker}] $(fCeTail)"

## A missing context builds from an empty dir, which is removed after, gets its
## own tag, and the run inside gets CONTAINER_CONTEXT_MISSING.
CE_CTX=nope fCeRun -y --container
ceCtx="$(sed -n 's/.*--build-context ctx=\([^ ]*\) .*/\1/p' <<<"${ceDocker}")"
{ ((ceRc == 0)) && [[ -n "${ceCtx}" && "${ceCtx}" != *ctxdir* && ! -e "${ceCtx}" && "$(fCeTag)" != "${ceTag}" ]] \
	&& grep -qE '^run .* --no-publish --no-demogif$' <<<"${ceDocker}"; } && _pass EsKCVVh "missing build context" \
	|| _fail EsKCVVh "missing build context" "ctx=[${ceCtx}] docker=[${ceDocker}] $(fCeTail)"
## A failed build used to leave that empty dir in TMPDIR.
CE_CTX=nope CE_BUILD_RC=1 fCeRun -y --container
## Retired 2026-10-25: a failed build now runs the stages on the host, so the
## run passes. Etil6xR checks TMPDIR the same way.
#{ ((ceRc == 1)) && [[ "${ceOut}" == *"could not build cbv-test-cicd:"* && -z "${ceTmp}" ]]; } && _pass EtAgsPA "failed image build leaves nothing in TMPDIR" \
#	|| _fail EtAgsPA "failed image build leaves nothing in TMPDIR" "docker=[${ceDocker}] $(fCeTail)"
{ ((ceRc == 0)) && [[ "${ceOut}" == *"NOTE: could not build cbv-test-cicd:"*", so stages 1 to 4 and 6 run on the host"* && "${ceOut}" == *"OK: integration harness"* ]] \
	&& [[ -z "${ceTmp}" && "${ceOut}" != *"passed in the container"* ]] && ! grep -q '^run ' <<<"${ceDocker}" && grep -q '^builder prune' <<<"${ceDocker}"; } \
	&& _pass Etil6xR "failed image build runs on the host" \
	|| _fail Etil6xR "failed image build runs on the host" "docker=[${ceDocker}] $(fCeTail)"
## No docker, or one with no daemon to answer, runs every stage here with a
## note, whether asked for or the default.
ceNoDocker=""
for ceCase in missing daemon default; do
	case "${ceCase}" in
		missing) CE_DOCKER="${ceDir}/nowhere/docker" fCeRun -y --container ;;
		daemon)  CE_DAEMON_RC=1 fCeRun -y --container ;;
		default) CE_DAEMON_RC=1 CE_CONTAINER_DEFAULT=1 fCeRun -y ;;
	esac
	ceNoDocker+="${ceCase}:${ceRc}:$(grep -c '^\[ NOTE: no working docker here, so every stage runs on the host \]$' <<<"${ceOut}" || true):$(grep -c 'OK: integration harness' <<<"${ceOut}" || true):$(grep -cvE '^(version |$)' <<<"${ceDocker}" || true);"
done
[[ "${ceNoDocker}" == "missing:0:1:1:0;daemon:0:1:1:0;default:0:1:1:0;" ]] && _pass Etil6xQ "no working docker runs on the host" \
	|| _fail Etil6xQ "no working docker runs on the host" "got=[${ceNoDocker}] $(fCeTail)"

## Hosted CI builds the image under the tag --image-tag prints, before the
## run, so that has to be the tag the run looks for, with the context there or
## not. Under CICD_IMAGE_PREBUILT=1 a missing image fails rather than build.
ceTagGot=""
for ceCtxCase in ctxdir nope; do
	CE_CTX="${ceCtxCase}" fCeRun --image-tag; ceTagOut="${ceOut}"; ceTagRc="${ceRc}"; ceTagDocker="${ceDocker}"
	CE_CTX="${ceCtxCase}" CE_HAVE_IMAGE=1 CE_PREBUILT=1 fCeRun -y --container
	{ ((ceTagRc == 0 && ceRc == 0)) && [[ -z "${ceTagDocker}" && "${ceTagOut}" =~ ^cbv-test-cicd:[0-9a-f]{12}$ && "${ceTagOut}" == "$(fCeTag)" && "${ceTagGot}" != "${ceTagOut}" ]] \
		&& grep -q '^run ' <<<"${ceDocker}"; } && _pass Et9eteN "--image-tag is the tag a run uses: context ${ceCtxCase}" \
		|| _fail Et9eteN "--image-tag is the tag a run uses: context ${ceCtxCase}" "printed=[${ceTagOut}] rc=${ceTagRc} docker=[${ceDocker}] $(fCeTail)"
	ceTagGot="${ceTagOut}"
done
CE_PREBUILT=1 fCeRun -y --container
{ ((ceRc == 1)) && [[ "${ceOut}" == *"CICD_IMAGE_PREBUILT=1 says it was built before this run"* && "${ceDocker}" != *"build "* && "${ceDocker}" != *"run "* ]]; } && _pass Et9etf7 "CICD_IMAGE_PREBUILT: no image fails, no build" \
	|| _fail Et9etf7 "CICD_IMAGE_PREBUILT: no image fails, no build" "docker=[${ceDocker}] $(fCeTail)"

## With CONTAINER_DEFAULT=1 a plain run goes to the container, --host stays
## here, and so does a run already inside.
CE_CONTAINER_DEFAULT=1 fCeRun -y; ceDefRun=0; grep -q '^run ' <<<"${ceDocker}" && ceDefRun=1
CE_CONTAINER_DEFAULT=1 fCeRun -y --host; ceHostOk=0; { ((ceRc == 0)) && [[ -z "${ceDocker}" && "${ceOut}" == *"OK: integration harness"* ]]; } && ceHostOk=1
CE_CONTAINER_DEFAULT=1 CE_INSIDE=1 fCeRun -y
{ ((ceDefRun && ceHostOk && ceRc == 0)) && [[ -z "${ceDocker}" && "${ceOut}" == *"OK: integration harness"* ]]; } && _pass EsKCVWM "CONTAINER_DEFAULT routing" \
	|| _fail EsKCVWM "CONTAINER_DEFAULT routing" "default ran=${ceDefRun} host ok=${ceHostOk} $(fCeTail)"
CE_CONTAINER_DEFAULT=1 fCeRun -y --no-container
{ ((ceRc == 0)) && [[ -z "${ceDocker}" && "${ceOut}" == *"OK: integration harness"* && "${ceOut}" != *"NOTE: no working"* ]]; } && _pass EtilQ9a "--no-container runs here" \
	|| _fail EtilQ9a "--no-container runs here" "docker=[${ceDocker}] $(fCeTail)"

## Lint: shellcheck and ruff check what the engine finds in a git repo of
## fixtures. A finding fails the run, and so does finding nothing to check,
## since a linter handed no files passes.
if command -v shellcheck >/dev/null 2>&1 && command -v ruff >/dev/null 2>&1; then
	clRepo="${ceDir}/lint"
	mkdir -p "${clRepo}/cicd/utility/include" "${clRepo}/lib" "${clRepo}/skip"
	cp "${meDir}/cicd.bash" "${clRepo}/cicd/"; cp "${meDir}/utility/include/gfs-rotate.bash" "${meDir}/utility/include/machine-use.bash" "${clRepo}/cicd/utility/include/"
	cp "${ceRepo}/lib/out" "${clRepo}/lib/out"
	## The linter commands are the real config's; the file list is the fixtures'.
	cp "${ceRepo}/cicd/config.bash" "${clRepo}/cicd/config.bash"
	grep -E '^(SHELLCHECK_PROBE|SHELLCHECK_CMD|RUFF_PROBE|RUFF_CMD)=' "${meDir}/config.bash" >>"${clRepo}/cicd/config.bash"
	cat >>"${clRepo}/cicd/config.bash" <<'EOF'
VET_CMD=(true); TEST_CMD=(true); FUZZ_ENABLE=0; DOGFOOD_FIXED_DESTS=()
SHELLCHECK_EXCLUDE=(cicd/ lib/ skip/ ${CL_SH_EXCLUDE:-})
EOF
	printf '%s\n' '#!/usr/bin/env bash' 'echo "${1:-}"' >"${clRepo}/ok.bash"
	printf '%s\n' '#!/bin/sh' 'echo "$1"' >"${clRepo}/tool"
	printf '%s\n' '#!/usr/bin/env node' 'console.log(1)' >"${clRepo}/run.mjs"
	printf '%s\n' '#!/usr/bin/env bash' 'echo $1' >"${clRepo}/skip/bad.bash"
	printf '%s\n' 'import sys' 'print(sys.argv)' >"${clRepo}/ok.py"
	printf '%s\n' 'import os' >"${clRepo}/skip/bad.py"
	printf '%s\n' '[tool.ruff]' 'extend-exclude = ["skip/"]' >"${clRepo}/pyproject.toml"
	chmod +x "${clRepo}/tool" "${clRepo}/run.mjs"
	git -C "${clRepo}" init -q
	fClRun(){
		clRc=0
		( cd "${clRepo}" && git add -A && env -u CICDTEST_EXE -u CICDTEST_DO_LONGTEST -u CICDTEST_DO_PERF -u CICDTEST_QUICK \
			HOME="${ceDir}/home" TMPDIR="${ceDir}/tmp" CICD_NO_SKIP=0 CICD_IN_CONTAINER=0 bash "${clRepo}/cicd/cicd.bash" -y </dev/null >"${CBT_OUT}" 2>&1 ) || clRc=$?
		clOut="$(<"${CBT_OUT}")"
	}
	fClTail(){ printf 'rc=%s out=[%s]' "${clRc}" "$(grep -E 'OK: (shellcheck|ruff)|FAILED|ABORTED|SC[0-9]{4}|\.py:' "${CBT_OUT}" | head -4 | tr '\n' ' ')"; }

	fClRun
	{ ((clRc == 0)) && [[ "${clOut}" == *"OK: shellcheck clean (2 files)"* && "${clOut}" == *"OK: ruff clean (1 files)"* ]]; } && _pass ErmroeI "lint file selection" \
		|| _fail ErmroeI "lint file selection" "$(fClTail)"
	printf '%s\n' '#!/bin/sh' 'echo $1' >"${clRepo}/tool"
	fClRun
	{ ((clRc != 0)) && [[ "${clOut}" == *"tool:2:"*"[SC2086]"* && "${clOut}" != *"OK: shellcheck clean"* ]]; } && _pass Ermroeo "lint: shellcheck finding, no .bash name" \
		|| _fail Ermroeo "lint: shellcheck finding, no .bash name" "$(fClTail)"
	clFound="${clOut}"
	printf '%s\n' '#!/bin/sh' 'echo "$1"' >"${clRepo}/tool"
	printf '%s\n' 'import os' >"${clRepo}/bad.py"
	fClRun
	{ ((clRc != 0)) && [[ "${clOut}" == *"bad.py:1:"*"F401"* && "${clOut}" != *"OK: ruff clean"* ]]; } && _pass ErmrofR "lint: ruff finding" \
		|| _fail ErmrofR "lint: ruff finding" "$(fClTail)"
	## The startup look at the newest run log has to show both kinds.
	mkdir -p "${ceDir}/lintlog"; printf '%s\n%s\n' "${clFound}" "${clOut}" >"${ceDir}/lintlog/run_20260101-000000.log"
	clReport="$(bash "${meDir}/utility/lint-report.bash" --file "${ceDir}/lintlog/run_20260101-000000.log" 2>&1 || true)"
	{ [[ "${clReport}" == "FLAG "*"tool:2:"*"[SC2086]"* && "${clReport}" == *"bad.py:1:"*"F401"* ]]; } && _pass Ermroh4 "lint-report findings" \
		|| _fail Ermroh4 "lint-report findings" "report=[${clReport}]"
	rm -f "${clRepo}/bad.py"
	CL_SH_EXCLUDE="ok.bash tool" fClRun
	{ ((clRc != 0)) && [[ "${clOut}" == *"FAILED: shellcheck: no Bash files found to check"* ]]; } && _pass Ermrofy "lint: shellcheck, no files" \
		|| _fail Ermrofy "lint: shellcheck, no files" "$(fClTail)"
	printf '%s\n' '[tool.ruff]' 'extend-exclude = ["*.py"]' >"${clRepo}/pyproject.toml"
	fClRun
	{ ((clRc != 0)) && [[ "${clOut}" == *"FAILED: ruff: no Python files found to check"* && "${clOut}" == *"OK: shellcheck clean"* ]]; } && _pass ErmrogW "lint: ruff, no files" \
		|| _fail ErmrogW "lint: ruff, no files" "$(fClTail)"
else
	_warn "ErmroeI Ermroeo ErmrofR Ermroh4 Ermrofy ErmrogW" "lint stage checks skipped: needs shellcheck and ruff"
fi

## PSScriptAnalyzer takes every tracked PowerShell file, with the real settings
## and runner. A finding fails the run, and so does finding nothing to check.
if pwsh -NoProfile -NonInteractive -Command 'Import-Module PSScriptAnalyzer -ErrorAction Stop' </dev/null >/dev/null 2>&1; then
	plRepo="${ceDir}/pslint"
	mkdir -p "${plRepo}/cicd/utility/include" "${plRepo}/lib"
	cp "${meDir}/cicd.bash" "${plRepo}/cicd/"; cp "${meDir}/utility/include/gfs-rotate.bash" "${meDir}/utility/include/machine-use.bash" "${plRepo}/cicd/utility/include/"
	cp "${meDir}/utility/pssa-lint.ps1" "${plRepo}/cicd/utility/"; cp "${meDir}/../PSScriptAnalyzerSettings.psd1" "${plRepo}/"
	cp "${ceRepo}/lib/out" "${plRepo}/lib/out"
	cp "${ceRepo}/cicd/config.bash" "${plRepo}/cicd/config.bash"
	grep -E '^(PSSA_PROBE|PSSA_CMD)=' "${meDir}/config.bash" >>"${plRepo}/cicd/config.bash"
	printf '%s\n' 'VET_CMD=(true); TEST_CMD=(true); FUZZ_ENABLE=0; DOGFOOD_FIXED_DESTS=(); SHELLCHECK_CMD=(); RUFF_CMD=()' >>"${plRepo}/cicd/config.bash"
	printf '%s\n' '[CmdletBinding()]' 'param([string]$Name)' 'Write-Output "hi $Name"' >"${plRepo}/ok.ps1"
	git -C "${plRepo}" init -q
	## The module may be in this user's own module dir, which follows HOME.
	plModPath="$(pwsh -NoProfile -NonInteractive -Command '$env:PSModulePath' </dev/null 2>/dev/null || true)"
	fPlRun(){
		plRc=0
		( cd "${plRepo}" && git add -A && env -u CICDTEST_EXE -u CICDTEST_DO_LONGTEST -u CICDTEST_DO_PERF -u CICDTEST_QUICK \
			HOME="${ceDir}/home" TMPDIR="${ceDir}/tmp" PSModulePath="${plModPath}" CICD_NO_SKIP=0 CICD_IN_CONTAINER=0 bash "${plRepo}/cicd/cicd.bash" -y </dev/null >"${CBT_OUT}" 2>&1 ) || plRc=$?
		plOut="$(<"${CBT_OUT}")"
	}
	fPlTail(){ printf 'rc=%s out=[%s]' "${plRc}" "$(grep -E 'PSScriptAnalyzer|FAILED|ABORTED|\.ps1:' "${CBT_OUT}" | head -4 | tr '\n' ' ')"; }
	fPlRun
	{ ((plRc == 0)) && [[ "${plOut}" == *"OK: PSScriptAnalyzer clean (3 files)"* ]]; } && _pass Et9uoQG "lint: PSScriptAnalyzer file selection" \
		|| _fail Et9uoQG "lint: PSScriptAnalyzer file selection" "$(fPlTail)"
	printf '%s\n' 'gci .' >"${plRepo}/bad.ps1"
	fPlRun
	{ ((plRc != 0)) && [[ "${plOut}" == *"bad.ps1:1:1: warning:"*"[PSAvoidUsingCmdletAliases]"* && "${plOut}" != *"OK: PSScriptAnalyzer clean"* ]]; } && _pass Et9uoQv "lint: PSScriptAnalyzer finding" \
		|| _fail Et9uoQv "lint: PSScriptAnalyzer finding" "$(fPlTail)"
	git -C "${plRepo}" rm -q --cached bad.ps1 ok.ps1 PSScriptAnalyzerSettings.psd1 cicd/utility/pssa-lint.ps1
	printf '%s\n' '*.ps1' '*.psd1' >"${plRepo}/.gitignore"
	fPlRun
	{ ((plRc != 0)) && [[ "${plOut}" == *"FAILED: PSScriptAnalyzer: no PowerShell files found to check"* ]]; } && _pass Et9uoRc "lint: PSScriptAnalyzer, no files" \
		|| _fail Et9uoRc "lint: PSScriptAnalyzer, no files" "$(fPlTail)"
else
	_warn "Et9uoQG Et9uoQv Et9uoRc" "PowerShell lint checks skipped: needs pwsh and PSScriptAnalyzer"
fi

## Hosted CI. The workflows read their pins from tool-versions.env and name
## none of them, so a bump there reaches them all. Actions are pinned by major
## version, which Dependabot keeps current.
wfDir="${meDir}/../.github/workflows"
wfPins=""; wfUses=""
while IFS='=' read -r wfKey wfVal; do
	[[ "${wfKey}" =~ ^[A-Z_]+$ && -n "${wfVal}" ]] || continue
	wfPins+="$(grep -rnF -- "${wfVal#v}" "${wfDir}" | sed "s|^${wfDir}/||" || true)"
done <"${meDir}/tool-versions.env"
wfUses="$(grep -rhoE 'uses:[[:space:]]*[^[:space:]]+' "${wfDir}" | grep -vE '^uses:[[:space:]]*[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@v[0-9]+$' || true)"
{ [[ -z "${wfPins}" && -z "${wfUses}" ]] && grep -qE 'uses:' "${wfDir}/ci.yml"; } && _pass Et9etfx "workflows: no pin of their own, actions by major version" \
	|| _fail Et9etfx "workflows: no pin of their own, actions by major version" "pins=[${wfPins}] uses=[${wfUses}]"
## The pipeline job builds the image as cicd.bash would: the tag it prints,
## the pins as build args, and every named context the Dockerfile copies from.
## Then the run must find that image rather than build its own.
wfCi="$(<"${wfDir}/ci.yml")"; wfMiss=""
wfCtxDir="$(sed -n 's/^CONTAINER_DIR="\(.*\)"$/\1/p' "${meDir}/config.bash")"
for wfWant in 'bash cicd/cicd.bash --image-tag' "grep -E '^[A-Z_]+=' cicd/tool-versions.env" "context: ${wfCtxDir:-none}" 'load: true' \
	'cache-from: type=gha' 'cache-to: type=gha' 'CICD_IMAGE_PREBUILT: "1"' 'run: bash cicd/cicd.bash --container --quick -y --no-sync --no-publish --no-dogfood'; do
	[[ "${wfCi}" == *"${wfWant}"* ]] || wfMiss+="[${wfWant}] "
done
while read -r wfFrom; do
	[[ "${wfCi}" == *[[:space:]]"${wfFrom}="* ]] || wfMiss+="[context ${wfFrom}] "
done < <(sed -n 's/^COPY --from=\([A-Za-z0-9_-]*\) .*/\1/p' "${meDir}/../${wfCtxDir:-none}/Dockerfile" 2>/dev/null)
{ [[ -n "${wfCtxDir}" && -z "${wfMiss}" ]] && grep -q '^COPY --from=' "${meDir}/../${wfCtxDir}/Dockerfile"; } && _pass Et9etgg "ci.yml builds the image cicd.bash runs" \
	|| _fail Et9etgg "ci.yml builds the image cicd.bash runs" "missing: ${wfMiss}"
## Hosted CI gets a new volume each run, a copy of the image's /cache, so a
## root-owned dir there broke the Go cache only on the runner. The Dockerfile's
## last RUN refuses one at build time; layers after it would get past it.
wfLastRun="$(grep -E '^RUN ' "${meDir}/../${wfCtxDir:-none}/Dockerfile" 2>/dev/null | tail -n 1)"
[[ "${wfLastRun}" == *"find /cache/home "* ]] && _pass EtAgsNr "the image's last step checks /cache/home is empty" \
	|| _fail EtAgsNr "the image's last step checks /cache/home is empty" "last RUN=[${wfLastRun}]"
if [[ "${CICD_IN_CONTAINER:-0}" == "1" && "$(id -u)" != "0" ]]; then
	wfRootOwned="$(find "${HOME}" -mindepth 1 -maxdepth 2 -user 0 2>/dev/null | head -n 5 || true)"
	[[ -z "${wfRootOwned}" ]] && _pass EtAgsOV "nothing root-owned in the container's HOME" \
		|| _fail EtAgsOV "nothing root-owned in the container's HOME" "found=[${wfRootOwned//$'\n'/ }]"
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Remote sync and the merge gate, on scratch repos with a bare origin. The
## engine is the CI engine copy above, with its config.
section "Remote sync and merge gate"
syDir="${CBT_TMP}/sy"; syA="${syDir}/a"; syB="${syDir}/b"
mkdir -p "${syDir}/home" "${syDir}/tmp"
fSyGit(){ env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE HOME="${syDir}/home" git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=dev "$@"; }
fSyGit init -q --bare "${syDir}/o.git"
fSyGit init -q "${syA}"
mkdir -p "${syA}/cicd/utility/include" "${syA}/lib"
cp "${ceRepo}/cicd/cicd.bash" "${ceRepo}/cicd/config.bash" "${syA}/cicd/"
cp "${ceRepo}/cicd/utility/include/gfs-rotate.bash" "${ceRepo}/cicd/utility/include/machine-use.bash" "${syA}/cicd/utility/include/"
cp "${meDir}/utility/pre-push" "${syA}/cicd/utility/"
cp "${ceRepo}/lib/out" "${syA}/lib/"
printf '%s\n' '[[ -z "${CE_GATE_FAIL:-}" ]] || UNIT_TEST_CMD=(false)' >>"${syA}/cicd/config.bash"
printf '%s\n' 'lib/bin/' 'prof/' >"${syA}/.gitignore"; printf 'one\n' >"${syA}/notes.txt"
fSyGit -C "${syA}" add -A; fSyGit -C "${syA}" commit -qm one
fSyGit -C "${syA}" config user.name t; fSyGit -C "${syA}" config user.email t@example.com
fSyGit -C "${syA}" remote add origin "${syDir}/o.git"; fSyGit -C "${syA}" push -q -u origin dev 2>/dev/null
fSyGit clone -q "${syDir}/o.git" "${syB}" 2>/dev/null
fSyPushB(){ printf '%s\n' "$2" >>"${syB}/$1"; fSyGit -C "${syB}" commit -qam "b $1"; fSyGit -C "${syB}" push -q origin dev 2>/dev/null; }
fSyRun(){
	syRc=0
	( cd "${syDir}" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u CICDTEST_EXE -u CICDTEST_DO_LONGTEST -u CICDTEST_DO_PERF -u CICDTEST_QUICK \
		HOME="${syDir}/home" TMPDIR="${syDir}/tmp" PATH="${ceBin}:${PATH}" CE_KNOBS="${syDir}/knobs" CICD_NO_SKIP=0 CICD_IN_CONTAINER=0 \
		bash "${syA}/cicd/cicd.bash" -y "$@" </dev/null >"${CBT_OUT}" 2>&1 ) || syRc=$?
	syOut="$(<"${CBT_OUT}")"
}
fSyTail(){ printf 'rc=%s out=[%s]' "${syRc}" "$(tail -5 "${CBT_OUT}" | tr '\n' ' ')"; }
fSyHead(){ fSyGit -C "$1" rev-parse HEAD; }

## Behind only: fast-forwards, and an edit in the tree comes through it.
fSyPushB notes.txt two; printf 'mine\n' >"${syA}/lib/out.note"; printf 'edit\n' >>"${syA}/.gitignore"
fSyRun
{ ((syRc == 0)) && [[ "${syOut}" == *"OK: fast-forwarded 1 commit(s) from origin/dev"* && "$(fSyHead "${syA}")" == "$(fSyHead "${syB}")" ]] \
	&& grep -qx edit "${syA}/.gitignore" && [[ -f "${syA}/lib/out.note" && -z "$(fSyGit -C "${syA}" stash list)" ]]; } && _pass EshVwHv "sync: behind, fast-forward" \
	|| _fail EshVwHv "sync: behind, fast-forward" "$(fSyTail)"
{ [[ -x "${syA}/.git/hooks/pre-push" ]] && grep -qF 'cicd/utility/pre-push' "${syA}/.git/hooks/pre-push"; } && _pass EshVwIZ "gate hook added" \
	|| _fail EshVwIZ "gate hook added" "hook=[$(cat "${syA}/.git/hooks/pre-push" 2>&1)]"
fSyGit -C "${syA}" checkout -q -- .gitignore

## --no-sync leaves it behind.
fSyPushB notes.txt three; syWas="$(fSyHead "${syA}")"
fSyRun --no-sync
{ ((syRc == 0)) && [[ "$(fSyHead "${syA}")" == "${syWas}" && "${syOut}" != *"fast-forwarded"* ]]; } && _pass EshVwJC "sync: --no-sync" \
	|| _fail EshVwJC "sync: --no-sync" "$(fSyTail)"

## A change to the pipeline itself starts the run over on the new copy.
fSyPushB cicd/config.bash '## from b'
fSyRun
{ ((syRc == 0)) && [[ "${syOut}" == *"OK: fast-forwarded 2 commit(s)"* && "${syOut}" == *"starting over"* && "${syOut}" == *"OK: integration harness"* ]] \
	&& [[ "$(grep -c 'fast-forwarded' <<<"${syOut}")" == 1 ]]; } && _pass EshVwJp "sync: pipeline changed, restart" \
	|| _fail EshVwJp "sync: pipeline changed, restart" "$(fSyTail)"

## Diverged stops before anything is built.
fSyPushB notes.txt four; printf 'a\n' >>"${syA}/notes.txt"; fSyGit -C "${syA}" commit -qam "a"
fSyRun
{ ((syRc == 1)) && [[ "${syOut}" == *"have diverged (1 ahead, 1 behind)"* && "${syOut}" != *"1/8  Format"* ]]; } && _pass EshVwKS "sync: diverged stops" \
	|| _fail EshVwKS "sync: diverged stops" "$(fSyTail)"
fSyGit -C "${syA}" reset -q --hard origin/dev

## No upstream, or no remote to reach, warns and goes on.
fSyGit -C "${syA}" checkout -q -b solo
fSyRun
{ ((syRc == 0)) && [[ "${syOut}" == *"WARNING: no upstream branch"* && "${syOut}" == *"OK: integration harness"* ]]; } && _pass EshVwL6 "sync: no upstream warns" \
	|| _fail EshVwL6 "sync: no upstream warns" "$(fSyTail)"
fSyGit -C "${syA}" checkout -q dev
fSyGit -C "${syA}" remote set-url origin "${syDir}/gone.git"
fSyRun
{ ((syRc == 0)) && [[ "${syOut}" == *"WARNING: couldn't fetch"* && "${syOut}" == *"OK: integration harness"* ]]; } && _pass EshVwLj "sync: offline warns" \
	|| _fail EshVwLj "sync: offline warns" "$(fSyTail)"
fSyGit -C "${syA}" remote set-url origin "${syDir}/o.git"

## The hook gates dev and main only, and not a delete or a publish.
syZeros="0000000000000000000000000000000000000000"; syHeadA="$(fSyHead "${syA}")"
fSyHook(){
	syRc=0
	( cd "${syA}" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u CICD_GATE_PASSED HOME="${syDir}/home" TMPDIR="${syDir}/tmp" PATH="${ceBin}:${PATH}" "$@" \
		bash "${syA}/.git/hooks/pre-push" origin "${syDir}/o.git" <<<"${syLine}" >"${CBT_OUT}" 2>&1 ) || syRc=$?
	syOut="$(<"${CBT_OUT}")"
}
syLine="refs/heads/dev ${syHeadA} refs/heads/dev ${syZeros}"; fSyHook env
syDev=0; { ((syRc == 0)) && [[ "${syOut}" == *"OK: gate passed"* && "${syOut}" != *"1/8"* ]]; } && syDev=1
syLine="refs/heads/x ${syHeadA} refs/heads/feature ${syZeros}"; fSyHook env
syFeat=0; { ((syRc == 0)) && [[ -z "${syOut}" ]]; } && syFeat=1
syLine="(delete) ${syZeros} refs/heads/main ${syHeadA}"; fSyHook env
syDel=0; { ((syRc == 0)) && [[ -z "${syOut}" ]]; } && syDel=1
syLine="refs/heads/dev ${syHeadA} refs/heads/dev ${syZeros}"; fSyHook env CICD_GATE_PASSED=1
syPub=0; { ((syRc == 0)) && [[ -z "${syOut}" ]]; } && syPub=1
((syDev && syFeat && syDel && syPub)) && _pass EshVwMN "pre-push: dev/main only" \
	|| _fail EshVwMN "pre-push: dev/main only" "dev=${syDev} feature=${syFeat} delete=${syDel} publish=${syPub} $(fSyTail)"

## A failed gate refuses the push, and a hook already there is left alone.
syLine="refs/heads/main ${syHeadA} refs/heads/main ${syZeros}"; fSyHook env CE_GATE_FAIL=1
{ ((syRc != 0)) && [[ "${syOut}" == *"running the merge gate"* && "${syOut}" != *"OK: gate passed"* ]]; } && _pass EshVwNd "pre-push: failed gate refuses" \
	|| _fail EshVwNd "pre-push: failed gate refuses" "$(fSyTail)"
printf '%s\n' '#!/bin/sh' 'exit 0' >"${syDir}/mine"; chmod +x "${syDir}/mine"
fSyGit -C "${syA}" config core.hooksPath "${syDir}/hooks2"; mkdir -p "${syDir}/hooks2"; cp "${syDir}/mine" "${syDir}/hooks2/pre-push"
fSyRun --gate
{ ((syRc == 0)) && cmp -s "${syDir}/mine" "${syDir}/hooks2/pre-push" && [[ "${syOut}" == *"OK: gate passed"* && "${syOut}" != *"added the pre-push hook"* ]]; } && _pass EshVwMz "gate keeps an existing hook" \
	|| _fail EshVwMz "gate keeps an existing hook" "$(fSyTail)"
fSyGit -C "${syA}" config --unset core.hooksPath


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Harness self-check. This whole run again, against a program that refuses
## everything, with Go off the PATH and the perf section on. Nearly every check
## fails, and each failure has to be counted and the run carried on to the
## summary. A section that needs Go skips instead. A fake go stands in for a
## missing one, since go can share a dir with tools the run needs.
if [[ "${CICDTEST_SELFCHECK:-0}" != "1" ]]; then
	section "Harness self-check"
	hsDir="${CBT_TMP}/hs"; mkdir -p "${hsDir}/bin" "${hsDir}/tmp"
	printf '%s\n' '#!/bin/sh' 'echo "refused" >&2' 'exit 1' >"${hsDir}/refuse"
	printf '%s\n' '#!/bin/sh' 'echo "go: command not found" >&2' 'exit 127' >"${hsDir}/bin/go"
	chmod +x "${hsDir}/refuse" "${hsDir}/bin/go"
	hsrc=0
	CICDTEST_SELFCHECK=1 CICDTEST_EXE="${hsDir}/refuse" CICDTEST_DO_LONGTEST=0 CICDTEST_DO_PERF=1 CICDTEST_QUICK=1 CICDTEST_FUZZ_ITERS=2 CICD_NO_SKIP=1 \
		TMPDIR="${hsDir}/tmp" PATH="${hsDir}/bin:${PATH}" bash "${meDir}/test.bash" </dev/null >"${hsDir}/out" 2>&1 || hsrc=$?
	hsSummary="$(grep -E 'FAIL +[0-9]+ of [0-9]+ checks failed' "${hsDir}/out" || true)"
	hsAbort="$(grep -F 'HARNESS ABORTED' "${hsDir}/out" | head -3 || true)"
	{ ((hsrc == 1)) && [[ -n "${hsSummary}" && -z "${hsAbort}" ]]; } && _pass ErmGPkH "all-fail run reaches summary" \
		|| _fail ErmGPkH "all-fail run reaches summary" "rc=${hsrc} aborts=[${hsAbort}] tail=[$(tail -3 "${hsDir}/out" | tr '\n' ' ')]"
	## Under CICD_NO_SKIP the skips Go's absence caused fail the run, and the
	## one --quick asked for doesn't.
	hsNoSkip="$(grep -F 'skipped under CICD_NO_SKIP=1: ' "${hsDir}/out" || true)"
	{ [[ "${hsNoSkip}" == *Elmd2Y4* && "${hsNoSkip}" != *ErlP6B8* ]]; } && _pass EsJjVsP "NO_SKIP asked vs unasked" \
		|| _fail EsJjVsP "NO_SKIP asked vs unasked" "line=[${hsNoSkip}]"
	grep -qF 'reactor module skipped: needs a Go 1.24+ toolchain' "${hsDir}/out" && _pass ErmGPkf "reactor skip, no Go" \
		|| _fail ErmGPkf "reactor skip, no Go" "no skip line for the reactor section"
	hsGoFail="$(grep -oE ' FAIL (EloQXv[6-9]|ErftBA[89A-D]) ' "${hsDir}/out" | sort -u | tr -d '\n' || true)"
	{ grep -qF 'frontend parity skipped: needs a Go toolchain' "${hsDir}/out" && grep -qF 'macOS universal binary tests skipped: needs a Go toolchain' "${hsDir}/out" \
		&& [[ -z "${hsGoFail}" ]]; } && _pass ErmzVUR "parity/macOS skip, no Go" \
		|| _fail ErmzVUR "parity/macOS skip, no Go" "skip lines missing or failures: [${hsGoFail}]"
	## A failed interop check names the first sample that differs.
	if command -v node >/dev/null 2>&1 && [[ -d "${meDir}/utility/interop/thirdparty" ]]; then
		hsDiff="$(grep -m1 -A1 -F 'interop encode == qntm base2048' "${hsDir}/out" | tail -1 || true)"
		[[ "${hsDiff}" =~ ^\ +sample\ [0-9]+\ of\ [0-9]+/[0-9]+:\  ]] && _pass ErmGPl4 "interop failure detail" \
			|| _fail ErmGPl4 "interop failure detail" "detail=[${hsDiff}]"
	else
		_warn ErmGPl4 "interop detail not checked: needs node and the vendored references"
	fi
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Performance: streaming throughput of the binary path (long test only)
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## A repeatable throughput baseline for the streaming binary<->text path, with
## the system base64 alongside for context. Round-trips must still be
## bit-perfect; the numbers are informational and guard against regressions.
if ((doPerf)); then
	section "Performance and profiling"
	perf_mib=4
	perfsrc="${CBT_TMP}/perf_src"; perfmid="${CBT_TMP}/perf_mid"; perfout="${CBT_TMP}/perf_out"
	head -c "$((perf_mib * 1024 * 1024))" /dev/urandom >"$perfsrc"
	for base in 16 64u; do
		t0=$(date +%s.%N)
		"${TIMEOUT[@]}" "${EXE}" --from bytes --to "$base" <"$perfsrc" >"$perfmid" 2>/dev/null || true
		"${TIMEOUT[@]}" "${EXE}" --from "$base" --to bytes <"$perfmid" >"$perfout" 2>/dev/null || true
		t1=$(date +%s.%N)
		if cmp -s "$perfsrc" "$perfout"; then
			mbps=$(awk "BEGIN{d=$t1-$t0; if(d>0) printf \"%.1f\", 2*$perf_mib/d; else print \"inf\"}")
			_pass EjGnHfk "perf ${base}: ${perf_mib} MiB round-trip (~${mbps} MiB/s)"
		else
			_fail EjGnHfk "perf ${base} round-trip" "output mismatch"
		fi
	done
	if command -v base64 >/dev/null 2>&1; then
		t0=$(date +%s.%N); base64 <"$perfsrc" >/dev/null; t1=$(date +%s.%N)
		refbps=$(awk "BEGIN{d=$t1-$t0; if(d>0) printf \"%.1f\", $perf_mib/d; else print \"inf\"}")
		printf '  %sreference: system base64 encode ~%s MiB/s%s\n' "${dim}" "$refbps" "${rst}"
	fi

	## Resource profile: peak memory and wall time for a large streaming encode,
	## via GNU time when available. Informational, but it flags a memory or speed
	## regression the throughput number alone would miss.
	if [[ -x /usr/bin/time ]]; then
		prof="${CBT_TMP}/prof"
		/usr/bin/time -v "${EXE}" --from bytes --to 64u <"$perfsrc" >"$perfmid" 2>"$prof" || true
		peak=$(awk -F': ' '/Maximum resident set size/{print $2}' "$prof")
		wall=$(awk -F': ' '/wall clock/{print $NF}' "$prof")
		printf '  %sprofile: base64url encode of %s MiB - peak RSS %s KiB, wall %s%s\n' "${dim}" "$perf_mib" "${peak:-?}" "${wall:-?}" "${rst}"
	fi

	## Peak memory must not scale with input size for any base that streams. This
	## is the guard that matters for the multi-byte bases: if one of them quietly
	## stops taking the streaming path it still produces correct output, just at
	## several hundred MiB instead of about twenty, which no round-trip check sees.
	if [[ -x /usr/bin/time ]]; then
		memsrc="${CBT_TMP}/mem_src"; memenc="${CBT_TMP}/mem_enc"; memprof="${CBT_TMP}/mem_prof"
		mem_mib=24
		mem_ceiling=120000 # KiB; streaming sits near 20 MiB, buffered runs 10-25x the input
		head -c "$((mem_mib * 1024 * 1024))" /dev/urandom >"$memsrc"
		## Every power-of-2 base, since which of the two streaming paths a base
		## takes depends on its symbol widths, and that is exactly what a new or
		## renamed base changes. The codecs are left out: they still buffer.
		for base in "${POW2_BASES[@]}"; do
			/usr/bin/time -f '%M' "${EXE}" --from bytes --to "$base" --no-newline <"$memsrc" >"$memenc" 2>"$memprof" || true
			encpeak=$(tail -1 "$memprof")
			/usr/bin/time -f '%M' "${EXE}" --from "$base" --to bytes <"$memenc" >/dev/null 2>"$memprof" || true
			decpeak=$(tail -1 "$memprof")
			if [[ "$encpeak" =~ ^[0-9]+$ && "$decpeak" =~ ^[0-9]+$ ]] \
				&& ((encpeak < mem_ceiling && decpeak < mem_ceiling)); then
				_pass El5P4dl "constant memory via ${base} (${mem_mib} MiB in, peak ${encpeak}/${decpeak} KiB)"
			else
				_fail El5P4dl "constant memory via ${base}" "peak enc=${encpeak} dec=${decpeak} KiB, ceiling ${mem_ceiling}"
			fi
		done
	fi

	## Throughput of a non-power-of-2 binary-to-text codec (base91), so a speed
	## regression in the codec path shows up next to the bit-packing numbers. Must
	## still round-trip bit-perfectly.
	cxsrc="${CBT_TMP}/cx_src"; cxmid="${CBT_TMP}/cx_mid"; cxout="${CBT_TMP}/cx_out"
	cx_mib=1; ((doLong)) && cx_mib=4
	head -c "$((cx_mib * 1024 * 1024))" /dev/urandom >"$cxsrc"
	t0=$(date +%s.%N)
	"${TIMEOUT[@]}" "${EXE}" --from bytes --to 91hk --no-newline <"$cxsrc" >"$cxmid" 2>/dev/null || true
	"${TIMEOUT[@]}" "${EXE}" --from 91hk --to bytes --no-newline <"$cxmid" >"$cxout" 2>/dev/null || true
	t1=$(date +%s.%N)
	if cmp -s "$cxsrc" "$cxout"; then
		cxbps=$(awk "BEGIN{d=$t1-$t0; if(d>0) printf \"%.1f\", 2*$cx_mib/d; else print \"inf\"}")
		_pass EjK8KIq "codec profile: ${cx_mib} MiB base-91 round-trip (~${cxbps} MiB/s)"
	else
		_fail EjK8KIq "codec profile round-trip" "output mismatch"
	fi
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Summary
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
printf '\n%s' "${b}"
printf '========================================================================%s\n' "${rst}"
for w in "${WARNINGS[@]}"; do printf '%s  SKIPPED  %s%s\n' "${ylw}" "$w" "${rst}"; done
## With every tool installed, a skip nobody asked for means one is missing after all.
noSkipFail=0
if [[ "${CICD_NO_SKIP:-0}" == "1" ]] && ((${#UNASKED[@]})); then
	noSkipFail=1
	printf '%s  FAIL  skipped under CICD_NO_SKIP=1: %s%s\n' "${red}${b}" "${UNASKED[*]}" "${rst}"
fi
if ((FAIL == 0 && ! noSkipFail)); then
	printf '%s  PASS  %d/%d checks%s\n' "${grn}${b}" "$PASS" "$TOTAL" "${rst}"
	exit 0
fi
if ((FAIL)); then
	printf '%s  FAIL  %d of %d checks failed%s\n' "${red}${b}" "$FAIL" "$TOTAL" "${rst}"
	for f in "${FAILURES[@]}"; do printf '    %s- %s%s\n' "${red}" "$f" "${rst}"; done
fi
exit 1


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##	Script history:
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##		- 2026-07-03 JC: Rewrote as a self-contained, table-driven harness. Bases enumerated from the binary, so new bases are covered automatically. Added security/robustness and binary-alignment checks. Prior harness kept under legacy/.
