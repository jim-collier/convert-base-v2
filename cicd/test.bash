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
##			- Full-coverage symbol fuzz: for every base, a random-length string of its own random symbols is carried through a random target base and back. Base names and alphabets are read from the binary, so all bases are covered.
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
## Performance section runs on any long run, or whenever the engine asks for it
## (it does so unless --quick was passed). A long run always includes it.
doPerf=0; { ((doLong)) || [[ "${CICDTEST_DO_PERF:-0}" == "1" ]]; } && doPerf=1

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
_run --list
{ ((_rc == 0)) && [[ "$_out" == *NAME* ]]; } && _pass "--list lists bases" || _fail "--list lists bases" "rc=$_rc"

## Base-introspection query flags (used by the full-coverage fuzz below).
_run --get-index-count
{ ((_rc == 0)) && [[ "$_out" =~ ^[0-9]+$ ]] && ((_out > 0)); } && _pass "--get-index-count prints a count" || _fail "--get-index-count prints a count" "rc=$_rc out=[$_out]"
check eq     "--get-base-name --by-index=0" 2               -- --get-base-name --by-index=0
check eq     "--get-base-name alias hex"    16              -- --get-base-name hex
check errmsg "--by-index out of range"      'out of range'  -- --get-base-name --by-index=999999
check errmsg "query needs a selector"       'select a base' -- --get-base-name
_run --show-symbols 16
{ ((_rc == 0)) && [[ "$(wc -l <"${CBT_OUT}")" -eq 16 ]]; } && _pass "--show-symbols 16 lists 16 symbols" || _fail "--show-symbols 16 lists 16 symbols" "rc=$_rc lines=$(wc -l <"${CBT_OUT}")"


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
## Big bases (more than 8 bits per char) round-trip at every input length,
## including the odd lengths a zero-padded tail used to corrupt. Sweep edge
## lengths for each.
for pair in "2048twitter" "2048rust" "32768qntm" "65536"; do
	bigfail=0
	for n in 0 1 2 3 4 5 7 8 15 16 17 31 32 33 64 333; do
		src="${CBT_TMP}/bp_src"; mid="${CBT_TMP}/bp_mid"; out="${CBT_TMP}/bp_out"
		head -c "$n" /dev/urandom >"$src"
		rc1=0; rc2=0
		"${TIMEOUT[@]}" "${EXE}" --from binary --to "$pair" <"$src" >"$mid" 2>"${CBT_ERR}" || rc1=$?
		"${TIMEOUT[@]}" "${EXE}" --from "$pair" --to binary <"$mid" >"$out" 2>"${CBT_ERR}" || rc2=$?
		{ ((rc1 == 0 && rc2 == 0)) && cmp -s "$src" "$out"; } || bigfail=$((bigfail+1))
	done
	((bigfail == 0)) && _pass "binary round-trip via ${pair} (all lengths)" || _fail "binary round-trip via ${pair}" "${bigfail} lengths mismatched"
done
## Every power-of-2 base (not just the handful above) round-trips raw bytes
## bit-perfectly. Blob lengths are picked to force a partial final chunk in each,
## so padding and tail handling get exercised. Bases and sizes come from --list,
## so a new power-of-2 base is covered with no edit here.
declare -a POW2_BASES=()
while read -r bname bsize _; do
	case "$bsize" in
		2|4|8|16|32|64|128|256|512|1024|2048|4096|8192|16384|32768|65536)
			[[ "$bname" == "binary" ]] || POW2_BASES+=("$bname") ;;
	esac
done < <("${EXE}" --list 2>/dev/null | tail -n +2)
raw_all_fail=0; raw_all_n=0
for base in "${POW2_BASES[@]}"; do
	for n in 1 2 3 5 7 11 13 17 31 63 100 255 257 $(( 1 + $(_rand16) % 512 )); do
		src="${CBT_TMP}/ra_src"; mid="${CBT_TMP}/ra_mid"; out="${CBT_TMP}/ra_out"
		head -c "$n" /dev/urandom >"$src"
		rc1=0; rc2=0
		"${TIMEOUT[@]}" "${EXE}" --from binary --to "$base" <"$src" >"$mid" 2>"${CBT_ERR}" || rc1=$?
		"${TIMEOUT[@]}" "${EXE}" --from "$base" --to binary <"$mid" >"$out" 2>"${CBT_ERR}" || rc2=$?
		raw_all_n=$((raw_all_n + 1))
		{ ((rc1 == 0 && rc2 == 0)) && cmp -s "$src" "$out"; } || { raw_all_fail=$((raw_all_fail+1)); _fail "raw round-trip ${base} n=${n}" "rc1=$rc1 rc2=$rc2 err=[$(cat "${CBT_ERR}")]"; }
	done
