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
##			- Binary/streaming: bit-perfect round-trips through power-of-2 bases, and the byte-alignment guard.
##			- Fuzz: random values round-tripped through every defined base (bases enumerated from the binary itself).
##			- Optional cross-check against the bundled v1 binary when present.
##		- Knobs (env):
##			- CICDTEST_EXE ..........: path to the binary under test (default: ../source/bin/convert-base-v2).
##			- CICDTEST_DO_LONGTEST ..: 1 for the exhaustive run (more fuzz iterations, larger inputs).
##			- CICDTEST_FUZZ_ITERS ...: override the fuzz iteration count.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail
export LANG="C.UTF-8" LC_ALL="C.UTF-8"

meDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

## Binary under test, and the optional v1 binary for back-compat cross-checks.
EXE="${CICDTEST_EXE:-${meDir}/../source/bin/convert-base-v2}"
EXE_V1B="${meDir}/utility/convert-base-v1b"
doLong=0; [[ "${CICDTEST_DO_LONGTEST:-0}" == "1" ]] && doLong=1

## Guard against hangs: a check that doesn't return quickly is a failure, not a wait.
TIMEOUT=(); command -v timeout >/dev/null 2>&1 && TIMEOUT=(timeout 60)

## Colors + counters.
b=$'\e[1m'; dim=$'\e[2m'; grn=$'\e[32m'; red=$'\e[31m'; ylw=$'\e[33m'; rst=$'\e[0m'
declare -i TOTAL=0 PASS=0 FAIL=0
declare -a FAILURES=()

CBT_OUT="$(mktemp)"; CBT_ERR="$(mktemp)"; CBT_TMP="$(mktemp -d)"
cleanup(){ rm -rf "${CBT_OUT}" "${CBT_ERR}" "${CBT_TMP}"; }
trap cleanup EXIT
trap 'rc=$?; printf "\n%sHARNESS ABORTED (exit %s) at line %s: %s%s\n" "${red}" "$rc" "$LINENO" "$BASH_COMMAND" "${rst}" >&2; exit $rc' ERR

section(){ printf '\n%s>>> %s%s\n' "${b}" "$*" "${rst}"; }

## _run ARGS...           : run EXE with ARGS (argv, never a shell string), capture _out/_err/_rc.
## _run_in FILE ARGS...   : same, but feed FILE on stdin.
_run(){    _rc=0; "${TIMEOUT[@]}" "${EXE}" "$@"        >"${CBT_OUT}" 2>"${CBT_ERR}" || _rc=$?; _out="$(cat "${CBT_OUT}")"; _err="$(cat "${CBT_ERR}")"; }
_run_in(){ local f="$1"; shift; _rc=0; "${TIMEOUT[@]}" "${EXE}" "$@" <"$f" >"${CBT_OUT}" 2>"${CBT_ERR}" || _rc=$?; _out="$(cat "${CBT_OUT}")"; _err="$(cat "${CBT_ERR}")"; }

