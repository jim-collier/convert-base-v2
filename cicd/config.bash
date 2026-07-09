#!/usr/bin/env bash

#  shellcheck disable=2001  ## 'See if you can use ${variable//search/replace} instead.' Complains about good uses of sed.
#  shellcheck disable=2016  ## 'Expressions don't expand in single quotes, use double quotes for that.' I know, and I often want an explicit '$'.
#  shellcheck disable=2034  ## 'variable appears unused.' Complains about valid use of variable indirection (e.g. later use of local -n var=$1)
#  shellcheck disable=2046  ## 'Quote to prevent word-splitting.' (OK for integers.)
#  shellcheck disable=2086  ## 'Double quote to prevent globbing and word splitting.' (OK for integers.)
#  shellcheck disable=2119  ## 'Use foo "$@" if function's $1 should mean script's $1.' Confusing and inapplicable.
#  shellcheck disable=2120  ## 'Foo references arguments, but none are ever passed.' Valid function argument overloading.
#  shellcheck disable=2128  ## 'Expanding an array without an index only gives the element in the index 0.' False hits on associative arrays.
#  shellcheck disable=2155  ## 'Declare and assign separately to avoid masking return values.' Cumbersome and unnecessary. For integers it's sometimes required to even come into existence for counters.
#  shellcheck disable=2162  ## 'read without -r will mangle backslashes.'
#  shellcheck disable=2178  ## 'Variable was used as an array but is now assigned a string.' False hits on associative arrays with e.g. 'local -n assocArray=$1'.
#  shellcheck disable=2181  ## 'Check exit code directly, not indirectly with $?.'
#  shellcheck disable=2317  ## 'Can't reach.' (I.e. an 'exit' is used for debugging - and makes an unusable visual mess.)
## shellcheck disable=2002  ## 'Useless use of cat.'
## shellcheck disable=2004  ## '$/${} is unnecessary on arithmetic variables.' Inappropriate complaining?
## shellcheck disable=2053  ## 'Quote the right-hand sid of = in [[ ]] to prevent glob matching.' Disable for Yoda Notation.
## shellcheck disable=2143  ## 'Use grep -q instead of echo | grep'

##	Purpose:
##		- Project-specific CI/CD settings for convert-base-v2.
##		- The engine (cicd.bash) stays generic; everything project-specific lives here.
##		- To reuse the pipeline elsewhere, copy the cicd/ directory and edit this file.
##		- All command arrays run from the repo root. Go tool stages (vet, lint, unit
##		  tests, fuzz, vuln, profile) run inside SRC_DIR - the engine does the cd.
##		  The engine prepends ~/.go/bin to PATH so `go install`ed tools win.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


## Only allow running 'sourced'.
declare -i isSourced_t6wqf=0; [[ "${BASH_SOURCE[0]}" == "${0}" ]] || isSourced_t6wqf=1
((isSourced_t6wqf)) || { echo -e "\nError in $(basename "${BASH_SOURCE[0]}"): This script is meant to be 'sourced' from within another script.\n"; exit 1; }


## Identity
APP_NAME="convert-base-v2"
EXE_NAME="convert-base-v2"

## Where the Go sources and Makefile live, relative to the repo root.
SRC_DIR="source"

## Stage 1: format the source in place before anything is compiled. Empty it
## (FMT_CMD=()) to skip. gofmt is a no-op on already-clean source. Never a Bash
## formatter here - bash is hand-formatted on purpose.
FMT_CMD=(make -C "${SRC_DIR}" fmt)

## Stage 2: native build. Produces NATIVE_BUILD_OUT, which the engine then copies
## to STAGED_BIN. STAGED_BIN lives outside what 'make release' cleans, so the tested
## binary survives the cross-compile stage and is the one that gets dogfooded.
NATIVE_BUILD_CMD=(make -C "${SRC_DIR}" local)
NATIVE_BUILD_OUT="${SRC_DIR}/${EXE_NAME}"
STAGED_BIN="${SRC_DIR}/bin/${EXE_NAME}"

## Stage 3: lint the first-party Go. Each is run inside SRC_DIR. VET is always
## available (part of the toolchain) and gating. golangci-lint and staticcheck are
## optional: a failed PROBE skips that one with a warning instead of aborting, so
## the pipeline still runs on a bare machine. Install them with:
##   go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest
##   go install honnef.co/go/tools/cmd/staticcheck@latest
VET_CMD=(go vet ./...)
LINT_PROBE=(golangci-lint version)
LINT_CMD=(golangci-lint run --concurrency="${CPU_CAP:-1}" ./...)
STATICCHECK_PROBE=(staticcheck -version)
STATICCHECK_CMD=(staticcheck ./...)

