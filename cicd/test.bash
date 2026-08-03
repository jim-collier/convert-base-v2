#!/usr/bin/env bash

#  shellcheck disable=1091  ## 'source is valid here, but shellcheck doesn't know the path to it.'
#  shellcheck disable=2001  ## 'See if you can use ${variable//search/replace} instead.' Complains about good uses of sed.
#  shellcheck disable=2016  ## 'Expressions don't expand in single quotes, use double quotes for that.' I know, and I often want an explicit '$'.
#  shellcheck disable=2034  ## 'variable appears unused.' Complains about valid use of variable indirection (e.g. later use of local -n var=$1)
#  shellcheck disable=2046  ## 'Quote to prevent word-splitting.' (OK for integers.)
#  shellcheck disable=2086  ## 'Double quote to prevent globbing and word splitting.' (OK for integers.)
#  shellcheck disable=2155  ## 'Declare and assign separately to avoid masking return values.' Cumbersome and unnecessary.
#  shellcheck disable=2162  ## 'read without -r will mangle backslashes.'
#  shellcheck disable=2154  ## 'referenced but not assigned.' False hit on trap strings that assign the var they use (rc=$?).
#  shellcheck disable=2181  ## 'Check exit code directly, not indirectly with $?.'
#  shellcheck disable=2207  ## 'Prefer mapfile or read -a to split command output.'
#  shellcheck disable=2317  ## 'Can't reach.' (an 'exit' used for debugging makes a visual mess.)

##	Purpose:
##		- Exhaustive, CI-friendly test harness for convert-base-v2. Exits non-zero if any check fails.
##		- Table-driven so cases are cheap to add: a check is one line (mode, label, expected, then the argv).
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
##			- Cross-check against the bundled convert-base-v1 and convert-base-v1b scripts: a base both tools share is checked against both, a base only one has is checked against that one. Every output base each tool offers is either mapped or listed as excused, so a gap can't go unnoticed. A missing script skips its suite with a warning that the summary repeats.
##		- Knobs (env):
##			- CICDTEST_EXE ..........: path to the binary under test (default: ../lib/bin/convert-base-v2).
##			- CICDTEST_DO_LONGTEST ..: 1 for the exhaustive run (more fuzz iterations, larger inputs).
##			- CICDTEST_FUZZ_ITERS ...: override the fuzz iteration count.
##	History: At bottom of script.

##	Copyright © 2023-2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
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

## Guard against hangs: a check that doesn't return quickly is a failure, not a wait.
TIMEOUT=(); command -v timeout >/dev/null 2>&1 && TIMEOUT=(timeout 60)

## Colors + counters.
b=$'\e[1m'; dim=$'\e[2m'; grn=$'\e[32m'; red=$'\e[31m'; ylw=$'\e[33m'; rst=$'\e[0m'
declare -i TOTAL=0 PASS=0 FAIL=0
declare -a FAILURES=() WARNINGS=()

CBT_OUT="$(mktemp)"; CBT_ERR="$(mktemp)"; CBT_TMP="$(mktemp -d)"
cleanup(){ rm -rf "${CBT_OUT}" "${CBT_ERR}" "${CBT_TMP}"; }
trap cleanup EXIT

## Sandbox the user config: the binary writes a default one on its first run,
## and that must land here, not in whoever's home is running the tests. The
## warm-up run does the creating, so no later check sees the one-time note.
export XDG_CONFIG_HOME="${CBT_TMP}/xdg"
"${TIMEOUT[@]}" "${EXE}" --get-index-count >/dev/null 2>&1 || true
trap 'rc=$?; printf "\n%sHARNESS ABORTED (exit %s) at line %s: %s%s\n" "${red}" "$rc" "$LINENO" "$BASH_COMMAND" "${rst}" >&2; exit $rc' ERR

section(){ printf '\n%s>>> %s%s\n' "${b}" "$*" "${rst}"; }

## _run ARGS...           : run EXE with ARGS (argv, never a shell string), capture _out/_err/_rc.
## _run_in FILE ARGS...   : same, but feed FILE on stdin.
_run(){    _rc=0; "${TIMEOUT[@]}" "${EXE}" "$@"        >"${CBT_OUT}" 2>"${CBT_ERR}" || _rc=$?; _out="$(cat "${CBT_OUT}")"; _err="$(cat "${CBT_ERR}")"; }
_run_in(){ local f="$1"; shift; _rc=0; "${TIMEOUT[@]}" "${EXE}" "$@" <"$f" >"${CBT_OUT}" 2>"${CBT_ERR}" || _rc=$?; _out="$(cat "${CBT_OUT}")"; _err="$(cat "${CBT_ERR}")"; }

_pass(){ PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); printf '%s  ok  %s%s\n' "${dim}" "$1" "${rst}"; }
_fail(){ FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); printf '%s FAIL %s%s\n       %s\n' "${red}" "$1" "${rst}" "$2"; FAILURES+=("$1 :: $2"); }
## A suite that did not run at all. Not a failure, but it must not read as one
## more quiet line either, so the summary repeats every one of these.
_warn(){ printf '%s SKIP %s%s\n' "${ylw}" "$1" "${rst}"; WARNINGS+=("$1"); }

## Assert against the last _run/_run_in result.
##   _assert MODE LABEL EXPECTED
##   MODE: eq | ne | ok | err | errmsg  (errmsg checks stderr contains EXPECTED)
_assert(){
	local mode="$1" label="$2" expected="${3:-}"
	if ((_rc == 124)); then _fail "$label" "timed out"; return; fi
	case "$mode" in
		eq)     { ((_rc == 0)) && [[ "$_out" == "$expected" ]]; } && _pass "$label" || _fail "$label" "rc=$_rc out=[$_out] want=[$expected] err=[$_err]" ;;
		ne)     { ((_rc == 0)) && [[ "$_out" != "$expected" ]]; } && _pass "$label" || _fail "$label" "rc=$_rc out=[$_out] should-differ-from=[$expected]" ;;
		ok)     ((_rc == 0)) && _pass "$label" || _fail "$label" "expected success, rc=$_rc err=[$_err]" ;;
		err)    ((_rc != 0)) && _pass "$label" || _fail "$label" "expected failure, got rc=0 out=[$_out]" ;;
		errmsg) { ((_rc != 0)) && [[ "$_err" == *"$expected"* ]]; } && _pass "$label" || _fail "$label" "rc=$_rc err=[$_err] want-substr=[$expected]" ;;
		*)      _fail "$label" "unknown assert mode '$mode'" ;;
	esac
}

## check MODE LABEL EXPECTED -- ARGS...   (ARGS go straight to the binary as argv)
check(){ local mode="$1" label="$2" expected="$3"; shift 3; [[ "${1:-}" == "--" ]] && shift; _run "$@"; _assert "$mode" "$label" "$expected"; }

## Random base-10 integer, 1..maxlen digits, no leading zeros.
_rand_int(){
	local -i maxlen="$1"
	local -i len=$(( 1 + $(od -An -N2 -tu2 /dev/urandom) % maxlen ))
	local digits; digits="$(head -c "$len" /dev/urandom | od -An -tu1 -v | tr ' ' '\n' | grep -E '[0-9]' | awk '{printf "%d", $1 % 10}')"
	digits="${digits:0:len}"
	digits="${digits#"${digits%%[!0]*}"}"
	[[ -z "$digits" ]] && digits="0"
	printf '%s' "$digits"
}

