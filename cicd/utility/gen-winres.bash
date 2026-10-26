#!/usr/bin/env bash

#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

##	Purpose:
##		- Writes the Windows resource (.syso) the Go linker picks up, so the .exe has an
##		  icon and the version details Explorer's Properties tab reads.
##		- package.bash calls it once per Windows arch, at build time, and hands the result
##		  to go build through -overlay. Nothing is written into the source tree, so a plain
##		  go build never sees a stale one and the other OSes never see one at all.
##		- The version is whatever package.bash stamps with -X main.version, so the
##		  Properties tab and --version agree. Same input, same bytes: goversioninfo puts
##		  no time in the file.
##	Syntax:
##		cicd/utility/gen-winres.bash [-q] --version VER --numeric A.B.C.D --arch ARCH -o FILE
##		cicd/utility/gen-winres.bash [-q] --icon    Rebuild assets/convert-base-v2.ico from assets/mascot.png.
##		  VER      the version string to show, leading v already gone, e.g. 3.0.1-beta1.
##		  A.B.C.D  the same as four numbers, for the fixed part of the resource.
##		  ARCH     amd64 or arm64.
##	Requires:
##		- goversioninfo on PATH, pinned in cicd/tool-versions.env:
##		      go install github.com/josephspurrier/goversioninfo/cmd/goversioninfo@v1.5.0
##		  Absent, it exits 3 without writing anything, so a caller can tell "no tool" from
##		  "failed".
##		- --icon needs ImageMagick, icoutils and optipng. It's a hand step, run when the
##		  mascot changes, and isn't part of any gate: the encoders differ between versions,
##		  so the .ico is a committed asset rather than a reproducible one.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 404 )); then
	printf '%s\n' "${0##*/}: needs bash 4.4 or newer, and this is bash ${BASH_VERSION}. On macOS, install one with 'brew install bash' and put it first on PATH." >&2; exit 1
fi
set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${here}/include/safe-rm.bash"
tmpRoot="$(realpath -- "${TMPDIR:-/tmp}")"
root="$(cd "${here}/../.." && pwd)"
exeName="convert-base-v2"
icon="${root}/assets/${exeName}.ico"
logo="${root}/assets/mascot.png"
mainGo="${root}/lib/cmd/${exeName}/main.go"

declare -i quiet=0 iconOnly=0
version="" numeric="" arch="" out=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		-q|--quiet) quiet=1; shift ;;
		--icon)     iconOnly=1; shift ;;
		--version)  version="${2:?}"; shift 2 ;;
		--numeric)  numeric="${2:?}"; shift 2 ;;
		--arch)     arch="${2:?}"; shift 2 ;;
		-o)         out="${2:?}"; shift 2 ;;
		-h|--help)  sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
		*)          echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
	esac
done

fEcho_Clean(){ ((quiet)) || printf '%s\n' "$*"; }
fDie(){ printf '%s\n' "gen-winres: $*" >&2; exit 1; }


##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## --icon: rebuild the .ico from the mascot. Six sizes. 16/32/48 stay BMP because Explorer before
## Windows 10 does not reliably draw a PNG-compressed entry below 256; the three large ones are
## PNG, quantized to 256 colors, which keeps the file small for a loss the eye can't find at
## icon size.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
if ((iconOnly)); then
	for tool in magick icotool optipng; do command -v "${tool}" >/dev/null 2>&1 || fDie "--icon needs ${tool}."; done
	[[ -f "${logo}" ]] || fDie "no mascot at assets/$(basename "${logo}")."
	tmp="$(mktemp -d "${tmpRoot}/cbv2-ico.XXXXXX")"
	trap 'fSafeRmUnder "${tmpRoot}" "${tmp}" || true' EXIT
	## A touch of unsharp on the small ones, or the face turns to mush at 16 px.
	for s in 16 32 48; do magick "${logo}" -filter Lanczos -resize "${s}x${s}" -unsharp 0x0.5+0.6+0.02 -strip "${tmp}/i${s}.png"; done
	for s in 64 128 256; do
		magick "${logo}" -filter Lanczos -resize "${s}x${s}" -dither Riemersma -colors 256 -strip "${tmp}/i${s}.png"
		optipng -quiet -o7 -strip all "${tmp}/i${s}.png" 2>/dev/null || true
	done
	icotool -c -o "${icon}" "${tmp}/i16.png" "${tmp}/i32.png" "${tmp}/i48.png" \
		--raw="${tmp}/i64.png" --raw="${tmp}/i128.png" --raw="${tmp}/i256.png" \
		|| fDie "icotool couldn't write ${icon}."
	fEcho_Clean "wrote assets/$(basename "${icon}") ($(stat -c%s "${icon}") bytes)"
	exit 0
