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
##	- Steps (fail-fast, any error aborts before the next step):
##	   - pins (pinned go tools, vendored source and interop references match their pins)
##	   - format (gofmt)
##	   - native build (staged aside so the cross step can't clobber it)
##	   - lint (go vet gating; golangci-lint, staticcheck, shellcheck, ruff and PSScriptAnalyzer if installed)
##	   - tests (unit + integration harness + fuzz + govulncheck security + leak checks)
##	   - profiler (flamegraph SVG; non-gating artifact - see failure policy)
##	   - cross-compile + package every shipping platform (archives, deb/rpm, Windows installers, checksums)
##	   - other hosts (the release builds run on the test boxes and VMs REMOTE_LOCAL names)
##	   - dogfood (install the optimized native build locally, fixed name, and any cross builds listed)
##	   - screenshots
##	   - demo gif
##	   - backup + publish to git (runs from repo root)
##	- Each step prints a rule, a Starting line, its output, and a PASS or FAIL line,
##	  each with the local time and "Step N of M". A step that's turned off isn't
##	  counted, and the first section says what turned it off.
##	- In a container run, the steps through tests, cross + package and the demo gif
##	  run first, in the container, then the rest here. So the profiler comes after
##	  cross + package there.
##	- Syntax:
##	  cicd/cicd.bash [options]
##	  Options:
##	   -q, --quiet         unattended, and no plan or progress lines; step lines, results and errors still print
##	   -y, --yes           unattended (no prompt) but not quiet
##	   -m, --message MSG   publish hands-off with this commit message (no editor)
##	       --msg MSG       alias for --message
##	   --no-fmt            skip the format step
##	   --no-lint           skip the lint step
##	   --no-cross          skip the cross-compile + package step
##	   --no-profile        skip the profiler step
##	   --no-dogfood        skip installing the builds locally
##	   --no-screenshots    skip regenerating README screenshots
##	   --no-demogif        skip regenerating the demo gif
##	   --no-publish        skip the git backup + publish step
##	   --no-sync           don't check the remote first (by default the run fetches, fast-forwards
##	                       when only behind, and stops when the branch and its upstream have diverged)
##	   --backlog-run-quick [AREA...]
##	                       the fast checks a backlog worker runs before it commits, in a few
##	                       minutes: the format check, lint, the Go unit tests and the quicker
##	                       harness areas, or only the areas named. --list shows the areas.
##	   --backlog-run-full  what a backlog round runs once at its end: every check of a plain run,
##	                       the other hosts included
##	   --merge-gate        the same checks as --backlog-run-full, before a merge to main. The git
##	                       pre-push hook runs it for a push to main, unless the push changes only
##	                       the paths MERGE_GATE_SKIP in config.bash names.
##	                       These 3 never sync, dogfood, publish, commit, push, install or prompt,
##	                       and never rewrite a tracked file: Format becomes the format check, the
##	                       pins are only checked, and the demo gif is made but not kept.
##	   --gate              another name for --backlog-run-quick
##	   --ci                another name for --merge-gate
##	   --list              print the steps the other flags would run, and the areas, and run nothing
##	   --no-remote         skip the builds and tests on the other hosts and VMs
##	   --long              the exhaustive tests (CICDTEST_DO_LONGTEST=1), and every leak check, the ones
##	                       that take hours too. A run without --quick has the tests already.
##	   --slow              another name for --long
##	   --leakcheck         every leak check, whatever its length: goleak in the unit tests, the Go
##	                       tests again under the race detector, the soak test, and CodeQL, which
##	                       keep their heap profiles and SARIF under cicd/artifacts
##	   --no-leakcheck      no leak checks at all, goleak and the fast ones included
##	   --quick             the fast checks only. Skips the profiler, screenshots, demo gif, the long tests,
##	                       the slow leak checks, and the checks that reach another host (vendor and interop pins,
##	                       govulncheck). Fuzz is shorter, and the harness skips its perf section and packaging
##	                       rebuild check. It still cross-compiles and packages, which takes seconds.
##	   --container         run the steps through tests, cross + package and the demo gif in the pinned
##	                       image from cicd/container/, where a missing tool is an error. The profiler,
##	                       dogfood, screenshots and publish then run here.
##	                       The default when config.bash sets CONTAINER_DEFAULT=1.
##	   --no-container      run every stage here, with whatever tools this machine has
##	   --host              another name for --no-container
##	   --keep-temp         keep the run's temp folder and containers, and print where they are at the end
##	   --image-tag         print the image tag a container run would use, and exit. Hosted CI
##	                       builds the image under that tag, with its layer cache, before the run.
##	   -h, --help          show this help, and the areas
##	- A run with no flags runs everything but the leak checks that take hours. --quick
##	  leaves out the long tests and slow leak checks, and --long puts them back.
##	- Each leak check has a length in LEAK_LENGTH in config.bash, by measured time.
##	  Fast ones run in every run, --quick and --backlog-run-quick included. Slow ones
##	  run in a plain run and with --long, and those that take hours only with --long.
##	  --leakcheck adds them all and --no-leakcheck takes them all out, and of the
##	  two the last one named wins.
##	- --quick still fetches first and publishes last. --no-sync and --no-publish skip those.
##	- If neither -q/-y nor -m is given, the run prompts once for a commit message
##	  (blank = git editor; Ctrl+C aborts the whole run), then finishes unattended.
##	- --container needs docker, or CICD_DOCKER naming a program that takes its arguments.
##	  Without a working one, or when the image won't build, the run says so and goes
##	  on here, as with --no-container.
##	  The image is built the first time it's needed, and again when anything in its
##	  dir or cicd/tool-versions.env changes. Its caches live in a docker volume.
##	  CICD_IMAGE_PREBUILT=1 makes a missing image an error instead, for a run whose
##	  image was built before it.
##	- Every step runs at nice 19, and idle I/O priority where ionice is there. It gets
##	  half the CPUs, or a quarter when the 1-minute load is over half the CPU count,
##	  checked before each step. The race detector, soak, fuzz and CodeQL get a quarter
##	  either way, and never under 1. A container gets the count as --cpus, with
##	  --cpu-shares 256, since nice out here doesn't reach it.
##	- What the run makes in docker is labeled dev.project and dev.run. At the end,
##	  pass or fail, it removes the run's containers, the project's dangling images,
##	  and after a pass every older image tag but one. Then the build cache older than
##	  a week, for every project, and the cache volume once it's over 2 GB. Nothing
##	  without the project's label is touched.
##	- One line at the end says what the cleanup removed, docker, stale run folders
##	  and the run's own folder, and about what it freed.
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

## Low priority for the whole run, which every child inherits. nice on the
## docker client doesn't reach a container, so fRunContainer caps that too.
renice -n 19 -p $$ >/dev/null 2>&1 || true
if command -v ionice >/dev/null 2>&1; then ionice -c 3 -p $$ >/dev/null 2>&1 || true; fi

## Job counts, worked out here and nowhere else: at the start, and again before
## each step since the load moves under a long run. CPU_CAP is for a normal
## step, and CPU_CAP_HEAVY for the race, soak, fuzz and CodeQL runs, which go
## through heavy_env. In a container nproc still counts the host's CPUs, so the
## run there gets its --cpus as CICD_JOBS_MAX.
## GOMAXPROCS bounds go build -p, go test, staticcheck and govulncheck, and
## GOFLAGS names -p and -parallel as well. Each compile runs up to 4 backend
## threads of its own on top of -p, which took a cold go test at -p 8 to 33
## runnable threads, so that's off. golangci-lint gets LINT_JOBS_FLAG, cargo and
## ruff their own variables, and the publish's rar reads CPU_CAP.
source "${here}/utility/include/machine-use.bash"
goflags_base=""; read -r -a _goflags <<<"${GOFLAGS:-}"
for _f in "${_goflags[@]}"; do [[ "${_f}" == -p=* || "${_f}" == -parallel=* ]] || goflags_base+="${goflags_base:+ }${_f}"; done
jobs_was=""; machine_line=""; heavy_env=(env)
fMachineUse(){
	local cpus load max="${CICD_JOBS_MAX:-}"
	cpus="$(fMachineCpus)"; load="$(fMachineLoad1)"
	fMachineJobs "${cpus}" "${load}"
	CPU_CAP="${machineJobs}"; CPU_CAP_HEAVY="${machineJobsHeavy}"
	if [[ "${max}" =~ ^[0-9]+$ ]] && ((10#${max} > 0 && CPU_CAP > 10#${max})); then CPU_CAP=$((10#${max})); fi
	((CPU_CAP_HEAVY <= CPU_CAP)) || CPU_CAP_HEAVY="${CPU_CAP}"
	export CPU_CAP GOMAXPROCS="${CPU_CAP}" CARGO_BUILD_JOBS="${CPU_CAP}" RAYON_NUM_THREADS="${CPU_CAP}" GO19CONCURRENTCOMPILATION=0
	export GOFLAGS="${goflags_base:+${goflags_base} }-p=${CPU_CAP} -parallel=${CPU_CAP}"
	heavy_env=(env "CPU_CAP=${CPU_CAP_HEAVY}" "GOMAXPROCS=${CPU_CAP_HEAVY}" "CARGO_BUILD_JOBS=${CPU_CAP_HEAVY}" "RAYON_NUM_THREADS=${CPU_CAP_HEAVY}"
		"GOFLAGS=${goflags_base:+${goflags_base} }-p=${CPU_CAP_HEAVY} -parallel=${CPU_CAP_HEAVY}")
	machine_line="${CPU_CAP} jobs, ${CPU_CAP_HEAVY} for the heavy steps (load ${load} on ${cpus} CPUs"
	if ((machineBusy)); then machine_line+=", busy"; fi
	if [[ -n "${max}" ]]; then machine_line+=", at most ${max} in this container"; fi
	machine_line+=")"
	if [[ -n "${jobs_was}" && "${jobs_was}" != "${CPU_CAP}" ]]; then fEcho_Chat "jobs now ${machine_line}"; fi
	jobs_was="${CPU_CAP}"
}
fMachineUse

source "${here}/config.bash"
[[ -v FMT_CHECK_CMD ]] || FMT_CHECK_CMD=()   ## older configs
[[ -v PIN_TOOLS_CMD ]] || PIN_TOOLS_CMD=()
[[ -v VENDOR_CHECK_CMD ]] || VENDOR_CHECK_CMD=()
[[ -v INTEROP_CHECK_CMD ]] || INTEROP_CHECK_CMD=()
[[ -v DOGFOOD_CROSS ]] || DOGFOOD_CROSS=()
[[ -v RACE_TEST_CMD ]] || RACE_TEST_CMD=()
[[ -v SOAK_CMD ]] || SOAK_CMD=()
[[ -v CODEQL_CMD ]] || CODEQL_CMD=()
## An older config has no lengths, so its leak checks are all slow, as they were.
declare -p LEAK_LENGTH >/dev/null 2>&1 || declare -A LEAK_LENGTH=()
[[ -v GOLEAK_OFF_TAG ]] || GOLEAK_OFF_TAG=""
for leakName in "${!LEAK_LENGTH[@]}"; do
	case "${LEAK_LENGTH[${leakName}]}" in fast|slow|hours) ;; *) echo "LEAK_LENGTH[${leakName}] is ${LEAK_LENGTH[${leakName}]}, not fast, slow or hours" >&2; exit 2 ;; esac
