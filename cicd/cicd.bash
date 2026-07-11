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
##	   3. lint (go vet gating; golangci-lint + staticcheck if installed)
##	   4. tests (unit + integration harness + fuzz + govulncheck security)
##	   5. profiler (flamegraph SVG; non-gating artifact - see failure policy)
##	   6. cross-compile every shipping platform (build sanity + release archives)
##	   7. dogfood (install the native build locally, fixed name) + screenshots
##	   8. backup + publish to git (runs from repo root)
##	- Syntax:
##	  cicd/cicd.bash [options]
##	  Options:
##	   -q, --quiet         quiet + unattended (no prompt); the publish step runs quiet too
##	   -y, --yes           unattended (no prompt) but not quiet
##	   -m, --message MSG   publish hands-off with this commit message (no editor)
##	       --msg MSG       alias for --message
##	   --no-fmt            skip the formatter stage
##	   --no-lint           skip the lint stage
##	   --no-cross          skip the cross-compile stage
##	   --no-profile        skip the profiler stage
##	   --no-dogfood        skip installing the native build locally
##	   --no-screenshots    skip regenerating README screenshots
##	   --no-publish        skip the git backup + publish stage
##	   --long              exhaustive test run (sets CICDTEST_DO_LONGTEST=1)
##	   --quick             skip the slow stages (cross-compile, profiler, screenshots) and shorten fuzz
##	   -h, --help          show this help
##	- If neither -q/-y nor -m is given, the run prompts once for a commit message
##	  (blank = git editor; Ctrl+C aborts the whole run), then finishes unattended.
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
export PATH="${HOME}/.go/bin:${HOME}/go/bin:${PATH}"   ## `go install`ed tools (golangci-lint, staticcheck, govulncheck) win

## Cap every stage at 50% of cores. build/test/lint all default to all cores;
## GOMAXPROCS bounds go build -p, go test, staticcheck and govulncheck, and
## CPU_CAP feeds golangci-lint's own --concurrency (it ignores GOMAXPROCS).
_cores="$(nproc 2>/dev/null || echo 2)"
CPU_CAP=$(( _cores / 2 )); (( CPU_CAP < 1 )) && CPU_CAP=1
export GOMAXPROCS="${CPU_CAP}"

source "${here}/config.bash"
source "${here}/utility/include/gfs-rotate.bash"       ## gfs_rotate() for the artifact dirs
cd "${root}"
stamp="$(date +%Y%m%d-%H%M%S)"

## Parse options.
assume_yes=0; quiet=0; quick=0; do_long=0; cli_message=""
while (($#)); do case "$1" in
	-q|--quiet)               quiet=1; assume_yes=1; shift ;;   ## quiet + unattended; publish runs quiet too
	-y|--yes)                 assume_yes=1; shift ;;
	--no-fmt)                 FMT_CMD=(); shift ;;
	--no-lint)                VET_CMD=(); LINT_CMD=(); STATICCHECK_CMD=(); shift ;;
	--no-cross)               BUILD_CROSS=0; shift ;;
	--no-profile)             PROFILE_ENABLE=0; shift ;;
	--no-dogfood)             DOGFOOD_FIXED_DESTS=(); shift ;;
	--no-screenshots)         DO_SCREENSHOTS=0; shift ;;
	--no-publish)             GIT_PUBLISH=(); shift ;;
	--long)                   do_long=1; shift ;;
	--quick)                  quick=1; BUILD_CROSS=0; PROFILE_ENABLE=0; DO_SCREENSHOTS=0; shift ;;
	--message=*|--msg=*|-m=*) cli_message="${1#*=}"; shift ;;
	-m|--message|--msg)       cli_message="${2-}"; shift; (($#)) && shift ;;
	-h|--help)                sed -n '/^##	- Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
	*) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac; done

## Publish commit message: -m wins, then config, then a default when unattended.
## Empty -> publish interactively (git commit opens an editor); when interactive
## we offer to capture a message at the preflight prompt below.
publish_msg=""
if   [[ -n "$cli_message" ]];              then publish_msg="$cli_message"
elif [[ -n "${PUBLISH_AUTO_MESSAGE:-}" ]]; then publish_msg="$PUBLISH_AUTO_MESSAGE"
elif ((assume_yes));                       then publish_msg="${APP_NAME} CI/CD ${stamp}"
fi

