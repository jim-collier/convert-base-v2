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
##	   3. lint (go vet gating; golangci-lint, staticcheck, shellcheck and ruff if installed)
##	   4. tests (unit + integration harness + fuzz + govulncheck security)
##	   5. profiler (flamegraph SVG; non-gating artifact - see failure policy)
##	   6. cross-compile + package every shipping platform (archives, deb/rpm, Windows installers, checksums)
##	   7. dogfood (install the optimized native build locally, fixed name) + screenshots + demo gif
##	   8. backup + publish to git (runs from repo root)
##	- Syntax:
##	  cicd/cicd.bash [options]
##	  Options:
##	   -q, --quiet         unattended, and no plan or progress lines; stage headers, results and errors still print
##	   -y, --yes           unattended (no prompt) but not quiet
##	   -m, --message MSG   publish hands-off with this commit message (no editor)
##	       --msg MSG       alias for --message
##	   --no-fmt            skip the formatter stage
##	   --no-lint           skip the lint stage
##	   --no-cross          skip the cross-compile + package stage
##	   --no-profile        skip the profiler stage
##	   --no-dogfood        skip installing the native build locally
##	   --no-screenshots    skip regenerating README screenshots
##	   --no-demogif        skip regenerating the demo gif
##	   --no-publish        skip the git backup + publish stage
##	   --long              exhaustive test run (sets CICDTEST_DO_LONGTEST=1)
##	   --quick             skip the slow stages (cross-compile, profiler, screenshots, demo gif), shorten fuzz,
##	                       and skip the harness perf section and packaging rebuild check
##	   --container         run stages 1 to 4, 6 and the demo gif in the pinned image from cicd/container/,
##	                       where a missing tool is an error. The profiler, dogfood and publish then run here.
##	                       The default when config.bash sets CONTAINER_DEFAULT=1.
##	   --host              run every stage here, with whatever tools this machine has
##	   -h, --help          show this help
##	- If neither -q/-y nor -m is given, the run prompts once for a commit message
##	  (blank = git editor; Ctrl+C aborts the whole run), then finishes unattended.
##	- --container needs docker, or CICD_DOCKER naming a program that takes its arguments.
##	  The image is built the first time it's needed, and again when anything in its
##	  dir or cicd/tool-versions.env changes. Its caches live in a docker volume.
##	- Reuse: copy the cicd/ directory into another project and edit config.bash.

##	History: At bottom of script.

##	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
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
export MAKEFLAGS="${MAKEFLAGS:+$MAKEFLAGS }--no-print-directory"  ## drop the Entering/Leaving dir noise

## Parse options.
assume_yes=0; quiet=0; quick=0; do_long=0; cli_message=""; use_container=""; inner_args=()
while (($#)); do case "$1" in
	-q|--quiet)               quiet=1; assume_yes=1; shift ;;
	-y|--yes)                 assume_yes=1; shift ;;
	--no-fmt)                 FMT_CMD=(); inner_args+=("$1"); shift ;;
	--no-lint)                VET_CMD=(); LINT_CMD=(); STATICCHECK_CMD=(); SHELLCHECK_CMD=(); RUFF_CMD=(); inner_args+=("$1"); shift ;;
	--no-cross)               BUILD_CROSS=0; inner_args+=("$1"); shift ;;
	--no-profile)             PROFILE_ENABLE=0; shift ;;
	--no-dogfood)             DOGFOOD_FIXED_DESTS=(); shift ;;
	--no-screenshots)         DO_SCREENSHOTS=0; inner_args+=("$1"); shift ;;
	--no-demogif)             DO_DEMOGIF=0; inner_args+=("$1"); shift ;;
	--no-publish)             GIT_PUBLISH=(); shift ;;
	--container)              use_container=1; shift ;;
	--host)                   use_container=0; shift ;;
	--long)                   do_long=1; inner_args+=("$1"); shift ;;
	--quick)                  quick=1; BUILD_CROSS=0; PROFILE_ENABLE=0; DO_SCREENSHOTS=0; DO_DEMOGIF=0; inner_args+=("$1"); shift ;;
	--message=*|--msg=*|-m=*) cli_message="${1#*=}"; shift ;;
	-m|--message|--msg)       cli_message="${2-}"; shift; (($#)) && shift ;;
	-h|--help)                sed -n '/^##	- Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
	*) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac; done