## One 16-bit unsigned random number (0..65535). Enough to index the largest base.
_rand16(){ od -An -N2 -tu2 /dev/urandom | tr -d ' '; }


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## CLI surface
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "CLI surface"
_run --version
{ ((_rc == 0)) && [[ "$_out" == v* ]]; } && _pass "--version prints a version" || _fail "--version prints a version" "rc=$_rc out=[$_out]"
check ok  "--help exits 0"          -   --help
check ok  "-h exits 0"              -   -h
check ok  "--examples exits 0"      -   --examples
## Explicit --help/--examples go to stdout so they can be piped (BxZNl-18).
_run --help
{ ((_rc == 0)) && [[ -n "$_out" ]] && [[ "$_out" == *Usage* ]]; } && _pass "--help writes to stdout" || _fail "--help writes to stdout" "rc=$_rc outlen=${#_out}"
_run --examples
{ ((_rc == 0)) && [[ -n "$_out" ]] && [[ "$_out" == *Examples* ]]; } && _pass "--examples writes to stdout" || _fail "--examples writes to stdout" "rc=$_rc outlen=${#_out}"
## No-args error path keeps help on stderr, exit 2, stdout empty.
_run
{ ((_rc == 2)) && [[ -z "$_out" ]] && [[ -n "$_err" ]]; } && _pass "no-args help stays on stderr" || _fail "no-args help stays on stderr" "rc=$_rc outlen=${#_out} errlen=${#_err}"
_run --list
{ ((_rc == 0)) && [[ "$_out" == *NAME* ]]; } && _pass "--list lists bases" || _fail "--list lists bases" "rc=$_rc"
## --list has an INDEX column, and row 0's name matches --by-index=0 (BxZNl-19).
_run --list
{ ((_rc == 0)) && [[ "$_out" == *INDEX* ]]; } && _pass "--list has an INDEX column" || _fail "--list has an INDEX column" "rc=$_rc"
## awk consumes the whole stream (NR==2 is the first data row) to avoid a SIGPIPE.
list_idx0="$("${EXE}" --list 2>/dev/null | awk 'NR==2{print $2}')"
byidx0="$("${EXE}" --get-base-name --by-index=0 2>/dev/null)"
[[ "$list_idx0" == "$byidx0" && -n "$byidx0" ]] && _pass "--list INDEX 0 matches --by-index=0" || _fail "--list INDEX 0 matches --by-index=0" "list=[$list_idx0] byidx=[$byidx0]"
## --list-compat shows only the v1/v1b compatibility bases, --list only the rest,
## and the two together cover every index exactly once. A compat base must still
## be reachable by name, it just isn't advertised in the everyday listing.
list_n="$("${EXE}" --list 2>/dev/null | awk '$1 ~ /^[0-9]+$/' | wc -l)"
compat_n="$("${EXE}" --list-compat 2>/dev/null | awk '$1 ~ /^[0-9]+$/' | wc -l)"
total_n="$("${EXE}" --get-index-count 2>/dev/null)"
(( compat_n > 0 )) && _pass "--list-compat lists compatibility bases (${compat_n})" || _fail "--list-compat lists compatibility bases" "got ${compat_n}"
(( list_n + compat_n == total_n )) && _pass "--list plus --list-compat covers every index" || _fail "--list plus --list-compat covers every index" "list=${list_n} compat=${compat_n} total=${total_n}"
_run --list
{ ((_rc == 0)) && [[ "$_out" != *_compat_* ]]; } && _pass "--list hides compatibility bases" || _fail "--list hides compatibility bases" "rc=$_rc"
check eq  "compat base still resolves" 128_compat_v1 -- --get-base-name 128v1compat
## The README bases table is generated from the binary, so a renamed base leaves
## it pointing at a name that no longer exists. Nothing else notices that.
README_MD="${meDir}/../README.md"
if [[ -r "${README_MD}" ]]; then
	readme_stale=""; readme_n=0
	while read -r rname; do
		readme_n=$((readme_n + 1))
		"${TIMEOUT[@]}" "${EXE}" --get-base-name "$rname" >/dev/null 2>&1 || readme_stale+=" ${rname}"
	done < <(grep -oP '^\| *[0-9]+ \| *\K[^ |]+' "${README_MD}" | sort -u)
	{ (( readme_n >= 20 )) && [[ -z "$readme_stale" ]]; } \
		&& _pass "README bases table resolves (${readme_n} names)" \
		|| _fail "README bases table resolves" "scraped=${readme_n} stale:${readme_stale:- none}"
else
	_warn "README bases table not checked: no readable file at ${README_MD}"
fi
## --by-index outside a query mode is ignored, with a stderr note.
_run --by-index 3 255 16
{ ((_rc == 0)) && [[ "$_out" == FF ]] && [[ "$_err" == *"--by-index is ignored"* ]]; } && _pass "--by-index note in conversion mode" || _fail "--by-index note in conversion mode" "rc=$_rc out=[$_out] err=[$_err]"

