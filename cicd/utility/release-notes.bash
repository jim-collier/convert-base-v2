#!/usr/bin/env bash

##	Purpose:
##		- Writes a release's notes to stdout: the version's changelog section, a
##		  downloads table with the OS in rows and the CPU architecture in columns,
##		  and the version line the released binary prints, build number and all.
##		- The table is made from the files package.bash wrote, so it lists what was
##		  built and nothing else. A file it can't place is still listed, under the
##		  table, with a warning on stderr.
##		- Publishes nothing, so it is safe to run by hand against `make release`.
##	Usage:
##		release-notes.bash --version vX.Y.Z --dist DIR [--repo OWNER/NAME] [--changelog FILE]
##	History: At bottom.

##	Copyright (c) 2026 Bubbles
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"

PKG="convert-base-v2"
VERSION=""
DIST=""
REPO="${GITHUB_REPOSITORY:-jim-collier/convert-base-v2}"
CHANGELOG="${root}/changelog.md"

fUsage(){ sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; }
fWarn(){ printf '[ WARNING: %s ]\n' "$*" >&2; }

while (($#)); do case "$1" in
	--version)   VERSION="${2:?}";   shift 2 ;;
	--dist)      DIST="${2:?}";      shift 2 ;;
	--repo)      REPO="${2:?}";      shift 2 ;;
	--changelog) CHANGELOG="${2:?}"; shift 2 ;;
	-h|--help)   fUsage; exit 0 ;;
	*) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac; done
[[ -n "${VERSION}" && -d "${DIST}" ]] || { echo "needs --version and an existing --dist dir (try --help)" >&2; exit 2; }


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The changelog section for this version, as written. The heading is matched
## up to its " - DATE", so v3.1.0 does not also take a v3.1.0-beta1 section.

section="$(awk -v ver="${VERSION}" '
	$0 == "## " ver || index($0, "## " ver " ") == 1 { on = 1; next }
	/^## / { on = 0 }
	on { print }
' "${CHANGELOG}" 2>/dev/null || true)"
## Leading and trailing blank lines only; the section's own spacing stays.
section="$(sed -e '/./,$!d' <<<"${section}")"
[[ -n "${section}" ]] || section="See changelog.md."
printf '%s\n' "${section}"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Downloads table.

## Sets cOs, cArch, cLabel and cRank (the order within a cell) for one asset
## name, or returns 1 when the name is not one package.bash makes.
fClassify(){
	local name="$1" stem=""
	cOs=""; cArch=""; cLabel=""; cRank=0
	case "${name}" in
		"${PKG}"_*_amd64.deb)        cOs=linux;   cArch=x86_64;    cLabel=".deb";      cRank=3 ;;
		"${PKG}"_*_arm64.deb)        cOs=linux;   cArch=arm64;     cLabel=".deb";      cRank=3 ;;
		"${PKG}"-*.x86_64.rpm)       cOs=linux;   cArch=x86_64;    cLabel=".rpm";      cRank=4 ;;
		"${PKG}"-*.aarch64.rpm)      cOs=linux;   cArch=arm64;     cLabel=".rpm";      cRank=4 ;;
		"${PKG}".wasm)               cOs=wasi;    cArch=universal; cLabel=".wasm";     cRank=1 ;;
		"${PKG}"-windows-*-setup.exe) stem="${name#"${PKG}"-}"; stem="${stem%-setup.exe}"; cLabel="installer"; cRank=5 ;;
		"${PKG}"-*.tgz)              stem="${name#"${PKG}"-}"; stem="${stem%.tgz}"; cLabel=".tgz";   cRank=2 ;;
		"${PKG}"-*.zip)              stem="${name#"${PKG}"-}"; stem="${stem%.zip}"; cLabel=".zip";   cRank=2 ;;
		"${PKG}"-*.exe)              stem="${name#"${PKG}"-}"; stem="${stem%.exe}"; cLabel=".exe";   cRank=1 ;;
		"${PKG}"-*-*)                stem="${name#"${PKG}"-}";                       cLabel="binary"; cRank=1 ;;
		*) return 1 ;;
	esac
	if [[ -n "${stem}" ]]; then cOs="${stem%%-*}"; cArch="${stem#*-}"; fi
	case "${cOs}/${cArch}" in
		linux/x86_64|linux/arm64|darwin/x86_64|darwin/arm64|darwin/universal) ;;
		windows/x86_64|windows/arm64|freebsd/x86_64|freebsd/arm64|wasi/universal) ;;
		*) return 1 ;;
	esac
}

