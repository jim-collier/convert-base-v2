#!/usr/bin/env bash

#  shellcheck disable=2086  ## 'Double quote to prevent globbing and word splitting.' (OK for integers.)
#  shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome for locals.
#  shellcheck disable=2094  ## 'Read and write the same file in one pipeline.' False hit: find leaves checksums.txt out by name.

##	Purpose:
##		- Self-contained release packager. Cross-builds every shipping platform
##		  and produces, into the output dir:
##		    - tarball (linux/darwin/freebsd) or zip (windows) of the bare binary
##		    - the bare binary itself, per platform/arch (grab-and-run)
##		    - a macOS universal binary (amd64 + arm64), as tarball and bare,
##		      when both darwin builds were made
##		    - the WASI build of the command, one .wasm for every CPU
##		    - .deb and .rpm per Linux arch (nfpm - cross-arch, no native tooling)
##		    - single-file Windows installer .exe per arch (makensis / NSIS)
##		    - checksums.txt
##		- Go builds are fully static (CGO off), so nothing here bundles a runtime.
##		- nfpm is a pinned go-installed tool (cicd/tool-versions.env); it writes
##		  deb and rpm directly for any arch, sidestepping rpmbuild's host-arch
##		  cross-build check. makensis/nfpm each probe-skip with a warning if
##		  missing, so a bare machine still gets the archives. Under
##		  CICD_NO_SKIP=1, as in the container, a missing or failed one is an error.
##		- Same script runs locally (via `make release` / cicd) and in the release
##		  workflow, so what ships is what was built and tested here.
##		- Every binary carries a build number, taken from the commit's time
##		  (--build-epoch, default HEAD's), so a rebuild matches the checksums.
##		  The archives, packages and installers take their file times from it
##		  too, with fixed owners and modes, so they rebuild to the same bytes.
##		- A file name with a character GitHub would change on upload, such as
##		  the ~ in a prerelease .deb or .rpm, is renamed to what GitHub serves
##		  before checksums.txt is written.
##		- The output dir is cleared first, but only when a build made it. A dir
##		  holding anything else is refused.
##	History: At bottom.

##	Copyright (c) 2026 Bubbles
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail
## Byte order for checksums.txt and the name rewrite, whatever the host's locale.
export LC_ALL=C

## Locations. This script lives in cicd/utility; the repo root is two up.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
src="${root}/lib"

## Identity / package metadata.
PKG="convert-base-v2"
EXE="convert-base-v2"
MAINTAINER="Jim Collier <jim-collier@users.noreply.github.com>"
HOMEPAGE="https://github.com/jim-collier/convert-base-v2"
SUMMARY="Universal base (radix) converter"
DESC_LONG="Convert numbers of arbitrary size to and from any base. Dozens of predefined named bases plus user-defined alphabets, the RFC base-16/32/64 standards, negatives, floating point, and streaming binary."

## Defaults, overridable by flags. The lib/vX.Y.Z module tags are skipped: they land
## on the same commits as the command's tags, so describe would stamp the wrong one.
VERSION="$(cd "${root}" && git describe --tags --always --dirty --exclude 'lib/*' 2>/dev/null || echo dev)"
## Commit time, not the clock, so the same commit always builds the same bytes.
BUILD_EPOCH="$(cd "${root}" && git log -1 --format=%ct 2>/dev/null || true)"
OUT="${src}/dist"
WANT_ARM=1

## Output helpers (bracketed status lines, matching cicd.bash).
fEcho(){ printf '[ %s ]\n' "$*"; }
fWarn(){ printf '[ WARNING: %s ]\n' "$*" >&2; }
## A package left out. In the container (CICD_NO_SKIP=1) every packager is
## installed, so there it's an error.
fSkip(){ [[ "${CICD_NO_SKIP:-0}" != "1" ]] || { printf '[ ERROR: %s ]\n' "$*" >&2; exit 1; }; fWarn "$*"; }

fUsage(){ sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; }

while (($#)); do case "$1" in
	--version) VERSION="${2:?}"; shift 2 ;;
	--build-epoch) BUILD_EPOCH="${2?}"; shift 2 ;;
	--out)     OUT="${2:?}";     shift 2 ;;
	--no-arm)  WANT_ARM=0;       shift ;;
	-h|--help) fUsage; exit 0 ;;
	*) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac; done
[[ -z "${BUILD_EPOCH}" || "${BUILD_EPOCH}" =~ ^[0-9]+$ ]] || { echo "--build-epoch takes unix seconds, not '${BUILD_EPOCH}'" >&2; exit 2; }
## Before the cross builds, so a missing packager fails in a second, not a minute.
if [[ "${CICD_NO_SKIP:-0}" == "1" ]]; then
	for tool in nfpm makensis; do command -v "${tool}" >/dev/null 2>&1 || fSkip "${tool} missing"; done