done
[[ -v PSSA_CMD ]] || PSSA_CMD=()
[[ -v LINT_JOBS_FLAG ]] || LINT_JOBS_FLAG=""
[[ -v REMOTE_CMD ]] || REMOTE_CMD=()
[[ -v UNIT_AREAS_CMD ]] || UNIT_AREAS_CMD=()
[[ -v TEST_AREAS_CMD ]] || TEST_AREAS_CMD=()
[[ -v QUICK_AREAS ]] || QUICK_AREAS=()
## Personal dogfood dirs, kept out of the repo. Before the options, so --no-dogfood still wins.
# shellcheck source=/dev/null
if [[ -n "${DOGFOOD_LOCAL:-}" && -f "${root}/${DOGFOOD_LOCAL}" ]]; then source "${root}/${DOGFOOD_LOCAL}"; fi
## The test boxes are personal too. A config with REMOTE_HOSTS runs REMOTE_CMD
## only when REMOTE_LOCAL names some; an older one runs it as it is.
# shellcheck source=/dev/null
if [[ -n "${REMOTE_LOCAL:-}" && -f "${root}/${REMOTE_LOCAL}" ]]; then source "${root}/${REMOTE_LOCAL}"; fi
## -v says no to an empty array, so declare -p it is.
remote_hosts_named=0; if declare -p REMOTE_HOSTS >/dev/null 2>&1; then remote_hosts_named=1; fi
[[ -v REMOTE_HOSTS ]] || REMOTE_HOSTS=()
[[ -v REMOTE_WRAP ]] || REMOTE_WRAP=()
source "${here}/utility/include/gfs-rotate.bash"       ## gfs_rotate() for the artifact dirs
source "${here}/utility/include/safe-rm.bash"          ## fSafeRm, fSafeRmUnder
cd "${root}"
stamp="$(date +%Y%m%d-%H%M%S)"
export MAKEFLAGS="${MAKEFLAGS:+$MAKEFLAGS }--no-print-directory"  ## drop the Entering/Leaving dir noise

## Parse options. The originals are kept for a restart after the sync.
## A flag that turns a step off names the step with fStepWhy, so the first
## section can say what turned it off.
declare -A step_why=()
fStepWhy(){ [[ -n "${step_why[$1]:-}" ]] || step_why[$1]="$2"; }
orig_args=("$@")
assume_yes=0; quiet=0; quick=0; do_long=""; long_named=0; do_leakcheck=""; cli_message=""; use_container=""; inner_args=(); do_sync=1; image_tag=0; keep_temp=0
run_mode=""; mode_note=""; quick_areas=(); list_only=0; want_help=0
fQuick(){ local s; quick=1; PROFILE_ENABLE=0; DO_SCREENSHOTS=0; DO_DEMOGIF=0; for s in Profiler Screenshots "Demo gif" Pins; do fStepWhy "${s}" "$1"; done; }
## One of the backlog runs or the merge gate, by its own name or the other one.
fRunMode(){
	if [[ -n "${run_mode}" && "${run_mode}" != "$1" ]]; then echo "pick one of --backlog-run-quick, --backlog-run-full and --merge-gate" >&2; exit 2; fi
	run_mode="$1"
	if [[ "$2" != "$1" ]]; then mode_note="$2 is another name for $1"; fi
}
while (($#)); do case "$1" in
	-q|--quiet)               quiet=1; assume_yes=1; shift ;;
	-y|--yes)                 assume_yes=1; shift ;;
	--no-fmt)                 FMT_CMD=(); FMT_CHECK_CMD=(); inner_args+=("$1"); fStepWhy Format "$1"; fStepWhy "Format check" "$1"; shift ;;
	--no-lint)                VET_CMD=(); LINT_CMD=(); STATICCHECK_CMD=(); SHELLCHECK_CMD=(); RUFF_CMD=(); PSSA_CMD=(); inner_args+=("$1"); fStepWhy Lint "$1"; shift ;;
	--no-cross)               BUILD_CROSS=0; inner_args+=("$1"); fStepWhy "Cross + package" "$1"; shift ;;
	--no-profile)             PROFILE_ENABLE=0; fStepWhy Profiler "$1"; shift ;;
	--no-dogfood)             DOGFOOD_FIXED_DESTS=(); DOGFOOD_CROSS=(); fStepWhy Dogfood "$1"; shift ;;
	--no-screenshots)         DO_SCREENSHOTS=0; inner_args+=("$1"); fStepWhy Screenshots "$1"; shift ;;
	--no-demogif)             DO_DEMOGIF=0; inner_args+=("$1"); fStepWhy "Demo gif" "$1"; shift ;;
	--no-publish)             GIT_PUBLISH=(); fStepWhy "Backup + publish" "$1"; shift ;;
	--container)              use_container=1; shift ;;
	--no-container|--host)    use_container=0; shift ;;
	--keep-temp)              keep_temp=1; shift ;;
	--image-tag)              image_tag=1; shift ;;
	--no-sync)                do_sync=0; shift ;;
	--no-remote)              REMOTE_CMD=(); fStepWhy "Other hosts" "$1"; shift ;;
	## The areas are the words after it, up to the next flag.
	--backlog-run-quick|--gate)
		fRunMode --backlog-run-quick "$1"; shift
		while (($#)) && [[ "$1" != -* ]]; do quick_areas+=("$1"); shift; done ;;
	--backlog-run-full)       fRunMode "$1" "$1"; shift ;;
	--merge-gate|--ci)        fRunMode --merge-gate "$1"; shift ;;
	--list)                   list_only=1; shift ;;
	--long|--slow)            do_long=1; long_named=1; inner_args+=(--long); shift ;;
	--leakcheck)              do_leakcheck=1; inner_args+=("$1"); shift ;;
	--no-leakcheck)           do_leakcheck=0; inner_args+=("$1"); shift ;;
	--quick)                  fQuick "$1"; inner_args+=("$1"); shift ;;
	--message=*|--msg=*|-m=*) cli_message="${1#*=}"; shift ;;
	-m|--message|--msg)       cli_message="${2-}"; shift; (($#)) && shift ;;
	-h|--help)                want_help=1; shift ;;
	*) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac; done
## The backlog runs and the merge gate never sync, dogfood, publish, commit,
## push, install or prompt, and never rewrite a tracked file. So Format is
## off and the format check runs instead, the pins are only checked, and the
## demo gif is made in the run's temp dir and left there. One line each, so
## the harness can take one out and see its check go red.
if [[ -n "${run_mode}" ]]; then
	assume_yes=1
	do_sync=0
	FMT_CMD=()
	DOGFOOD_FIXED_DESTS=(); DOGFOOD_CROSS=()
	DO_SCREENSHOTS=0
	GIT_PUBLISH=()
	if ((${#PIN_TOOLS_CMD[@]})); then PIN_TOOLS_CMD+=(--check); fi
	for modeOff in Format Dogfood Screenshots "Backup + publish"; do fStepWhy "${modeOff}" "${run_mode}"; done
fi
## On top of that, the quick one is --quick less the pins, cross builds, fuzz
## and the other hosts.
if [[ "${run_mode}" == --backlog-run-quick ]]; then
	fQuick "${run_mode}"; PIN_TOOLS_CMD=(); BUILD_CROSS=0; FUZZ_ENABLE=0; REMOTE_CMD=()
	for modeOff in "Cross + package" "Other hosts"; do fStepWhy "${modeOff}" "${run_mode}"; done
elif [[ -n "${run_mode}" ]]; then
	inner_args+=("${run_mode}")
fi
## The slow extras a plain run does and --quick doesn't. Each starts empty, and
## its flag sets it to 1, so naming one keeps it in a quick run.
full_extras=(do_long)
for extra in "${full_extras[@]}"; do [[ -n "${!extra}" ]] || printf -v "${extra}" '%s' "$(( ! quick ))"; done
## Leak checks go by length. --leakcheck and --no-leakcheck beat it, the last
## one named winning. Fast is every run, slow a plain run, hours only --long.
fLeakOn(){
	case "${do_leakcheck}" in 1) return 0 ;; 0) return 1 ;; esac
	case "${LEAK_LENGTH[$1]:-slow}" in
		fast)  return 0 ;;
		slow)  ((! quick || long_named)) ;;
		*)     ((long_named)) ;;
	esac
}
## Why one is off, for its skip line.
fLeakWhy(){ if [[ "${do_leakcheck}" == 0 ]]; then echo "--no-leakcheck"; else echo "${LEAK_LENGTH[$1]:-slow}"; fi; }
## --quick stays on this machine. These checks reach another host.
if ((quick)); then VENDOR_CHECK_CMD=(); INTEROP_CHECK_CMD=(); VULN_CMD=(); fi
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
[[ -v CONTAINER_VOLUME_CAP ]] || CONTAINER_VOLUME_CAP=2000000000

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

