#!/usr/bin/env bash
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## install.bash
##
##	One-line installer for convert-base-v2 on Linux, FreeBSD, macOS, and WSL.
##	Downloads a release binary, verifies its checksum against the release's
##	checksums.txt, and installs it. States its plan and asks first.
##
##	Usage:
##		bash <(curl -fsSL https://raw.githubusercontent.com/jim-collier/convert-base-v2/main/install.bash) [options]
##	Options:
##		--release stable|dev ... stable = newest release (default), dev = newest including pre-releases
##		--target user|system ... user = ~/.local/bin (default), system = /usr/local/bin (may need sudo)
##		-y|--yes ............... skip the confirmation prompt
##		--version .............. print this installer's version
##		-h|--help .............. this help
##	Notes:
##		- Options take "--name value" or "--name=value".
##		- The OS and CPU are detected. With no stable release yet, stable takes the newest pre-release.
##		- Needs bash 3.2+, curl, and sha256sum or shasum.
##		- Windows: use install.ps1, or the installer .exe from the Releases page.
##		- Re-running is safe; an already-current install is left alone.
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••

##	Copyright (c) 2026 Bubbles
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

INSTALLER_VERSION="1.1.2"
PKG="convert-base-v2"
REPO="jim-collier/convert-base-v2"
API="https://api.github.com/repos/${REPO}/releases"

RELEASE="stable"
TARGET="user"
ASSUME_YES=0

fEcho(){ printf '[ %s ]\n' "$*"; }
fEcho_Clean(){ printf '%s\n' "$*"; }
fDie(){ printf '[ ERROR: %s ]\n' "$*" >&2; echo; exit 1; }

## Spelled out rather than scraped from the header above. The advertised way to
## run this is `bash <(curl ...)`, and there the source is a file descriptor the
## shell has already read, so scraping it prints nothing. Keep the two in step.
fUsage(){ cat <<'EOF'
Usage:
	bash <(curl -fsSL https://raw.githubusercontent.com/jim-collier/convert-base-v2/main/install.bash) [options]
Options:
	--release stable|dev ... stable = newest release (default), dev = newest including pre-releases
	--target user|system ... user = ~/.local/bin (default), system = /usr/local/bin (may need sudo)
	-y|--yes ............... skip the confirmation prompt
	--version .............. print this installer's version
	-h|--help .............. this help
Notes:
	- Options take "--name value" or "--name=value".
	- The OS and CPU are detected. With no stable release yet, stable takes the newest pre-release.
	- Needs bash 3.2+, curl, and sha256sum or shasum.
	- Windows: use install.ps1, or the installer .exe from the Releases page.
	- Re-running is safe; an already-current install is left alone.
EOF
}

while (($#)); do case "$1" in
	--release)   RELEASE="${2:-}"; shift; (($#)) && shift ;;
	--release=*) RELEASE="${1#*=}"; shift ;;
	--target)    TARGET="${2:-}";  shift; (($#)) && shift ;;
	--target=*)  TARGET="${1#*=}"; shift ;;
	-y|--yes)    ASSUME_YES=1;     shift ;;
	--version)   echo "${PKG} installer v${INSTALLER_VERSION}"; exit 0 ;;
	-h|--help)   fUsage; exit 0 ;;
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
	*) fDie "unsupported OS '$(uname -s)'. Windows: use install.ps1, or the installer .exe from the Releases page." ;;
esac

case "$(uname -m)" in
	x86_64|amd64)  ARCH="x86_64" ;;
	aarch64|arm64) ARCH="arm64" ;;
	*) fDie "unsupported CPU '$(uname -m)'. Builds exist for x86_64 and arm64." ;;
esac

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