fi

## A relative --out is resolved against the caller's CWD (make/cicd invoke from
## the source dir, so their `--out dist` lands at lib/dist as before).
[[ "${OUT}" = /* ]] || OUT="${PWD}/${OUT}"

## nfpm reads this for every time it writes. Without a commit there is no
## stable time to use, so such a build takes the clock and won't repeat.
[[ -z "${BUILD_EPOCH}" ]] || export SOURCE_DATE_EPOCH="${BUILD_EPOCH}"

## What goes into an archive or installer gets the commit's time and a mode
## that doesn't depend on the umask.
fStamp(){ chmod 0755 "$@"; [[ -z "${BUILD_EPOCH}" ]] || touch -d "@${BUILD_EPOCH}" "$@"; }

## gzip -n leaves the clock out of the gzip header.
fTgz(){
	local dir="$1" file="$2" out="$3"
	tar -C "${dir}" --format=ustar --sort=name --owner=0 --group=0 --numeric-owner -cf - "${file}" | gzip -n >"${out}"
}

## Package version: strip the leading v. nfpm turns 1.1.0-beta7 into 1.1.0~beta7
## itself (Debian/RPM read '~' as "sorts before the final"); the NSIS installer
## just displays it. Only the file name loses the ~, at the end.
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

## Only a dir with the mark is cleared, so --out can't empty someone's folder.
## An empty dir is taken over. lib/Makefile writes the same mark.
distMark=".convert-base-v2-dist"
if [[ -f "${OUT}/${distMark}" ]]; then
	rm -rf "${OUT}"
elif [[ -e "${OUT}" ]]; then
	rmdir "${OUT}" 2>/dev/null || { echo "${OUT} has files in it and no sign a build made them; empty it or pick another --out" >&2; exit 1; }
fi
mkdir -p "${OUT}"
echo "Made by package.bash, and cleared on every run." >"${OUT}/${distMark}"

fEcho "packaging ${PKG} ${VERSION} -> ${OUT}"
for p in "${platforms[@]}"; do
	os="${p%/*}"; arch="${p#*/}"
	((WANT_ARM)) || [[ "${arch}" != arm64 ]] || continue
	label="${arch}"; [[ "${arch}" == amd64 ]] && label="x86_64"
	ext=""; [[ "${os}" == windows ]] && ext=".exe"
	bindir="${work}/${os}-${arch}"; mkdir -p "${bindir}"
	binpath="${bindir}/${EXE}${ext}"

	## No VCS stamp or build ID, so a dirty tree or a source tarball of the
	## same commit builds the same bytes.
	( cd "${src}" && CGO_ENABLED=0 GOOS="${os}" GOARCH="${arch}" \
		go build -trimpath -buildvcs=false -ldflags "-s -w -buildid= -X main.version=${VERSION} -X main.buildEpoch=${BUILD_EPOCH}" -o "${binpath}" ./cmd/convert-base-v2 )
	fStamp "${binpath}"

	if [[ "${os}" == windows ]]; then
		## -X drops the owner and unix time fields. The DOS time is local time.
		( cd "${bindir}" && TZ=UTC zip -qX "${OUT}/${PKG}-${os}-${label}.zip" "${EXE}${ext}" )
	else
		fTgz "${bindir}" "${EXE}${ext}" "${OUT}/${PKG}-${os}-${label}.tgz"
	fi
	# Also ship the bare binary alongside the archive (grab-and-run; unix
	# loses the exec bit on browser download, hence the archives stay too).
	cp "${binpath}" "${OUT}/${PKG}-${os}-${label}${ext}"
	fEcho "built ${os}/${arch}"
done


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## macOS universal binary: both darwin builds in one file, for a Mac of either
## kind. The per-arch assets stay, since install.bash fetches those and they are
## half the size. Packaging runs without lipo, so macho-fat joins them.

if [[ -f "${work}/darwin-amd64/${EXE}" && -f "${work}/darwin-arm64/${EXE}" ]]; then
	unidir="${work}/darwin-universal"; mkdir -p "${unidir}"
	( cd "${here}/macho-fat" && go run . -o "${unidir}/${EXE}" "${work}/darwin-amd64/${EXE}" "${work}/darwin-arm64/${EXE}" )
	fStamp "${unidir}/${EXE}"
	fTgz "${unidir}" "${EXE}" "${OUT}/${PKG}-darwin-universal.tgz"
	cp "${unidir}/${EXE}" "${OUT}/${PKG}-darwin-universal"
	fEcho "built darwin/universal"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The whole command for any WASI runtime. Same build as `make wasm`, less the
## VCS stamp.

( cd "${src}" && CGO_ENABLED=0 GOOS=wasip1 GOARCH=wasm \
	go build -trimpath -buildvcs=false -ldflags "-s -w -buildid= -X main.version=${VERSION} -X main.buildEpoch=${BUILD_EPOCH}" -o "${OUT}/${PKG}.wasm" ./cmd/convert-base-v2 )
fEcho "built wasip1/wasm"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Linux packages: .deb and .rpm per arch, via nfpm (cross-arch, no native
## tooling). nfpm maps the one arch value to each format (deb: amd64/arm64,
## rpm: x86_64/aarch64) and turns 1.1.0-beta7 into 1.1.0~beta7 itself.

fBuildNfpm(){
	local arch="$1" bin="$2"   ## arch: amd64|arm64
	command -v nfpm >/dev/null 2>&1 || { fSkip "nfpm missing; skipping .deb/.rpm (${arch}) - go install github.com/goreleaser/nfpm/v2/cmd/nfpm"; return 0; }
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
		rpm:
		  buildhost: localhost
		contents:
		  - src: ${bin}
		    dst: /usr/bin/${EXE}
		    file_info:
		      mode: 0755
		  - src: ${root}/license.md
		    dst: /usr/share/doc/${PKG}/copyright
		    packager: deb
		    file_info:
		      mode: 0644
		  - src: ${root}/license.md
		    dst: /usr/share/licenses/${PKG}/license.md
		    packager: rpm
		    file_info:
		      mode: 0644
	EOF
	local fmt
	for fmt in deb rpm; do
		if nfpm package --config "${cfg}" --packager "${fmt}" --target "${OUT}/" >/dev/null 2>&1; then
			fEcho "built .${fmt} (${arch})"
		else
			fSkip "nfpm ${fmt} failed (${arch})"
		fi
	done
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Windows: single-file installer .exe per arch (bare .exe still ships in the zip).

fBuildNsis(){
	local arch="$1" bin="$2"
	command -v makensis >/dev/null 2>&1 || { fSkip "makensis missing; skipping installer (${arch})"; return 0; }
	local label="${arch}"; [[ "${arch}" == amd64 ]] && label="x86_64"
	local outfile="${OUT}/${PKG}-windows-${label}-setup.exe"
	if makensis -V1 \
		"-DAPPVERSION=${plainver}" "-DAPPARCH=${label}" \
		"-DEXEPATH=${bin}" "-DOUTFILE=${outfile}" \
		"${here}/nsis/installer.nsi" >/dev/null 2>&1; then
		fEcho "built installer (${label})"
	else
		fSkip "makensis failed (${label}); skipping installer"
	fi
}

for arch in amd64 arm64; do
	((WANT_ARM)) || [[ "${arch}" != arm64 ]] || continue
	fBuildNfpm "${arch}" "${work}/linux-${arch}/${EXE}"
	fBuildNsis "${arch}" "${work}/windows-${arch}/${EXE}.exe"
done


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## GitHub serves an uploaded file with every character outside [A-Za-z0-9._-]
## turned into a dot, so 3.1.0~beta1 downloads as 3.1.0.beta1. Use that name
## here, or checksums.txt names a file nobody can download.

for path in "${OUT}"/*; do
	name="${path##*/}"; served="${name//[!A-Za-z0-9._-]/.}"
	if [[ "${name}" != "${served}" ]]; then
		[[ ! -e "${OUT}/${served}" ]] || { echo "both ${name} and ${served} would download as ${served}" >&2; exit 1; }
		mv "${path}" "${OUT}/${served}"
	fi
done


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Checksums over everything produced.

( cd "${OUT}" && find . -maxdepth 1 -type f ! -name checksums.txt ! -name "${distMark}" -printf '%P\n' | sort \
	| xargs -r sha256sum > checksums.txt )

fEcho "done: $(find "${OUT}" -maxdepth 1 -type f ! -name checksums.txt ! -name "${distMark}" | wc -l) artifacts in ${OUT}"


##	History:
##		- 2026-07-12: Created. Self-contained cross-build + deb/rpm/NSIS packaging, replacing goreleaser.
##		- 2026-10-03: macOS universal binary alongside the per-arch darwin builds.
##		- 2026-10-04: Build number from the commit's time (--build-epoch). The WASI build ships too.
##		- 2026-10-04: Archives, packages and installers rebuild to the same bytes. Names GitHub would change are changed first.
##		- 2026-10-04: --out is cleared only when a build made it.
##		- 2026-10-10: A skipped package is an error under CICD_NO_SKIP=1.
