#!/usr/bin/env bash

#  shellcheck disable=2086  ## 'Double quote to prevent globbing and word splitting.' (OK for integers.)
#  shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome for locals.

##	Purpose:
##		- Self-contained release packager. Cross-builds every shipping platform
##		  and produces, into the output dir:
##		    - tarball (linux/darwin/freebsd) or zip (windows) of the bare binary
##		    - the bare binary itself, per platform/arch (grab-and-run)
##		    - .deb and .rpm per Linux arch (nfpm - cross-arch, no native tooling)
##		    - single-file Windows installer .exe per arch (makensis / NSIS)
##		    - checksums.txt
##		- Go builds are fully static (CGO off), so nothing here bundles a runtime.
##		- nfpm is a pinned go-installed tool (cicd/tool-versions.env); it writes
##		  deb and rpm directly for any arch, sidestepping rpmbuild's host-arch
##		  cross-build check. makensis/nfpm each probe-skip with a warning if
##		  missing, so a bare machine still gets the archives.
##		- Same script runs locally (via `make release` / cicd) and in the release
##		  workflow, so what ships is what was built and tested here.
##	History: At bottom.

##	Copyright © 2026 Jim Collier
##	Licensed under GNU GPL v2 <https://www.gnu.org/licenses/gpl-2.0.html>. No warranty.
##	SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

## Locations. This script lives in cicd/utility; the repo root is two up.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
src="${root}/source"

## Identity / package metadata.
PKG="convert-base-v2"
EXE="convert-base-v2"
MAINTAINER="Jim Collier <jim-collier@users.noreply.github.com>"
HOMEPAGE="https://github.com/jim-collier/convert-base-v2"
SUMMARY="Universal base (radix) converter"
DESC_LONG="Convert numbers of arbitrary size to and from any base. Dozens of predefined named bases plus user-defined alphabets, the RFC base-16/32/64 standards, negatives, floating point, and streaming binary."

## Defaults, overridable by flags.
VERSION="$(cd "${root}" && git describe --tags --always --dirty 2>/dev/null || echo dev)"
OUT="${src}/dist"
WANT_ARM=1

## Output helpers (bracketed status lines, matching cicd.bash).
fEcho(){ printf '[ %s ]\n' "$*"; }
fWarn(){ printf '[ WARNING: %s ]\n' "$*" >&2; }

fUsage(){ sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; }

while (($#)); do case "$1" in
	--version) VERSION="${2:?}"; shift 2 ;;
	--out)     OUT="${2:?}";     shift 2 ;;
	--no-arm)  WANT_ARM=0;       shift ;;
	-h|--help) fUsage; exit 0 ;;
	*) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac; done