## GitHub serves an uploaded asset under a name with every character outside
## [A-Za-z0-9._-] turned into a dot, so a "3.1.0~beta1" package downloads as
## "3.1.0.beta1". package.bash already renames them, so this only matters for
## a dist dir made some other way. Link the name it will have.
baseUrl="https://github.com/${REPO}/releases/download/${VERSION}"
entries=(); others=(); checksums=""
for path in "${DIST}"/*; do
	[[ -f "${path}" ]] || continue
	name="${path##*/}"
	served="${name//[!A-Za-z0-9._-]/.}"
	if [[ "${name}" == checksums.txt ]]; then
		checksums="[checksums.txt](${baseUrl}/${served})"
	elif fClassify "${name}"; then
		entries+=("${cRank}"$'\t'"${cOs}/${cArch}"$'\t'"[${cLabel}](${baseUrl}/${served})")
	else
		fWarn "not a known asset, listed under the table: ${name}"
		others+=("[${name}](${baseUrl}/${served})")
	fi
done

declare -A cells=()
if ((${#entries[@]})); then
	while IFS=$'\t' read -r _ key link; do
		cells[${key}]="${cells[${key}]:+${cells[${key}]}, }${link}"
	done < <(printf '%s\n' "${entries[@]}" | sort -s -t $'\t' -k1,1n)
fi

osIds=(linux darwin windows freebsd wasi)
declare -A osNames=([linux]=Linux [darwin]=macOS [windows]=Windows [freebsd]=FreeBSD [wasi]="WebAssembly (WASI)")
archIds=(x86_64 arm64 universal)
declare -A archNames=([x86_64]=x86_64 [arm64]=arm64 [universal]=Universal)

## Only the rows and columns that have something in them.
rows=(); cols=()
for os in "${osIds[@]}"; do
	for arch in "${archIds[@]}"; do [[ -n "${cells[${os}/${arch}]:-}" ]] && { rows+=("${os}"); break; }; done
done
for arch in "${archIds[@]}"; do
	for os in "${osIds[@]}"; do [[ -n "${cells[${os}/${arch}]:-}" ]] && { cols+=("${arch}"); break; }; done
done

printf '\n### Downloads\n\n'
if ((${#rows[@]})); then
	## Not padded: the links make the cells far too wide for that to help.
	fRow(){
		local line="" field
		for field in "$@"; do line+="| ${field} "; done
		printf '%s\n' "${line%"${line##*[! ]}"}"
	}
	header=(OS); rule=(":---")
	for arch in "${cols[@]}"; do header+=("${archNames[${arch}]}"); rule+=(":---"); done
	fRow "${header[@]}"
	fRow "${rule[@]}"
	for os in "${rows[@]}"; do
		line=("${osNames[${os}]}")
		for arch in "${cols[@]}"; do line+=("${cells[${os}/${arch}]:-}"); done
		fRow "${line[@]}"
	done
else
	fWarn "no packaged assets found in ${DIST}"
	printf 'See the files below.\n'
fi
if ((${#others[@]})); then
	also="${others[0]}"
	for link in "${others[@]:1}"; do also+=", ${link}"; done
	printf '\nAlso: %s\n' "${also}"
fi
[[ -z "${checksums}" ]] || printf '\nChecksums for every file: %s\n' "${checksums}"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The version line, read back from the build for this machine, so the notes
## and the download can't disagree about the build number.

case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; FreeBSD) os=freebsd ;; *) os="" ;; esac
case "$(uname -m)" in x86_64|amd64) arch=x86_64 ;; aarch64|arm64) arch=arm64 ;; *) arch="" ;; esac
native="${DIST}/${PKG}-${os}-${arch}"
versionLine=""
if [[ -n "${os}" && -n "${arch}" && -x "${native}" ]]; then
	versionLine="$("${native}" --version 2>/dev/null || true)"
fi
versionLine="${versionLine%%$'\n'*}"
if [[ -z "${versionLine}" ]]; then
	fWarn "could not run ${native} --version, so the notes name no build number"
elif [[ "${versionLine%% *}" != "${VERSION}" ]]; then
	fWarn "${native} says '${versionLine}', not ${VERSION}, so the notes name no build number"
else
	printf '\n---\n\n%s %s\n' "${PKG}" "${versionLine}"
fi


##	History:
##		- 2026-10-04: Created. Changelog section, downloads table, build line.