fi


[[ -n "${version}" && -n "${out}" ]] || fDie "needs --version, --numeric, --arch and -o (see --help)."
[[ "${numeric}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || fDie "--numeric takes four numbers, not '${numeric}'."
verMajor="${BASH_REMATCH[1]}"; verMinor="${BASH_REMATCH[2]}"; verPatch="${BASH_REMATCH[3]}"; verBuild="${BASH_REMATCH[4]}"
for n in "${verMajor}" "${verMinor}" "${verPatch}" "${verBuild}"; do
	[[ "${#n}" -le 5 && "$((10#${n}))" -le 65535 ]] || fDie "--numeric parts are 16 bits each, and '${numeric}' doesn't fit."
done
## Anything past X.Y.Z (a beta, commits past the tag, a dirty tree) is flagged prerelease.
fileFlags="00"; [[ "${version}" == "${verMajor}.${verMinor}.${verPatch}" ]] || fileFlags="02"

## goversioninfo names the word size and the family, not the GOARCH, so the mapping is by hand.
case "${arch}" in
	amd64) archFlags=(-64) ;;
	arm64) archFlags=(-arm -64) ;;
	*)     fDie "no goversioninfo flags known for windows/${arch}." ;;
esac

[[ -f "${icon}" ]] || fDie "no icon at assets/$(basename "${icon}") - run with --icon."
command -v goversioninfo >/dev/null 2>&1 || { fEcho_Clean "  goversioninfo isn't installed (see --help)" >&2; exit 3; }

## The years come from the program, so the Properties tab and --about can't disagree. No ID marker
## on purpose: Explorer shows LegalCopyright.
copyrightYear="$(sed -n 's/^[[:space:]]*copyrightYear[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${mainGo}" || true)"
[[ -n "${copyrightYear}" ]] || fDie "couldn't read copyrightYear from lib/cmd/${exeName}/main.go."

scratch="$(mktemp -d "${tmpRoot}/cbv2-winres.XXXXXX")"
trap 'fSafeRmUnder "${tmpRoot}" "${scratch}" || true' EXIT
json="${scratch}/versioninfo.json"
cat > "${json}" <<-JSON
	{
		"FixedFileInfo": {
			"FileVersion":    { "Major": ${verMajor}, "Minor": ${verMinor}, "Patch": ${verPatch}, "Build": ${verBuild} },
			"ProductVersion": { "Major": ${verMajor}, "Minor": ${verMinor}, "Patch": ${verPatch}, "Build": ${verBuild} },
			"FileFlagsMask": "3f",
			"FileFlags": "${fileFlags}",
			"FileOS": "040004",
			"FileType": "01",
			"FileSubType": "00"
		},
		"StringFileInfo": {
			"CompanyName": "Jim Collier",
			"FileDescription": "Universal base (radix) converter",
			"FileVersion": "${version}",
			"InternalName": "${exeName}",
			"LegalCopyright": "Copyright © ${copyrightYear} Jim Collier. Licensed under the GNU GPL v2.0 or later.",
			"OriginalFilename": "${exeName}.exe",
			"ProductName": "${exeName}",
			"ProductVersion": "${version}"
		},
		"VarFileInfo": {
			"Translation": { "LangID": "0409", "CharsetID": "04B0" }
		},
		"IconPath": "${icon}"
	}
JSON

goversioninfo "${archFlags[@]}" -o "${out}" "${json}" || fDie "goversioninfo failed for windows/${arch}."
fEcho_Clean "  wrote $(basename "${out}") ($(stat -c%s "${out}") bytes)"
exit 0


##	History:
##		- 20260819 JC: Created in gitsby, as a committed resource.
##		- 20261019 JC: Taken into convert-base-v2. Built at package time from the stamped
##		  version instead of committed, and the icon comes from the mascot.
