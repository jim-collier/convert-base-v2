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
##		- All command arrays run from the repo root (the cicd/.. directory). This is a Go
##		  project, so the build targets live under source/ and are reached with 'make -C source'.
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
## (FMT_CMD=()) to skip. gofmt is a no-op on already-clean source.
FMT_CMD=(make -C "${SRC_DIR}" fmt)

## Stage 2: native build. Produces NATIVE_BUILD_OUT, which the engine then copies
## to STAGED_BIN. STAGED_BIN lives outside what 'make release' cleans, so the tested
## binary survives the cross-compile stage and is the one that gets dogfooded.
NATIVE_BUILD_CMD=(make -C "${SRC_DIR}" local)
NATIVE_BUILD_OUT="${SRC_DIR}/${EXE_NAME}"
STAGED_BIN="${SRC_DIR}/bin/${EXE_NAME}"

## Stage 3: tests. The harness takes the binary under test via CICDTEST_EXE (the
## engine sets it to the absolute STAGED_BIN). Set CICDTEST_DO_LONGTEST=1 for the
## exhaustive run.
TEST_CMD=(cicd/test.bash)

## Stage 4: cross-compile every shipping platform into source/dist as tgz/zip.
## This doubles as a build-sanity gate. Set BUILD_CROSS=0 (or --no-cross/--quick) to skip.
BUILD_CROSS=1
RELEASE_CMD=(make -C "${SRC_DIR}" release)
RELEASE_ARTIFACT_DIR="${SRC_DIR}/dist"

## Stage 5: dogfood. Overwrite EXE_NAME in the first existing dir below (the stable
## path you launch by hand). Empty the list to skip. No rotating copy for this project.
DOGFOOD_FIXED_DESTS=(
	"${HOME}/synced/0-0/common/exec/util/linux/bin"
	"/usr/local/sbin"
)

## Stage 6: backup + publish to git (runs from repo root). --quiet keeps it
## non-interactive so the whole pipeline can finish unattended.
GIT_PUBLISH=(cicd/utility/n8git_backup-and-publish --quiet)


##	History:
##		- 2026-07-03 JC: Created (converted from the monolithic cicd.bash to the generic engine + config split).