## Base-introspection query flags (used by the full-coverage fuzz below).
_run --get-index-count
{ ((_rc == 0)) && [[ "$_out" =~ ^[0-9]+$ ]] && ((_out > 0)); } && _pass "--get-index-count prints a count" || _fail "--get-index-count prints a count" "rc=$_rc out=[$_out]"
check eq     "--get-base-name --by-index=0" 2               -- --get-base-name --by-index=0
check eq     "--get-base-name alias hex"    16              -- --get-base-name hex
check errmsg "--by-index out of range"      'out of range'  -- --get-base-name --by-index=999999
check errmsg "query needs a selector"       'select a base' -- --get-base-name
_run --show-symbols 16
{ ((_rc == 0)) && [[ "$_out" == "0123456789ABCDEF" ]]; } && _pass "--show-symbols 16 concatenates 16 symbols" || _fail "--show-symbols 16 concatenates 16 symbols" "rc=$_rc out=[$_out]"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Basic conversions and aliases
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Basic conversions and aliases"
check eq  "255 -> 16"               FF        -- 255 16
check eq  "255 -> 8"                377       -- 255 8
check eq  "255 -> 2"                11111111  -- 255 2
check eq  "hex FF -> 10"            255       -- --from 16 FF
check eq  "bin 11111111 -> 10"     255       -- --from 2 11111111
check eq  "alias hex -> 10"         255       -- --from hex FF
check eq  "alias octal out"         377       -- 255 octal
check eq  "alias decimal in"        2A        -- --from decimal 42 16
check eq  "leading zeros ignored"   FF        -- 000255 16
check eq  "--to flag beats posn"    FF        -- --to 16 255 10
## "base"/"base-"/"base_"/"base " prefix on any name or alias.
check eq  "base16 prefix"           FF        -- 255 base16
check eq  "base-16 prefix"          FF        -- 255 base-16
check eq  "base_16 prefix"          FF        -- 255 base_16
check eq  "base hex prefix"         FF        -- 255 "base hex"
check eq  "base-hex prefix in"      255       -- --from base-hex FF
check eq  "base_ prefix on alias"   255       -- --from base_hex FF
## Crockford base32 is asymmetric: reads O as 0, I/L as 1 (case-insensitive),
## but never emits them. O1=1, I1=L1=33, LO=32; output for 24 stays R (no O/I/L).
check eq  "32c decode O->0"          1         -- --from 32c --to 10 -- O1
check eq  "32c decode o->0"          1         -- --from 32c --to 10 -- o1
check eq  "32c decode I->1"          33        -- --from 32c --to 10 -- I1
check eq  "32c decode L->1"          33        -- --from 32c --to 10 -- L1
check eq  "32c decode l->1"          33        -- --from 32c --to 10 -- l1
check eq  "32c encode stays strict"  r         -- --from 10 --to 32c -- 24


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Negatives, fractionals, precision, lower, raw
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Negatives, fractionals, precision, lower, raw"
check eq  "negative -- guard"       -1E240    -- -- -123456 16
check eq  "fractional 1.5 -> 16"    1.8       -- 1.5 16
## 1.5 -> base3 is 1.1111...; at precision 2 it rounds half-up (0.111.. -> "12"3), not truncates.
check eq  "fractional rounding"     1.12      -- --precision 2 1.5 3
## More fixed fractional pins (fuzz only does integers, so the frac path needs
## its own coverage): signed fractions, a clean power-of-two fraction, and the
## imprecise 0.1 tail rounded to precision.
check eq  "fraction 0.5 -> 16"       0.8       -- --number 0.5 16
check eq  "neg fraction -0.5 -> 2"   -0.1      -- --number --precision 6 -- -0.5 2
check eq  "neg mixed -255.5 -> 16"   -FF.8     -- --number -- -255.5 16
check eq  "fraction 255.5 -> 16"     FF.8      -- --number 255.5 16
check eq  "fraction 0.1 -> 16 p6"     0.19999A -- --number --precision 6 0.1 16
## Auto precision (the default): output frac length tracks the input's scaled by
## base size, so a short decimal input does not grow an invented tail. Weird
## corners: widening (dec->bin), narrowing (hex->dec), an odd base ratio, a
## terminating value that trims, and a big base down to a small one.
check eq  "auto 0.1 -> 16"            0.1A      -- --number 0.1 16
check eq  "auto 0.1 -> 2"             0.00011   -- --number 0.1 2
check eq  "auto 0.1 -> 3"             0.0022    -- --number 0.1 3
check eq  "auto FF.8 -> 10"           255.5     -- --from 16 --to 10 FF.8
check eq  "auto 0.5 -> 2 (trims)"     0.1       -- --number 0.5 2
check eq  "auto 0.9 -> 2 (round up)"  0.11101   -- --number 0.9 2
check eq  "auto 288 -> 10"            0.0035    -- --from 288j1 --to 10 0.1
check eq  "auto tiny 0.000001 -> 16"  0.000011  -- --number 0.000001 16
## Independent (non-round-trip) known-value pins for bases that otherwise only
## get self-round-trip fuzz, so a bug mirrored in encode+decode can't hide.
check eq  "pin 1000000 -> 60tc"      4cmf      -- --number 1000000 60tc
check eq  "pin 65535 -> 60tc"        JCF       -- --number 65535 60tc
check eq  "pin 1000000 -> 62"        4C92      -- --number 1000000 62
check eq  "pin 1000000 -> 36"        LFLS      -- --number 1000000 36
check eq  "pin 1000000 -> 85ipv6"    1rYy      -- --number 1000000 85ipv6
check eq  "pin 65535 -> 62"          H31       -- --number 65535 62
check eq  "--lower on hex"          ff        -- --lower 255 16
check errmsg "--lower on mixed-case" "--lower is invalid for mixed-case" -- --lower 9 62
## --no-newline: exact bytes, no trailing newline.
_run --no-newline 255 16
{ ((_rc == 0)) && [[ "$(wc -c <"${CBT_OUT}")" == "2" ]]; } && _pass "--no-newline has no trailing newline" || _fail "--no-newline has no trailing newline" "bytes=$(wc -c <"${CBT_OUT}")"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Custom symbol specs
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Custom symbol specs"
check eq  "custom in, fractional"   148.25    -- --from-symbols ABCD --to 10 CBBA.B
check eq  "custom out, neg+dec"     -9FCC.8M6 -- --from-symbols "aeiouy.-_0" --from-neg "~" --from-dec "/" --to 20ws "~y0-._/ooo"
## Markers are separate from the symbols. The retired in-string tokens must be an
## error, never silently absorbed as a digit.
check errmsg "retired neg= token"   'no longer part of the symbol spec' -- --from-symbols "0123456789 neg=~" --to 10 5
check errmsg "retired dec= token"   'no longer part of the symbol spec' -- --from-symbols "0123456789 dec=," --to 10 5
check errmsg "retired pad= token"   'no longer part of the symbol spec' -- --from-symbols "0123456789 pad==" --to 10 5
## Markers apply to named bases too, not just custom alphabets.
check eq  "marker on named base"    -255      -- --from 16 --from-neg "~" --to 10 "~ff"
check eq  "marker on output base"   "~FF"     -- --from 10 --to 16 --to-neg "~" -- -255
check errmsg "marker collides"      'is also a digit' -- --from 16 --from-neg "a" --to 10 ff
check errmsg "markers vs bytes"     'carries raw bytes' -- --from bytes --from-neg "~" --to 16 5
check ok  "custom both sides"       -         -- --from-symbols ABCD --to-symbols 0123 CBBA
check errmsg "one-symbol spec fails" 'at least 2 symbols' -- --from-symbols A 5 16
## Spec parser edge cases: multi-token comma split makes a base-4 alphabet
## (decimal 3 stays a single digit "3"; the old bug made it base-3); escaped
## space is a literal-space digit; a digit that contains a marker is rejected.
check eq  "spec comma-split -> base4"  3        -- --number --from 10 --to-symbols "0,1 2 3" 3
check eq  "spec escaped-space digit"   2        -- --from-symbols 'a\ b' --to 10 -- b
check err "spec marker-in-digit"       -        -- --from-symbols "a b a.b" --to 10 -- a.b
## 85ps carries a literal comma and backslash as their own digits; its alphabet
## must stay exactly 85 symbols (regression pin for the escape/comma-split bug).
sym85=$("${EXE}" --show-symbols-0 85ps 2>/dev/null | tr '\0' '\n' | grep -c .)
[[ "$sym85" == 85 ]] && _pass "85ps has exactly 85 symbols" || _fail "85ps has exactly 85 symbols" "got=$sym85"

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
check eq  "config base loads"        yx        -- --config "$cfg" --from 10 --to myb 6
check errmsg "config base absent otherwise" 'unknown base' -- --from 10 --to myb 6
check errmsg "explicit missing config errors" 'no such file' -- --config "${CBT_TMP}/nope.shcl" 255 16
## Extra names from the aliases field; the "base:" line stays canonical.
check eq  "config alias resolves"    yx        -- --config "$cfg" --from 10 --to mb 6
check eq  "config canonical name"    myb       -- --config "$cfg" --get-base-name mybase
## A marker set, and a marker switched off on purpose by leaving it empty.
check eq  "config negative marker"   N11       -- --config "$cfg" --from 10 --to u12 -- -13
check errmsg "config empty marker disables" 'no decimal marker' -- --config "$cfg" --from 10 --to nodec 12.5
## Both list spellings: stacked one per line, and inline with a symbol that
## carries a space of its own.
check eq  "config stacked list"      '🍊🍋'    -- --config "$cfg" --from 10 --to fruit4 6
spacesym=$("${EXE}" --config "$cfg" --show-symbols-0 spacey 2>/dev/null | tr '\0' '|')
[[ "$spacesym" == 'a b|c|d|e' ]] && _pass "config symbol with a space" || _fail "config symbol with a space" "got='$spacesym'"
## A typo has to fail loudly: silently dropping a field means the wrong alphabet.
printf 'base: x\n\tsybmols: abc\n' >"${CBT_TMP}/typo.shcl"
check errmsg "config typo rejected"  'unknown base field' -- --config "${CBT_TMP}/typo.shcl" 255 16
printf 'base: x\n\tsymbols: abc\n  bogus indent\n' >"${CBT_TMP}/bad.shcl"
check errmsg "config bad line rejected" 'line 3'          -- --config "${CBT_TMP}/bad.shcl" 255 16
## First run writes the default config, and 10emoji comes from it rather than
## from the built-in set. XDG_CONFIG_HOME was sandboxed at the top of the run.
usercfg="${XDG_CONFIG_HOME}/convert-base-v2/convert-base-v2.shcl"
[[ -s "$usercfg" ]] && _pass "first run creates the user config" || _fail "first run creates the user config" "missing $usercfg"
check eq  "10emoji comes from config"  '😑😔😘😜' -- --from 10 --to 10emoji 1234
check eq  "10emoji keeps its old name" '😑😔😘😜' -- --from 10 --to emoji10 1234


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Errors and robustness (security by construction: input is argv, never eval'd)
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Errors and robustness"
check errmsg "unknown base"         'unknown base'                       -- 10 nope
## Friendlier stumble messages (BxZNl-16).
check errmsg "unknown base near-match" 'did you mean "hex"'              -- 255 hexx
check errmsg "unknown base to --list"  'see --list'                      -- 255 nope
check errmsg "flags after number"      'flags must come before'          -- 255 16 --lower
check errmsg "neg number without --"   'a "--" separator'                -- -123 16
check errmsg "unknown flag hint"       'unknown flag'                    -- --lowr 255 16
check errmsg "bad digit for base"   'not in base'                        -- --from 2 9
check errmsg "extra positional"     'unexpected extra positional'        -- 1 2 3
check errmsg "precision < 0"        'non-negative integer or'            -- --precision -1 1
check errmsg "precision bad word"   'non-negative integer or'            -- --precision foo 1 16
check errmsg "empty input"          'empty input'                        -- "" 16
check err   "multiple decimals"     -                                     -- --from 10 1.2.3 16
check err   "double negative"       -                                     -- -- --5 16

## Conflicting base selectors: still convert, but emit a stderr note (BxZNl-17).
_run --to 16 255 8
{ ((_rc == 0)) && [[ "$_out" == FF ]] && [[ "$_err" == *"overrides positional output base"* ]]; } && _pass "conflict note: --to over positional" || _fail "conflict note: --to over positional" "rc=$_rc out=[$_out] err=[$_err]"
_run --from 16 --from-symbols 01 10 10
{ ((_rc == 0)) && [[ "$_out" == 2 ]] && [[ "$_err" == *"--from-symbols overrides --from"* ]]; } && _pass "conflict note: --from-symbols over --from" || _fail "conflict note: --from-symbols over --from" "rc=$_rc out=[$_out] err=[$_err]"
_run --to 16 255 hex
{ ((_rc == 0)) && [[ "$_out" == FF ]] && [[ -z "$_err" ]]; } && _pass "no conflict note when --to and positional agree" || _fail "no conflict note when --to and positional agree" "rc=$_rc out=[$_out] err=[$_err]"

## Shell-metachar / injection strings are just invalid digits: must error, never execute.
sentinel="${CBT_TMP}/PWNED"
check err "injection: command sub"  -   -- '$(touch '"${sentinel}"')' 16
check err "injection: backticks"    -   -- '`touch '"${sentinel}"'`' 16
check err "injection: semicolon"    -   -- 'touch '"${sentinel}"'; echo' 16
[[ ! -e "$sentinel" ]] && _pass "injection created no file" || _fail "injection created no file" "sentinel exists: $sentinel"

## Oversized input stays bounded and correct (round-trips, does not hang or crash).
biglen=2000; ((doLong)) && biglen=8000
big="$(_rand_int "$biglen")"
_run --from 10 --to 62 -- "$big"; enc="$_out"
if ((_rc == 0)); then
	_run --from 62 --to 10 -- "$enc"
	{ ((_rc == 0)) && [[ "$_out" == "$big" ]]; } && _pass "oversized input round-trips (${#big} digits)" || _fail "oversized input round-trips" "mismatch or rc=$_rc"
else
	_fail "oversized input round-trips" "encode rc=$_rc err=[$_err]"
fi

## Invalid UTF-8 on stdin must fail gracefully (no hang, no crash).
printf '\xff\xfe\x00\x9c' >"${CBT_TMP}/badutf8"
_run_in "${CBT_TMP}/badutf8" --from 2048qntm -
((_rc != 0 && _rc != 124)) && _pass "invalid UTF-8 stdin errors gracefully" || _fail "invalid UTF-8 stdin errors gracefully" "rc=$_rc"


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
(( ${#RAW_BASES[@]} >= 8 ))   && _pass "raw-base scrape found bases (${#RAW_BASES[@]})"          || _fail "raw-base scrape found bases" "only ${#RAW_BASES[@]} scraped (--list format changed?)"
(( ${#POW2_BASES[@]} >= 20 )) && _pass "power-of-2 scrape found bases (${#POW2_BASES[@]})" || _fail "power-of-2 scrape found bases" "only ${#POW2_BASES[@]} scraped (--list format changed?)"

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
		{ ((rc1 == 0 && rc2 == 0)) && cmp -s "$src" "$out"; } || { p2fail=$((p2fail+1)); p2detail="n=${n} rc1=${rc1} rc2=${rc2} err=[$(cat "${CBT_ERR}")]"; }
	done
	((p2fail == 0)) && _pass "binary round-trip via ${base} (all lengths, bit-perfect)" || _fail "binary round-trip via ${base}" "${p2fail} lengths mismatched, last: ${p2detail}"
done
## Raw binary round-trips through every base the tool advertises as a codec (the
## RAW column of --list): power-of-2 bases via bit-packing, plus base45, ascii85,
## z85, and base91 via their own schemes. Blob lengths force partial final chunks
## so padding/tail handling is exercised; Z85 requires 4-aligned input, so its
## lengths are rounded down. --no-newline both ways stays byte-exact for bases that carry
## newline as a digit.
raw_all_fail=0; raw_all_n=0
for base in "${RAW_BASES[@]}"; do
	for n in 1 2 3 4 5 7 8 11 13 16 17 31 63 100 255 257 $(( 1 + $(_rand16) % 512 )); do
		len=$n
		[[ "$base" == "85z" ]] && len=$(( (n / 4) * 4 )) # Z85: multiple of 4 only
		src="${CBT_TMP}/ra_src"; mid="${CBT_TMP}/ra_mid"; out="${CBT_TMP}/ra_out"
		head -c "$len" /dev/urandom >"$src"
		rc1=0; rc2=0
		"${TIMEOUT[@]}" "${EXE}" --from bytes --to "$base" --no-newline <"$src" >"$mid" 2>"${CBT_ERR}" || rc1=$?
		"${TIMEOUT[@]}" "${EXE}" --from "$base" --to bytes --no-newline <"$mid" >"$out" 2>"${CBT_ERR}" || rc2=$?
		raw_all_n=$((raw_all_n + 1))
		{ ((rc1 == 0 && rc2 == 0)) && cmp -s "$src" "$out"; } || { raw_all_fail=$((raw_all_fail+1)); _fail "raw round-trip ${base} n=${len}" "rc1=$rc1 rc2=$rc2 err=[$(cat "${CBT_ERR}")]"; }
	done
done
((raw_all_fail == 0)) && _pass "raw round-trip, all codec bases (${#RAW_BASES[@]} bases, ${raw_all_n} blobs)" || printf '  %s%d raw round-trip failures above%s\n' "${red}" "$raw_all_fail" "${rst}"

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
	((wrapfail == 0)) && _pass "wrapped input decodes via ${base}" || _fail "wrapped input decodes via ${base}" "${wrapfail} failures"
done

## A base the tool does NOT advertise as a codec (RAW column "-") must refuse raw
## binary, not silently mis-handle it. Spot-check a spread, including the two
## whole-value base-N encoding (base85-RFC1924) that deliberately doesn't stream.
for base in 10 62 keyboard 60tc 85ipv6 26 36; do
	rc=0; printf 'hi' | "${TIMEOUT[@]}" "${EXE}" --from bytes --to "$base" >/dev/null 2>"${CBT_ERR}" || rc=$?
	((rc != 0)) && _pass "non-codec base ${base} refuses raw binary" || _fail "non-codec base ${base} refuses raw binary" "expected error, got rc=0"
done

## Fixed vectors for the binary-to-text codecs, straight from each official spec
## (RFC 9285, Adobe Ascii85, ZeroMQ RFC 32, basE91). Exact bytes -> exact text,
## so a codec regression is caught precisely, not just as a round-trip drift.
cvec(){ # LABEL BASE INPUT_HEX EXPECTED_TEXT
	local label="$1" base="$2" hex="$3" want="$4" src got
	src="${CBT_TMP}/cv_src"
	printf '%b' "$(printf '%s' "$hex" | sed 's/../\\x&/g')" >"$src"
	got=$("${TIMEOUT[@]}" "${EXE}" --from bytes --to "$base" --no-newline <"$src" 2>"${CBT_ERR}")
	[[ "$got" == "$want" ]] && _pass "codec vector ${label}" || _fail "codec vector ${label}" "want=[$want] got=[$got]"
}
cvec "base45 AB"       45   4142             "BB8"
cvec "base45 ietf!"    45   6965746621       "QED8WEX0"
cvec "ascii85 sure."   85ps 737572652e       "F*2M7/c"
cvec "ascii85 zeros"   85ps 00000000         "z"
cvec "z85 helloworld"  85z  864fd26fb559f75b "HelloWorld"
cvec "base91 test"     91hk 74657374         "fPNKd"
## The four big bases match the published third-party layouts byte-for-byte.
## These fixed vectors (input bytes -> exact output code points) guard that
## interop; they come straight from the reference implementations. Each pins the
## tail/secondary-block handling, and for 65536 the little-endian byte order.
nvec(){ # LABEL BASE INPUT_HEX EXPECTED_CODEPOINTS(space-separated hex)
	local label="$1" base="$2" hex="$3" cps="$4" src exp="" got cp
	src="${CBT_TMP}/nv_src"
	printf '%b' "$(printf '%s' "$hex" | sed 's/../\\x&/g')" >"$src"
	for cp in $cps; do exp+=$(printf "\\U$(printf '%08x' "0x${cp}")"); done
	got=$("${TIMEOUT[@]}" "${EXE}" --from bytes --to "$base" <"$src" 2>"${CBT_ERR}")
	[[ "$got" == "$exp" ]] && _pass "native vector ${label}" \
		|| _fail "native vector ${label}" "want=[$cps] got=[$(printf '%s' "$got" | od -An -tx1 | tr -d '\n')]"
}
nvec "65536 lone byte"   65536qntm   00         1500
nvec "65536 byte order"  65536qntm   0102       3601
nvec "65536 pair+tail"   65536qntm   010203     "3601 1503"
nvec "65536 high block"  65536qntm   ffff       285FF
nvec "65536 Hello"       65536qntm   48656c6c6f "9A48 A36C 156F"
nvec "32768 one byte"    32768qntm   00         06BF
nvec "32768 two bytes"   32768qntm   0000       "04A0 025F"
nvec "32768 short tail"  32768qntm   000000000000 "04A0 04A0 04A0 018F"
nvec "2048 one byte"     2048qntm 00         0046
nvec "2048 two bytes"    2048qntm 0000       "0038 0110"
nvec "2048 three-bit tail" 2048qntm 010203   "0047 01B7 0037"
nvec "rust one byte"     2048llfourn    00         00D8
nvec "rust tail zero"    2048llfourn    000000     "00D8 00D8 0F0D"
nvec "rust tail three"   2048llfourn    010203     "00C5 0140 0F10"

## RFC 4648 padding: every RFC variant (base64 s4, base32 s6, and the URL/hex
## variants 64u/64h/32h) emits '=' padding to the group boundary in codec mode
## (vectors from RFC 4648 s10). Number-mode output is never padded. Decode is
## lenient: padded or unpadded input both accepted.
pipecheck(){ # LABEL FROM TO INPUT EXPECTED
	local label="$1" f="$2" t="$3" in="$4" want="$5" got
	got=$(printf '%s' "$in" | "${TIMEOUT[@]}" "${EXE}" --from "$f" --to "$t" 2>"${CBT_ERR}")
	[[ "$got" == "$want" ]] && _pass "$label" || _fail "$label" "in='$in' want='$want' got='$got'"
}
pipecheck "rfc64 pad f"        bytes 64  "f"        "Zg=="
pipecheck "rfc64 pad fo"       bytes 64  "fo"       "Zm8="
pipecheck "rfc64 pad foobar"   bytes 64  "foobar"   "Zm9vYmFy"
pipecheck "rfc32 pad f"        bytes 32  "f"        "MY======"
pipecheck "rfc32 pad foob"     bytes 32  "foob"     "MZXW6YQ="
pipecheck "rfc32 pad foobar"   bytes 32  "foobar"   "MZXW6YTBOI======"
pipecheck "base64url pad foob" bytes 64u "foob"     "Zm9vYg=="
pipecheck "base64hex pad foob" bytes 64h "foob"     "PczlOW=="
pipecheck "base32hex pad f"    bytes 32h "f"        "CO======"
pipecheck "base64 strips pad"  64  bytes "Zm9vYmFy" "foobar"
pipecheck "base64url takes pad" 64u bytes "Zm9vYg==" "foob"
## Decode still accepts UNPADDED input on the now-padded variants.
pipecheck "base64url takes unpadded" 64u bytes "Zm9vYg" "foob"
## Number-mode output is never padded, even for the RFC variants.
pipecheck "base64url number unpadded" 10 64u "255" "D_"

## Custom (user-defined) bases can opt into the same padding with --to-pad.
## This custom alphabet mirrors RFC 4648 base32, so its padded output must match.
B32C="ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
padgot=$(printf 'A' | "${TIMEOUT[@]}" "${EXE}" --from bytes --to-symbols "$B32C" --to-pad "=" 2>"${CBT_ERR}")
[[ "$padgot" == "IE======" ]] && _pass "custom base32 emits pad" || _fail "custom base32 emits pad" "got='$padgot'"
padrt=$(printf 'A' | "${TIMEOUT[@]}" "${EXE}" --from bytes --to-symbols "$B32C" --to-pad "=" 2>/dev/null | "${TIMEOUT[@]}" "${EXE}" --from-symbols "$B32C" --from-pad "=" --to bytes 2>"${CBT_ERR}")
[[ "$padrt" == "A" ]] && _pass "custom pad round-trips" || _fail "custom pad round-trips" "got='$padrt'"
padun=$(printf 'IE' | "${TIMEOUT[@]}" "${EXE}" --from-symbols "$B32C" --from-pad "=" --to bytes 2>"${CBT_ERR}")
[[ "$padun" == "A" ]] && _pass "custom pad decode takes unpadded" || _fail "custom pad decode takes unpadded" "got='$padun'"
check errmsg "pad collides with digit" 'is also a digit' -- --from-symbols "0123456789ABCDEF" --from-pad "A" --to 10 5
## A pad is only ever applied on the bit-packed path, one character at a time.
## Definitions that could never take effect are rejected where they are written.
check errmsg "multi-char pad rejected" 'must be a single character' -- --from bytes --to 64 --to-pad "==" 5
check errmsg "pad above 8 bits rejected" 'at most 256 symbols' -- --from bytes --to 512tt --to-pad "=" 5
check errmsg "pad on non-2^N rejected" 'at most 256 symbols' -- --from bytes --to 45 --to-pad "=" 5

## A user-defined base above 8 bits streams only once it declares a tail. Without
## one the packing writes a leading length, which can't be known while streaming.
SYM512=""; for ((cp=0x4E00; cp<0x5000; cp++)); do SYM512+=$(printf "\\U$(printf '%08x' "$cp")")" "; done
tailrt=$(head -c 37 /bin/cat | "${TIMEOUT[@]}" "${EXE}" --from bytes --to-symbols "$SYM512" --to-tail "⸐ ⸑" -n 2>/dev/null \
	| "${TIMEOUT[@]}" "${EXE}" --from-symbols "$SYM512" --from-tail "⸐ ⸑" --to bytes -n 2>"${CBT_ERR}" | md5sum | cut -d' ' -f1)
tailwant=$(head -c 37 /bin/cat | md5sum | cut -d' ' -f1)
[[ "$tailrt" == "$tailwant" ]] && _pass "custom tail round-trips" || _fail "custom tail round-trips" "got='$tailrt'"
## The same base with no tail still round-trips, on the length-prefixed layout.
ntrt=$(head -c 37 /bin/cat | "${TIMEOUT[@]}" "${EXE}" --from bytes --to-symbols "$SYM512" -n 2>/dev/null \
	| "${TIMEOUT[@]}" "${EXE}" --from-symbols "$SYM512" --to bytes -n 2>"${CBT_ERR}" | md5sum | cut -d' ' -f1)
[[ "$ntrt" == "$tailwant" ]] && _pass "custom no-tail round-trips" || _fail "custom no-tail round-trips" "got='$ntrt'"
## A tail that could never be used is rejected where it is declared.
check errmsg "tail below 8 bits rejected" 'above 256 symbols' -- --from bytes --to 64 --to-tail "⸐ ⸑" 5
check errmsg "tail not power of 2 rejected" 'power of 2' -- --from bytes --to-symbols "$SYM512" --to-tail "⸐ ⸑ ⸒" 5
check errmsg "tail too narrow rejected" 'must be between' -- --from bytes --to 1024tt --to-tail "⸐ ⸑" 5
check errmsg "tail on bytes rejected" 'do not apply' -- --from bytes --to 16 --from-tail "⸐ ⸑" 5

## Same tail declared in a config file rather than on the command line.
tailcfg="${CBT_TMP}/tail.shcl"
printf -- 'base: cfgtail\n\tsymbols: "%s"\n\ttail: "⸐ ⸑"\n' "$SYM512" >"$tailcfg"
cfgrt=$(head -c 37 /bin/cat | "${TIMEOUT[@]}" "${EXE}" --config "$tailcfg" --from bytes --to cfgtail -n 2>/dev/null \
	| "${TIMEOUT[@]}" "${EXE}" --config "$tailcfg" --from cfgtail --to bytes -n 2>"${CBT_ERR}" | md5sum | cut -d' ' -f1)
[[ "$cfgrt" == "$tailwant" ]] && _pass "config tail round-trips" || _fail "config tail round-trips" "got='$cfgrt'"

## Odd-length hex has no whole-byte representation: decoding to binary must error.
check errmsg "odd hex -> binary guarded" 'cannot decode to binary' -- --from 16 --to bytes ABC


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## --binary: byte re-encoding between two text bases (like basenc)
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Without a mode flag, two power-of-2 text bases convert numerically (leading
## zeros dropped) and a note goes to stderr. --binary routes through the bytes
## base so the result matches the two-stage pipe and basenc byte-for-byte.
section "--binary byte mode"

## Known vector: the four bytes 0xDE 0xAD 0xBE 0xEF as base64.
bm=$("${TIMEOUT[@]}" "${EXE}" --binary --from 16 --to 64 deadbeef 2>/dev/null)
[[ "$bm" == "3q2+7w==" ]] && _pass "--binary hex->64 (argv)" || _fail "--binary hex->64 (argv)" "got='$bm'"

## Streaming (stdin) must match the argv result.
bms=$(printf 'deadbeef' | "${TIMEOUT[@]}" "${EXE}" --binary --from 16 --to 64 2>/dev/null)
[[ "$bms" == "3q2+7w==" ]] && _pass "--binary hex->64 (stream)" || _fail "--binary hex->64 (stream)" "got='$bms'"

## --binary must equal the explicit two-stage route through the bytes base.
bmp=$(printf 'deadbeef' | "${TIMEOUT[@]}" "${EXE}" --from 16 --to bytes 2>/dev/null | "${TIMEOUT[@]}" "${EXE}" --from bytes --to 32 2>/dev/null)
bm32=$("${TIMEOUT[@]}" "${EXE}" --binary --from 16 --to 32 deadbeef 2>/dev/null)
[[ "$bm32" == "$bmp" ]] && _pass "--binary == pipe-through-bytes (hex->32)" || _fail "--binary == pipe-through-bytes" "flag='$bm32' pipe='$bmp'"

## Aliases -b and --bin behave the same.
bmb=$(printf 'deadbeef' | "${TIMEOUT[@]}" "${EXE}" -b --from 16 --to 64 2>/dev/null)
bmbin=$(printf 'deadbeef' | "${TIMEOUT[@]}" "${EXE}" --bin --from 16 --to 64 2>/dev/null)
{ [[ "$bmb" == "3q2+7w==" ]] && [[ "$bmbin" == "3q2+7w==" ]]; } && _pass "--binary aliases -b/--bin" || _fail "--binary aliases -b/--bin" "b='$bmb' bin='$bmbin'"

## Round-trip through byte mode restores the bytes (case normalizes to base-16 canonical).
bmrt=$(printf 'deadbeef' | "${TIMEOUT[@]}" "${EXE}" -b --from 16 --to 64 2>/dev/null | "${TIMEOUT[@]}" "${EXE}" -b --from 64 --to 16 2>/dev/null)
[[ "$bmrt" == "DEADBEEF" ]] && _pass "--binary round-trip 16<->64" || _fail "--binary round-trip 16<->64" "got='$bmrt'"

## A non-power-of-2 base has no byte encoding: --binary must error.
check errmsg "--binary rejects non-pow2" 'byte mode requires a power-of-2' -- --binary --from 10 --to 64 255

## --binary and --number are mutually exclusive.
check errmsg "--binary + --number conflict" 'not both' -- --binary --number --from 16 --to 64 dead

## The ambiguity note: fires on pow2->pow2 with no mode flag, on stderr only, and
## stdout still carries the numeric result.
_run --from 16 --to 64 deadbeef
{ ((_rc == 0)) && [[ "$_out" == "Derb7v" ]] && [[ "$_err" == *"--binary"* ]]; } && _pass "pow2->pow2 note on stderr" || _fail "pow2->pow2 note on stderr" "out='$_out' err='$_err'"

## --number asserts numeric intent and silences the note.
_run --number --from 16 --to 64 deadbeef
{ ((_rc == 0)) && [[ "$_out" == "Derb7v" ]] && [[ -z "$_err" ]]; } && _pass "--number silences note" || _fail "--number silences note" "out='$_out' err='$_err'"

## -N alias silences too.
_run -N --from 16 --to 64 deadbeef
[[ -z "$_err" ]] && _pass "-N alias silences note" || _fail "-N alias silences note" "err='$_err'"

## No note when a non-power-of-2 base is involved (no byte ambiguity).
_run --from 10 --to 16 255
[[ -z "$_err" ]] && _pass "no note for non-pow2 conversion" || _fail "no note for non-pow2 conversion" "err='$_err'"


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
((kfail == 0)) && _pass "keyboard sample round-trips (base 16 and 10)" || _fail "keyboard sample round-trips" "${kfail} of 2 failed"
## Random text blobs of only valid keyboard bytes, forced to start on a non-tab
## byte so no leading digit is lost.
krand_fail=0
for len in 1 2 5 33 200 1500; do
	{ printf '#'; head -c "$((len * 8 + 64))" /dev/urandom | LC_ALL=C tr -cd '\11\12\15\40-\176' | head -c "$len"; } >"$ksrc" || true
	if "${TIMEOUT[@]}" "${EXE}" --from keyboard --to 16 <"$ksrc" >"$kmid" 2>"${CBT_ERR}" \
		&& "${TIMEOUT[@]}" "${EXE}" --from 16 --to keyboard --no-newline <"$kmid" >"$kout" 2>"${CBT_ERR}" \
		&& cmp -s "$ksrc" "$kout"; then :; else krand_fail=$((krand_fail+1)); fi
done
((krand_fail == 0)) && _pass "keyboard random text round-trips (6 blobs)" || _fail "keyboard random text round-trips" "${krand_fail} lengths mismatched"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Control-character escapes
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Tab, newline and return are digits of the keyboard base, so they can also be
## written as a name. Input takes raw and escaped forms mixed, always; output
## writes them only when asked. The pins are literal on both sides, so a change
## to either direction shows up here rather than cancelling itself out.
section "Control-character escapes"
kesc_lf=$'A\nB'
check eq "escape LF reads as the raw character"   "102225" -- --from keyboard --to 10 -n 'A⊳LFB'
check eq "raw LF reads the same"                  "102225" -- --from keyboard --to 10 -n "$kesc_lf"
check eq "lowercase name"                         "102225" -- --from keyboard --to 10 -n 'A⊳lfB'
check eq "NEWLINE alias"                          "102225" -- --from keyboard --to 10 -n 'A⊳NEWLINEB'
check eq "hex form"                               "102225" -- --from keyboard --to 10 -n 'A⊳x0AB'
check eq "escaped output"                         'A⊳LFB'  -- --from 10 --to keyboard --escape-controls -n 102225
check eq "output stays raw without the flag"      "$kesc_lf" -- --from 10 --to keyboard -n 102225
## Raw and escaped in one value, and the same value written the other way.
check eq "raw and escaped mixed"      "52830726402316" -- --from keyboard --to 10 -n 'x⊳HTy⊳CRz⊳LFw'
check eq "all three escaped on output" 'x⊳HTy⊳CRz⊳LFw' -- --from 10 --to keyboard --escape-controls -n 52830726402316
## A base with no control digits never grows an escape.
check eq "no escapes where there are no controls" '!4' -- --from 10 --to keyboard --escape-controls -n 6472
## --show-symbols is where the alphabet is actually legible.
_run --show-symbols --escape-controls keyboard
{ ((_rc == 0)) && [[ "$_out" == *'⊳HT⊳LF⊳CR'* ]]; } \
	&& _pass "--show-symbols escapes the control digits" \
	|| _fail "--show-symbols escapes the control digits" "rc=$_rc out=[$_out]"
## Guards.
check errmsg "unrecognized escape is an error"    "unrecognized escape" -- --from keyboard --to 10 -n 'A⊳ZZZB'
check errmsg "escape the base cannot carry"       "not in base"         -- --from 16 --to 10 -n '⊳LF'
check errmsg "escaping is refused in byte mode"   "number conversions only" -- --from 10 --to 16 --binary --escape-controls -n 65
## The marker is not a digit of any built-in base, so it is never mistaken for one.
check err "a bare marker is not a digit"          "" -- --from keyboard --to 10 -n 'A⊳'


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Fuzz: random values round-tripped through every defined base
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Fuzz round-trips (all bases)"
## Column 2 is NAME (column 1 is the INDEX). Both listings, so the compatibility
## bases get fuzzed too; the index filter drops the header rows.
mapfile -t BASE_NAMES < <("${EXE}" --list --list-compat 2>/dev/null | awk '$1 ~ /^[0-9]+$/ {print $2}')
## Floor check so a --list format change can't silently empty the fuzz set.
(( ${#BASE_NAMES[@]} >= 50 )) && _pass "base-name scrape found bases (${#BASE_NAMES[@]})" || _fail "base-name scrape found bases" "only ${#BASE_NAMES[@]} scraped (--list format changed?)"
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
((matrix_fail == 0)) && _pass "all-base matrix round-trip (${matrix_n} conversions)" || _fail "all-base matrix round-trip" "${matrix_fail} of ${matrix_n} failed"

## Randomized fuzz: random base, random large value.
iters="${CICDTEST_FUZZ_ITERS:-60}"; ((doLong)) && iters="${CICDTEST_FUZZ_ITERS:-800}"
maxlen=48; ((doLong)) && maxlen=160
fuzz_fail=0
for ((i=0; i<iters; i++)); do
	idx=$(( $(od -An -N2 -tu2 /dev/urandom) % ${#FUZZ_BASES[@]} ))
	base="${FUZZ_BASES[idx]}"
	val="$(_rand_int "$maxlen")"
	_run --from 10 --to "$base" -- "$val"; enc="$_out"; ((_rc == 0)) || { fuzz_fail=$((fuzz_fail+1)); _fail "fuzz enc base=$base val-len=${#val}" "rc=$_rc err=[$_err]"; continue; }
	## A lone "-" output (a base whose single digit is "-", e.g. hostname value 36)
	## is the read-stdin sentinel as a positional, so it can't round-trip via argv.
	[[ "$enc" == "-" ]] && continue
	_run --from "$base" --to 10 -- "$enc"
	{ ((_rc == 0)) && [[ "$_out" == "$val" ]]; } || { fuzz_fail=$((fuzz_fail+1)); _fail "fuzz round-trip base=$base" "val=[$val] enc=[$enc] got=[$_out] rc=$_rc"; }
done
((fuzz_fail == 0)) && _pass "randomized fuzz round-trip (${iters} iterations, maxlen ${maxlen})" || printf '  %s%d fuzz failures above%s\n' "${red}" "$fuzz_fail" "${rst}"

## Full-coverage symbol round-trip: for every base (not just a handful), build a
## random-length string from its own randomly chosen symbols, carry it through a
## random target base, and bring it back. Bases, names, and symbol alphabets all
## come from the binary itself (--get-index-count, --get-base-name, --show-symbols-0),
## so every defined base is exercised with no hand-maintained tables. The first
## symbol is kept off the zero digit so the source string is already canonical and
## a clean string compare is a valid round-trip check. The bytes base (raw bytes)
## is the one left out; it is covered bit-perfectly in its own section above.
n_bases="$("${EXE}" --get-index-count)"
declare -a IDX_NAME=()
for ((i=0; i<n_bases; i++)); do IDX_NAME[i]="$("${EXE}" --get-base-name --by-index="$i")"; done
declare -a ELIGIBLE=()
for ((i=0; i<n_bases; i++)); do
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
	local -i len=$(( 1 + $(_rand16) % maxlen ))
	local rand_vals; mapfile -t rand_vals < <(head -c $((2 * len)) /dev/urandom | od -An -v -tu2 | tr -s ' ' '\n' | grep -v '^$')
	local out=""; local -i j rand_val idx
	for ((j = 0; j < len; j++)); do
		rand_val=${rand_vals[j]:-0}
		if ((j == 0)); then idx=$(( 1 + rand_val % (size - 1) )); else idx=$(( rand_val % size )); fi
		out+="${syms[idx]}"
	done
	printf '%s' "$out"
}

symfuzz_fail=0; symfuzz_n=0
for ((i = 0; i < iters; i++)); do
	src_idx="${ELIGIBLE[$(( $(_rand16) % ${#ELIGIBLE[@]} ))]}"
	tgt_idx="${ELIGIBLE[$(( $(_rand16) % ${#ELIGIBLE[@]} ))]}"
	_load_syms "$src_idx"
	src_name="${IDX_NAME[src_idx]}"; tgt_name="${IDX_NAME[tgt_idx]}"
	src_str="$(_rand_symbols "$src_idx")"
	## A lone "-" as a positional value is the read-stdin sentinel, not a digit,
	## so a base that carries "-" in its alphabet (hostname, username, ...) can't
	## pass the single-digit "-" through argv. Skip just that one string on either
	## side; any longer value that merely contains "-" is unambiguous and fine.
	[[ "$src_str" == "-" ]] && continue
	_run --from "$src_name" --to "$tgt_name" -- "$src_str"; encoded="$_out"; ((_rc == 0)) || { symfuzz_fail=$((symfuzz_fail+1)); _fail "symbol fuzz enc $src_name->$tgt_name" "src=[$src_str] rc=$_rc err=[$_err]"; continue; }
	[[ "$encoded" == "-" ]] && continue
	_run --from "$tgt_name" --to "$src_name" -- "$encoded"; symfuzz_n=$((symfuzz_n + 1))
	{ ((_rc == 0)) && [[ "$_out" == "$src_str" ]]; } || { symfuzz_fail=$((symfuzz_fail+1)); _fail "symbol fuzz round-trip $src_name<->$tgt_name" "src=[$src_str] enc=[$encoded] got=[$_out] rc=$_rc"; }
done
((symfuzz_fail == 0)) && _pass "full-coverage symbol round-trip (${symfuzz_n} iterations, ${#ELIGIBLE[@]} bases, maxlen ${maxlen})" || printf '  %s%d symbol-fuzz failures above%s\n' "${red}" "$symfuzz_fail" "${rst}"


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

## fCheckCoverage LABEL MAPVAR ALLVAR EXCUSEDVAR
## A legacy base that no map reaches is a silent hole, and a map entry naming a
## base the tool doesn't have is a stale entry, so both directions are checked.
fCheckCoverage(){
	local label="$1"; local -n _map="$2" _all="$3" _excused="$4"
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
		&& _pass "${label} base coverage (${#_all[@]} bases, excused: ${note})" \
		|| _fail "${label} base coverage" "unmapped:${missing:- none} stale:${stale:- none}"
}

## fCheckLegacy BINARY LABEL MAP...
fCheckLegacy(){
	local exe="$1" label="$2"; shift 2
	local pair v2n lgn extra enc_fail rt_fail detail val o2 o1 back r
	local reps=3; ((doLong)) && reps=20
	for pair in "$@"; do
		v2n="${pair%%:*}"; lgn="${pair#*:}"; extra="${lgn#*:}"; lgn="${lgn%%:*}"
		[[ "$extra" == "$lgn" ]] && extra=""
		## A renamed v2 base would otherwise read as a byte mismatch on every
		## single value, which says nothing about what actually went wrong.
		if ! "${TIMEOUT[@]}" "${EXE}" --get-base-name "$v2n" >/dev/null 2>&1; then
			_fail "v2 base ${v2n} exists (mapped to ${label} ${lgn})" "unknown base - renamed or removed?"
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
		((enc_fail == 0)) && _pass "v2==${label} encode: ${v2n} (== ${label} ${lgn})" || _fail "v2==${label} encode: ${v2n} (== ${label} ${lgn})" "$detail"
		((rt_fail == 0))  && _pass "${label}->v2 round-trip: ${v2n} (from ${label} ${lgn})" || _fail "${label}->v2 round-trip: ${v2n} (from ${label} ${lgn})" "$detail"
	done
}

## Don't skip silently: a missing legacy script means that back-compat suite did
## not run, which is easy to mistake for "passed". The summary repeats it.
section "Back-compat vs v1 (byte-for-byte + round-trip)"
if [[ -x "${EXE_V1}" ]]; then
	fCheckCoverage v1 V1_MAP V1_BASES V1_EXCUSED
	fCheckLegacy "${EXE_V1}" v1 "${V1_MAP[@]}"
else
	_warn "v1 back-compat skipped: script not found at ${EXE_V1}"
fi

section "Back-compat vs v1b (byte-for-byte + round-trip)"
if [[ -x "${EXE_V1B}" ]]; then
	fCheckCoverage v1b V1B_MAP V1B_BASES V1B_EXCUSED
	fCheckLegacy "${EXE_V1B}" v1b "${V1B_MAP[@]}"
else
	_warn "v1b back-compat skipped: script not found at ${EXE_V1B}"
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
		if ((i <= 24)); then len=$i; else len=$(( 1 + $(_rand16) % 4096 )); fi
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
		_fail "interop ${label}" "reference adapter would not run: $(head -2 "${CBT_ERR}")"
		return
	fi

	while IFS= read -r hex; do
		printf '%b' "$(printf '%s' "$hex" | sed 's/../\\x&/g')" >"$bin"
		"${TIMEOUT[@]}" "${EXE}" --from bytes --to "$v2base" --no-newline <"$bin" 2>/dev/null || true
		echo
	done <"$samples" >"$ours"
	cmp -s "$ours" "$theirs" \
		&& _pass "interop encode == ${label} (${nSamples} samples)" \
		|| _fail "interop encode == ${label}" "$(fFirstDiff "$ours" "$theirs")"

	while IFS= read -r enc; do
		printf '%s' "$enc" >"$bin"
		"${TIMEOUT[@]}" "${EXE}" --from "$v2base" --to bytes <"$bin" 2>/dev/null | od -An -tx1 -v | tr -d ' \n' || true
		echo
	done <"$theirs" >"$ourdec"
	cmp -s "$ourdec" "$samples" \
		&& _pass "interop decode of ${label} output (${nSamples} samples)" \
		|| _fail "interop decode of ${label} output" "$(fFirstDiff "$ourdec" "$samples")"

	if ! "$@" decode <"$ours" >"$theirdec" 2>"${CBT_ERR}"; then
		_fail "interop ${label} reads our output" "reference adapter would not run: $(head -2 "${CBT_ERR}")"
		return
	fi
	cmp -s "$theirdec" "$samples" \
		&& _pass "interop ${label} reads our output (${nSamples} samples)" \
		|| _fail "interop ${label} reads our output" "$(fFirstDiff "$theirdec" "$samples")"
}

section "Interop vs the published reference implementations"
if [[ ! -d "${INTEROP_DIR}/thirdparty" ]]; then
	_warn "interop skipped: no vendored references at ${INTEROP_DIR}/thirdparty (utility/interop/fetch.bash --refresh)"
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
		_pass "interop references verbatim (${#INTEROP_PINS[@]} pinned packages)"
	else
		_fail "interop references verbatim" "$("${INTEROP_DIR}/fetch.bash" --verify 2>&1 | tail -2)"
	fi

	if command -v node >/dev/null 2>&1; then
		fCheckInterop 2048qntm  "qntm base2048 ${INTEROP_VER[base2048-qntm]}"   node "${INTEROP_QNTM}" 2048
		fCheckInterop 32768qntm "qntm base32768 ${INTEROP_VER[base32768-qntm]}" node "${INTEROP_QNTM}" 32768
		fCheckInterop 65536qntm "qntm base65536 ${INTEROP_VER[base65536-qntm]}" node "${INTEROP_QNTM}" 65536
	else
		_warn "interop vs qntm base2048/base32768/base65536 skipped: node not installed"
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
		_warn "interop vs llfourn base2048 skipped: no adapter binary and cargo could not build one"
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
goMinor="$(go env GOVERSION 2>/dev/null | sed -E 's/^go1\.([0-9]+).*$/\1/')"
if [[ ! "${goMinor}" =~ ^[0-9]+$ ]] || ((goMinor < 24)); then
	_warn "reactor module skipped: needs a Go 1.24+ toolchain (have $(go env GOVERSION 2>/dev/null || echo none))"
elif ! (cd "${meDir}/../lib" && GOOS=wasip1 GOARCH=wasm go build -trimpath -buildmode=c-shared -o "${REACTOR_WASM}" ./reactor) >"${CBT_ERR}" 2>&1; then
	_fail "reactor module build" "$(tail -2 "${CBT_ERR}")"
elif ! (cd "${REACTOR_HOST_DIR}" && go build -o "${CBT_TMP}/reactor-host" .) >"${CBT_ERR}" 2>&1; then
	_warn "reactor ABI skipped: host harness would not build (wazero not cached and offline?)"
elif "${CBT_TMP}/reactor-host" "${REACTOR_WASM}" >"${CBT_OUT}" 2>"${CBT_ERR}"; then
	_pass "reactor ABI (exports, conversions, metadata, streams, errors, leak loops)"
else
	_fail "reactor ABI" "$(tail -1 "${CBT_ERR}")"
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Frontend parity: the Go module and the reactor against the command
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Conversion behavior lives in the library, but each frontend has its own
## resolve-and-call plumbing, so the same requests run through all three: the
## command, the module natively (utility/module-driver), and the reactor
## (reactor-host --batch), and the answers must agree byte for byte. Every
## listed base, compat included, gets an integer both directions plus a signed
## fractional value; a base that can't represent one must refuse it in all
## three places, so agreement covers the error cases too. The compat and
## interop suites stay on the command alone on purpose: parity here extends
## what they establish to the other two frontends transitively.
section "Frontend parity"
MODDRV_DIR="${meDir}/utility/module-driver"
MODDRV="${CBT_TMP}/module-driver"
RHOST="${CBT_TMP}/reactor-host"
if ! (cd "${MODDRV_DIR}" && go build -o "${MODDRV}" .) >"${CBT_ERR}" 2>&1; then
	_fail "module driver build" "$(tail -2 "${CBT_ERR}")"
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
	(( ${#PARITY_BASES[@]} >= 30 )) && _pass "parity scrape found bases (${#PARITY_BASES[@]})" || _fail "parity scrape found bases" "only ${#PARITY_BASES[@]} scraped (--list format changed?)"
	for pname in "${PARITY_BASES[@]}"; do
		parity_case 10 "$pname" -1 "12345678901234567890"
		if [[ "$(tail -1 "$pcli")" == ok* ]]; then
			pfwd="$(tail -1 "$pcli" | cut -f2 | xxd -r -p)"
			parity_case "$pname" 10 -1 "$pfwd"
		fi
		parity_case 10 "$pname" 8 "-255.755"
	done
	if "${MODDRV}" <"$preq" >"$pout" 2>"${CBT_ERR}"; then
		cmp -s "$pcli" "$pout" && _pass "module answers match the command (${pn} cases)" || _fail "module answers match the command" "first diff: $(diff "$pcli" "$pout" | head -3 | tr '\n' ' ')"
	else
		_fail "module driver run" "$(tail -1 "${CBT_ERR}")"
	fi
	if [[ -x "$RHOST" && -s "$REACTOR_WASM" ]]; then
		if "$RHOST" --batch "$REACTOR_WASM" <"$preq" >"$pout" 2>"${CBT_ERR}"; then
			cmp -s "$pcli" "$pout" && _pass "reactor answers match the command (${pn} cases)" || _fail "reactor answers match the command" "first diff: $(diff "$pcli" "$pout" | head -3 | tr '\n' ' ')"
		else
			_fail "reactor batch run" "$(tail -1 "${CBT_ERR}")"
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
			[[ -z "$sfail" ]] && _pass "stream parity via ${pname}" || _fail "stream parity via ${pname}" "$sfail"
		done
	else
		_warn "reactor parity skipped: reactor module or host not built"
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
		"${TIMEOUT[@]}" "${EXE}" --from bytes --to "$base" <"$perfsrc" >"$perfmid" 2>/dev/null
		"${TIMEOUT[@]}" "${EXE}" --from "$base" --to bytes <"$perfmid" >"$perfout" 2>/dev/null
		t1=$(date +%s.%N)
		if cmp -s "$perfsrc" "$perfout"; then
			mbps=$(awk "BEGIN{d=$t1-$t0; if(d>0) printf \"%.1f\", 2*$perf_mib/d; else print \"inf\"}")
			_pass "perf ${base}: ${perf_mib} MiB round-trip (~${mbps} MiB/s)"
		else
			_fail "perf ${base} round-trip" "output mismatch"
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
				_pass "constant memory via ${base} (${mem_mib} MiB in, peak ${encpeak}/${decpeak} KiB)"
			else
				_fail "constant memory via ${base}" "peak enc=${encpeak} dec=${decpeak} KiB, ceiling ${mem_ceiling}"
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
	"${TIMEOUT[@]}" "${EXE}" --from bytes --to 91hk --no-newline <"$cxsrc" >"$cxmid" 2>/dev/null
	"${TIMEOUT[@]}" "${EXE}" --from 91hk --to bytes --no-newline <"$cxmid" >"$cxout" 2>/dev/null
	t1=$(date +%s.%N)
	if cmp -s "$cxsrc" "$cxout"; then
		cxbps=$(awk "BEGIN{d=$t1-$t0; if(d>0) printf \"%.1f\", 2*$cx_mib/d; else print \"inf\"}")
		_pass "codec profile: ${cx_mib} MiB base-91 round-trip (~${cxbps} MiB/s)"
	else
		_fail "codec profile round-trip" "output mismatch"
	fi
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Summary
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
printf '\n%s' "${b}"
printf '========================================================================%s\n' "${rst}"
for w in "${WARNINGS[@]}"; do printf '%s  SKIPPED  %s%s\n' "${ylw}" "$w" "${rst}"; done
if ((FAIL == 0)); then
	printf '%s  PASS  %d/%d checks%s\n' "${grn}${b}" "$PASS" "$TOTAL" "${rst}"
	exit 0
else
	printf '%s  FAIL  %d of %d checks failed%s\n' "${red}${b}" "$FAIL" "$TOTAL" "${rst}"
	for f in "${FAILURES[@]}"; do printf '    %s- %s%s\n' "${red}" "$f" "${rst}"; done
	exit 1
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##	Script history:
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##		- 2026-07-03 JC: Rewrote as a self-contained, table-driven harness. Bases enumerated from the binary, so new bases are covered automatically. Added security/robustness and binary-alignment checks. Prior harness kept under legacy/.