_pass(){ PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); printf '%s  ok  %s%s\n' "${dim}" "$1" "${rst}"; }
_fail(){ FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); printf '%s FAIL %s%s\n       %s\n' "${red}" "$1" "${rst}" "$2"; FAILURES+=("$1 :: $2"); }

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


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## CLI surface
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "CLI surface"
_run --version
{ ((_rc == 0)) && [[ "$_out" == v* ]]; } && _pass "--version prints a version" || _fail "--version prints a version" "rc=$_rc out=[$_out]"
check ok  "--help exits 0"          -   --help
check ok  "-h exits 0"              -   -h
check ok  "--examples exits 0"      -   --examples
_run --list
{ ((_rc == 0)) && [[ "$_out" == *NAME* ]]; } && _pass "--list lists bases" || _fail "--list lists bases" "rc=$_rc"


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


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Negatives, fractionals, precision, lower, raw
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Negatives, fractionals, precision, lower, raw"
check eq  "negative -- guard"       -1E240    -- -- -123456 16
check eq  "fractional 1.5 -> 16"    1.8       -- 1.5 16
check eq  "precision clamp"         1.11      -- --precision 2 1.5 3
check eq  "--lower on hex"          ff        -- --lower 255 16
check errmsg "--lower on mixed-case" "--lower is invalid for mixed-case" -- --lower 9 62
## --raw: exact bytes, no trailing newline.
_run --raw 255 16
{ ((_rc == 0)) && [[ "$(wc -c <"${CBT_OUT}")" == "2" ]]; } && _pass "--raw has no trailing newline" || _fail "--raw has no trailing newline" "bytes=$(wc -c <"${CBT_OUT}")"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Custom symbol specs
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Custom symbol specs"
check eq  "custom in, fractional"   148.25    -- --from-symbols ABCD --to 10 CBBA.B
check eq  "custom out, neg+dec"     -9FCC.8M6 -- --from-symbols "aeiouy.-_0 neg=~ dec=/" --to 20w "~y0-._/ooo"
check ok  "custom both sides"       -         -- --from-symbols ABCD --to-symbols 0123 CBBA
check errmsg "one-symbol spec fails" 'at least 2 symbols' -- --from-symbols A 5 16


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Errors and robustness (security by construction: input is argv, never eval'd)
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Errors and robustness"
check errmsg "unknown base"         'unknown base'                       -- 10 nope
check errmsg "bad digit for base"   'not in base'                        -- --from 2 9
check errmsg "extra positional"     'unexpected extra positional'        -- 1 2 3
check errmsg "precision < 0"        'precision must be >= 0'             -- --precision -1 1
check errmsg "empty input"          'empty input'                        -- "" 16
check err   "multiple decimals"     -                                     -- --from 10 1.2.3 16
check err   "double negative"       -                                     -- -- --5 16

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
_run_in "${CBT_TMP}/badutf8" --from 2048twitter -
((_rc != 0 && _rc != 124)) && _pass "invalid UTF-8 stdin errors gracefully" || _fail "invalid UTF-8 stdin errors gracefully" "rc=$_rc"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Binary / streaming: bit-perfect round-trips + the byte-alignment guard
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Binary / streaming"
mkbin(){ head -c "$1" /dev/urandom >"$2"; }
for pair in "16" "64u" "32h" "64"; do
	src="${CBT_TMP}/bin_src"; mid="${CBT_TMP}/bin_mid"; out="${CBT_TMP}/bin_out"
	mkbin 777 "$src"
	rc1=0; rc2=0
	"${TIMEOUT[@]}" "${EXE}" --from binary --to "$pair" <"$src" >"$mid" 2>"${CBT_ERR}" || rc1=$?
	"${TIMEOUT[@]}" "${EXE}" --from "$pair" --to binary <"$mid" >"$out" 2>"${CBT_ERR}" || rc2=$?
	if ((rc1 == 0 && rc2 == 0)) && cmp -s "$src" "$out"; then
		_pass "binary round-trip via ${pair} (bit-perfect)"
	else
		_fail "binary round-trip via ${pair}" "rc1=$rc1 rc2=$rc2 err=[$(cat "${CBT_ERR}")]"
	fi
done
## Odd-length hex has no whole-byte representation: decoding to binary must error.
check errmsg "odd hex -> binary guarded" 'cannot decode to binary' -- --from 16 --to binary ABC


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Fuzz: random values round-tripped through every defined base
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Fuzz round-trips (all bases)"
mapfile -t BASE_NAMES < <("${EXE}" --list 2>/dev/null | tail -n +2 | awk '{print $1}')
declare -a FUZZ_BASES=()
for n in "${BASE_NAMES[@]}"; do [[ "$n" == "binary" ]] || FUZZ_BASES+=("$n"); done
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
	_run --from "$base" --to 10 -- "$enc"
	{ ((_rc == 0)) && [[ "$_out" == "$val" ]]; } || { fuzz_fail=$((fuzz_fail+1)); _fail "fuzz round-trip base=$base" "val=[$val] enc=[$enc] got=[$_out] rc=$_rc"; }
done
((fuzz_fail == 0)) && _pass "randomized fuzz round-trip (${iters} iterations, maxlen ${maxlen})" || printf '  %s%d fuzz failures above%s\n' "${red}" "$fuzz_fail" "${rst}"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Back-compat against the bundled v1 binary (gating, byte-for-byte)
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Each pair is "v2-base:v1-base". For a shared base, v2 must reproduce v1 output
## byte-for-byte (encode side), and must read v1 output back to the original
## (decode side). v1 only accepts base 10 (among a few) as input, so tests feed
## base-10 values. These pairs were confirmed to agree across a range of values.
V1_MAP=(
	2:2  8:8  10:10  16:16  26:26  36:36  52:52  62:62
	32:32  32h:32h  32c:32c  32ws:32ws
	64:64  64u:64u  64h:64h  64jc1:64jc1
	128jc1:128jc1  256jc1:256jc1  288jc1:288jc1
	48v1compat:48v1compat  64v1compat:64v1compat  128v1compat:128v1compat
	hostname:38host  username:39user  email:45email
	48ws:48jc1ws  64w:64jc1ws  128w:128jc1ws
)
## Best-guess pairs that did NOT agree, left off until sorted out.
## Double-check the correct mapping for these:
#	45:45email   ## v2 base-45 (RFC 4648) uses a different alphabet than v1 45email; v1 has no plain base-45.

if [[ -x "${EXE_V1B}" ]]; then
	section "Back-compat vs v1 (byte-for-byte + round-trip)"
	reps=3; ((doLong)) && reps=20
	for pair in "${V1_MAP[@]}"; do
		v2n="${pair%%:*}"; v1n="${pair##*:}"
		enc_fail=0; rt_fail=0; detail=""
		for ((r=0; r<reps; r++)); do
			val="$(_rand_int 30)"
			o2="$("${EXE}"     --from 10 --to "$v2n" -- "$val" 2>/dev/null || true)"
			o1="$("${EXE_V1B}" --ibase 10 "$val" "$v1n"       2>/dev/null || true)"
			if [[ -z "$o1" || "$o2" != "$o1" ]]; then enc_fail=1; detail="val=[$val] v2=[$o2] v1=[$o1]"; fi
			back="$("${EXE}" --from "$v2n" --to 10 -- "$o1" 2>/dev/null || true)"
			[[ -n "$o1" && "$back" == "$val" ]] || { rt_fail=1; detail="val=[$val] v1enc=[$o1] v2dec=[$back]"; }
		done
		((enc_fail == 0)) && _pass "v2==v1 encode: ${v2n} (== v1 ${v1n})" || _fail "v2==v1 encode: ${v2n} (== v1 ${v1n})" "$detail"
		((rt_fail == 0))  && _pass "v1->v2 round-trip: ${v2n} (from v1 ${v1n})" || _fail "v1->v2 round-trip: ${v2n} (from v1 ${v1n})" "$detail"
	done
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Summary
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
printf '\n%s' "${b}"
printf '========================================================================%s\n' "${rst}"
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