done
((raw_all_fail == 0)) && _pass "raw round-trip, all power-of-2 bases (${#POW2_BASES[@]} bases, ${raw_all_n} blobs)" || printf '  %s%d raw round-trip failures above%s\n' "${red}" "$raw_all_fail" "${rst}"
## The four big bases match the published third-party layouts byte-for-byte.
## These fixed vectors (input bytes -> exact output code points) guard that
## interop; they come straight from the reference implementations. Each pins the
## tail/secondary-block handling, and for 65536 the little-endian byte order.
nvec(){ # LABEL BASE INPUT_HEX EXPECTED_CODEPOINTS(space-separated hex)
	local label="$1" base="$2" hex="$3" cps="$4" src exp="" got cp
	src="${CBT_TMP}/nv_src"
	printf '%b' "$(printf '%s' "$hex" | sed 's/../\\x&/g')" >"$src"
	for cp in $cps; do exp+=$(printf "\\U$(printf '%08x' "0x${cp}")"); done
	got=$("${TIMEOUT[@]}" "${EXE}" --from binary --to "$base" <"$src" 2>"${CBT_ERR}")
	[[ "$got" == "$exp" ]] && _pass "native vector ${label}" \
		|| _fail "native vector ${label}" "want=[$cps] got=[$(printf '%s' "$got" | od -An -tx1 | tr -d '\n')]"
}
nvec "65536 lone byte"   65536       00         1500
nvec "65536 byte order"  65536       0102       3601
nvec "65536 pair+tail"   65536       010203     "3601 1503"
nvec "65536 high block"  65536       ffff       285FF
nvec "65536 Hello"       65536       48656c6c6f "9A48 A36C 156F"
nvec "32768 one byte"    32768qntm   00         06BF
nvec "32768 two bytes"   32768qntm   0000       "04A0 025F"
nvec "32768 short tail"  32768qntm   000000000000 "04A0 04A0 04A0 018F"
nvec "2048 one byte"     2048twitter 00         0046
nvec "2048 two bytes"    2048twitter 0000       "0038 0110"
nvec "2048 three-bit tail" 2048twitter 010203   "0047 01B7 0037"
nvec "rust one byte"     2048rust    00         00D8
nvec "rust tail zero"    2048rust    000000     "00D8 00D8 0F0D"
nvec "rust tail three"   2048rust    010203     "00C5 0140 0F10"

## RFC 4648 padding: the strict base64 (s4) and base32 (s6) variants emit '='
## padding to the group boundary (vectors from RFC 4648 s10). The URL/hex
## variants stay unpadded but still accept padded input on decode.
pipecheck(){ # LABEL FROM TO INPUT EXPECTED
	local label="$1" f="$2" t="$3" in="$4" want="$5" got
	got=$(printf '%s' "$in" | "${TIMEOUT[@]}" "${EXE}" --from "$f" --to "$t" 2>"${CBT_ERR}")
	[[ "$got" == "$want" ]] && _pass "$label" || _fail "$label" "in='$in' want='$want' got='$got'"
}
pipecheck "rfc64 pad f"        raw 64  "f"        "Zg=="
pipecheck "rfc64 pad fo"       raw 64  "fo"       "Zm8="
pipecheck "rfc64 pad foobar"   raw 64  "foobar"   "Zm9vYmFy"
pipecheck "rfc32 pad f"        raw 32  "f"        "MY======"
pipecheck "rfc32 pad foob"     raw 32  "foob"     "MZXW6YQ="
pipecheck "rfc32 pad foobar"   raw 32  "foobar"   "MZXW6YTBOI======"
pipecheck "base64url unpadded" raw 64u "foob"     "Zm9vYg"
pipecheck "base64 strips pad"  64  raw "Zm9vYmFy" "foobar"
pipecheck "base64url takes pad" 64u raw "Zm9vYg==" "foob"