## A relative --out is resolved against the caller's CWD (make/cicd invoke from
## the source dir, so their `--out dist` lands at source/dist as before).
[[ "${OUT}" = /* ]] || OUT="${PWD}/${OUT}"

## Package version: strip the leading v. nfpm turns 1.1.0-beta7 into 1.1.0~beta7
## itself (Debian/RPM read '~' as "sorts before the final"); the NSIS installer
## just displays it.
plainver="${VERSION#v}"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Cross-build + archive every platform.

platforms=(
	linux/amd64   linux/arm64
	darwin/amd64  darwin/arm64
	windows/amd64 windows/arm64
	freebsd/amd64 freebsd/arm64
)

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

rm -rf "${OUT}"; mkdir -p "${OUT}"

fEcho "packaging ${PKG} ${VERSION} -> ${OUT}"
for p in "${platforms[@]}"; do
	os="${p%/*}"; arch="${p#*/}"
	((WANT_ARM)) || [[ "${arch}" != arm64 ]] || continue
	label="${arch}"; [[ "${arch}" == amd64 ]] && label="x86_64"
	ext=""; [[ "${os}" == windows ]] && ext=".exe"
	bindir="${work}/${os}-${arch}"; mkdir -p "${bindir}"
	binpath="${bindir}/${EXE}${ext}"

	( cd "${src}" && CGO_ENABLED=0 GOOS="${os}" GOARCH="${arch}" \
		go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o "${binpath}" ./... )

	if [[ "${os}" == windows ]]; then
		( cd "${bindir}" && zip -qr "${OUT}/${PKG}-${os}-${label}.zip" "${EXE}${ext}" )
	else
		tar -C "${bindir}" -czf "${OUT}/${PKG}-${os}-${label}.tgz" "${EXE}${ext}"
	fi
	# Also ship the bare binary alongside the archive (grab-and-run; unix
	# loses the exec bit on browser download, hence the archives stay too).
	cp "${binpath}" "${OUT}/${PKG}-${os}-${label}${ext}"
	fEcho "built ${os}/${arch}"
done


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Linux packages: .deb and .rpm per arch, via nfpm (cross-arch, no native
## tooling). nfpm maps the one arch value to each format (deb: amd64/arm64,
## rpm: x86_64/aarch64) and turns 1.1.0-beta7 into 1.1.0~beta7 itself.

fBuildNfpm(){
	local arch="$1" bin="$2"   ## arch: amd64|arm64
	command -v nfpm >/dev/null 2>&1 || { fWarn "nfpm missing; skipping .deb/.rpm (${arch}) - go install github.com/goreleaser/nfpm/v2/cmd/nfpm"; return 0; }
	local cfg="${work}/nfpm-${arch}.yaml"
	cat >"${cfg}" <<-EOF
		name: ${PKG}
		arch: ${arch}
		version: ${plainver}
		maintainer: ${MAINTAINER}
		description: |
		  ${SUMMARY}.
		  ${DESC_LONG}
		homepage: ${HOMEPAGE}
		license: GPL-2.0-or-later
		section: utils
		priority: optional
		contents:
		  - src: ${bin}
		    dst: /usr/bin/${EXE}
		    file_info:
		      mode: 0755
		  - src: ${root}/license.md
		    dst: /usr/share/doc/${PKG}/copyright
		    packager: deb
		  - src: ${root}/license.md
		    dst: /usr/share/licenses/${PKG}/license.md
		    packager: rpm
	EOF
	local fmt
	for fmt in deb rpm; do
		if nfpm package --config "${cfg}" --packager "${fmt}" --target "${OUT}/" >/dev/null 2>&1; then
			fEcho "built .${fmt} (${arch})"
		else
			fWarn "nfpm ${fmt} failed (${arch})"
		fi
	done
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Windows: single-file installer .exe per arch (bare .exe still ships in the zip).

fBuildNsis(){
	local arch="$1" bin="$2"
	command -v makensis >/dev/null 2>&1 || { fWarn "makensis missing; skipping installer (${arch})"; return 0; }
	local label="${arch}"; [[ "${arch}" == amd64 ]] && label="x86_64"
	local outfile="${OUT}/${PKG}-windows-${label}-setup.exe"
	if makensis -V1 \
		"-DAPPVERSION=${plainver}" "-DAPPARCH=${label}" \
		"-DEXEPATH=${bin}" "-DOUTFILE=${outfile}" \
		"${here}/nsis/installer.nsi" >/dev/null 2>&1; then
		fEcho "built installer (${label})"
	else
		fWarn "makensis failed (${label}); skipping installer"
	fi
}

for arch in amd64 arm64; do
	((WANT_ARM)) || [[ "${arch}" != arm64 ]] || continue
	fBuildNfpm "${arch}" "${work}/linux-${arch}/${EXE}"
	fBuildNsis "${arch}" "${work}/windows-${arch}/${EXE}.exe"
done


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Checksums over everything produced.

( cd "${OUT}" && find . -maxdepth 1 -type f ! -name checksums.txt -printf '%P\n' | sort \
	| xargs -r sha256sum > checksums.txt )

fEcho "done: $(find "${OUT}" -maxdepth 1 -type f ! -name checksums.txt | wc -l) artifacts in ${OUT}"


##	History:
##		- 2026-07-12 JC: Created. Self-contained cross-build + deb/rpm/NSIS packaging, replacing goreleaser.