fEcho "Looking up the newest ${RELEASE} release"
## The list, not releases/latest, which is stable-only and 404s while every
## release is a pre-release. The API returns one field per line.
releaseJson="$(curl -fsSL "${API}?per_page=100")" || fDie "couldn't reach the GitHub API (offline, or rate-limited?)"
## Tag, then 1 for a pre-release. Drafts aren't public, but skip them anyway.
fListReleases(){
	awk '
		/^ *"tag_name": *"/ { tag = $0; sub(/^ *"tag_name": *"/, "", tag); sub(/".*/, "", tag) }
		/^ *"draft": *true/ { tag = "" }
		/^ *"prerelease": *(true|false)/ { if (tag != "") print tag " " ($0 ~ /true/ ? 1 : 0); tag = "" }
	' <<<"${releaseJson}"
}
## Newest by version, never by listing order. A pre-release sorts below its
## final (3.1.0-beta2 < 3.1.0) and digit runs compare as numbers (beta2 <
## beta10), which sort -V gets wrong and isn't on every BSD.
fNewest(){
	awk '{
		ver = $1; sub(/^v/, "", ver); pre = ""
		if (index(ver, "-")) { pre = substr(ver, index(ver, "-") + 1); ver = substr(ver, 1, index(ver, "-") - 1) }
		n = split(ver, part, ".")
		key = sprintf("%08d%08d%08d", part[1], (n > 1 ? part[2] : 0), (n > 2 ? part[3] : 0))
		if (pre == "") { key = key "1" } else {
			key = key "0"
			while (match(pre, /[0-9]+/)) { key = key substr(pre, 1, RSTART - 1) sprintf("%08d", substr(pre, RSTART, RLENGTH)); pre = substr(pre, RSTART + RLENGTH) }
			key = key pre
		}
		print key " " $1
	}' | LC_ALL=C sort -r | awk 'NR == 1 { print $2 }'
}
releases="$(fListReleases || true)"
if [[ "${RELEASE}" == "stable" ]]; then
	tag="$(awk '$2 == 0' <<<"${releases}" | fNewest || true)"
	if [[ -z "${tag}" ]]; then
		tag="$(fNewest <<<"${releases}" || true)"
		[[ -z "${tag}" ]] || fEcho "No stable release yet, so this takes the newest pre-release"
	fi
else
	tag="$(fNewest <<<"${releases}" || true)"
fi
[[ -n "${tag}" ]] || fDie "couldn't determine the ${RELEASE} release tag"

asset="${PKG}-${os}-${ARCH}"
url="https://github.com/${REPO}/releases/download/${tag}/${asset}"

## Already current? Then there is nothing to do.
if [[ -x "${destPath}" ]]; then
	## "convert-base-v2 v3.1.0 build dbrk8", then the copyright. Before 3.0.1 it had no name in front.
	haveVer="$("${destPath}" --version 2>/dev/null || true)"; haveVer="${haveVer%%$'\n'*}"; haveVer="${haveVer#"${PKG} "}"
	if [[ "${haveVer%% *}" == "${tag}" ]]; then
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
	## Ctrl-D or no terminal reads as no.
	answer=""; read -r -p "Proceed? [y/N] " answer || true
	case "${answer}" in y|Y|yes|YES) : ;; *) fEcho "aborted; nothing was touched"; echo; exit 1 ;; esac
	fEcho_Clean ""
fi

tmpRoot="$(cd "${TMPDIR:-/tmp}" && pwd -P)" || fDie "no temp folder at ${TMPDIR:-/tmp}"
work="$(mktemp -d "${tmpRoot}/cbv2-install.XXXXXX")" || fDie "couldn't make a work folder in ${tmpRoot}"
## Removes only the one folder it made, under the one temp folder it named.
fWorkGone(){
	case "${work}" in
		"${tmpRoot}"/cbv2-install.?*) if [[ -d "${work}" && ! -L "${work}" && "${work}" != *..* ]]; then rm -rf -- "${work}"; fi ;;
	esac
}
trap fWorkGone EXIT

fEcho "Downloading ${asset} ${tag}"
curl -fSL --progress-bar -o "${work}/${asset}" "${url}" || fDie "download failed: ${url}"
curl -fsSL -o "${work}/checksums.txt" "https://github.com/${REPO}/releases/download/${tag}/checksums.txt" \
	|| fDie "download failed: checksums.txt for ${tag}"

fEcho "Verifying checksum"
want="$(grep -m1 -E " \*?${asset}\$" "${work}/checksums.txt" | cut -d' ' -f1 || true)"
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

nowVer="$("${destPath}" --version)"; fEcho "Installed: ${nowVer%%$'\n'*}"
case ":${PATH}:" in
	*":${destDir}:"*) : ;;
	*) fEcho "NOTE: ${destDir} isn't in your PATH" ;;
esac

echo
