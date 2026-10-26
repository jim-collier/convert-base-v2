#!/usr/bin/env bash

##	Purpose: The pipeline's only way to remove a folder tree. Sourced by cicd.bash and its helpers.
##		- fSafeRm PATH: one absolute path somewhere under a folder named tmp, never that folder
##		  itself, or under ${HOST_TEMP}/${projectName}, since the macOS and Windows temp folders
##		  aren't named tmp.
##		- fSafeRmUnder PARENT PATH: for anything else, a path strictly under the one PARENT named.
##		- Both refuse an empty path, .., //, a newline, a link, a path through a link, or one that
##		  isn't there, and stay on one filesystem where rm can.
##		- Callers resolve HOST_TEMP or PARENT with realpath first, since macOS's temp folder sits
##		  behind the /var link.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


## BSD and macOS rm have no --one-file-system.
__safeRmOneFs=()
if rm --one-file-system --version >/dev/null 2>&1; then __safeRmOneFs=(--one-file-system); fi

__fSafeRmTail(){
	local p="${1}" real=''
	if [[ -L "${p}" ]]; then printf 'safe-rm: refused, a link: %s\n' "${p}" >&2; return 1; fi
	if [[ ! -e "${p}" ]]; then printf 'safe-rm: refused, not there: %s\n' "${p}" >&2; return 1; fi
	real="$(realpath -- "${p}" 2>/dev/null)" || { printf 'safe-rm: refused, not there: %s\n' "${p}" >&2; return 1; }
	if [[ "${real}" != "${p}" ]]; then printf 'safe-rm: refused, goes through a link: %s\n' "${p}" >&2; return 1; fi
	rm -rf "${__safeRmOneFs[@]}" -- "${p}"
}

__fSafeRmBad(){ [[ -z "${1}" || "${1}" != /* || "${1}" == *..* || "${1}" == *//* || "${1}" == *$'\n'* ]]; }

fSafeRm(){
	local p="${1:-}" own=''
	if [[ -n "${HOST_TEMP:-}" && -n "${projectName:-}" ]]; then own="${HOST_TEMP%/}/${projectName}"; fi
	if [[ "${#}" -ne 1 ]] || __fSafeRmBad "${p}"; then
		printf 'safe-rm: refused, bad path: "%s"\n' "${p}" >&2; return 1
	fi
	p="${p%/}"
	if ! [[ "${p}" =~ ^/(.+/)?tmp/[^/]+(/[^/]+)*$ || ( -n "${own}" && "${p}" == "${own}"/?* ) ]]; then
		printf 'safe-rm: refused, not under a tmp folder: %s\n' "${p}" >&2; return 1
	fi
	__fSafeRmTail "${p}"
}

fSafeRmUnder(){
	local parent="${1:-}" p="${2:-}"
	if [[ "${#}" -ne 2 ]] || __fSafeRmBad "${parent}" || __fSafeRmBad "${p}" || [[ "${parent}" == "/" ]]; then
		printf 'safe-rm: refused, bad path: "%s" under "%s"\n' "${p}" "${parent}" >&2; return 1
	fi
	parent="${parent%/}"; p="${p%/}"
	if [[ "${p}" != "${parent}"/?* ]]; then
		printf 'safe-rm: refused, not under %s: %s\n' "${parent}" "${p}" >&2; return 1
	fi
	__fSafeRmTail "${p}"
}


##	History:
##		- 2026-10-25 JC: Created.