## Output helpers: fEcho / fEcho_Clean, blank-collapsing.
## fEcho "msg" -> "[ msg ]" status line; fEcho_Clean "msg" -> plain line, and a
## bare call collapses repeated blanks. fSection draws the leading-blank + rule
## letterbox before a major stage header; fDie prints a fatal line and exits.
declare -i _wasLastEchoBlank=0
fEcho_ResetBlankCounter(){ _wasLastEchoBlank=0; }
fEcho_Clean(){ if [[ -n "${1:-}" ]]; then echo -e "$*"; _wasLastEchoBlank=0; elif [[ $_wasLastEchoBlank -eq 0 ]] && echo; then _wasLastEchoBlank=1; fi; }
fEcho(){       if [[ -n "$*"     ]]; then fEcho_Clean "[ $* ]"; else fEcho_Clean ""; fi; }
fEcho_Force(){ fEcho_ResetBlankCounter; fEcho "$*"; }
_letterbox="••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••"
fSection(){ fEcho_Clean; fEcho_Clean "${_letterbox}"; fEcho "$*"; }
fDie(){ { fEcho_Force "FAILED: $*"; } >&2; exit 1; }
## Run a command array inside the Go module dir (SRC_DIR). Go tool stages need it.
in_src(){ ( cd "${root}/${SRC_DIR}" && "$@" ); }
trap 'rc=$?; printf "\n[ CICD ABORTED (exit %s) at line %s: %s ]\n" "$rc" "$LINENO" "$BASH_COMMAND" >&2; exit $rc' ERR

## Preflight: show the plan with resolved paths, then confirm.
profile_dir="$(cd "${root}" && mkdir -p "${PROFILE_OUT_DIR}" 2>/dev/null; cd "${PROFILE_OUT_DIR}" 2>/dev/null && pwd || echo "${root}/${PROFILE_OUT_DIR}")"
fixed_dest=""; for d in "${DOGFOOD_FIXED_DESTS[@]:-}"; do [[ -d "$d" && -w "$d" ]] && { fixed_dest="$d"; break; }; done