## The container run does its part and leaves the rest to the host run that
## started it. The host run also keeps the log, so this one doesn't.
if [[ "${CICD_IN_CONTAINER:-0}" == "1" ]]; then
	[[ "${use_container}" != "1" ]] || { echo "--container is for the host, not the container" >&2; exit 2; }
	use_container=0; LINT_LOG_DIR=""
fi
[[ -n "${use_container}" ]] || use_container="${CONTAINER_DEFAULT:-0}"
## Older configs don't have these.
[[ -v CONTAINER_MOUNTS ]] || CONTAINER_MOUNTS=()
[[ -v CONTAINER_CONTEXTS ]] || CONTAINER_CONTEXTS=()
[[ -v CONTAINER_CONTEXT_MISSING ]] || CONTAINER_CONTEXT_MISSING=()

## Brief beat after each stage header so the cheap fast stages stay readable.
## Off for unattended runs (-q/-y) where nobody is watching.
stage_pause=0.4; ((assume_yes)) && stage_pause=0

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
## fEcho_Chat is fEcho_Clean for the plan and progress lines that -q drops.
declare -i _wasLastEchoBlank=0
fEcho_ResetBlankCounter(){ _wasLastEchoBlank=0; }
fEcho_Clean(){ if [[ -n "${1:-}" ]]; then echo -e "$*"; _wasLastEchoBlank=0; elif [[ $_wasLastEchoBlank -eq 0 ]] && echo; then _wasLastEchoBlank=1; fi; }
fEcho(){       if [[ -n "$*"     ]]; then fEcho_Clean "[ $* ]"; else fEcho_Clean ""; fi; }
fEcho_Force(){ fEcho_ResetBlankCounter; fEcho "$*"; }
fEcho_Chat(){  if ((quiet)); then return 0; fi; fEcho_Clean "$@"; }
_letterbox="••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••"
fSection(){ fEcho_Clean; fEcho_Clean "${_letterbox}"; fEcho "$*"; [[ "${stage_pause:-0}" == 0 ]] || sleep "${stage_pause}"; }
fDie(){ { fEcho_Force "FAILED: $*"; } >&2; exit 1; }
## A tool that isn't installed skips its check, except where every tool is meant
## to be (CICD_NO_SKIP=1, set in the container).
fSkip(){ [[ "${CICD_NO_SKIP:-0}" != "1" ]] || fDie "$* (CICD_NO_SKIP=1)"; fEcho "WARNING: $*"; }
## Run a command array inside the Go module dir (SRC_DIR). Go tool stages need it.
in_src(){ ( cd "${root}/${SRC_DIR}" && "$@" ); }
## Every tracked Bash file into the named array: a *.bash name, or an executable
## with a sh or bash shebang. Paths starting with a SHELLCHECK_EXCLUDE entry are
## left out. A new script is checked without being listed anywhere.
fShellFiles(){
	local -n files_fsf="$1"
	local entry mode path exclude firstLine
	local shebangRe='^#!.*[/[:space:]](ba)?sh([[:space:]]|$)'
	files_fsf=()
	while IFS= read -r -d '' entry; do
		mode="${entry%% *}"; path="${entry#*$'\t'}"
		for exclude in "${SHELLCHECK_EXCLUDE[@]}"; do
			if [[ "${path}" == "${exclude}"* ]]; then continue 2; fi
		done
		if [[ "${path}" != *.bash ]]; then
			[[ "${mode}" == "100755" ]] || continue
			firstLine=""; IFS= read -r firstLine <"${root}/${path}" || true
			[[ "${firstLine}" =~ ${shebangRe} ]] || continue
		fi
		files_fsf+=("${path}")
	done < <(git -C "${root}" ls-files -s -z)
}
## A build context dir from CONTAINER_CONTEXTS, if it's there and has anything in it.
fContextDir(){ local dir="${root}/${1#*=}"; if [[ -d "${dir}" && -n "$(ls -A "${dir}")" ]]; then readlink -f "${dir}"; fi; }
## Tagged by a hash of the recipe dir, the tool pins and which contexts are
## there, so changing any of them can't run on the old image. A context's files
## are checked against the recipe inside the build.
fContainerImage(){
	local c
	printf '%s:%s' "${CONTAINER_IMAGE}" "$( {
		find "${root}/${CONTAINER_DIR}" -maxdepth 1 -type f -print0 | LC_ALL=C sort -z | xargs -0 cat
		cat "${root}/cicd/tool-versions.env"
		for c in "${CONTAINER_CONTEXTS[@]}"; do if [[ -n "$(fContextDir "${c}")" ]]; then echo "${c%%=*}"; fi; done
	} | git hash-object --stdin | cut -c1-12)"
}
## Stages 1 to 4, 6 and the demo gif, in the pinned image, as this user. The repo
## is mounted at the same path, so paths in logs and caches still point at
## something, and so is a linked worktree's git dir.
fRunContainer(){
	local engine="${CICD_DOCKER:-docker}" image old k v m c
	command -v "${engine}" >/dev/null 2>&1 || fDie "no ${engine} to run the stages in a container; install it, or run with --host"
	local -a inner=(-y)
	if ((quiet)); then inner=(-q); fi
	inner+=(--no-profile --no-dogfood --no-publish "${inner_args[@]}")
	[[ -f "${root}/${CONTAINER_DIR}/Dockerfile" ]] || fDie "no container recipe at ${CONTAINER_DIR}/Dockerfile"
	image="$(fContainerImage)"
	if "${engine}" image inspect "${image}" >/dev/null 2>&1; then
		fEcho_Chat "image ${image}"
	else
		fEcho "building ${image}"
		local -a buildArgs=()
		while IFS='=' read -r k v; do
			if [[ "${k}" =~ ^[A-Z_]+$ ]]; then buildArgs+=(--build-arg "${k}=${v}"); fi
		done <"${root}/cicd/tool-versions.env"
		## A missing context builds from an empty dir.
		local c dir empty=""
		for c in "${CONTAINER_CONTEXTS[@]}"; do
			dir="$(fContextDir "${c}")"
			if [[ -z "${dir}" ]]; then [[ -n "${empty}" ]] || empty="$(mktemp -d)"; dir="${empty}"; fi
			buildArgs+=(--build-context "${c%%=*}=${dir}")
		done
		"${engine}" build -t "${image}" "${buildArgs[@]}" "${root}/${CONTAINER_DIR}" || fDie "could not build ${image}"
		if [[ -n "${empty}" ]]; then rmdir "${empty}"; fi
		## What it replaces is a few GB nobody runs again.
		while IFS= read -r old; do
			if [[ -z "${old}" || "${old}" == "${image}" ]]; then continue; fi
			if "${engine}" rmi "${old}" >/dev/null 2>&1; then fEcho_Chat "removed ${old}"; else fEcho_Chat "kept ${old} (in use)"; fi
		done < <("${engine}" image ls "${CONTAINER_IMAGE}" --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true)
	fi
	local -a mounts=(-v "${root}:${root}" -v "${CONTAINER_VOLUME}:/cache")
	## This machine's time zone, so stamped names match the ones made out here.
	if [[ -e /etc/localtime ]]; then mounts+=(-v /etc/localtime:/etc/localtime:ro); fi
	local gitCommon; gitCommon="$(git -C "${root}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
	if [[ -n "${gitCommon}" && "${gitCommon}" != "${root}/"* ]]; then mounts+=(-v "${gitCommon}:${gitCommon}"); fi
	for m in "${CONTAINER_MOUNTS[@]}"; do
		if [[ -d "${root}/${m}" ]]; then mounts+=(-v "$(readlink -f "${root}/${m}"):$(cd "${root}/${m}" && pwd)"); fi
	done
	for c in "${CONTAINER_CONTEXTS[@]}"; do
		if [[ -z "$(fContextDir "${c}")" ]]; then
			fEcho "NOTE: no ${c#*=}, so the container runs with ${CONTAINER_CONTEXT_MISSING[*]}"
			inner+=("${CONTAINER_CONTEXT_MISSING[@]}")
			break
		fi
	done
	fEcho_Chat "inside: cicd/cicd.bash ${inner[*]}"
	"${engine}" run --rm --init --user "$(id -u):$(id -g)" "${mounts[@]}" -w "${root}" "${image}" \
		bash "${root}/cicd/cicd.bash" "${inner[@]}" || fDie "the run in the container failed; its output is above"
}
trap 'rc=$?; printf "\n[ CICD ABORTED (exit %s) at line %s: %s ]\n" "$rc" "$LINENO" "$BASH_COMMAND" >&2; exit $rc' ERR