## Stage 4a: unit tests (Go, run inside SRC_DIR) plus the integration harness
## (cicd/test.bash, run from root against the staged binary via CICDTEST_EXE).
UNIT_TEST_CMD=(go test ./...)
TEST_CMD=(cicd/test.bash)

## Stage 4b: fuzz. Go runs one -fuzz target per invocation, so the engine discovers
## the Fuzz* funcs and runs each for FUZZ_TIME (FUZZ_TIME_QUICK under --quick). Set
## FUZZ_ENABLE=0 to skip. Corpus finds are written under source/testdata (committed).
FUZZ_ENABLE=1
FUZZ_TIME="20s"
FUZZ_TIME_QUICK="4s"

## Stage 4c: security. govulncheck scans this module AND its dependencies (library
## code) against the Go vulnerability database. Optional (PROBE-gated). Install with:
##   go install golang.org/x/vuln/cmd/govulncheck@latest
VULN_PROBE=(govulncheck -version)
VULN_CMD=(govulncheck ./...)

## Stage 5: profiler (non-gating artifact, not a pass/fail test). Runs the
## BenchmarkProfile workload (big-int math/big path + streaming codec path) under
## the Go CPU sampler for PROFILE_TIME, then pprof2flame.py folds cpu.prof into an
## inferno-style flamegraph SVG (no external flamegraph tool needed). Skipped by
## --quick / --no-profile. See cicd.bash for the skip-vs-abort failure policy.
PROFILE_ENABLE=1
PROFILE_BENCH="BenchmarkProfile"
PROFILE_TIME="8s"
PROFILE_OUT_DIR="cicd/artifacts/profiling"  # relative to repo root; created if missing (gitignored)
PROFILE_STRICT=0                            # 1 = any profiler failure aborts the pipeline

## Full run output is tee'd here (gitignored) so warnings from any stage (vet,
## lint, staticcheck, vuln) can be reviewed after the fact with lint-report.bash.
## Kept rotated like the flamegraphs.
LINT_LOG_DIR="cicd/artifacts/lint"          # relative to repo root; created if missing (gitignored)

## Both artifact dirs are pruned by gfs_rotate (cicd/utility/include/gfs-rotate.bash):
## keeps ~30 - first + newest-per-hour/day/week/month/year + last 10. Tune with the
## GFS_KEEP_* env vars (GFS_KEEP_FREQUENT, GFS_KEEP_DAILY, ...) if needed.

## Stage 6: cross-compile every shipping platform into source/dist as tgz/zip.
## This doubles as a build-sanity gate. Set BUILD_CROSS=0 (or --no-cross/--quick) to skip.
BUILD_CROSS=1
RELEASE_CMD=(make -C "${SRC_DIR}" release)
RELEASE_ARTIFACT_DIR="${SRC_DIR}/dist"

## Stage 7: dogfood. Overwrite EXE_NAME in the first existing dir below (the stable
## path you launch by hand). Empty the list to skip. No rotating copy for this project.
DOGFOOD_FIXED_DESTS=(
	"${HOME}/synced/0-0/common/exec/util/linux/bin"
	"/usr/local/sbin"
)

## Stage 7 (after dogfood): screenshots. The README no longer shows them, so this is
## off by default. The generator (utility/gen-screenshots.bash) is kept, so flip this
## to 1 to regenerate on demand. Called with the repo root and the tested binary; a
## failure is a warning, not a stop. Also skipped by --quick.
DO_SCREENSHOTS=0
SCREENSHOT_CMD=(utility/gen-screenshots.bash)

## Stage 8: backup + publish to git (runs from repo root). The engine always passes
## --quiet (it already gave the message prompt) and, when it has one, -m MESSAGE.
GIT_PUBLISH=(cicd/utility/n8git_backup-and-publish)

## Set a non-empty commit message to publish hands-off (suppresses the prompt and
## supplies the message so `git commit` won't open an editor). Left empty, publish
## prompts once at preflight unless -m/--message or -q is given (see cicd.bash).
PUBLISH_AUTO_MESSAGE=""


##	History:
##		- 2026-07-03 JC: Created (converted from the monolithic cicd.bash to the generic engine + config split).
##		- 2026-07-09 JC: Added lint (vet/golangci/staticcheck), fuzz, vuln, and profiler stages; artifact dirs; quiet/message publish.