#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Output helpers: fEcho / fEcho_Clean, blank-collapsing.
## fEcho "msg" -> "[ msg ]" status line; fEcho_Clean "msg" -> plain line, and a
## bare call collapses repeated blanks. fSection draws the leading-blank + rule
## letterbox before a header that isn't a step; fDie prints a fatal line and exits.
## fEcho_Chat is fEcho_Clean for the plan and progress lines that -q drops.
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
declare -i _wasLastEchoBlank=0
fEcho_ResetBlankCounter(){ _wasLastEchoBlank=0; }
fEcho_Clean(){ if [[ -n "${1:-}" ]]; then echo -e "$*"; _wasLastEchoBlank=0; elif [[ $_wasLastEchoBlank -eq 0 ]] && echo; then _wasLastEchoBlank=1; fi; }
fEcho(){       if [[ -n "$*"     ]]; then fEcho_Clean "[ $* ]"; else fEcho_Clean ""; fi; }
fEcho_Force(){ fEcho_ResetBlankCounter; fEcho "$*"; }
fEcho_Chat(){  if ((quiet)); then return 0; fi; fEcho_Clean "$@"; }
_letterbox="•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••"
## Local time to the hundredth, as YYYYmmDD-HHMMSS.NN, into step_stamp. Some
## locales put a comma in EPOCHREALTIME, and bash before 5 has none.
fStepStamp(){
	local t="${EPOCHREALTIME:-}"; t="${t/,/.}"
	if [[ "${t}" == *.* ]]; then printf -v step_stamp '%(%Y%m%d-%H%M%S)T.%s' "${t%.*}" "${t#*.}"; step_stamp="${step_stamp:0:18}"
	else printf -v step_stamp '%(%Y%m%d-%H%M%S)T.00' -1; fi
}
## Each step checks the load again before it starts.
fSection(){ fEcho_Clean; fEcho_Clean "${_letterbox}"; fStepStamp; fEcho "${step_stamp}: $*"; fMachineUse; [[ "${stage_pause:-0}" == 0 ]] || sleep "${stage_pause}"; }