## Preflight: show the plan with resolved paths, then confirm.
profile_dir="$(cd "${root}" && mkdir -p "${PROFILE_OUT_DIR}" 2>/dev/null; cd "${PROFILE_OUT_DIR}" 2>/dev/null && pwd || echo "${root}/${PROFILE_OUT_DIR}")"
fixed_dest=""; for d in "${DOGFOOD_FIXED_DESTS[@]:-}"; do [[ -d "$d" && -w "$d" ]] && { fixed_dest="$d"; break; }; done

fEcho_Chat
fEcho_Chat "${APP_NAME} local CI/CD"
fEcho_Chat
fEcho_Chat "Repo root ...........: ${root}"
((use_container)) && \
fEcho_Chat "Container ...........: $(fContainerImage) (stages 1-4, 6 and the demo gif)"
fEcho_Chat "Vendor pins .........: ${VENDOR_CHECK_CMD[*]:-(skipped)}"
fEcho_Chat "Interop pins ........: ${INTEROP_CHECK_CMD[*]:-(skipped)}"
fEcho_Chat "Format ..............: ${FMT_CMD[*]:-(skipped)}"
fEcho_Chat "Native build ........: ${NATIVE_BUILD_CMD[*]} -> ${STAGED_BIN} (debug)"
((${#RELEASE_BUILD_CMD[@]})) && \
fEcho_Chat "                       ${RELEASE_BUILD_CMD[*]} -> ${STAGED_RELEASE_BIN} (release, dogfooded)"
if ((${#VET_CMD[@]})); then
	fEcho_Chat "Lint ................: ${VET_CMD[*]}  (+ golangci-lint, staticcheck, shellcheck, ruff if installed)"
else
	fEcho_Chat "Lint ................: (skipped)"
fi
fEcho_Chat "Tests ...............: ${UNIT_TEST_CMD[*]} + ${TEST_CMD[*]}$( ((do_long)) && echo '  (long)')"
if ((FUZZ_ENABLE)); then
	fEcho_Chat "Fuzz ................: ${FUZZ_TIME}/target, ${FUZZ_MINIMIZE_TIME}/find$( ((quick)) && echo " (quick: ${FUZZ_TIME_QUICK}, ${FUZZ_MINIMIZE_TIME_QUICK})")"
else
	fEcho_Chat "Fuzz ................: (disabled)"
fi
fEcho_Chat "Security ............: ${VULN_CMD[*]}  (if installed)"
if ((PROFILE_ENABLE)); then
	fEcho_Chat "Profiler ............: bench ${PROFILE_BENCH} ${PROFILE_TIME} -> flamegraph SVG"
	fEcho_Chat "  output dir ........: ${profile_dir}"
else
	fEcho_Chat "Profiler ............: (skipped)"
fi
if ((BUILD_CROSS)); then
	fEcho_Chat "Cross + package .....: ${RELEASE_CMD[*]} -> ${RELEASE_ARTIFACT_DIR}/ (tgz/zip, deb/rpm, installers)"
else
	fEcho_Chat "Cross + package .....: (skipped)"
fi
if ((${#DOGFOOD_FIXED_DESTS[@]})); then
	if [[ -n "$fixed_dest" ]]; then fEcho_Chat "Dogfood, fixed name .: overwrite ${fixed_dest}/${EXE_NAME}"
	else fEcho_Chat "Dogfood, fixed name .: <none of: ${DOGFOOD_FIXED_DESTS[*]} exists - will skip>"; fi
else
	fEcho_Chat "Dogfood, fixed name .: (disabled)"
fi
fEcho_Chat "Screenshots .........: $( ((DO_SCREENSHOTS)) && echo "${SCREENSHOT_CMD[*]}" || echo '(skipped)')"
gif_plan="${DEMOGIF_CMD[*]}"
((DO_DEMOGIF)) || gif_plan="(skipped)"
if ((DO_DEMOGIF && ! use_container)) && [[ "${DEMOGIF_CONTAINER_ONLY:-0}" == "1" && "${CICD_IN_CONTAINER:-0}" != "1" ]]; then gif_plan="(skipped: only container runs make it)"; fi
fEcho_Chat "Demo gif ............: ${gif_plan}"
if ((${#GIT_PUBLISH[@]} == 0)); then
	fEcho_Chat "Publish (last) ......: (disabled)"
elif [[ -n "$publish_msg" ]]; then
	fEcho_Chat "Publish (last) ......: ${GIT_PUBLISH[*]} (hands-off: \"${publish_msg}\")"
else
	fEcho_Chat "Publish (last) ......: ${GIT_PUBLISH[*]} (will prompt for message; blank = editor)"
fi
fEcho_Chat
fEcho_Chat "Fail-fast: any error aborts before the next stage."
fEcho_Chat

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
	## Wait for tee to drain on exit, else the shell prompt returns mid-flush and
	## the last output lands after it (looks like the prompt "came back").
	tee_pid=$!
	trap 'exec 1>&- 2>&-; wait "${tee_pid}" 2>/dev/null' EXIT
fi

container_done=0
if ((use_container)); then
	fSection "Container"
	fRunContainer
	container_done=1
	fEcho "OK: stages 1 to 4 and 6 passed in the container"
else
	## Pinned tools: bring any go-installed tool that drifted from tool-versions.env
	## back in line (warn-only; probe-gated stages still skip anything missing).
	if [[ -n "${PIN_TOOLS_CMD[*]:-}" ]]; then
		"${PIN_TOOLS_CMD[@]}"
	fi

	## Pinned vendor: a vendored drop-in that drifted from its upstream tag aborts
	## here, before anything is built against it. Warn-only when offline.
	if [[ -n "${VENDOR_CHECK_CMD[*]:-}" ]]; then
		"${VENDOR_CHECK_CMD[@]}" || fDie "vendored source does not match its pin (see cicd/vendor-pins.env)"
	fi

	## Same idea for the interop suite's reference implementations, which are the
	## only thing proving the four big bases interoperate at all.
	if [[ -n "${INTEROP_CHECK_CMD[*]:-}" ]]; then
		"${INTEROP_CHECK_CMD[@]}" || fDie "interop reference does not match its pin (see cicd/utility/interop/pins.env)"
	fi

	## Stage 1: format.
	fSection "1/8  Format"
	if ((${#FMT_CMD[@]} == 0)); then
		fEcho_Chat "format skipped"
	else
		"${FMT_CMD[@]}"
		fEcho "OK: formatted (${FMT_CMD[*]})"
	fi

	## Stage 2: native builds, staged aside from what the cross stage cleans. The
	## debug build (symbols) is what the tests and profiler run against; the
	## optimized build is smoke-checked here and dogfooded in stage 7.
	fSection "2/8  Native build"
	"${NATIVE_BUILD_CMD[@]}"
	[[ -f "${NATIVE_BUILD_OUT}" ]] || fDie "debug build produced no binary: ${NATIVE_BUILD_OUT}"
	mkdir -p "$(dirname "${STAGED_BIN}")"
	cp -f "${NATIVE_BUILD_OUT}" "${STAGED_BIN}"
	fEcho "OK: debug build: ${STAGED_BIN} ($(du -h "${STAGED_BIN}" | cut -f1))  ($("${STAGED_BIN}" --version))"
	if ((${#RELEASE_BUILD_CMD[@]})); then
		"${RELEASE_BUILD_CMD[@]}"
		[[ -f "${RELEASE_BUILD_OUT}" ]] || fDie "release build produced no binary: ${RELEASE_BUILD_OUT}"
		cp -f "${RELEASE_BUILD_OUT}" "${STAGED_RELEASE_BIN}"
		"${STAGED_RELEASE_BIN}" --version >/dev/null 2>&1 || fDie "release build smoke check failed"
		fEcho "OK: release build: ${STAGED_RELEASE_BIN} ($(du -h "${STAGED_RELEASE_BIN}" | cut -f1))  ($("${STAGED_RELEASE_BIN}" --version))"
	fi

	## Stage 3: lint. go vet is gating; golangci-lint, staticcheck, shellcheck and ruff
	## run when installed (a failed probe skips that one with a warning). Any finding
	## from one that runs aborts. All output lands in the run log.
	fSection "3/8  Lint"
	if ((${#VET_CMD[@]} == 0)); then
		fEcho_Chat "lint skipped"
	else
		in_src "${VET_CMD[@]}"
		fEcho "OK: go vet clean"
		if ((${#LINT_CMD[@]})); then
			if in_src "${LINT_PROBE[@]}" >/dev/null 2>&1; then
				in_src "${LINT_CMD[@]}"; fEcho "OK: golangci-lint clean"
			else
				fSkip "golangci-lint skipped (not installed: go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest)"
			fi
		fi
		if ((${#STATICCHECK_CMD[@]})); then
			if in_src "${STATICCHECK_PROBE[@]}" >/dev/null 2>&1; then
				in_src "${STATICCHECK_CMD[@]}"; fEcho "OK: staticcheck clean"
			else
				fSkip "staticcheck skipped (not installed: go install honnef.co/go/tools/cmd/staticcheck@latest)"
			fi
		fi
		## A linter handed no files passes, so an empty list is a failure.
		if [[ -n "${SHELLCHECK_CMD[*]:-}" ]]; then
			if "${SHELLCHECK_PROBE[@]}" >/dev/null 2>&1; then
				fShellFiles shellFiles
				((${#shellFiles[@]})) || fDie "shellcheck: no Bash files found to check"
				"${SHELLCHECK_CMD[@]}" "${shellFiles[@]}"; fEcho "OK: shellcheck clean (${#shellFiles[@]} files)"
			else
				fSkip "shellcheck skipped (not installed: apt install shellcheck)"
			fi
		fi
		if [[ -n "${RUFF_CMD[*]:-}" ]]; then
			if "${RUFF_PROBE[@]}" >/dev/null 2>&1; then
				pyCount="$("${RUFF_CMD[@]}" --show-files 2>/dev/null | grep -c '\.py$' || true)"
				((pyCount)) || fDie "ruff: no Python files found to check"
				"${RUFF_CMD[@]}"; fEcho "OK: ruff clean (${pyCount} files)"
			else
				fSkip "ruff skipped (not installed: pipx install ruff)"
			fi
		fi
	fi

	## Stage 4: tests. Unit (Go), integration harness (against the staged binary),
	## fuzz (one target per invocation), and govulncheck security (module + deps).
	fSection "4/8  Tests"
	## Every test has its own ID, so a failure, a backlog item and a commit can all
	## name the same one. Each prints with its ID.
	if ((${#TEST_ID_CMD[@]})); then
		(cd "${root}" && "${TEST_ID_CMD[@]}" check) || fDie "a test has no ID, a bad one, or shares one"
		in_src "${UNIT_TEST_CMD[@]}" 2>&1 | (cd "${root}" && "${TEST_ID_CMD[@]}" report) || fDie "unit tests failed"
	else
		in_src "${UNIT_TEST_CMD[@]}"
	fi
	fEcho "OK: unit tests"
	## The harness runs its perf section and packaging rebuild check unless --quick.
	do_perf=1; ((quick)) && do_perf=0
	CICDTEST_EXE="${root}/${STAGED_BIN}" CICDTEST_DO_LONGTEST="${do_long}" CICDTEST_DO_PERF="${do_perf}" CICDTEST_QUICK="${quick}" "${TEST_CMD[@]}"
	fEcho "OK: integration harness"

	## 4b: fuzz each discovered target for a bounded time (shorter under --quick).
	if ((FUZZ_ENABLE)); then
		ft="${FUZZ_TIME}"; ((quick)) && ft="${FUZZ_TIME_QUICK}"
		fuzz_min="${FUZZ_MINIMIZE_TIME:-2s}"; ((quick)) && fuzz_min="${FUZZ_MINIMIZE_TIME_QUICK:-1s}"
		mapfile -t fuzz_targets < <(in_src go test -list '^Fuzz' "${GO_TEST_PKG:-.}" 2>/dev/null | grep -E '^Fuzz' || true)
		if ((${#fuzz_targets[@]})); then
			fuzz_log="$(mktemp -t cicd-fuzz.XXXXXX)"
			for t in "${fuzz_targets[@]}"; do
				fEcho_Chat "fuzz ${t} (${ft}) ..."
				## Only || keeps the ERR trap off a failed run; set +e does not.
				fuzz_rc=0
				in_src go test -run '^$' -fuzz "^${t}$" -fuzztime "${ft}" -fuzzminimizetime "${fuzz_min}" "${GO_TEST_PKG:-.}" 2>&1 | tee "${fuzz_log}" || fuzz_rc=$?
				fuzz_id="-------"
				((${#TEST_ID_CMD[@]})) && fuzz_id="$(cd "${root}" && "${TEST_ID_CMD[@]}" lookup "${SRC_DIR}/${GO_TEST_PKG:-.}" "${t}" || true)"
				if ((fuzz_rc)); then
					## A bare "context deadline exceeded" with no crasher is the
					## -fuzztime boundary, not a find: the coordinator reads the
					## worker context before cancellation has reached it, so the
					## deadline gets reported as the run's error. Real finds name
					## the failing input file.
					if grep -q 'Failing input written to' "${fuzz_log}" \
					|| ! grep -q 'context deadline exceeded' "${fuzz_log}"; then
						printf ' FAIL %s  %s (fuzz, %s)\n' "${fuzz_id}" "${t}" "${ft}"
						rm -f "${fuzz_log}"; fDie "fuzz ${t} found a failure"
					fi
					fEcho "NOTE: fuzz ${t} reported the -fuzztime deadline; no failing input recorded"
				fi
				printf '  ok  %s  %s (fuzz, %s)\n' "${fuzz_id}" "${t}" "${ft}"
			done
			rm -f "${fuzz_log}"
			fEcho "OK: fuzz (${#fuzz_targets[@]} target(s), ${ft} each)"
		else
			fEcho_Chat "no Fuzz* targets found; skipping fuzz"
		fi
	fi

	## 4c: security. govulncheck scans the module and its dependencies (library code).
	if ((${#VULN_CMD[@]})); then
		if in_src "${VULN_PROBE[@]}" >/dev/null 2>&1; then
			in_src "${VULN_CMD[@]}"; fEcho "OK: no known vulnerabilities"
		else
			fSkip "govulncheck skipped (not installed: go install golang.org/x/vuln/cmd/govulncheck@latest)"
		fi
	fi
	fEcho "OK: tests passed"
fi

## Stage 5: profiler (non-gating artifact; failures classified below).
run_profiler(){
	((PROFILE_ENABLE)) || { fEcho_Chat "profiler disabled"; return 0; }

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

	fEcho_Chat "sampling bench ${PROFILE_BENCH} for ${PROFILE_TIME} ..."
	if ! in_src go test -run '^$' -bench "^${PROFILE_BENCH}$" -benchtime "${PROFILE_TIME}" \
		-cpuprofile "${prof}" -o /dev/null "${GO_TEST_PKG:-.}"; then
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

if ((! container_done)); then
	## Stage 6: cross-compile + package (build sanity + release artifacts).
	fSection "6/8  Cross + package"
	if ((BUILD_CROSS)); then
		"${RELEASE_CMD[@]}"
		count="$(find "${RELEASE_ARTIFACT_DIR}" -maxdepth 1 -type f \( -name '*.tgz' -o -name '*.zip' -o -name '*.deb' -o -name '*.rpm' -o -name '*.exe' \) 2>/dev/null | wc -l)"
		((count > 0)) || fDie "cross + package produced no artifacts in ${RELEASE_ARTIFACT_DIR}/"
		fEcho "OK: release artifacts: ${count} in ${RELEASE_ARTIFACT_DIR}/"
	else
		fEcho_Chat "cross + package skipped"
	fi
fi

## Stage 7: dogfood (fixed name) + screenshots. Dogfood the optimized release
## build (the real thing), falling back to the debug build if it wasn't made.
fSection "7/8  Dogfood"
dogfood_bin="${STAGED_BIN}"
[[ -n "${STAGED_RELEASE_BIN:-}" && -f "${STAGED_RELEASE_BIN}" ]] && dogfood_bin="${STAGED_RELEASE_BIN}"
if ((${#DOGFOOD_FIXED_DESTS[@]})); then
	if [[ -n "$fixed_dest" ]]; then
		## sudo -n never prompts, so it can't hang a run, and an unattended run
		## doesn't try it at all.
		dogfood_to="${fixed_dest}/${EXE_NAME}"; dogfood_how=""
		if cp -f "${dogfood_bin}" "${dogfood_to}"; then :
		elif [[ "${fixed_dest}" == "${HOME}/"* ]] || ((assume_yes)); then fDie "could not install ${dogfood_to}"
		elif sudo -n cp -f "${dogfood_bin}" "${dogfood_to}"; then dogfood_how=" (sudo)"
		else fDie "could not install ${dogfood_to}, even with sudo -n"
		fi
		fEcho "OK: installed${dogfood_how} -> ${dogfood_to}"
	else
		fEcho "WARNING: no dogfood dest exists (${DOGFOOD_FIXED_DESTS[*]}); skipping"
	fi
else
	fEcho_Chat "dogfood disabled"
fi

## Screenshots: off by default (retired, so the skip is silent); a failure is a
## warning, never a stop.
screenshot_util="${root}/${SCREENSHOT_CMD[0]}"
if ((! DO_SCREENSHOTS)); then
	: ## silent - the preflight summary already says skipped
elif [[ -f "${screenshot_util}" ]]; then
	if bash "${screenshot_util}" "${root}" "${root}/${STAGED_BIN}"; then fEcho "OK: screenshots regenerated"
	else fEcho "WARNING: screenshot generation failed (continuing)"; fi
else
	fEcho_Clean "no screenshot utility at ${screenshot_util}; skipping"
fi

## Demo gif: types the scenario into a fake terminal, runs each command against the
## tested binary, renders the animated loop. A failure is a warning, never a stop.
demogif_util="${root}/${DEMOGIF_CMD[0]}"
if ((container_done)); then
	: ## made in the container
elif ((! DO_DEMOGIF)); then
	fEcho_Chat "demo gif skipped"
elif [[ "${DEMOGIF_CONTAINER_ONLY:-0}" == "1" && "${CICD_IN_CONTAINER:-0}" != "1" ]]; then
	## Its fallback fonts are whatever this machine has, so it would flip back
	## and forth against the container's.
	fEcho_Chat "demo gif skipped: only container runs make it"
elif [[ -f "${demogif_util}" ]]; then
	demogif_out="${root}/${DEMOGIF_OUT}"
	demogif_tmp="${demogif_out}.new"
	if (cd "${root}" && python3 "${DEMOGIF_CMD[@]}" --out "${demogif_tmp}" --bin "${root}/${STAGED_BIN}"); then
		if [[ -f "${demogif_out}" ]] && cmp -s "${demogif_tmp}" "${demogif_out}"; then
			rm -f "${demogif_tmp}"
			fEcho "OK: demo gif unchanged"
		else
			## Keep the new original out of tree (GFS-pruned), then land it in the repo.
			mkdir -p "${DEMOGIF_ARCHIVE_DIR}"
			cp -f "${demogif_tmp}" "${DEMOGIF_ARCHIVE_DIR}/demo_$(date +%Y%m%d-%H%M%S).gif"
			gfs_rotate "${DEMOGIF_ARCHIVE_DIR}" demo gif >/dev/null 2>&1 || true
			mv -f "${demogif_tmp}" "${demogif_out}"
			fEcho "OK: demo gif regenerated"
		fi
	else
		rm -f "${demogif_tmp}"
		fSkip "demo gif generation failed"
	fi
else
	fEcho_Clean "no demo gif utility at ${demogif_util}; skipping"
fi

## Stage 8: backup + publish.
fSection "8/8  Backup + publish"
## Optional out-of-tree pre-publish hook (kept under ../private so it never ships
## in the repo). Run it if present + executable; a missing dir/file is skipped,
## not an error. Non-zero exit aborts before anything is published.
if [[ -n "${PREPUBLISH_HOOK:-}" && -x "${PREPUBLISH_HOOK}" ]]; then
	fEcho_Chat "pre-publish hook: ${PREPUBLISH_HOOK}"
	"${PREPUBLISH_HOOK}" "${root}" || fDie "pre-publish hook rejected the tree"
fi
## Always run the publisher quiet: cicd already gave the initial prompt, so skip
## its redundant continue-prompt. With no message it still lets git open the editor.
pub_flags=(--quiet)
if ((${#GIT_PUBLISH[@]} == 0)); then
	fEcho_Chat "publish disabled"
elif [[ -n "$publish_msg" ]]; then
	## Hands-off: the publisher fills the empty commit message from -m so `git
	## commit` won't open an editor.
	fEcho_Chat "hands-off publish (commit message: \"${publish_msg}\")"
	"${GIT_PUBLISH[@]}" "${pub_flags[@]}" -m "${publish_msg}"
	fEcho "OK: published"
else
	"${GIT_PUBLISH[@]}" "${pub_flags[@]}"
	fEcho "OK: published"
fi

if [[ "${CICD_IN_CONTAINER:-0}" == "1" ]]; then fSection "${APP_NAME} CI/CD: container part done."; else fSection "${APP_NAME} CI/CD: done."; fi
fEcho_Clean


##	History:
##		- 2026-07-03 JC: Created. Generic engine + config.bash, adapted from the sister project; Go build staging, exhaustive tests, quiet publish.
##		- 2026-07-09 JC: silkterm-style output (fEcho/fSection letterbox); -q/-m/--quick flags; lint, fuzz, vuln, profiler stages; tee'd run log; message prompt replaces y/n.
##		- 2026-07-29 JC: Vendored drop-in files are verified against their pinned upstream release before the build.
##		- 2026-10-04 JC: shellcheck and ruff in the lint stage.
##		- 2026-10-10 JC: --container runs the tool-heavy stages in a pinned image, where no check may skip.
##		- 2026-10-10 JC: Container runs can be the default (CONTAINER_DEFAULT), with --host to opt out. Build contexts from outside the repo.
