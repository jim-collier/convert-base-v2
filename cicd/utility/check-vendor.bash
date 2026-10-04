#!/usr/bin/env bash

##	Purpose:
##		- Verify every vendored drop-in file listed in cicd/vendor-pins.env still
##		  matches the upstream release or commit it is pinned to, and say so when
##		  upstream has moved on.
##		- Hard-fails (exit 1) when a local copy differs from its pinned ref. That
##		  means either the copy was edited here or the pin names the wrong ref;
##		  both are wrong, and neither shows up in lint (vendored paths are
##		  excluded on purpose) or in any output the program produces.
##		- Warn-only when the fetch cannot happen (offline, rate-limited), and
##		  warn-only when a newer release exists. A newer upstream is news, not a
##		  failure - refreshing the copy is a deliberate act.
##		- A pin on a commit SHA rather than a tag is checked just as strictly, and
##		  prints a pre-release notice on every run, so it is not forgotten once a
##		  release exists.
##		- Runnable by hand: cicd/utility/check-vendor.bash
##	History: At bottom.

##	Copyright (c) 2026 Bubbles
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

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
## "upstream moved" notices, so a miss here is never fatal. A SHA pin is waiting
## on a release that may come out as a prerelease first, and releases/latest
## skips those, so it asks the full list instead.
fLatestTag(){
	local repo="$1" endpoint="releases/latest"
	[[ "${2:-}" == "any" ]] && endpoint="releases?per_page=1"
	curl -sSfL --max-time 15 "${curlAuth[@]}" \
		"https://api.github.com/repos/${repo}/${endpoint}" 2>/dev/null \
		| sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true
}

for pin in "${VENDOR_PINS[@]}"; do
	IFS='|' read -r localPath repo ref upstreamPath <<< "${pin}"
	## Only a full SHA counts as a commit. A short one could also be a tag name,
	## and the raw host does not reliably expand it.
	isCommit=0; [[ "${ref}" =~ ^[0-9a-f]{40}$ ]] && isCommit=1
	refShown="${ref}"; ((isCommit)) && refShown="commit ${ref:0:8}"
	label="${localPath##*/} <- ${repo} ${refShown}"

	if ((isCommit)); then
		latest="$(fLatestTag "${repo}" any)"
		echo "[ vendor: NOTICE: ${localPath} is pinned to unreleased ${refShown} of ${repo}, a pre-release build ]"
		echo "[ vendor:   newest upstream release: ${latest:-unknown}. Re-pin to a tag in cicd/vendor-pins.env once the one this waits on is out ]"
	fi

	if [[ ! -f "${root}/${localPath}" ]]; then
		echo "[ vendor: FAILED: ${localPath} is pinned but missing ]" >&2
		failed=1
		continue
	fi

	## Keep a 404 (bad pin) separate from an unreachable network. Without the
	## status a typo'd tag would read as "offline" and quietly verify nothing.
	fetched="${tmp}/$(echo "${localPath}" | tr '/' '_')"
	status="$(curl -sSL --max-time 30 "${curlAuth[@]}" -o "${fetched}" -w '%{http_code}' \
		"https://raw.githubusercontent.com/${repo}/${ref}/${upstreamPath}" 2>/dev/null)" || true
	case "${status:-000}" in
		200) ;;
		404)
			echo "[ vendor: FAILED: ${repo} has no ${upstreamPath} at ${refShown} - fix the pin in cicd/vendor-pins.env ]" >&2
			failed=1
			continue ;;
		*)
			echo "[ vendor: WARNING: could not reach ${repo} (http ${status}) - ${localPath} unverified ]"
			unchecked+=1
			continue ;;
	esac

	if ! cmp -s "${fetched}" "${root}/${localPath}"; then
		echo "[ vendor: FAILED: ${localPath} does not match ${repo} ${refShown}:${upstreamPath} ]" >&2
		echo "[ vendor:   either the local copy was edited (it must stay verbatim) or the pin in ]" >&2
		echo "[ vendor:   cicd/vendor-pins.env names the wrong tag or commit. Diff: ]" >&2
		diff -u "${fetched}" "${root}/${localPath}" | head -40 >&2 || true
		failed=1
		continue
	fi

	checked+=1
	if ((isCommit)); then
		echo "[ vendor: ${label} verbatim ]"
		continue
	fi
	latest="$(fLatestTag "${repo}")"
	if [[ -n "${latest}" && "${latest}" != "${ref}" ]]; then
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
##		- 2026-10-03: A pin may name a commit SHA, with a pre-release notice each run.
