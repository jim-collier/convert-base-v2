#!/usr/bin/env bash
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## install.bash
##
##	One-line installer for convert-base-v2 on Linux, BSD, macOS, and WSL.
##	Downloads a release binary, verifies its checksum against the release's
##	checksums.txt, and installs it. States its plan and asks first.
##
##	Usage:
##		bash <(curl -fsSL https://raw.githubusercontent.com/jim-collier/convert-base-v2/main/install.bash) [options]
##	Options:
##		--release stable|dev ... stable = latest release (default), dev = newest including pre-releases
##		--target user|system ... user = ~/.local/bin (default), system = /usr/local/bin (may need sudo)
##		--arch x86_64|arm64 .... override the detected architecture
##		-y|--yes ............... skip the confirmation prompt
##	Notes:
##		- Needs bash 3.2+, curl, and sha256sum or shasum.
##		- Windows: use the installer .exe from the Releases page instead.
##		- Re-running is safe; an already-current install is left alone.
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••

##	Copyright © 2026 Bubbles (ID: XଌฅრX۳ᛟԃლፀƅꓩหδლც)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

PKG="convert-base-v2"
REPO="jim-collier/convert-base-v2"
API="https://api.github.com/repos/${REPO}/releases"

RELEASE="stable"
TARGET="user"
ARCH=""
ASSUME_YES=0

fEcho(){ printf '[ %s ]\n' "$*"; }
fEcho_Clean(){ printf '%s\n' "$*"; }
fDie(){ printf '[ ERROR: %s ]\n' "$*" >&2; echo; exit 1; }

fUsage(){ sed -n '/^##	Usage:/,/^#••/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##\t\{0,1\}//'; }

while (($#)); do case "$1" in
	--release) RELEASE="${2:?}"; shift 2 ;;
	--target)  TARGET="${2:?}";  shift 2 ;;
	--arch)    ARCH="${2:?}";    shift 2 ;;
	-y|--yes)  ASSUME_YES=1;     shift ;;
	-h|--help) fUsage; exit 0 ;;
	*) fDie "unknown option: $1 (try --help)" ;;
esac; done

[[ "${RELEASE}" == "stable" || "${RELEASE}" == "dev" ]] || fDie "--release must be stable or dev"
[[ "${TARGET}"  == "user"   || "${TARGET}"  == "system" ]] || fDie "--target must be user or system"

echo

#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Figure out what to fetch and where to put it.

case "$(uname -s)" in
	Linux)   os="linux" ;;
	Darwin)  os="darwin" ;;
	FreeBSD) os="freebsd" ;;
	*) fDie "unsupported OS '$(uname -s)'. Windows: use the installer .exe from the Releases page." ;;
esac

if [[ -z "${ARCH}" ]]; then
	case "$(uname -m)" in
		x86_64|amd64)  ARCH="x86_64" ;;
		aarch64|arm64) ARCH="arm64" ;;
		*) fDie "unsupported architecture '$(uname -m)' (override with --arch)" ;;
	esac
fi
[[ "${ARCH}" == "x86_64" || "${ARCH}" == "arm64" ]] || fDie "--arch must be x86_64 or arm64"

if [[ "${TARGET}" == "user" ]]; then
	destDir="${HOME}/.local/bin"
else
	destDir="/usr/local/bin"
fi
destPath="${destDir}/${PKG}"

command -v curl >/dev/null || fDie "curl is required"
if command -v sha256sum >/dev/null; then
	shaCmd="sha256sum"
elif command -v shasum >/dev/null; then
	shaCmd="shasum -a 256"
else
	fDie "sha256sum or shasum is required"
fi

fEcho "Looking up the latest ${RELEASE} release"
if [[ "${RELEASE}" == "stable" ]]; then
	releaseJson="$(curl -fsSL "${API}/latest")" || fDie "could not reach the GitHub API (offline, or rate-limited?)"
else
	releaseJson="$(curl -fsSL "${API}?per_page=1")" || fDie "could not reach the GitHub API (offline, or rate-limited?)"
fi
tag="$(printf '%s' "${releaseJson}" | grep -m1 '"tag_name"' | sed 's/.*: *"//; s/".*//')"
[[ -n "${tag}" ]] || fDie "could not determine the ${RELEASE} release tag"

asset="${PKG}-${os}-${ARCH}"
url="https://github.com/${REPO}/releases/download/${tag}/${asset}"

## Already current? Then there is nothing to do.
if [[ -x "${destPath}" ]]; then
	haveVer="$("${destPath}" --version 2>/dev/null || true)"
	if [[ "${haveVer}" == "${tag}" ]]; then
		fEcho "${destPath} is already ${tag}; nothing to do"
		echo
		exit 0
	fi
fi

#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Say the plan, get a yes, then do it.

fEcho_Clean ""
fEcho "Plan"
fEcho_Clean "    Release: ${tag} (${RELEASE})"
fEcho_Clean "    Download: ${url}"
fEcho_Clean "    Verify: sha256 against the release's checksums.txt"
if [[ -x "${destPath}" ]]; then
	fEcho_Clean "    Install: ${destPath} (replacing ${haveVer:-an unknown version})"
else
	fEcho_Clean "    Install: ${destPath}"
fi
[[ "${TARGET}" == "system" && "$(id -u)" != "0" ]] && fEcho_Clean "    Uses sudo for the final copy."
fEcho_Clean ""

if ((! ASSUME_YES)); then
	read -r -p "Proceed? [y/N] " answer
	case "${answer}" in y|Y|yes|YES) : ;; *) fEcho "aborted; nothing was touched"; echo; exit 1 ;; esac
	fEcho_Clean ""
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

fEcho "Downloading ${asset} ${tag}"
curl -fSL --progress-bar -o "${work}/${asset}" "${url}" || fDie "download failed: ${url}"
curl -fsSL -o "${work}/checksums.txt" "https://github.com/${REPO}/releases/download/${tag}/checksums.txt" \
	|| fDie "download failed: checksums.txt for ${tag}"

fEcho "Verifying checksum"
want="$(grep -E " \*?${asset}\$" "${work}/checksums.txt" | head -n1 | cut -d' ' -f1)"
[[ -n "${want}" ]] || fDie "no checksum for ${asset} in checksums.txt"
got="$(${shaCmd} "${work}/${asset}" | cut -d' ' -f1)"
[[ "${got}" == "${want}" ]] || fDie "checksum mismatch (expected ${want}, got ${got})"

fEcho "Installing to ${destPath}"
chmod 0755 "${work}/${asset}"
if [[ "${TARGET}" == "system" && "$(id -u)" != "0" ]]; then
	sudo install -m 0755 "${work}/${asset}" "${destPath}"
else
	mkdir -p "${destDir}"
	install -m 0755 "${work}/${asset}" "${destPath}"
fi

fEcho "Installed: $("${destPath}" --version)"
case ":${PATH}:" in
	*":${destDir}:"*) : ;;
	*) fEcho "NOTE: ${destDir} is not in your PATH" ;;
esac

echo