fEcho_Clean
fEcho_Clean "${APP_NAME} local CI/CD"
fEcho_Clean
fEcho_Clean "Repo root ...........: ${root}"
fEcho_Clean "Format ..............: ${FMT_CMD[*]:-(skipped)}"
fEcho_Clean "Native build ........: ${NATIVE_BUILD_CMD[*]} -> ${STAGED_BIN}"
if ((${#VET_CMD[@]})); then
	fEcho_Clean "Lint ................: ${VET_CMD[*]}  (+ golangci-lint, staticcheck if installed)"
else
	fEcho_Clean "Lint ................: (skipped)"
fi
fEcho_Clean "Tests ...............: ${UNIT_TEST_CMD[*]} + ${TEST_CMD[*]}$( ((do_long)) && echo '  (long)')"
if ((FUZZ_ENABLE)); then
	fEcho_Clean "Fuzz ................: ${FUZZ_TIME}/target$( ((quick)) && echo " (quick: ${FUZZ_TIME_QUICK})")"
else
	fEcho_Clean "Fuzz ................: (disabled)"
fi
fEcho_Clean "Security ............: ${VULN_CMD[*]}  (if installed)"
if ((PROFILE_ENABLE)); then
	fEcho_Clean "Profiler ............: bench ${PROFILE_BENCH} ${PROFILE_TIME} -> flamegraph SVG"
	fEcho_Clean "  output dir ........: ${profile_dir}"
else
	fEcho_Clean "Profiler ............: (skipped)"
fi
if ((BUILD_CROSS)); then
	fEcho_Clean "Cross-compile .......: ${RELEASE_CMD[*]} -> ${RELEASE_ARTIFACT_DIR}/"
else
	fEcho_Clean "Cross-compile .......: (skipped)"
fi
if ((${#DOGFOOD_FIXED_DESTS[@]})); then
	if [[ -n "$fixed_dest" ]]; then fEcho_Clean "Dogfood, fixed name .: overwrite ${fixed_dest}/${EXE_NAME}"
	else fEcho_Clean "Dogfood, fixed name .: <none of: ${DOGFOOD_FIXED_DESTS[*]} exists - will skip>"; fi
else
	fEcho_Clean "Dogfood, fixed name .: (disabled)"
fi
fEcho_Clean "Screenshots .........: $( ((DO_SCREENSHOTS)) && echo "${SCREENSHOT_CMD[*]}" || echo '(skipped)')"
if ((${#GIT_PUBLISH[@]} == 0)); then
	fEcho_Clean "Publish (last) ......: (disabled)"
elif [[ -n "$publish_msg" ]]; then
	fEcho_Clean "Publish (last) ......: ${GIT_PUBLISH[*]} (hands-off: \"${publish_msg}\")"
else
	fEcho_Clean "Publish (last) ......: ${GIT_PUBLISH[*]} (will prompt for message; blank = editor)"
fi
fEcho_Clean
fEcho_Clean "Fail-fast: any error aborts before the next stage."
fEcho_Clean

if ((! assume_yes)); then
	## Capture the commit message up front so the run can finish unattended. This
	## is the natural place to bail on the common (publish) path - Ctrl+C here
	## aborts; there is no separate "Proceed? [y/N]" (removed to cut friction).
	if ((${#GIT_PUBLISH[@]})) && [[ -z "$publish_msg" ]]; then
		read -r -p "Publish commit message (blank = editor; Ctrl+C aborts): " m
		fEcho_ResetBlankCounter
		[[ -n "$m" ]] && publish_msg="$m"
	fi
fi

## Tee the rest of the run (all stages) to a gitignored log so warnings from any
## stage can be reviewed after the fact. Rotate the prior (closed) logs first.
if [[ -n "${LINT_LOG_DIR:-}" ]] && mkdir -p "${root}/${LINT_LOG_DIR}" 2>/dev/null; then
	gfs_rotate "${root}/${LINT_LOG_DIR}" run log >/dev/null 2>&1 || true
	exec > >(tee "${root}/${LINT_LOG_DIR}/run_${stamp}.log") 2>&1
fi

## Pinned tools: bring any go-installed tool that drifted from tool-versions.env
## back in line (warn-only; probe-gated stages still skip anything missing).
if [[ -n "${PIN_TOOLS_CMD[*]:-}" ]]; then
	"${PIN_TOOLS_CMD[@]}"
fi

## Stage 1: format.
fSection "1/8  Format"
if ((${#FMT_CMD[@]} == 0)); then
	fEcho_Clean "format skipped"
else
	"${FMT_CMD[@]}"
	fEcho "OK: formatted (${FMT_CMD[*]})"
fi

## Stage 2: native build, staged aside from what the cross stage cleans.
fSection "2/8  Native build"
"${NATIVE_BUILD_CMD[@]}"
[[ -f "${NATIVE_BUILD_OUT}" ]] || fDie "native build produced no binary: ${NATIVE_BUILD_OUT}"
mkdir -p "$(dirname "${STAGED_BIN}")"
cp -f "${NATIVE_BUILD_OUT}" "${STAGED_BIN}"
fEcho "OK: native build: ${STAGED_BIN} ($(du -h "${STAGED_BIN}" | cut -f1))  ($("${STAGED_BIN}" --version))"

## Stage 3: lint. go vet is gating; golangci-lint / staticcheck run when installed
## (a failed probe skips that one with a warning). All output lands in the run log.
fSection "3/8  Lint"
if ((${#VET_CMD[@]} == 0)); then
	fEcho_Clean "lint skipped"
else
	in_src "${VET_CMD[@]}"
	fEcho "OK: go vet clean"
	if ((${#LINT_CMD[@]})); then
		if in_src "${LINT_PROBE[@]}" >/dev/null 2>&1; then
			in_src "${LINT_CMD[@]}"; fEcho "OK: golangci-lint clean"
		else
			fEcho "WARNING: golangci-lint skipped (not installed: go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest)"
		fi
	fi
	if ((${#STATICCHECK_CMD[@]})); then
		if in_src "${STATICCHECK_PROBE[@]}" >/dev/null 2>&1; then
			in_src "${STATICCHECK_CMD[@]}"; fEcho "OK: staticcheck clean"
		else
			fEcho "WARNING: staticcheck skipped (not installed: go install honnef.co/go/tools/cmd/staticcheck@latest)"
		fi
	fi
fi

## Stage 4: tests. Unit (Go), integration harness (against the staged binary),
## fuzz (one target per invocation), and govulncheck security (module + deps).
fSection "4/8  Tests"
in_src "${UNIT_TEST_CMD[@]}"
fEcho "OK: unit tests"
CICDTEST_EXE="${root}/${STAGED_BIN}" CICDTEST_DO_LONGTEST="${do_long}" "${TEST_CMD[@]}"
fEcho "OK: integration harness"

## 4b: fuzz each discovered target for a bounded time (shorter under --quick).
if ((FUZZ_ENABLE)); then
	ft="${FUZZ_TIME}"; ((quick)) && ft="${FUZZ_TIME_QUICK}"
	mapfile -t fuzz_targets < <(in_src go test -list '^Fuzz' ./... 2>/dev/null | grep -E '^Fuzz' || true)
	if ((${#fuzz_targets[@]})); then
		for t in "${fuzz_targets[@]}"; do
			fEcho_Clean "fuzz ${t} (${ft}) ..."
			in_src go test -run '^$' -fuzz "^${t}$" -fuzztime "${ft}" ./... || fDie "fuzz ${t} found a failure"
		done
		fEcho "OK: fuzz (${#fuzz_targets[@]} target(s), ${ft} each)"
	else
		fEcho_Clean "no Fuzz* targets found; skipping fuzz"
	fi
fi

## 4c: security. govulncheck scans the module and its dependencies (library code).
if ((${#VULN_CMD[@]})); then
	if in_src "${VULN_PROBE[@]}" >/dev/null 2>&1; then
		in_src "${VULN_CMD[@]}"; fEcho "OK: no known vulnerabilities"
	else
		fEcho "WARNING: govulncheck skipped (not installed: go install golang.org/x/vuln/cmd/govulncheck@latest)"
	fi
fi
fEcho "OK: tests passed"

## Stage 5: profiler (non-gating artifact; failures classified below).
run_profiler(){
	((PROFILE_ENABLE)) || { fEcho_Clean "profiler disabled"; return 0; }

	## Mundane/environmental reasons -> skip with a warning (not the app's fault),
	## unless PROFILE_STRICT. Genuine run failures below still abort.
	local skip=""
	command -v go      >/dev/null 2>&1 || skip="go not found"
	[[ -z "$skip" ]] && ! command -v python3 >/dev/null 2>&1 && skip="python3 not found"
	if [[ -n "$skip" ]]; then
		((PROFILE_STRICT)) && fDie "profiler: ${skip}"
		fEcho "WARNING: profiler skipped: ${skip}"; return 0
	fi

	mkdir -p "${profile_dir}"
	local prof="${profile_dir}/cpu_${stamp}.prof"
	## Born canonical (role "frequent"); the rotation retags the newest as "latest".
	local out="${profile_dir}/flame_${stamp}_frequent.svg"

	fEcho_Clean "sampling bench ${PROFILE_BENCH} for ${PROFILE_TIME} ..."
	if ! in_src go test -run '^$' -bench "^${PROFILE_BENCH}$" -benchtime "${PROFILE_TIME}" \
		-cpuprofile "${prof}" -o /dev/null ./...; then
		((PROFILE_STRICT)) && fDie "profiler benchmark failed (app problem)"
		fEcho "WARNING: profiler benchmark failed (continuing)"; return 0
	fi
	[[ -s "${prof}" ]] || { fEcho "WARNING: profiler produced no profile (continuing)"; return 0; }

	if python3 "${here}/utility/pprof2flame.py" --prof "${prof}" --out "${out}" \
		--title "${APP_NAME} CPU flamegraph (${stamp})"; then
		rm -f "${prof}"
		gfs_rotate "${profile_dir}" flame svg
		gfs_rotate "${profile_dir}" cpu prof >/dev/null 2>&1 || true   ## in case an old .prof lingers
		## Rotation retags this run's file by role (latest/first/...); find it by stamp.
		local latest="$out" cand
		for cand in "${profile_dir}/flame_${stamp}_"*.svg; do [[ -e "$cand" ]] && { latest="$cand"; break; }; done
		fEcho "OK: flamegraph: ${latest}"
		fEcho_Clean "open: ${latest}  (in a browser)"
		## Hot-spot summary into the log (non-fatal, no marker - the marker is for
		## the per-session --check gate, not the pipeline).
		local report="${here}/utility/flame-report.py"
		if [[ -f "$report" ]]; then
			fEcho_Clean
			python3 "$report" --dir "${profile_dir}" 2>/dev/null || fEcho_Clean "hot spots: (report unavailable)"
		fi
	else
		rm -f "${prof}"
		fEcho "WARNING: flamegraph generation failed (continuing)"
	fi
}
fSection "5/8  Profiler"
run_profiler

## Stage 6: cross-compile (build sanity + release archives).
fSection "6/8  Cross-compile"
if ((BUILD_CROSS)); then
	"${RELEASE_CMD[@]}"
	count="$(find "${RELEASE_ARTIFACT_DIR}" -maxdepth 1 -type f \( -name '*.tgz' -o -name '*.zip' \) 2>/dev/null | wc -l)"
	((count > 0)) || fDie "cross-compile produced no archives in ${RELEASE_ARTIFACT_DIR}/"
	fEcho "OK: release archives: ${count} in ${RELEASE_ARTIFACT_DIR}/"
else
	fEcho_Clean "cross-compile skipped"
fi

## Stage 7: dogfood (fixed name) + screenshots.
fSection "7/8  Dogfood"
if ((${#DOGFOOD_FIXED_DESTS[@]})); then
	if [[ -n "$fixed_dest" ]]; then
		if ! cp -f "${STAGED_BIN}" "${fixed_dest}/${EXE_NAME}" && [[ "${fixed_dest}" != "${HOME}/"* ]]; then
			sudo cp -f "${STAGED_BIN}" "${fixed_dest}/${EXE_NAME}"
		fi
		fEcho "OK: installed -> ${fixed_dest}/${EXE_NAME}"
	else
		fEcho "WARNING: no dogfood dest exists (${DOGFOOD_FIXED_DESTS[*]}); skipping"
	fi
else
	fEcho_Clean "dogfood disabled"
fi

## Screenshots: off by default; a failure is a warning, never a stop.
screenshot_util="${root}/${SCREENSHOT_CMD[0]}"
if ((! DO_SCREENSHOTS)); then
	fEcho_Clean "screenshots skipped"
elif [[ -f "${screenshot_util}" ]]; then
	if bash "${screenshot_util}" "${root}" "${root}/${STAGED_BIN}"; then fEcho "OK: screenshots regenerated"
	else fEcho "WARNING: screenshot generation failed (continuing)"; fi
else
	fEcho_Clean "no screenshot utility at ${screenshot_util}; skipping"
fi

## Stage 8: backup + publish.
fSection "8/8  Backup + publish"
## Always run the publisher quiet: cicd already gave the initial prompt, so skip
## its redundant continue-prompt. With no message it still lets git open the editor.
pub_flags=(--quiet)
if ((${#GIT_PUBLISH[@]} == 0)); then
	fEcho_Clean "publish disabled"
elif [[ -n "$publish_msg" ]]; then
	## Hands-off: the publisher fills the empty commit message from -m so `git
	## commit` won't open an editor.
	fEcho_Clean "hands-off publish (commit message: \"${publish_msg}\")"
	"${GIT_PUBLISH[@]}" "${pub_flags[@]}" -m "${publish_msg}"
	fEcho "OK: published"
else
	"${GIT_PUBLISH[@]}" "${pub_flags[@]}"
	fEcho "OK: published"
fi

fSection "${APP_NAME} CI/CD: done."
fEcho_Clean


##	History:
##		- 2026-07-03 JC: Created. Generic engine + config.bash, adapted from the sister project; Go build staging, exhaustive tests, quiet publish.
##		- 2026-07-09 JC: silkterm-style output (fEcho/fSection letterbox); -q/-m/--quick flags; lint, fuzz, vuln, profiler stages; tee'd run log; message prompt replaces y/n.