## Custom (user-defined) bases can opt into the same padding with a pad= token.
## This custom alphabet mirrors RFC 4648 base32, so its padded output must match.
B32C="ABCDEFGHIJKLMNOPQRSTUVWXYZ234567 pad=="
padgot=$(printf 'A' | "${TIMEOUT[@]}" "${EXE}" --from binary --to-symbols "$B32C" 2>"${CBT_ERR}")
[[ "$padgot" == "IE======" ]] && _pass "custom base32 emits pad" || _fail "custom base32 emits pad" "got='$padgot'"
padrt=$(printf 'A' | "${TIMEOUT[@]}" "${EXE}" --from binary --to-symbols "$B32C" 2>/dev/null | "${TIMEOUT[@]}" "${EXE}" --from-symbols "$B32C" --to binary 2>"${CBT_ERR}")
[[ "$padrt" == "A" ]] && _pass "custom pad round-trips" || _fail "custom pad round-trips" "got='$padrt'"
padun=$(printf 'IE' | "${TIMEOUT[@]}" "${EXE}" --from-symbols "$B32C" --to binary 2>"${CBT_ERR}")
[[ "$padun" == "A" ]] && _pass "custom pad decode takes unpadded" || _fail "custom pad decode takes unpadded" "got='$padun'"
check errmsg "pad collides with digit" 'is also a digit' -- --from-symbols "0123456789ABCDEF pad=A" --to 10 5

## Odd-length hex has no whole-byte representation: decoding to binary must error.
check errmsg "odd hex -> binary guarded" 'cannot decode to binary' -- --from 16 --to binary ABC


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Keyboard (text) base: a plain-text document is valid input as-is
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Every printable keyboard character plus tab/newline/return is a digit, so
## source code, prose, JSON, and the like convert with no escaping. Like binary
## it holds newline as a digit, so it needs --raw output and file-based checks.
## Round-trips are exact except a leading zero-digit (tab), which vanishes like
## any leading zero, so the samples start on a non-tab byte.
section "Keyboard (text) base"
ksrc="${CBT_TMP}/kb_src"; kmid="${CBT_TMP}/kb_mid"; kout="${CBT_TMP}/kb_out"
printf 'def f(x):\n\treturn {"k": [1, 2], "s": "a+b/c=d"}  # note\n' >"$ksrc"
kfail=0
for tb in 16 10; do
	if "${TIMEOUT[@]}" "${EXE}" --from keyboard --to "$tb" <"$ksrc" >"$kmid" 2>"${CBT_ERR}" \
		&& "${TIMEOUT[@]}" "${EXE}" --from "$tb" --to keyboard --raw <"$kmid" >"$kout" 2>"${CBT_ERR}" \
		&& cmp -s "$ksrc" "$kout"; then :; else kfail=$((kfail+1)); fi
done
((kfail == 0)) && _pass "keyboard sample round-trips (base 16 and 10)" || _fail "keyboard sample round-trips" "${kfail} of 2 failed"
## Random text blobs of only valid keyboard bytes, forced to start on a non-tab
## byte so no leading digit is lost.
krand_fail=0
for len in 1 2 5 33 200 1500; do
	{ printf '#'; head -c "$((len * 8 + 64))" /dev/urandom | LC_ALL=C tr -cd '\11\12\15\40-\176' | head -c "$len"; } >"$ksrc" || true
	if "${TIMEOUT[@]}" "${EXE}" --from keyboard --to 16 <"$ksrc" >"$kmid" 2>"${CBT_ERR}" \
		&& "${TIMEOUT[@]}" "${EXE}" --from 16 --to keyboard --raw <"$kmid" >"$kout" 2>"${CBT_ERR}" \
		&& cmp -s "$ksrc" "$kout"; then :; else krand_fail=$((krand_fail+1)); fi
