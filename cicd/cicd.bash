#!/usr/bin/env bash

#  shellcheck disable=1091  ## 'source is valid here, but shellcheck doesn't know the path to it.'
#  shellcheck disable=2001  ## 'See if you can use ${variable//search/replace} instead.' Complains about good uses of sed.
#  shellcheck disable=2016  ## 'Expressions don't expand in single quotes, use double quotes for that.' I know, and I often want an explicit '$'.
#  shellcheck disable=2034  ## 'variable appears unused.' Complains about valid use of variable indirection (e.g. later use of local -n var=$1)
#  shellcheck disable=2046  ## 'Quote to prevent word-splitting.' (OK for integers.)
#  shellcheck disable=2086  ## 'Double quote to prevent globbing and word splitting.' (OK for integers.)
#  shellcheck disable=2119  ## 'Use foo "$@" if function's $1 should mean script's $1.' Confusing and inapplicable.
#  shellcheck disable=2120  ## 'Foo references arguments, but none are ever passed.' Valid function argument overloading.
#  shellcheck disable=2128  ## 'Expanding an array without an index only gives the element in the index 0.' False hits on associative arrays.
#  shellcheck disable=2154  ## 'referenced but not assigned.' False hit on trap strings that assign the var they use (rc=$?).
#  shellcheck disable=2155  ## 'Declare and assign separately to avoid masking return values.' Cumbersome and unnecessary. For integers it's sometimes required to even come into existence for counters.
#  shellcheck disable=2162  ## 'read without -r will mangle backslashes.'
#  shellcheck disable=2178  ## 'Variable was used as an array but is now assigned a string.' False hits on associative arrays with e.g. 'local -n assocArray=$1'.
#  shellcheck disable=2181  ## 'Check exit code directly, not indirectly with $?.'
#  shellcheck disable=2317  ## 'Can't reach.' (I.e. an 'exit' is used for debugging - and makes an unusable visual mess.)
## shellcheck disable=2002  ## 'Useless use of cat.'
## shellcheck disable=2004  ## '$/${} is unnecessary on arithmetic variables.' Inappropriate complaining?
## shellcheck disable=2053  ## 'Quote the right-hand sid of = in [[ ]] to prevent glob matching.' Disable for Yoda Notation.
## shellcheck disable=2143  ## 'Use grep -q instead of echo | grep'

##	- Purpose: Local CI/CD pipeline. Generic engine, per-project settings live in config.bash.
##	- Stages (fail-fast, any error aborts before the next stage):
##	   1. format (gofmt)
##	   2. native build (staged aside so the cross stage can't clobber it)
##	   3. tests (exhaustive: deterministic, security, fuzz, binary round-trips)
##	   4. cross-compile every shipping platform (build sanity + release archives)
##	   5. dogfood (install the native build locally, fixed name)
##	   6. backup + publish to git (runs from repo root)
##	- Syntax:
##	  cicd/cicd.bash [options]
##	  Options:
##	   -y, --yes       run unattended (no confirm prompt)
##	   --no-fmt        skip the formatter stage
##	   --no-cross      skip the cross-compile stage
##	   --no-dogfood    skip installing the native build locally
##	   --no-publish    skip the git backup + publish stage
##	   --long          exhaustive test run (sets CICDTEST_DO_LONGTEST=1)
##	   --quick         skip the slow stage (cross-compile)
##	- Reuse: copy the cicd/ directory into another project and edit config.bash.

##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

## Find the repo root and load project config.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"   ## the git repo root (cicd/..)
source "${here}/config.bash"
cd "${root}"
stamp="$(date +%Y%m%d-%H%M%S)"

## Parse options.
assume_yes=0; do_long=0
while (($#)); do case "$1" in
	-y|--yes)     assume_yes=1; shift ;;
	--no-fmt)     FMT_CMD=(); shift ;;
	--no-cross)   BUILD_CROSS=0; shift ;;
	--no-dogfood) DOGFOOD_FIXED_DESTS=(); shift ;;
	--no-publish) GIT_PUBLISH=(); shift ;;
	--long)       do_long=1; shift ;;
	--quick)      BUILD_CROSS=0; shift ;;
	-h|--help)    sed -n '/^##	- Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
	*) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac; done

## Output helpers.
b=$'\e[1m'; dim=$'\e[2m'; grn=$'\e[32m'; ylw=$'\e[33m'; red=$'\e[31m'; rst=$'\e[0m'
hr(){   echo; printf '%s\n' "${dim}••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••${rst}"; }
step(){ hr; printf '%s[ %s ] %s%s\n' "${b}" "$(date +%H:%M:%S)" "$*" "${rst}"; }
note(){ printf '  %s\n' "$*"; }
ok(){   printf '%s  OK: %s%s\n' "${grn}" "$*" "${rst}"; }
warn(){ printf '%s  WARN: %s%s\n' "${ylw}" "$*" "${rst}" >&2; }
die(){  printf '\n%sCICD FAILED: %s%s\n' "${red}" "$*" "${rst}" >&2; exit 1; }
trap 'rc=$?; printf "\n%sCICD ABORTED (exit %s) at line %s: %s%s\n" "${red}" "$rc" "$LINENO" "$BASH_COMMAND" "${rst}" >&2; exit $rc' ERR