#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Steps. fStepPlan works out which are on, in the order they run, from the
## flags and config. Each step is `if fStep NAME; then ...; fStepDone; fi`, and
## fStep says no for one that's off, or that runs on the other side of the
## container. A step still open at exit is a FAIL, or a PASS on exit 0.
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The backlog runs and the merge gate check the format where Format would fix it.
fmt_steps=(Format); if [[ -n "${run_mode}" ]]; then fmt_steps=(Format "Format check"); fi
## Which steps run inside the container. Their order comes from step_order.
container_steps=(Pins "${fmt_steps[@]}" "Native build" Lint Tests "Cross + package" "Demo gif")
steps_on=(); steps_off=(); steps_numbered=(); step_open=""; step_num=0; step_stamp=""
fInList(){ local want="$1" item; shift; for item in "$@"; do if [[ "${item}" == "${want}" ]]; then return 0; fi; done; return 1; }
## Why a step is off, into step_off_why, or empty when it's on. What a flag
## turned off says the flag; anything else says what in config.bash did it.
fStepOffWhy(){
	local why="" ctx="" c
	case "$1" in
		Pins)               ((${#PIN_TOOLS_CMD[@]} + ${#VENDOR_CHECK_CMD[@]} + ${#INTEROP_CHECK_CMD[@]})) || why="none in config.bash" ;;
		Format)             ((${#FMT_CMD[@]})) || why="no FMT_CMD in config.bash" ;;
		"Format check")     ((${#FMT_CHECK_CMD[@]})) || why="no FMT_CHECK_CMD in config.bash" ;;
		"Native build")     ((run_harness)) || why="no harness area" ;;
		Lint)               ((${#VET_CMD[@]})) || why="no VET_CMD in config.bash" ;;
		Tests)              ((run_unit || run_harness)) || why="no test area" ;;
		Profiler)           ((PROFILE_ENABLE)) || why="PROFILE_ENABLE=0 in config.bash" ;;
		"Cross + package")  ((BUILD_CROSS)) || why="BUILD_CROSS=0 in config.bash" ;;
		"Other hosts")
			if ((! ${#REMOTE_CMD[@]})); then why="no REMOTE_CMD in config.bash"
			elif ((remote_hosts_named && ! ${#REMOTE_HOSTS[@]})); then why="no boxes in ${REMOTE_LOCAL:-REMOTE_LOCAL}"; fi ;;
		Dogfood)            ((${#DOGFOOD_FIXED_DESTS[@]} + ${#DOGFOOD_CROSS[@]})) || why="no dogfood dirs in config.bash" ;;
		Screenshots)        ((DO_SCREENSHOTS)) || why="DO_SCREENSHOTS=0 in config.bash" ;;
		"Backup + publish") ((${#GIT_PUBLISH[@]})) || why="no GIT_PUBLISH in config.bash" ;;
		"Demo gif")
			for c in "${CONTAINER_CONTEXTS[@]}"; do if [[ -z "$(fContextDir "${c}")" ]]; then ctx="${c#*=}"; break; fi; done
			if ((! DO_DEMOGIF)); then why="DO_DEMOGIF=0 in config.bash"
			## Its fallback fonts are whatever this machine has, so it would flip
			## back and forth against the container's.
			elif ((! use_container)) && [[ "${DEMOGIF_CONTAINER_ONLY:-0}" == "1" && "${CICD_IN_CONTAINER:-0}" != "1" ]]; then why="only container runs make it"
			elif ((use_container)) && [[ -n "${ctx}" ]] && fInList --no-demogif "${CONTAINER_CONTEXT_MISSING[@]}"; then why="no ${ctx}"
			elif [[ ! -f "${root}/${DEMOGIF_CMD[0]}" ]]; then why="no ${DEMOGIF_CMD[0]}"
			fi ;;
	esac
	if [[ -n "${why}" && -n "${step_why[$1]:-}" ]]; then why="${step_why[$1]}"; fi
	step_off_why="${why}"
}
## Inside the container only its own steps run, numbered as the host run that
## started it says in CICD_STEPS. A container run does all of those first, then
## the rest, each part in the order below, which is the order of the script.
step_order=(Pins "${fmt_steps[@]}" "Native build" Lint Tests Profiler "Cross + package" "Other hosts" Dogfood Screenshots "Demo gif" "Backup + publish")
fStepPlan(){
	local s
	local -a order=() rest=()
	for s in "${step_order[@]}"; do if fInList "${s}" "${container_steps[@]}"; then order+=("${s}"); else rest+=("${s}"); fi; done
	if [[ "${CICD_IN_CONTAINER:-0}" == "1" ]]; then :
	elif ((use_container)); then order+=("${rest[@]}")
	else order=("${step_order[@]}"); fi
	steps_on=(); steps_off=()
	for s in "${order[@]}"; do
		fStepOffWhy "${s}"
		if [[ -n "${step_off_why}" ]]; then steps_off+=("${s} (${step_off_why})"); else steps_on+=("${s}"); fi
	done
	steps_numbered=("${steps_on[@]}")
	if [[ "${CICD_IN_CONTAINER:-0}" == "1" && -n "${CICD_STEPS:-}" ]]; then IFS='|' read -r -a steps_numbered <<<"${CICD_STEPS}"; fi
}
fStepsCount(){ if ((${#steps_numbered[@]} == 1)); then echo "1 step"; else echo "${#steps_numbered[@]} steps"; fi; }
fStepsOffList(){
	local s label="Turned off ..........: "
	for s in "${steps_off[@]}"; do fEcho_Clean "${label}${s}"; label="                       "; done
}
fStepLine(){ fStepStamp; fEcho "${step_stamp}: Step ${step_num} of ${#steps_numbered[@]}; $1 ${step_open}"; }
fStep(){
	local i
	fInList "$1" "${steps_on[@]}" || return 1
	if ((${container_done:-0})) && fInList "$1" "${container_steps[@]}"; then return 1; fi
	fStepDone
	step_open="$1"; step_num="?"
	for i in "${!steps_numbered[@]}"; do if [[ "${steps_numbered[i]}" == "$1" ]]; then step_num=$((i + 1)); break; fi; done
	fEcho_Clean; fEcho_Clean "${_letterbox}"; fStepLine Starting
	fMachineUse; [[ "${stage_pause:-0}" == 0 ]] || sleep "${stage_pause}"
	return 0
}
fStepDone(){ if [[ -n "${step_open}" ]]; then fStepLine PASS; step_open=""; fEcho_Clean; fi; }
fStepExit(){
	[[ -n "${step_open}" ]] || return 0
	if [[ "${1:-0}" == 0 ]]; then fStepLine PASS; else fStepLine FAIL; fi
	step_open=""; fEcho_Clean
}
## The run's own trap replaces this one, and calls it first.
trap 'fStepExit "$?"' EXIT

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
## The container steps, in the pinned image, as this user. The repo
## is mounted at the same path, so paths in logs and caches still point at
## something, and so is a linked worktree's git dir. Sets container_done once
## they pass. When docker can't make the image or volume, they run on the host.
fRunContainer(){
	local engine="${docker_engine}" image k v m c
	docker_used=1
	local -a inner=(-y)
	if ((quiet)); then inner=(-q); fi
	inner+=(--no-profile --no-dogfood --no-publish "${inner_args[@]}")
	[[ -f "${root}/${CONTAINER_DIR}/Dockerfile" ]] || fDie "no container recipe at ${CONTAINER_DIR}/Dockerfile"
	image="$(fContainerImage)"
	if "${engine}" image inspect "${image}" >/dev/null 2>&1; then
		fEcho_Chat "image ${image}"
	else
		## A rebuild there would quietly take the slow road, without its cache.
		[[ "${CICD_IMAGE_PREBUILT:-0}" != "1" ]] || fDie "no image ${image}, and CICD_IMAGE_PREBUILT=1 says it was built before this run"
		fEcho "building ${image}"
		local -a buildArgs=()
		while IFS='=' read -r k v; do
			if [[ "${k}" =~ ^[A-Z_]+$ ]]; then buildArgs+=(--build-arg "${k}=${v}"); fi
		done <"${root}/cicd/tool-versions.env"
		## A missing context builds from an empty dir.
		local c dir empty=""
		for c in "${CONTAINER_CONTEXTS[@]}"; do
			dir="$(fContextDir "${c}")"
			if [[ -z "${dir}" ]]; then empty="${run_tmp}/empty-context"; mkdir -p "${empty}"; dir="${empty}"; fi
			buildArgs+=(--build-context "${c%%=*}=${dir}")
		done
		if ! "${engine}" build -t "${image}" "${docker_labels[@]}" "${buildArgs[@]}" "${root}/${CONTAINER_DIR}"; then
			fEcho "NOTE: could not build ${image}, so the container steps run on the host"
			return 0
		fi
	fi
	run_image="${image}"
	## One made before the labels is still used, but cleanup leaves it alone.
	if ! "${engine}" volume inspect "${CONTAINER_VOLUME}" >/dev/null 2>&1 \
		&& ! "${engine}" volume create "${docker_labels[@]}" "${CONTAINER_VOLUME}" >/dev/null; then
		fEcho "NOTE: could not make the volume ${CONTAINER_VOLUME}, so the container steps run on the host"
		return 0
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
	local -a gone=(--rm); if ((keep_temp)); then gone=(); fi
	## The steps are numbered across both runs, so the one inside gets the list.
	local steps; printf -v steps '%s|' "${steps_numbered[@]}"
	fEcho_Chat "inside: cicd/cicd.bash ${inner[*]}"
	## Ctrl+C reaches only the init process, and without the whole group the
	## step in progress would carry on. nice out here stops at the docker client,
	## so the container gets this run's job count as its CPU limit, and a low share.
	"${engine}" run "${gone[@]}" --init -e TINI_KILL_PROCESS_GROUP=1 --name "${APP_NAME}-${run_name}-stages" "${docker_labels[@]}" \
		--cpus "${CPU_CAP}" --cpu-shares 256 -e "CICD_JOBS_MAX=${CPU_CAP}" -e "CICD_STEPS=${steps%|}" --user "$(id -u):$(id -g)" "${mounts[@]}" -w "${root}" "${image}" \
		bash "${root}/cicd/cicd.bash" "${inner[@]}" || fDie "the run in the container failed; its output is above"
	container_done=1
}
## docker system df sizes are decimal, such as 1.404GB, and this sums them.
fDockerBytes(){
	awk '{ n = $1 + 0; u = $1; sub(/^[0-9.]+/, "", u); m = 1
		if (u == "kB") m = 1e3; else if (u == "MB") m = 1e6; else if (u == "GB") m = 1e9; else if (u == "TB") m = 1e12
		t += n * m } END { printf "%.0f\n", t }'
}
## Each image's unique size, by short ID and by name, and each volume's size,
## into docker_sizes. What can't be read counts as 0, so a busy daemon gives a
## low figure rather than a wrong one.
declare -A docker_sizes=()
fDockerSizes(){
	local kind name size ref
	docker_sizes=()
	while read -r kind name size ref; do
		size="$(fDockerBytes <<<"${size}")"
		if [[ "${kind}" == I ]]; then name="${name#sha256:}"; docker_sizes["${name:0:12}"]="${size}"; docker_sizes["${ref}"]="${size}"
		elif [[ "${kind}" == V ]]; then docker_sizes["volume ${name}"]="${size}"; fi
	done < <("${docker_engine}" system df -v --format '{{range .Images}}I {{.ID}} {{.UniqueSize}} {{.Repository}}:{{.Tag}}{{println}}{{end}}{{range .Volumes}}V {{.Name}} {{.Size}}{{println}}{{end}}' 2>/dev/null || true)
}
## du -k, since macOS du has no -b.
fDirBytes(){ local kb; kb="$(du -sk -- "$1" 2>/dev/null | cut -f1)"; echo "$(( ${kb:-0} * 1024 ))"; }
fBytesSay(){ awk -v b="${1:-0}" 'BEGIN { if (b >= 1e9) printf "%.1f GB", b / 1e9; else if (b >= 1e6) printf "%.1f MB", b / 1e6; else printf "%d KB", int((b + 999) / 1000) }'; }
cleanup_what=(); cleanup_bytes=0; cleanup_said=0
## What this run made in docker, pass or fail. Only what has this project's
## label, and never rmi -f or system prune, since other projects share docker.
## What it freed is the sum of what it removed, sized before. Docker's total
## before and after would count what other projects did meanwhile. Containers
## add nothing, since they ran with --rm and this only finds a leftover.
fDockerCleanup(){
	if ((! docker_used || docker_cleaned)); then return 0; fi
	docker_cleaned=1
	local engine="${docker_engine}" proj="dev.project=${APP_NAME}" id ref volProj volSize pruned i=0
	local -i nCont=0 nImg=0 freed=0
	local -a tags=() what=()
	fDockerSizes
	if ((keep_temp)); then
		while IFS= read -r id; do
			if [[ -n "${id}" ]]; then fEcho "kept container ${id} (--keep-temp)"; fi
		done < <("${engine}" ps -a --filter "label=${proj}" --filter "label=dev.run=${run_name}" --format '{{.Names}}' 2>/dev/null || true)
	else
		while IFS= read -r id; do
			if [[ -n "${id}" ]] && "${engine}" rm -f "${id}" >/dev/null 2>&1; then nCont+=1; fi
		done < <("${engine}" ps -aq --filter "label=${proj}" --filter "label=dev.run=${run_name}" 2>/dev/null || true)
	fi
	while IFS= read -r id; do
		if [[ -n "${id}" ]] && "${engine}" rmi "${id}" >/dev/null 2>&1; then nImg+=1; freed+=${docker_sizes["${id:0:12}"]:-0}; fi
	done < <("${engine}" image ls -q --filter dangling=true --filter "label=${proj}" 2>/dev/null || true)
	## Older tags go once a newer one passed. The one before it stays. Ordered
	## by when each was tagged here, since a reproducible build's created date
	## can be the base image's.
	if ((container_done)) && [[ -n "${run_image}" ]]; then
		mapfile -t tags < <("${engine}" image ls "${CONTAINER_IMAGE}" --filter "label=${proj}" --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true)
		mapfile -t tags < <(for ref in "${tags[@]}"; do
			if [[ -n "${ref}" ]]; then printf '%s %s\n' "$("${engine}" image inspect --format '{{.Metadata.LastTagTime.Unix}}' "${ref}" 2>/dev/null || echo 0)" "${ref}"; fi
		done | sort -rn | cut -d' ' -f2)
		for ref in "${tags[@]}"; do
			if [[ -z "${ref}" || "${ref}" == "${run_image}" ]]; then continue; fi
			i=$((i + 1)); if ((i == 1)); then continue; fi
			if "${engine}" rmi "${ref}" >/dev/null 2>&1; then nImg+=1; freed+=${docker_sizes["${ref}"]:-0}; else fEcho_Chat "kept ${ref} (in use)"; fi
		done
	fi
	if ((nCont)); then what+=("${nCont} container(s)"); fi
	if ((nImg)); then what+=("${nImg} image(s)"); fi
	## Emptied whole, by removing it. The next run makes it again.
	volProj="$("${engine}" volume inspect --format '{{index .Labels "dev.project"}}' "${CONTAINER_VOLUME}" 2>/dev/null || true)"
	if [[ "${volProj}" == "${APP_NAME}" ]]; then
		volSize="${docker_sizes["volume ${CONTAINER_VOLUME}"]:-0}"
		if (( volSize > CONTAINER_VOLUME_CAP )) && "${engine}" volume rm "${CONTAINER_VOLUME}" >/dev/null 2>&1; then what+=("volume ${CONTAINER_VOLUME}"); freed+=volSize; fi
	elif "${engine}" volume inspect "${CONTAINER_VOLUME}" >/dev/null 2>&1; then
		fEcho_Chat "NOTE: volume ${CONTAINER_VOLUME} has no ${proj} label, so its size isn't checked"
	fi
	## A week of every project's build cache stays, so the next build is warm.
	pruned="$("${engine}" builder prune -f --filter until=168h 2>&1 | grep -oE '[0-9.]+[kMGT]?B' | tail -1 || true)"
	what+=("build cache older than a week (${pruned:-0B})")
	freed+="$(fDockerBytes <<<"${pruned:-0B}")"
	cleanup_what+=("${what[@]}")
	cleanup_bytes=$((cleanup_bytes + freed))
}
## What the run's cleanup removed and about what it freed, in one line. The run
## folder goes right after, and is counted here so the line comes before the
## closing banner.
fCleanupReport(){
	local runBytes w line=""
	if ((cleanup_said)); then return 0; fi
	cleanup_said=1
	fDockerCleanup
	## The container goes with its run folder in it, and the host run says the rest.
	if [[ "${CICD_IN_CONTAINER:-0}" == "1" ]]; then return 0; fi
	if ((! keep_temp)) && [[ -n "${run_tmp}" && -d "${run_tmp}" ]]; then
		runBytes="$(fDirBytes "${run_tmp}")"
		cleanup_what+=("the run folder ($(fBytesSay "${runBytes}"))"); cleanup_bytes=$((cleanup_bytes + runBytes))
	fi
	if ((${#cleanup_what[@]})); then
		for w in "${cleanup_what[@]}"; do line+="${line:+, }${w}"; done
		fEcho "cleanup: removed ${line}; about $(fBytesSay "${cleanup_bytes}") freed"
	else
		fEcho "cleanup: nothing to remove"
	fi
	fEcho_Clean
}
## Stage 3. go vet is gating; golangci-lint, staticcheck, shellcheck,
## ruff and PSScriptAnalyzer run when installed (a failed probe skips that one with
## a warning). Any finding from one that runs aborts.
fLint(){
	local -a shellFiles=() psFiles=()
	local pyCount
	in_src "${VET_CMD[@]}"
	fEcho "OK: go vet clean"
	if ((${#LINT_CMD[@]})); then
		if in_src "${LINT_PROBE[@]}" >/dev/null 2>&1; then
			local -a lintJobs=(); if [[ -n "${LINT_JOBS_FLAG}" ]]; then lintJobs=("${LINT_JOBS_FLAG}=${CPU_CAP}"); fi
			in_src "${LINT_CMD[@]}" "${lintJobs[@]}"; fEcho "OK: golangci-lint clean"
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
	if [[ -n "${PSSA_CMD[*]:-}" ]]; then
		if "${PSSA_PROBE[@]}" >/dev/null 2>&1; then
			mapfile -t psFiles < <(git -C "${root}" ls-files -- '*.ps1' '*.psm1' '*.psd1')
			((${#psFiles[@]})) || fDie "PSScriptAnalyzer: no PowerShell files found to check"
			"${PSSA_CMD[@]}" "${psFiles[@]}"; fEcho "OK: PSScriptAnalyzer clean (${#psFiles[@]} files)"
		else
			fSkip "PSScriptAnalyzer skipped (needs pwsh, then Install-Module PSScriptAnalyzer)"
		fi
	fi
}
## Every test has its own ID, so a failure, a backlog item and a commit can all
## name the same one. Each prints with its ID.
fGoTests(){
	if ((${#TEST_ID_CMD[@]})); then in_src "$@" 2>&1 | (cd "${root}" && "${TEST_ID_CMD[@]}" report)
	else in_src "$@"; fi
}
fUnitTests(){
	if ((${#TEST_ID_CMD[@]})); then
		(cd "${root}" && "${TEST_ID_CMD[@]}" check) || fDie "a test has no ID, a bad one, or shares one"
	fi
	## goleak is in the unit tests, so --no-leakcheck builds them without it.
	if [[ "${do_leakcheck}" == 0 && -n "${GOLEAK_OFF_TAG}" ]]; then
		fGoTests env "GOFLAGS=${GOFLAGS} -tags=${GOLEAK_OFF_TAG}" "${UNIT_TEST_CMD[@]}" || fDie "unit tests failed"
		fEcho "OK: unit tests, without goleak (--no-leakcheck)"
	else
		fGoTests "${UNIT_TEST_CMD[@]}" || fDie "unit tests failed"
		fEcho "OK: unit tests"
	fi
}
## Stage 4d, the leak checks, each when its length says, per fLeakOn. The Go
## tests again under the race detector, then the soak test, which keeps its
## heap profiles, then CodeQL, which keeps its SARIF. Any CodeQL result fails.
fLeakCheck(){
	local name
	for name in race soak codeql; do
		if ! fLeakOn "${name}"; then fEcho_Chat "${name} leak check skipped ($(fLeakWhy "${name}"))"; fi
	done
	if ((${#RACE_TEST_CMD[@]})) && fLeakOn race && ((! run_unit)); then
		fEcho_Chat "race leak check skipped (no Go area named)"
	elif ((${#RACE_TEST_CMD[@]})) && fLeakOn race; then
		if in_src "${RACE_PROBE[@]}" >/dev/null 2>&1; then
			fGoTests "${heavy_env[@]}" "${RACE_TEST_CMD[@]}" || fDie "tests failed under the race detector"
			fEcho "OK: race detector clean"
		else
			fSkip "race detector skipped (it needs cgo and a C compiler)"
		fi
	fi
	if ((${#SOAK_CMD[@]})) && fLeakOn soak; then
		local soakDir="${root}/${SOAK_OUT_DIR}"
		mkdir -p "${soakDir}"
		fGoTests "${heavy_env[@]}" "CICD_SOAK_OUT=${soakDir}" "${SOAK_CMD[@]}" || fDie "soak test failed; its heap profiles are in ${SOAK_OUT_DIR}/"
		gfs_rotate "${soakDir}" heap-n pprof >/dev/null 2>&1 || true
		gfs_rotate "${soakDir}" heap-2n pprof >/dev/null 2>&1 || true
		fEcho "OK: soak test, heap profiles in ${SOAK_OUT_DIR}/"
	fi
	if ((${#CODEQL_CMD[@]})) && fLeakOn codeql; then
		if "${CODEQL_PROBE[@]}" >/dev/null 2>&1; then
			local codeqlDir="${root}/${CODEQL_OUT_DIR}"
			mkdir -p "${codeqlDir}"
			"${heavy_env[@]}" "${CODEQL_CMD[@]}" "${codeqlDir}/codeql_${stamp}.sarif" || fDie "CodeQL found something, or couldn't run; the SARIF is in ${CODEQL_OUT_DIR}/"
			gfs_rotate "${codeqlDir}" codeql sarif >/dev/null 2>&1 || true
			fEcho "OK: CodeQL clean, SARIF in ${CODEQL_OUT_DIR}/"
		else
			fSkip "CodeQL skipped (it's in the container image, and never installed here)"
		fi
	fi
}
## gitsby picks the account for the folder; plain git where it isn't installed.
fGit(){ if command -v gitsby >/dev/null 2>&1; then gitsby raw git "$@"; else git "$@"; fi; }
## Publish pulls after the tests, so a remote change would go out untested.
## Pulling first means the run tests what it publishes. Offline, or no
## upstream, just warns. Edits in the tree are stashed around the fast-forward.
fSyncRemote(){
	local upstream counts ahead behind before stashed=0
	if ! git -C "${root}" rev-parse --git-dir >/dev/null 2>&1; then
		fEcho "WARNING: not a git checkout, so no remote sync"
		return 0
	fi
	upstream="$(git -C "${root}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
	if [[ -z "${upstream}" ]]; then
		fEcho "WARNING: no upstream branch, so no remote sync"
		return 0
	fi
	if ! (cd "${root}" && fGit fetch --quiet) 2>/dev/null; then
		fEcho "WARNING: couldn't fetch for ${upstream} (offline?), so this builds what's here"
		return 0
	fi
	counts="$(git -C "${root}" rev-list --left-right --count 'HEAD...@{u}')"
	read -r ahead behind <<<"${counts}"
	if ((behind == 0)); then
		if ((ahead)); then fEcho_Chat "up to date with ${upstream}, ${ahead} ahead"; else fEcho_Chat "up to date with ${upstream}"; fi
		return 0
	fi
	((ahead == 0)) || fDie "this branch and ${upstream} have diverged (${ahead} ahead, ${behind} behind). Merge them, then run again."
	before="$(git -C "${root}" rev-parse HEAD)"
	if ! git -C "${root}" diff --quiet HEAD --; then
		git -C "${root}" stash push --quiet -m "cicd sync ${stamp}" || fDie "couldn't stash the edits in the tree before the fast-forward"
		stashed=1
	fi
	if ! git -C "${root}" merge --quiet --ff-only '@{u}'; then
		((stashed)) && git -C "${root}" stash pop --quiet
		fDie "couldn't fast-forward to ${upstream}"
	fi
	if ((stashed)); then
		git -C "${root}" stash pop --quiet || fDie "fast-forwarded, but the stashed edits didn't go back cleanly. They're still in 'git stash list'."
	fi
	fEcho "OK: fast-forwarded ${behind} commit(s) from ${upstream}"
	## Bash reads a script as it runs, so a pipeline that just changed starts over.
	if ! git -C "${root}" diff --quiet "${before}" HEAD -- cicd/; then
		fEcho "the pipeline itself changed, so starting over"
		exec bash "${here}/cicd.bash" "${orig_args[@]}" --no-sync
	fi
}
## The pre-push hook runs --merge-gate for a push to main. Hooks are per clone,
## so this adds a stub that calls the tracked script, never over one already there.
fInstallGateHook(){
	local hook
	hook="$(git -C "${root}" rev-parse --path-format=absolute --git-path hooks/pre-push 2>/dev/null || true)"
	if [[ -z "${hook}" || -e "${hook}" || -L "${hook}" || ! -f "${root}/cicd/utility/pre-push" ]]; then return 0; fi
	mkdir -p "$(dirname "${hook}")"
	printf '%s\n' '#!/usr/bin/env bash' '## Put here by cicd/cicd.bash. Runs the merge gate hook of whichever checkout is pushing.' \
		'hook="$(git rev-parse --show-toplevel)/cicd/utility/pre-push"' 'if [[ -x "${hook}" ]]; then exec "${hook}" "$@"; fi' >"${hook}"
	chmod +x "${hook}"
	fEcho "added the pre-push hook: ${hook}"
}
## The backlog runs and the merge gate check the format, and fix nothing.
fFormatCheck(){
	local unformatted
	unformatted="$(in_src "${FMT_CHECK_CMD[@]}")" || fDie "format check didn't run: ${FMT_CHECK_CMD[*]}"
	[[ -z "${unformatted}" ]] || fDie "needs formatting (${FMT_CMD[*]:-gofmt}): ${unformatted//$'\n'/ }"
	fEcho "OK: format"
}

## Areas, for --backlog-run-quick: format, lint, go for every Go package or
## one package by its dir's name, and the harness's own from TEST_AREAS_CMD.
## Kept as names, what each covers, and for a package its path.
area_names=(); area_what=(); declare -A area_pkg=()
## Only a quick run needs them all. --help and --list say what's missing.
fAreaMiss(){ [[ "${run_mode}" != --backlog-run-quick ]] || fDie "couldn't list $1"; fEcho "NOTE: couldn't list $1"; }
fAreas(){
	local pkg name what i j pkgs="" harness=""
	area_names=(format lint go); area_what=("the format check" "the lint step" "the Go unit tests, every package")
	if ((${#UNIT_AREAS_CMD[@]})); then pkgs="$(in_src "${UNIT_AREAS_CMD[@]}")" || fAreaMiss "the Go packages: ${UNIT_AREAS_CMD[*]}"; fi
	while IFS= read -r pkg; do
		[[ -n "${pkg}" && "${pkg}" != "." ]] || continue
		area_names+=("${pkg##*/}"); area_what+=("the Go unit tests in ${pkg}"); area_pkg[${pkg##*/}]="${pkg}"
	done <<<"${pkgs}"
	if ((${#TEST_AREAS_CMD[@]})); then harness="$("${TEST_AREAS_CMD[@]}")" || fAreaMiss "the harness areas: ${TEST_AREAS_CMD[*]}"; fi
	while IFS=$'\t' read -r name what; do
		if [[ -n "${name}" ]]; then area_names+=("${name}"); area_what+=("harness: ${what}"); fi
	done <<<"${harness}"
	## A second area of one name could never be picked.
	for i in "${!area_names[@]}"; do for ((j = i + 1; j < ${#area_names[@]}; j++)); do
		[[ "${area_names[i]}" != "${area_names[j]}" ]] || fDie "two areas are named ${area_names[i]}"
	done; done
}
## What runs, from the areas named, or QUICK_AREAS when none are. A step none
## of them asks for is off. go_all is the go area, which beats any one package.
run_unit=1; run_harness=1; harness_areas=""; unit_pkgs=()
fPickAreas(){
	local a go_all=0 fmt=0 lint=0 w hit=0
	local -a narrowed=()
	((${#quick_areas[@]})) || quick_areas=("${QUICK_AREAS[@]}")
	run_unit=0; run_harness=0
	for a in "${quick_areas[@]}"; do
		fInList "${a}" "${area_names[@]}" || { echo "unknown area: ${a} (--list shows them)" >&2; exit 2; }
		case "${a}" in
			format) fmt=1 ;;
			lint)   lint=1 ;;
			go)     run_unit=1; go_all=1 ;;
			*)      if [[ -n "${area_pkg[${a}]:-}" ]]; then run_unit=1; unit_pkgs+=("${area_pkg[${a}]}")
			        else run_harness=1; harness_areas+="${harness_areas:+ }${a}"; fi ;;
		esac
	done
	local why="not in the areas named"
	((fmt))  || { FMT_CHECK_CMD=(); fStepWhy "Format check" "${why}"; }
	((lint)) || { VET_CMD=(); fStepWhy Lint "${why}"; }
	((run_harness)) || fStepWhy "Native build" "no harness area named"
	((run_unit || run_harness)) || fStepWhy Tests "no test area named"
	if ((go_all || ! ${#unit_pkgs[@]})); then unit_pkgs=(); return 0; fi
	for w in "${UNIT_TEST_CMD[@]}"; do
		if [[ "${w}" == "./..." ]]; then narrowed+=("${unit_pkgs[@]}"); hit=1; else narrowed+=("${w}"); fi
	done
	((hit)) || fDie "UNIT_TEST_CMD has no ./... to narrow to ${unit_pkgs[*]}"
	UNIT_TEST_CMD=("${narrowed[@]}")
	## The race run is the same tests again, so it takes the same packages.
	narrowed=()
	for w in "${RACE_TEST_CMD[@]}"; do
		if [[ "${w}" == "./..." ]]; then narrowed+=("${unit_pkgs[@]}"); else narrowed+=("${w}"); fi
	done
	RACE_TEST_CMD=("${narrowed[@]}")
}
## The area table for --help and --list. A * marks what a --backlog-run-quick
## with these flags would run.
fAreaTable(){
	local i mark
	fEcho_Clean "Areas, for --backlog-run-quick (* runs$( [[ "${run_mode}" == --backlog-run-quick ]] || echo " when none are named")):"
	for i in "${!area_names[@]}"; do
		mark=" "; if fInList "${area_names[i]}" "${quick_areas[@]}"; then mark="*"; fi
		fEcho_Clean "$(printf '  %s %-18s %s' "${mark}" "${area_names[i]}" "${area_what[i]}")"
	done
}
trap 'rc=$?; printf "\n[ CICD ABORTED (exit %s) at line %s: %s ]\n" "$rc" "$LINENO" "$BASH_COMMAND" >&2; exit $rc' ERR

if ((image_tag)); then fContainerImage; echo; exit 0; fi

if ((want_help || list_only)) || [[ "${run_mode}" == --backlog-run-quick ]]; then
	fAreas
	if [[ "${run_mode}" == --backlog-run-quick ]]; then fPickAreas; inner_args+=(--backlog-run-quick "${quick_areas[@]}")
	else quick_areas=("${QUICK_AREAS[@]}"); fi
fi
if ((want_help)); then
	sed -n '/^##	- Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'
	fAreaTable; fEcho_Clean
	exit 0
fi

if [[ "${CICD_IN_CONTAINER:-0}" != "1" ]] && ((! list_only)); then
	if ((do_sync)); then fSyncRemote; fi
	if [[ -z "${run_mode}" ]]; then fInstallGateHook; fi
fi

## No docker, or none that answers, is no reason to fail a run.
docker_engine="${CICD_DOCKER:-docker}"; docker_used=0; docker_cleaned=0; run_image=""; container_done=0
if ((use_container)) && ! "${docker_engine}" version --format '{{.Server.Version}}' >/dev/null 2>&1; then
	fEcho "NOTE: no working ${docker_engine##*/} here, so every step runs on the host"
	use_container=0
fi

## --list: the steps in order, what's off and why, and the areas. Nothing runs.
if ((list_only)); then
	fStepPlan
	fSection "${APP_NAME} ${run_mode:-local CI/CD}: $(fStepsCount)$( ((use_container)) && echo ", the container ones in $(fContainerImage)")"
	if [[ -n "${mode_note}" ]]; then fEcho "NOTE: ${mode_note}"; fi
	for i in "${!steps_on[@]}"; do fEcho_Clean "$(printf '%3d  %s' "$((i + 1))" "${steps_on[i]}")"; done
	fStepsOffList
	fEcho_Clean; fAreaTable; fEcho_Clean
	exit 0
fi

## Preflight: show the plan with resolved paths, then confirm.
profile_dir="$(cd "${root}" && mkdir -p "${PROFILE_OUT_DIR}" 2>/dev/null; cd "${PROFILE_OUT_DIR}" 2>/dev/null && pwd || echo "${root}/${PROFILE_OUT_DIR}")"
fixed_dest=""; for d in "${DOGFOOD_FIXED_DESTS[@]:-}"; do [[ -d "$d" && -w "$d" ]] && { fixed_dest="$d"; break; }; done
## First existing, writable dir of a DOGFOOD_CROSS entry, or nothing.
fCrossDest(){
	local d; local -a parts; IFS='|' read -r -a parts <<<"$1"
	for d in "${parts[@]:2}"; do [[ -d "$d" && -w "$d" ]] && { echo "$d"; return 0; }; done
	return 0
}

## The first section: the plan, and which steps are off and why. A run inside
## the container that the host started leaves that to the host.
fStepPlan
if [[ "${CICD_IN_CONTAINER:-0}" != "1" || -z "${CICD_STEPS:-}" ]]; then
	fSection "${APP_NAME} local CI/CD${run_mode:+ (${run_mode})}: $(fStepsCount)"
	if [[ -n "${mode_note}" ]]; then fEcho "NOTE: ${mode_note}"; fi
	fEcho_Chat "Repo root ...........: ${root}"
	[[ -z "${run_mode}" ]] || \
	fEcho_Chat "Hands off ...........: no sync, dogfood, publish, install or prompt, and nothing tracked is rewritten"
	fEcho_Chat "Jobs ................: ${machine_line}"
	((use_container)) && \
	fEcho_Chat "Container ...........: $(fContainerImage) (the steps through tests, cross + package and the demo gif)"
	fEcho_Chat "Vendor pins .........: ${VENDOR_CHECK_CMD[*]:-(skipped)}"
	fEcho_Chat "Interop pins ........: ${INTEROP_CHECK_CMD[*]:-(skipped)}"
	fEcho_Chat "Format ..............: ${FMT_CMD[*]:-(skipped)}"
	fEcho_Chat "Native build ........: ${NATIVE_BUILD_CMD[*]} -> ${STAGED_BIN} (debug)"
	((${#RELEASE_BUILD_CMD[@]})) && \
	fEcho_Chat "                       ${RELEASE_BUILD_CMD[*]} -> ${STAGED_RELEASE_BIN} (release, dogfooded)"
	if ((${#VET_CMD[@]})); then
		fEcho_Chat "Lint ................: ${VET_CMD[*]}  (+ golangci-lint, staticcheck, shellcheck, ruff, PSScriptAnalyzer if installed)"
	else
		fEcho_Chat "Lint ................: (skipped)"
	fi
	tests_plan=""
	((run_unit)) && tests_plan="${UNIT_TEST_CMD[*]}"
	((run_harness)) && tests_plan+="${tests_plan:+ + }${TEST_CMD[*]}${harness_areas:+ (areas: ${harness_areas})}"
	fEcho_Chat "Tests ...............: ${tests_plan:-(skipped)}$( ((do_long)) && echo '  (long)')"
	if ((FUZZ_ENABLE)); then
		fEcho_Chat "Fuzz ................: ${FUZZ_TIME}/target, ${FUZZ_MINIMIZE_TIME}/find$( ((quick)) && echo " (quick: ${FUZZ_TIME_QUICK}, ${FUZZ_MINIMIZE_TIME_QUICK})")"
	else
		fEcho_Chat "Fuzz ................: (disabled)"
	fi
	if ((${#VULN_CMD[@]})); then fEcho_Chat "Security ............: ${VULN_CMD[*]}  (if installed)"; else fEcho_Chat "Security ............: (skipped)"; fi
	leak_plan=()
	if [[ -n "${GOLEAK_OFF_TAG}" && "${do_leakcheck}" != 0 ]]; then leak_plan+=("goleak in the unit tests (fast)"); fi
	if ((${#RACE_TEST_CMD[@]})) && fLeakOn race; then leak_plan+=("${RACE_TEST_CMD[*]} ($(fLeakWhy race))"); fi
	if ((${#SOAK_CMD[@]})) && fLeakOn soak; then leak_plan+=("${SOAK_CMD[*]} -> ${SOAK_OUT_DIR}/ ($(fLeakWhy soak))"); fi
	if ((${#CODEQL_CMD[@]})) && fLeakOn codeql; then leak_plan+=("${CODEQL_CMD[*]} -> ${CODEQL_OUT_DIR}/ ($(fLeakWhy codeql), if installed)"); fi
	if ((${#leak_plan[@]})); then
		fEcho_Chat "Leak checks .........: ${leak_plan[0]}"
		for leakLine in "${leak_plan[@]:1}"; do fEcho_Chat "                       ${leakLine}"; done
	else
		fEcho_Chat "Leak checks .........: (skipped)"
	fi
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
	for entry in "${DOGFOOD_CROSS[@]:-}"; do
		[[ -n "$entry" ]] || continue
		if ((! BUILD_CROSS)); then fEcho_Chat "Dogfood, cross ......: ${entry%%|*} (skipped, no cross + package step)"
		elif d="$(fCrossDest "$entry")"; [[ -n "$d" ]]; then fEcho_Chat "Dogfood, cross ......: ${entry%%|*} -> ${d}/$(cut -d'|' -f2 <<<"$entry")"
		else fEcho_Chat "Dogfood, cross ......: ${entry%%|*} <no dir exists - will skip>"; fi
	done
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
	fStepsOffList
	fEcho_Chat "Fail-fast: any error aborts before the next step."
fi

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

## Scratch for this run, gone however it ends. An abort used to leave the fuzz log.
## ${HOST_TEMP}/<project>/<time>_<NNN>, and what the steps write lands there too.
HOST_TEMP="$(realpath -- "${HOST_TEMP:-${TMPDIR:-/tmp}}")" || fDie "no temp folder: ${HOST_TEMP:-${TMPDIR:-/tmp}}"
projectName="${APP_NAME}"; run_parent="${HOST_TEMP}/${projectName}"; run_tmp=""
export HOST_TEMP projectName
mkdir -p "${run_parent}" || fDie "could not make ${run_parent}"
## A run folder older than 2 days whose run.pid names no live process is a
## leftover from a killed run. A folder with no run.pid wasn't made by a run.
## kill -0 rather than ps, which the cicd image doesn't have. Not permitted
## still means the process is there, just another user's.
fPidLive(){ local e; e="$(LC_ALL=C kill -0 "$1" 2>&1)" && return 0; [[ "${e}" == *"not permitted"* ]]; }
fRunTmpSweep(){
	local d pid bytes staleBytes=0
	local -i staleN=0
	while IFS= read -r d; do
		pid=""; if [[ -f "${d}/run.pid" ]]; then read -r pid <"${d}/run.pid" || true; else continue; fi
		if [[ "${pid}" =~ ^[0-9]+$ ]] && fPidLive "${pid}"; then continue; fi
		bytes="$(fDirBytes "${d}")"
		if fSafeRm "${d}"; then fEcho_Chat "removed stale run folder ${d}"; staleN+=1; staleBytes=$((staleBytes + bytes)); fi
	done < <(find "${run_parent}" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*-[0-9]*_[0-9][0-9][0-9]' -mmin +2880 2>/dev/null)
	if ((staleN)); then cleanup_what+=("${staleN} stale run folder(s) ($(fBytesSay "${staleBytes}"))"); cleanup_bytes=$((cleanup_bytes + staleBytes)); fi
}
fRunTmpSweep
for ((runN = 1; runN < 1000; runN++)); do
	printf -v run_tmp '%s/%s_%03d' "${run_parent}" "${stamp}" "${runN}"
	## Another run can take the empty project folder away at its end.
	if mkdir -p "${run_parent}" 2>/dev/null && mkdir "${run_tmp}" 2>/dev/null; then break; fi
	run_tmp=""
done
[[ -n "${run_tmp}" ]] || fDie "no free run folder under ${run_parent} for ${stamp}"
printf '%s\n' "$$" >"${run_tmp}/run.pid"
export TMPDIR="${run_tmp}" TEMP="${run_tmp}" TMP="${run_tmp}"
fRunTmpGone(){
	if [[ -z "${run_tmp}" || ! -d "${run_tmp}" ]]; then return 0; fi
	if ((keep_temp)); then fEcho "kept temp folder ${run_tmp} (--keep-temp)"; return 0; fi
	fSafeRm "${run_tmp}" || true
	rmdir "${run_parent}" 2>/dev/null || true
}
fRunCleanup(){ fStepExit "${1:-$?}"; fCleanupReport; fRunTmpGone; }
trap fRunCleanup EXIT
## docker catches Ctrl+C and exits on its own, which bash takes as handled, so
## without this a failed build would carry on here and a container run go on to
## the host steps.
trap '{ fEcho_Force "STOPPED: Ctrl+C"; } >&2; exit 130' INT
## Every container, image and volume the run makes says whose it is.
run_name="${run_tmp##*/}"
docker_labels=(--label "dev.project=${APP_NAME}" --label "dev.run=${run_name}")

## Tee the rest of the run (all steps) to a gitignored log so warnings from any
## step can be reviewed after the fact. Rotate the prior (closed) logs first.
if [[ -n "${LINT_LOG_DIR:-}" ]] && mkdir -p "${root}/${LINT_LOG_DIR}" 2>/dev/null; then
	gfs_rotate "${root}/${LINT_LOG_DIR}" run log >/dev/null 2>&1 || true
	exec > >(tee "${root}/${LINT_LOG_DIR}/run_${stamp}.log") 2>&1
	## Wait for tee to drain on exit, else the shell prompt returns mid-flush and
	## the last output lands after it (looks like the prompt "came back").
	tee_pid=$!
	## The rotation keeps a failed run's log no longer than any other, so a
	## failure is copied aside, the newest few kept.
	fRunLogEnd(){
		local rc=$? old kept
		fRunCleanup "${rc}"; exec 1>&- 2>&-; wait "${tee_pid}" 2>/dev/null
		((rc)) || return 0
		cp -- "${root}/${LINT_LOG_DIR}/run_${stamp}.log" "${root}/${LINT_LOG_DIR}/failed_${stamp}.log" 2>/dev/null || return 0
		## Names sort by stamp, so the oldest come first.
		mapfile -t kept < <(printf '%s\n' "${root}/${LINT_LOG_DIR}"/failed_*.log)
		((${#kept[@]} > 20)) || return 0
		for old in "${kept[@]:0:${#kept[@]}-20}"; do fSafeRmUnder "${root}/${LINT_LOG_DIR}" "${old}" >/dev/null 2>&1 || true; done
		return 0
	}
	trap fRunLogEnd EXIT
fi

if ((use_container)); then
	fSection "Container"
	fRunContainer
	## The run inside ends on a blank line, so the next step doesn't add one.
	if ((container_done)); then _wasLastEchoBlank=1
	else use_container=0; fStepPlan; fi
fi
if ((! container_done)); then
	if fStep Pins; then
		## Pinned tools: bring any go-installed tool that drifted from tool-versions.env
		## back in line (warn-only; probe-gated steps still skip anything missing).
		if ((${#PIN_TOOLS_CMD[@]})); then
			"${PIN_TOOLS_CMD[@]}"
		fi

		## Pinned vendor: a vendored drop-in that drifted from its upstream tag aborts
		## here, before anything is built against it. Warn-only when offline.
		if ((${#VENDOR_CHECK_CMD[@]})); then
			"${VENDOR_CHECK_CMD[@]}" || fDie "vendored source does not match its pin (see cicd/vendor-pins.env)"
		fi

		## Same idea for the interop suite's reference implementations, which are the
		## only thing proving the four big bases interoperate at all.
		if ((${#INTEROP_CHECK_CMD[@]})); then
			"${INTEROP_CHECK_CMD[@]}" || fDie "interop reference does not match its pin (see cicd/utility/interop/pins.env)"
		fi
		fStepDone
	fi

	## Stage 1: format, or in the backlog runs and the merge gate the check.
	if fStep Format; then
		"${FMT_CMD[@]}"
		fEcho "OK: formatted (${FMT_CMD[*]})"
		fStepDone
	fi
	if fStep "Format check"; then fFormatCheck; fStepDone; fi

	## Stage 2: native builds, staged aside from what the cross stage cleans. The
	## debug build (symbols) is what the tests and profiler run against; the
	## optimized build is smoke-checked here and dogfooded in stage 7.
	## A backlog quick run with no harness area has no use for it.
	if fStep "Native build"; then
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
		fStepDone
	fi

	## Stage 3: lint. go vet is gating; golangci-lint, staticcheck, shellcheck, ruff and
	## PSScriptAnalyzer run when installed (a failed probe skips that one with a
	## warning). Any finding from one that runs aborts. All output lands in the run log.
	if fStep Lint; then fLint; fStepDone; fi

	## Stage 4: tests. Unit (Go), integration harness (against the staged binary),
	## fuzz (one target per invocation), govulncheck security (module + deps), and
	## the leak checks.
	if fStep Tests; then
		## Every test has its own ID, so a failure, a backlog item and a commit can all
		## name the same one. Each prints with its ID.
		if ((run_unit)); then fUnitTests; fi
		## The harness runs its perf section and packaging rebuild check unless
		## --quick, and only the areas a backlog quick run names. None is all of them.
		if ((run_harness)); then
			do_perf=1; ((quick)) && do_perf=0
			CICDTEST_EXE="${root}/${STAGED_BIN}" CICDTEST_DO_LONGTEST="${do_long}" CICDTEST_DO_PERF="${do_perf}" CICDTEST_QUICK="${quick}" CICDTEST_AREAS="${harness_areas}" \
				"${TEST_CMD[@]}"
			fEcho "OK: integration harness"
		fi

		## 4b: fuzz each discovered target for a bounded time (shorter under --quick).
		if ((FUZZ_ENABLE)); then
			ft="${FUZZ_TIME}"; ((quick)) && ft="${FUZZ_TIME_QUICK}"
			fuzz_min="${FUZZ_MINIMIZE_TIME:-2s}"; ((quick)) && fuzz_min="${FUZZ_MINIMIZE_TIME_QUICK:-1s}"
			mapfile -t fuzz_targets < <(in_src go test -list '^Fuzz' "${GO_TEST_PKG:-.}" 2>/dev/null | grep -E '^Fuzz' || true)
			if ((${#fuzz_targets[@]})); then
				fuzz_log="${run_tmp}/fuzz.log"
				for t in "${fuzz_targets[@]}"; do
					fEcho_Chat "fuzz ${t} (${ft}) ..."
					## Only || keeps the ERR trap off a failed run; set +e does not.
					fuzz_rc=0
					in_src "${heavy_env[@]}" go test -run '^$' -fuzz "^${t}$" -fuzztime "${ft}" -fuzzminimizetime "${fuzz_min}" -parallel "${CPU_CAP_HEAVY}" "${GO_TEST_PKG:-.}" 2>&1 | tee "${fuzz_log}" || fuzz_rc=$?
					fuzz_id="-----"
					((${#TEST_ID_CMD[@]})) && fuzz_id="$(cd "${root}" && "${TEST_ID_CMD[@]}" lookup "${SRC_DIR}/${GO_TEST_PKG:-.}" "${t}" || true)"
					if ((fuzz_rc)); then
						## A bare "context deadline exceeded" with no crasher is the
						## -fuzztime boundary, not a find: the coordinator reads the
						## worker context before cancellation has reached it, so the
						## deadline gets reported as the run's error. Real finds name
						## the failing input file.
						if grep -q 'Failing input written to' "${fuzz_log}" \
						|| ! grep -q 'context deadline exceeded' "${fuzz_log}"; then
							printf 'FAIL %s %s (fuzz, %s)\n' "${fuzz_id}" "${t}" "${ft}"
							fDie "fuzz ${t} found a failure"
						fi
						fEcho "NOTE: fuzz ${t} reported the -fuzztime deadline; no failing input recorded"
					fi
					printf 'PASS %s %s (fuzz, %s)\n' "${fuzz_id}" "${t}" "${ft}"
				done
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

		## 4d: race detector, soak test and CodeQL.
		fLeakCheck
		fEcho "OK: tests passed"
		fStepDone
	fi
fi

## Stage 5: profiler (non-gating artifact; failures classified below).
run_profiler(){
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
		## the --check look, not the pipeline).
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
if fStep Profiler; then run_profiler; fStepDone; fi

## Stage 6: cross-compile + package (build sanity + release artifacts).
if fStep "Cross + package"; then
	"${RELEASE_CMD[@]}"
	count="$(find "${RELEASE_ARTIFACT_DIR}" -maxdepth 1 -type f \( -name '*.tgz' -o -name '*.zip' -o -name '*.deb' -o -name '*.rpm' -o -name '*.pkg' -o -name '*.exe' \) 2>/dev/null | wc -l)"
	((count > 0)) || fDie "cross + package produced no artifacts in ${RELEASE_ARTIFACT_DIR}/"
	fEcho "OK: release artifacts: ${count} in ${RELEASE_ARTIFACT_DIR}/"
	fStepDone
fi

## Builds and tests on the test boxes and VMs, which REMOTE_LOCAL names. A box
## that isn't there is a SKIP, and --no-remote turns the step off.
if fStep "Other hosts"; then
	remote_wrap=(); for w in "${REMOTE_WRAP[@]}"; do remote_wrap+=(--wrap "${w}"); done
	CICD_APP="${EXE_NAME}" CICD_DIST="${RELEASE_ARTIFACT_DIR}" CICD_REF_BIN="${STAGED_RELEASE_BIN:-${STAGED_BIN}}" \
		CICD_CROSS_RAN="${BUILD_CROSS}" CICD_RUN_TMP="${run_tmp}" "${REMOTE_CMD[@]}" "${remote_wrap[@]}" "${REMOTE_HOSTS[@]}"
	fStepDone
fi

## Stage 7: dogfood (fixed name), screenshots and the demo gif. Dogfood the optimized
## release build (the real thing), falling back to the debug build if it wasn't made.
## sudo -n never prompts, so it can't hang a run, and an unattended run
## doesn't try it at all.
fDogfoodCopy(){
	local from="$1" to="$2" how=""
	if cp -f "${from}" "${to}"; then :
	elif [[ "${to}" == "${HOME}/"* ]] || ((assume_yes)); then fDie "could not install ${to}"
	elif sudo -n cp -f "${from}" "${to}"; then how=" (sudo)"
	else fDie "could not install ${to}, even with sudo -n"
	fi
	fEcho "OK: installed${how} -> ${to}"
}
if fStep Dogfood; then
	dogfood_bin="${STAGED_BIN}"
	[[ -n "${STAGED_RELEASE_BIN:-}" && -f "${STAGED_RELEASE_BIN}" ]] && dogfood_bin="${STAGED_RELEASE_BIN}"
	if ((${#DOGFOOD_FIXED_DESTS[@]})); then
		if [[ -n "$fixed_dest" ]]; then
			fDogfoodCopy "${dogfood_bin}" "${fixed_dest}/${EXE_NAME}"
		else
			fEcho "WARNING: no dogfood dest exists (${DOGFOOD_FIXED_DESTS[*]}); skipping"
		fi
	else
		fEcho_Chat "no fixed-name dogfood dir"
	fi
	## The cross builds only count when cross + package made them this run. An old dist/ copy
	## would be dogfooding something nobody tested.
	for entry in "${DOGFOOD_CROSS[@]:-}"; do
		[[ -n "$entry" ]] || continue
		artifact="${entry%%|*}"
		if ((! BUILD_CROSS)); then fEcho_Chat "dogfood ${artifact}: skipped, the cross + package step didn't run"; continue; fi
		[[ -f "${RELEASE_ARTIFACT_DIR}/${artifact}" ]] || fDie "dogfood: cross + package made no ${RELEASE_ARTIFACT_DIR}/${artifact}"
		d="$(fCrossDest "$entry")"
		if [[ -z "$d" ]]; then fEcho "WARNING: no dogfood dir exists for ${artifact}; skipping"; continue; fi
		fDogfoodCopy "${RELEASE_ARTIFACT_DIR}/${artifact}" "${d}/$(cut -d'|' -f2 <<<"$entry")"
	done
	fStepDone
fi

## Screenshots: off by default (retired); a failure is a warning, never a stop.
if fStep Screenshots; then
	screenshot_util="${root}/${SCREENSHOT_CMD[0]}"
	if [[ -f "${screenshot_util}" ]]; then
		if bash "${screenshot_util}" "${root}" "${root}/${STAGED_BIN}"; then fEcho "OK: screenshots regenerated"
		else fEcho "WARNING: screenshot generation failed (continuing)"; fi
	else
		fEcho_Clean "no screenshot utility at ${screenshot_util}; skipping"
	fi
	fStepDone
fi

## Demo gif: types the scenario into a fake terminal, runs each command against the
## tested binary, renders the animated loop. A failure is a warning, never a stop.
## The backlog runs and the merge gate make it in the run's temp dir, say
## whether it changed, and leave the repo's copy and the archive alone.
if fStep "Demo gif"; then
	demogif_out="${root}/${DEMOGIF_OUT}"
	demogif_tmp="${demogif_out}.new"
	if [[ -n "${run_mode}" ]]; then demogif_tmp="${run_tmp}/demo.gif"; fi
	if (cd "${root}" && python3 "${DEMOGIF_CMD[@]}" --out "${demogif_tmp}" --bin "${root}/${STAGED_BIN}"); then
		if [[ -f "${demogif_out}" ]] && cmp -s "${demogif_tmp}" "${demogif_out}"; then
			rm -f "${demogif_tmp}"
			fEcho "OK: demo gif unchanged"
		elif [[ -n "${run_mode}" ]]; then
			fEcho "NOTE: the demo gif came out different, and ${DEMOGIF_OUT} is left as it was (${run_mode})"
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
	fStepDone
fi

## Stage 8: backup + publish.
if fStep "Backup + publish"; then
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
	## The pre-push hook would run the gate again on what this run just tested.
	export CICD_GATE_PASSED=1
	if [[ -n "$publish_msg" ]]; then
		## Hands-off: the publisher fills the empty commit message from -m so `git
		## commit` won't open an editor.
		fEcho_Chat "hands-off publish (commit message: \"${publish_msg}\")"
		"${GIT_PUBLISH[@]}" "${pub_flags[@]}" -m "${publish_msg}"
	else
		"${GIT_PUBLISH[@]}" "${pub_flags[@]}"
	fi
	fEcho "OK: published"
	fStepDone
fi

fCleanupReport
## Inside the container the host run has more steps to go, and says when it's done.
if [[ "${CICD_IN_CONTAINER:-0}" != "1" ]]; then fSection "${APP_NAME} CI/CD: done."
elif [[ -z "${CICD_STEPS:-}" ]]; then fSection "${APP_NAME} CI/CD: container part done."; fi
fEcho_Clean


##	History:
##		- 2026-07-03 JC: Created. Generic engine + config.bash, adapted from the sister project; Go build staging, exhaustive tests, quiet publish.
##		- 2026-07-09 JC: silkterm-style output (fEcho/fSection letterbox); -q/-m/--quick flags; lint, fuzz, vuln, profiler stages; tee'd run log; message prompt replaces y/n.
##		- 2026-07-29 JC: Vendored drop-in files are verified against their pinned upstream release before the build.
##		- 2026-10-04 JC: shellcheck and ruff in the lint stage.
##		- 2026-10-10 JC: --container runs the tool-heavy stages in a pinned image, where no check may skip.
##		- 2026-10-10 JC: Container runs can be the default (CONTAINER_DEFAULT), with --host to opt out. Build contexts from outside the repo.
##		- 2026-10-19 JC: --image-tag and CICD_IMAGE_PREBUILT, for hosted CI.
##		- 2026-10-14 JC: --gate and its pre-push hook; fetch and fast-forward before building, --no-sync to skip.
##		- 2026-10-14 JC: Dogfood the cross builds too (DOGFOOD_CROSS), with personal dirs read from DOGFOOD_LOCAL.
##		- 2026-10-19 JC: A plain run has the long tests. --quick still cross-compiles, and skips the checks that reach another host.
##		- 2026-10-19 JC: --leakcheck: the Go tests under the race detector, and a soak test. A plain run has them.
##		- 2026-10-19 JC: CodeQL in the leak checks.
##		- 2026-10-19 JC: --no-leakcheck.
##		- 2026-10-19 JC: Per-run temp dir, removed on exit.
##		- 2026-10-19 JC: PSScriptAnalyzer in the lint stage.
##		- 2026-10-25 JC: No docker, or an image that won't build, runs on the host. --no-container, --keep-temp.
##		- 2026-10-25 JC: Labels on what the run makes in docker, and cleanup of it at the end.
##		- 2026-10-25 JC: nice and ionice for the run, half the CPUs or a quarter when busy or heavy, rechecked each step. --cpus and --cpu-shares on the container.
##		- 2026-10-25 JC: Step lines with the time and "Step N of M", PASS or FAIL, and the steps turned off listed first. The pin checks are a step.
##		- 2026-10-25 JC: Fuzz lines read PASS or FAIL, then the ID and target.
##		- 2026-10-25 JC: --backlog-run-quick with areas, --backlog-run-full and --merge-gate, which never sync, dogfood, publish or rewrite a tracked file. --gate and --ci are other names for them. --list, --no-remote, --slow.
##		- 2026-10-25 JC: The Other hosts step runs the boxes REMOTE_LOCAL names.
##		- 2026-10-25 JC: The run folder is ${HOST_TEMP}/<project>/<time>_<NNN>, with TMPDIR, TEMP and TMP pointing at it, and --keep-temp keeps it. Stale ones of ours go at the start. Removal goes through safe-rm.bash.
##		- 2026-10-25 JC: Leak checks run by length, fast, slow or hours, from LEAK_LENGTH. --no-leakcheck drops goleak too.
##		- 2026-10-25 JC: One cleanup line at the end for docker, the stale run folders and the run folder.