done
((krand_fail == 0)) && _pass "keyboard random text round-trips (6 blobs)" || _fail "keyboard random text round-trips" "${krand_fail} lengths mismatched"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Fuzz: random values round-tripped through every defined base
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
section "Fuzz round-trips (all bases)"
mapfile -t BASE_NAMES < <("${EXE}" --list 2>/dev/null | tail -n +2 | awk '{print $1}')
declare -a FUZZ_BASES=()
## binary and keyboard both carry newline as a digit, so their output can't
## survive $(...) capture (it strips trailing newlines). Both get their own
## file-based, --raw round-trip sections instead.
for n in "${BASE_NAMES[@]}"; do
	case "$n" in binary|keyboard) continue ;; esac
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
	_run --from "$base" --to 10 -- "$enc"
	{ ((_rc == 0)) && [[ "$_out" == "$val" ]]; } || { fuzz_fail=$((fuzz_fail+1)); _fail "fuzz round-trip base=$base" "val=[$val] enc=[$enc] got=[$_out] rc=$_rc"; }
done
((fuzz_fail == 0)) && _pass "randomized fuzz round-trip (${iters} iterations, maxlen ${maxlen})" || printf '  %s%d fuzz failures above%s\n' "${red}" "$fuzz_fail" "${rst}"

## Full-coverage symbol round-trip: for every base (not just a handful), build a
## random-length string from its own randomly chosen symbols, carry it through a
## random target base, and bring it back. Bases, names, and symbol alphabets all
## come from the binary itself (--get-index-count, --get-base-name, --show-symbols),
## so every defined base is exercised with no hand-maintained tables. The first
## symbol is kept off the zero digit so the source string is already canonical and
## a clean string compare is a valid round-trip check. Binary (raw bytes) is the
## one base left out; it is covered bit-perfectly in its own section above.
n_bases="$("${EXE}" --get-index-count)"
declare -a IDX_NAME=()
for ((i=0; i<n_bases; i++)); do IDX_NAME[i]="$("${EXE}" --get-base-name --by-index="$i")"; done
declare -a ELIGIBLE=()
for ((i=0; i<n_bases; i++)); do
	case "${IDX_NAME[i]}" in binary|keyboard) continue ;; esac
	ELIGIBLE+=("$i")
done

## Symbols are loaded once per base, on first use, into a per-index array.
declare -A SYM_LOADED=()
_load_syms(){
	local idx="$1"
	[[ -n "${SYM_LOADED[$idx]:-}" ]] && return
	mapfile -t "SYMS_${idx}" < <("${EXE}" --show-symbols --by-index="$idx")
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
	_run --from "$src_name" --to "$tgt_name" -- "$src_str"; encoded="$_out"; ((_rc == 0)) || { symfuzz_fail=$((symfuzz_fail+1)); _fail "symbol fuzz enc $src_name->$tgt_name" "src=[$src_str] rc=$_rc err=[$_err]"; continue; }
	_run --from "$tgt_name" --to "$src_name" -- "$encoded"; symfuzz_n=$((symfuzz_n + 1))
	{ ((_rc == 0)) && [[ "$_out" == "$src_str" ]]; } || { symfuzz_fail=$((symfuzz_fail+1)); _fail "symbol fuzz round-trip $src_name<->$tgt_name" "src=[$src_str] enc=[$encoded] got=[$_out] rc=$_rc"; }
done
((symfuzz_fail == 0)) && _pass "full-coverage symbol round-trip (${symfuzz_n} iterations, ${#ELIGIBLE[@]} bases, maxlen ${maxlen})" || printf '  %s%d symbol-fuzz failures above%s\n' "${red}" "$symfuzz_fail" "${rst}"


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
## Performance: streaming throughput of the binary path (long test only)
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## A repeatable throughput baseline for the streaming binary<->text path, with
## the system base64 alongside for context. Round-trips must still be
## bit-perfect; the numbers are informational and guard against regressions.
if ((doPerf)); then
	section "Performance (streaming throughput)"
	perf_mib=4
	perfsrc="${CBT_TMP}/perf_src"; perfmid="${CBT_TMP}/perf_mid"; perfout="${CBT_TMP}/perf_out"
	head -c "$((perf_mib * 1024 * 1024))" /dev/urandom >"$perfsrc"
	for base in 16 64u; do
		t0=$(date +%s.%N)
		"${TIMEOUT[@]}" "${EXE}" --from binary --to "$base" <"$perfsrc" >"$perfmid" 2>/dev/null
		"${TIMEOUT[@]}" "${EXE}" --from "$base" --to binary <"$perfmid" >"$perfout" 2>/dev/null
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
