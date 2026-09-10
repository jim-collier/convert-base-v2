#!/usr/bin/env bash

##	Purpose:
##		- Verify every vendored drop-in file listed in cicd/vendor-pins.env still
##		  matches the upstream release it is pinned to, and say so when upstream
##		  has moved on.
##		- Hard-fails (exit 1) when a local copy differs from its pinned tag. That
##		  means either the copy was edited here or the pin names the wrong tag;
##		  both are wrong, and neither shows up in lint (vendored paths are
##		  excluded on purpose) or in any output the program produces.
##		- Warn-only when the fetch cannot happen (offline, rate-limited), and
##		  warn-only when a newer release exists. A newer upstream is news, not a
##		  failure - refreshing the copy is a deliberate act.
##		- Runnable by hand: cicd/utility/check-vendor.bash
##	History: At bottom.

##	Copyright (c) 2026 Bubbles
##	Licensed under GNU GPL v2 <https://www.gnu.org/licenses/gpl-2.0.html>. No warranty.
##	SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
[[ "${1:-}" == "--repo" && -n "${2:-}" ]] && root="$2"

# shellcheck disable=1091  ## 'Not following.' The pin file is data, and it sits next to this script.
source "${here}/../vendor-pins.env"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

declare -i failed=0 checked=0 unchecked=0

## Private repos and Actions runners need the token; a bare local run does not.
curlAuth=()
[[ -n "${GITHUB_TOKEN:-}" ]] && curlAuth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

## Newest published release, or empty when the query fails. Only used for the
## "upstream moved" notice, so a miss here is never fatal.
fLatestTag(){
	local repo="$1"
	curl -sSfL --max-time 15 "${curlAuth[@]}" \
		"https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
		| sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

for pin in "${VENDOR_PINS[@]}"; do
	IFS='|' read -r localPath repo tag upstreamPath <<< "${pin}"
	label="${localPath##*/} <- ${repo} ${tag}"

	if [[ ! -f "${root}/${localPath}" ]]; then
		echo "[ vendor: FAILED: ${localPath} is pinned but missing ]" >&2
		failed=1
		continue
	fi

	## Keep a 404 (bad pin) separate from an unreachable network. Without the
	## status a typo'd tag would read as "offline" and quietly verify nothing.
	fetched="${tmp}/$(echo "${localPath}" | tr '/' '_')"
	status="$(curl -sSL --max-time 30 "${curlAuth[@]}" -o "${fetched}" -w '%{http_code}' \
		"https://raw.githubusercontent.com/${repo}/${tag}/${upstreamPath}" 2>/dev/null)" || true
	case "${status:-000}" in
		200) ;;
		404)
			echo "[ vendor: FAILED: ${repo} has no ${upstreamPath} at ${tag} - fix the pin in cicd/vendor-pins.env ]" >&2
			failed=1
			continue ;;
		*)
			echo "[ vendor: WARNING: could not reach ${repo} (http ${status}) - ${localPath} unverified ]"
			unchecked+=1
			continue ;;
	esac

	if ! cmp -s "${fetched}" "${root}/${localPath}"; then
		echo "[ vendor: FAILED: ${localPath} does not match ${repo} ${tag}:${upstreamPath} ]" >&2
		echo "[ vendor:   either the local copy was edited (it must stay verbatim) or the pin in ]" >&2
		echo "[ vendor:   cicd/vendor-pins.env names the wrong tag. Diff: ]" >&2
		diff -u "${fetched}" "${root}/${localPath}" | head -40 >&2 || true
		failed=1
		continue
	fi

	checked+=1
	latest="$(fLatestTag "${repo}")"
	if [[ -n "${latest}" && "${latest}" != "${tag}" ]]; then
		echo "[ vendor: ${label} verbatim - upstream is now ${latest}, worth a look ]"
	else
		echo "[ vendor: ${label} verbatim ]"
	fi
done

((failed)) && exit 1
((unchecked)) || echo "[ vendor ok: ${checked} pinned file(s) verbatim ]"
exit 0


##	History:
##		- 2026-07-29: Created. Drift guard for the vendored SHCL binding, once SHCL reached v1.0.0.