## Preflight: show the plan with resolved paths, then confirm.
fixed_dest=""; for d in "${DOGFOOD_FIXED_DESTS[@]:-}"; do [[ -d "$d" && -w "$d" ]] && { fixed_dest="$d"; break; }; done

printf '\n%s%s local CI/CD%s\n' "${b}" "${APP_NAME}" "${rst}"
echo
note "Repo root ...........: ${root}"
note "Format ..............: ${FMT_CMD[*]:-(skipped)}"
note "Native build ........: ${NATIVE_BUILD_CMD[*]} -> ${STAGED_BIN}"
note "Tests ...............: ${TEST_CMD[*]}$( ((do_long)) && echo '  (long)')"
if ((BUILD_CROSS)); then
	note "Cross-compile .......: ${RELEASE_CMD[*]} -> ${RELEASE_ARTIFACT_DIR}/"
else
	note "Cross-compile .......: (skipped)"
fi
if ((${#DOGFOOD_FIXED_DESTS[@]})); then
	if [[ -n "$fixed_dest" ]]; then note "Dogfood, fixed name .: overwrite ${fixed_dest}/${EXE_NAME}"
	else note "Dogfood, fixed name .: <none of: ${DOGFOOD_FIXED_DESTS[*]} exists - will skip>"; fi
else
	note "Dogfood, fixed name .: (disabled)"
fi
if ((${#GIT_PUBLISH[@]})); then
	note "Publish (last) ......: ${GIT_PUBLISH[*]}"
else
	note "Publish (last) ......: (disabled)"
fi
printf '\n%sFail-fast: any error aborts before the next stage.%s\n' "${dim}" "${rst}"

if ((! assume_yes)); then
	read -r -p "Proceed? (Ctrl+C aborts, Enter continues) " _
fi

## Stage 1: format.
step "1/6  Format"
if ((${#FMT_CMD[@]} == 0)); then
	note "format skipped"
else
	"${FMT_CMD[@]}"
	ok "formatted (${FMT_CMD[*]})"
fi

## Stage 2: native build, staged aside from what the cross stage cleans.
step "2/6  Native build"
"${NATIVE_BUILD_CMD[@]}"
[[ -f "${NATIVE_BUILD_OUT}" ]] || die "native build produced no binary: ${NATIVE_BUILD_OUT}"
mkdir -p "$(dirname "${STAGED_BIN}")"
cp -f "${NATIVE_BUILD_OUT}" "${STAGED_BIN}"
ok "native build: ${STAGED_BIN} ($(du -h "${STAGED_BIN}" | cut -f1))  ($("${STAGED_BIN}" --version))"

## Stage 3: tests, against the staged binary.
step "3/6  Tests"
CICDTEST_EXE="${root}/${STAGED_BIN}" CICDTEST_DO_LONGTEST="${do_long}" "${TEST_CMD[@]}"
ok "tests passed"

## Stage 4: cross-compile (build sanity + release archives).
step "4/6  Cross-compile"
if ((BUILD_CROSS)); then
	"${RELEASE_CMD[@]}"
	count="$(find "${RELEASE_ARTIFACT_DIR}" -maxdepth 1 -type f \( -name '*.tgz' -o -name '*.zip' \) 2>/dev/null | wc -l)"
	((count > 0)) || die "cross-compile produced no archives in ${RELEASE_ARTIFACT_DIR}/"
	ok "release archives: ${count} in ${RELEASE_ARTIFACT_DIR}/"
else
	note "cross-compile skipped"
fi

## Stage 5: dogfood (fixed name).
step "5/6  Dogfood"
if ((${#DOGFOOD_FIXED_DESTS[@]})); then
	if [[ -n "$fixed_dest" ]]; then
		if ! cp -f "${STAGED_BIN}" "${fixed_dest}/${EXE_NAME}" && [[ "${fixed_dest}" != "${HOME}/"* ]]; then
			sudo cp -f "${STAGED_BIN}" "${fixed_dest}/${EXE_NAME}"
		fi
		ok "installed -> ${fixed_dest}/${EXE_NAME}"
	else
		warn "no dogfood dest exists (${DOGFOOD_FIXED_DESTS[*]}); skipping"
	fi
else
	note "dogfood disabled"
fi

## Stage 6: backup + publish.
step "6/6  Backup + publish"
if ((${#GIT_PUBLISH[@]})); then
	"${GIT_PUBLISH[@]}"
	ok "published"
else
	note "publish disabled"
fi

hr; printf '%s%s CI/CD: done.%s\n' "${grn}${b}" "${APP_NAME}" "${rst}"


##	History:
##		- 2026-07-03 JC: Created. Generic engine + config.bash, adapted from the sister project; Go build staging, exhaustive tests, quiet publish.
