#!/usr/bin/env bash

##	Purpose:
##		- Manage the third-party reference implementations under thirdparty/,
##		  which the interop suite runs our own output against.
##		- --verify (default): offline. Re-hash every vendored file against
##		  manifest.sha256 and fail on any difference. A reference that has been
##		  edited is worse than no reference at all, because the suite would then
##		  agree with something nobody published.
##		- --upstream: online. Re-download each pinned archive and diff it against
##		  what is unpacked here, so a pin that was edited without a refetch is
##		  caught. The manifest alone cannot see that: it says the tree is
##		  unmodified, not that it is the release pins.env claims. Unreachable
##		  network warns and carries on; a mismatch fails.
##		- --refresh: download each pinned archive, check it against the hash in
##		  pins.env, and unpack it over thirdparty/, then rewrite the manifest.
##		  Needs the network. A deliberate act, never part of a test run.
##	History: At bottom.

##	Copyright © 2026 Bubbles (ID: XଌฅრX۳ᛟԃლፀƅꓩหδლც)
##	Licensed under GNU GPL v2 <https://www.gnu.org/licenses/gpl-2.0.html>. No warranty.
##	SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="${here}/manifest.sha256"

# shellcheck disable=1091  ## 'Not following.' The pin file is data, and it sits next to this script.
source "${here}/pins.env"

fEcho(){ echo "[ interop: $* ]"; }
fDie(){ echo "[ interop: FAILED: $* ]" >&2; exit 1; }

## Every vendored file, sorted, hashed, relative to this directory - so the
## manifest reads the same no matter where the repo lives.
fWriteManifest(){
	( cd "${here}" && find thirdparty -type f -print0 | LC_ALL=C sort -z \
		| xargs -0 sha256sum ) > "${manifest}"
	fEcho "manifest rewritten ($(wc -l < "${manifest}") files)"
}

fVerify(){
	[[ -f "${manifest}" ]] || fDie "no manifest at ${manifest} - run fetch.bash --refresh"
	[[ -d "${here}/thirdparty" ]] || fDie "thirdparty/ is missing - run fetch.bash --refresh"

	## sha256sum -c catches an edited or missing file but says nothing about a
	## file that was added, so the count is compared too.
	local want have
	want="$(wc -l < "${manifest}")"
	have="$(find "${here}/thirdparty" -type f | wc -l)"
	((want == have)) || fDie "thirdparty/ holds ${have} files, manifest lists ${want}"

	( cd "${here}" && sha256sum --quiet --check "${manifest}" ) \
		|| fDie "vendored reference implementations differ from the manifest"
	fEcho "ok: ${want} vendored file(s) verbatim"
}

## Download one pinned archive into DEST and check it against the hash in
## pins.env. Returns 1 for an unreachable host, and dies for a hash mismatch: a
## wrong hash is a bad pin or a tampered release, never a transient.
fDownloadPin(){ # DEST URL NAME VERSION WANT_SHA
	local dest="$1" url="$2" name="$3" version="$4" want="$5" got
	## crates.io answers 403 without a user agent, and both hosts redirect.
	curl -sSfL --max-time 60 -A "convert-base-v2 interop fetch" -o "${dest}" "${url}" || return 1
	got="$(sha256sum "${dest}" | cut -d' ' -f1)"
	[[ "${got}" == "${want}" ]] || fDie "${name} ${version} hashed ${got}, pins.env says ${want}"
}

fRefresh(){
	command -v curl >/dev/null 2>&1 || fDie "curl is needed to refresh"
	local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' RETURN

	local pin name version url want upstream archive dest
	for pin in "${INTEROP_PINS[@]}"; do
		IFS='|' read -r name version url want upstream <<< "${pin}"
		archive="${tmp}/${name}.archive"
		fDownloadPin "${archive}" "${url}" "${name}" "${version}" "${want}" \
			|| fDie "could not download ${name} ${version} from ${url}"

		## Both archive kinds wrap everything in one top directory whose name
		## carries the version, so strip it and keep our own stable name.
		dest="${here}/thirdparty/${name}"
		rm -rf "${dest}"
		mkdir -p "${dest}"
		tar xzf "${archive}" -C "${dest}" --strip-components=1
		fEcho "${name} ${version} <- ${upstream}"
	done

	fWriteManifest
}

## Newest published version, or empty when the query fails. Only feeds the
## "upstream moved" notice, so a miss here is never fatal. Both registries
## expose it at a path derivable from the download URL already in pins.env.
fLatestVersion(){ # URL
	local url="$1" api="" body=""
	case "${url}" in
		https://registry.npmjs.org/*) api="${url%%/-/*}" ;;
		https://crates.io/api/v1/crates/*) api="${url%/*/download}" ;;
		*) return 0 ;;
	esac
	body="$(curl -sSfL --max-time 15 -A "convert-base-v2 interop fetch" "${api}" 2>/dev/null)" || return 0
	## Narrow to the one object first. The npm document mentions "latest" in
	## several places, so an unanchored match could pick up the wrong one.
	case "${url}" in
		https://registry.npmjs.org/*) body="$(grep -o '"dist-tags":{[^}]*}' <<< "${body}" | grep -o '"latest":"[^"]*"')" ;;
		*)                            body="$(grep -o '"max_stable_version":"[^"]*"' <<< "${body}")" ;;
	esac
	sed -n 's/.*:"\([^"]*\)"/\1/p' <<< "${body}" | head -1
}

fUpstream(){
	command -v curl >/dev/null 2>&1 || { fEcho "WARNING: no curl - pins unverified against upstream"; return 0; }
	local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' RETURN

	local pin name version url want upstream archive dest latest
	local -i failed=0 checked=0 unreached=0
	for pin in "${INTEROP_PINS[@]}"; do
		IFS='|' read -r name version url want upstream <<< "${pin}"
		archive="${tmp}/${name}.archive"
		if ! fDownloadPin "${archive}" "${url}" "${name}" "${version}" "${want}"; then
			fEcho "WARNING: could not reach ${upstream} - ${name} unverified"
			unreached+=1
			continue
		fi
		dest="${tmp}/${name}"
		mkdir -p "${dest}"
		tar xzf "${archive}" -C "${dest}" --strip-components=1
		if diff -rq "${dest}" "${here}/thirdparty/${name}" >/dev/null 2>&1; then
			checked+=1
			## A new release of a reference is worth knowing about - it can change
			## an alphabet - but taking it is a decision, so this only ever says so.
			latest="$(fLatestVersion "${url}")"
			[[ -n "${latest}" && "${latest}" != "${version}" ]] \
				&& fEcho "${name} ${version} verbatim - upstream is now ${latest}, worth a look"
		else
			echo "[ interop: FAILED: thirdparty/${name} is not ${upstream} ${version} ]" >&2
			echo "[ interop:   either the copy was edited or pins.env was bumped without --refresh ]" >&2
			diff -rq "${dest}" "${here}/thirdparty/${name}" 2>&1 | head -10 >&2 || true
			failed=1
		fi
	done

	((failed)) && exit 1
	((unreached)) || fEcho "ok: ${checked} pinned package(s) match upstream"
	return 0
}

case "${1:---verify}" in
	--verify)   fVerify ;;
	--upstream) fVerify; fUpstream ;;
	--refresh)  fRefresh ;;
	*)          fDie "usage: fetch.bash [--verify|--upstream|--refresh]" ;;
esac


##	History:
##		- 2026-07-31: Created, with the interop suite.
