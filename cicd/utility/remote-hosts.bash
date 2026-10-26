#!/usr/bin/env bash

#  shellcheck disable=2016  ## 'Expressions don't expand in single quotes.' Some are meant for the far side.

##	Purpose: The Other hosts step of cicd.bash. Runs a release build on each test
##	box and checks its answers against the native build's.
##	- Syntax: remote-hosts.bash [--wrap WORD]... BOX|PLATFORM|SSH_TARGET[|ROOT_TARGET] ...
##	  e.g. "vmFreeBSD|freebsd-x86_64|bsdtest@vmFreeBSD|root@vmFreeBSD". PLATFORM
##	  picks the build, dist/APP-PLATFORM, and a case in fPlatformId.
##	- ROOT_TARGET, where the platform has a package in fPackageId, installs it,
##	  runs the same cases with the installed binary, and removes it. A package
##	  that's already installed, or a binary already in its place, is a SKIP, so
##	  nobody's install is touched. Without ROOT_TARGET the package is a SKIP.
##	- The --wrap words make a command that holds a box for its turn, with {} for
##	  the box and the command to run after them. It takes the box in the host
##	  lock and wakes a VM, then puts it back as it was found. Without one the
##	  box is used as it is.
##	- A box that doesn't answer, or can't be had, is a SKIP with a warning, and
##	  the rest go on. Any FAIL fails the step.
##	- The box gets a work folder under its temp root, TMPDIR/APP/YYYYmmDD-HHMMSS_NNN,
##	  removed at the end. Folders of ours there older than 2 days are removed too.
##	- Both sides run the same cases with HOME in a scratch folder, so neither
##	  touches a user config, and TZ=UTC, since --version shows a local date.
##	  That folder reads as HOME in the answers.
##	- From cicd.bash: CICD_APP, CICD_DIST, CICD_REF_BIN, CICD_CROSS_RAN, and
##	  CICD_RUN_TMP, the run's temp folder, which it removes.
##	  CICD_SSH stands in for ssh in the tests.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
app="${CICD_APP:-convert-base-v2}"
dist="${CICD_DIST:-lib/dist}"
refBin="${CICD_REF_BIN:-lib/bin/${app}-release}"
read -r -a sshCmd <<<"${CICD_SSH:-ssh}"
sshCmd+=(-o BatchMode=yes -o ConnectTimeout=10)
declare -ri rcPass=0 rcFail=10 rcSkip=77

## The test ID for each platform's check, per the harness's rule.
fPlatformId(){
	case "$1" in
		freebsd-x86_64) echo dee6x ;;
		*) return 1 ;;
	esac
}

## The package each platform installs, as a glob in dist, and its check's ID.
fPackageId(){
	case "$1" in
		freebsd-x86_64) echo "dee9x ${app}-*-$1.pkg" ;;
		*) return 1 ;;
	esac
}

## The cases, as a POSIX sh script fed on stdin, with the binary as $1. ASCII only.
fCases(){
	cat <<-'EOF'
		b="$1"
		c(){ printf '== %s\n' "$*"; "$b" "$@" 2>&1; printf 'rc=%s\n' "$?"; }
		p(){ input="$1"; shift; printf '== %s | %s\n' "${input}" "$*"; printf '%s' "${input}" | "$b" "$@" 2>&1; printf 'rc=%s\n' "$?"; }
		c --version
		c 255 16
		c --from 16 ff 2
		c -- -3.75 12
		c 123456789012345678901234567890 62
		c --from 62 2aYls9bkamJJSwhr0 10
		c --to-symbols "a b c" 1000
		c --precision 40 1 3
		c --list
		c --from nosuchbase 1
		p 'hello world' --from bytes - 64
		p 'aGVsbG8gd29ybGQ=' --from 64 - bytes
		p 'hello world' --from bytes - 85ps
	EOF
}

## Run the cases here, against the native build, in a fresh HOME.
fRunLocal(){
	local home="$1"
	mkdir "${home}"
	local out
	out="$(cd "${home}" && HOME="${home}" XDG_CONFIG_HOME="${home}/.config" TZ=UTC sh -s "$2" < <(fCases) 2>&1)" || true
	printf '%s\n' "${out//"${home}"/HOME}"
}

## The package, installed as root, runs the cases, and is removed. Reads fOne's
## locals. Prints the result word and any reason.
fPackage(){
	local rootTarget="$1" pkgFile="$2" pkgHome="${work}/pkg-home" bin="/usr/local/bin/${app}" rc=0 got
	[[ -n "${rootTarget}" ]] || { echo "SKIP no root login for ${box}"; return; }
	[[ -n "${pkgFile}" ]] || { echo "FAIL no package in ${dist}"; return; }
	"${sshCmd[@]}" "${target}" "cat >'${work}/${app}.pkg'" <"${pkgFile}" || { echo "FAIL package copy failed"; return; }
	"${sshCmd[@]}" "${rootTarget}" "if pkg info -e '${app}'; then exit 77; fi; [ ! -e '${bin}' ] || exit 78
		ASSUME_ALWAYS_YES=yes nice -n 19 pkg add '${work}/${app}.pkg'" </dev/null >/dev/null 2>&1 || rc=$?
	case "${rc}" in
		0) ;;
		77) echo "SKIP ${app} is already installed on ${box}, so it's left alone"; return ;;
		78) echo "SKIP ${bin} on ${box} isn't from the package, so it's left alone"; return ;;
		*) echo "FAIL pkg add exit ${rc}"; return ;;
	esac
	got="$(fCases | "${sshCmd[@]}" "${rootTarget}" "mkdir '${pkgHome}' && cd '${pkgHome}' && HOME='${pkgHome}' XDG_CONFIG_HOME='${pkgHome}/.config' TZ=UTC nice -n 19 sh -s '${bin}'" 2>&1)" || true
	got="${got//"${pkgHome}"/HOME}"
	## Removed either way, and nothing of it left behind.
	rc=0; "${sshCmd[@]}" "${rootTarget}" "rm -rf -- '${pkgHome}'; ASSUME_ALWAYS_YES=yes nice -n 19 pkg delete -y '${app}' >/dev/null || exit 1
		! pkg info -e '${app}' && [ ! -e '${bin}' ] && [ ! -e '/usr/local/share/licenses/${app}' ]" </dev/null >/dev/null 2>&1 || rc=$?
	if [[ "${got}" != "$(<"${want}")" ]]; then
		echo "FAIL installed package answers differ from the native build's"
		diff <(cat "${want}") <(printf '%s\n' "${got}") | head -40 >&2 || true
	elif ((rc)); then echo "FAIL pkg delete left the package or its files on ${box}"
	else echo PASS; fi
}

## One box, inside its hold. Exits rcPass, rcFail or rcSkip. A package result,
## when asked for, goes to the file pkgResult.
fOne(){
	local box="$1" platform="$2" target="$3" bin="$4" want="$5" rootTarget="${6:-}" pkgFile="${7:-}" pkgResult="${8:-}" work="" base got rc
	## The box's own temp root, for whatever shell it logs in with.
	base='"${TMPDIR:-/tmp}"'
	if ! "${sshCmd[@]}" "${target}" 'uname -sm' </dev/null >/dev/null 2>&1; then
		echo "${box}: no answer from ${target}"; return "${rcSkip}"
	fi
	work="$("${sshCmd[@]}" "${target}" "set -e; umask 077; t=${base}/${app}; mkdir -p \"\$t\"
		find \"\$t\" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*-[0-9]*_[0-9][0-9][0-9]' -mtime +2 -exec rm -rf {} + 2>/dev/null || true
		s=\$(date +%Y%m%d-%H%M%S); n=1
		while ! mkdir \"\$t/\${s}_\$(printf %03d \$n)\" 2>/dev/null; do n=\$((n + 1)); [ \$n -lt 1000 ]; done
		echo \"\$t/\${s}_\$(printf %03d \$n)\"" </dev/null)" || { echo "${box}: no work folder"; return "${rcFail}"; }
	## What comes back goes into an rm, so it has to look like ours.
	if ! [[ "${work}" =~ ^/[^\'\"\ ]*/${app}/[0-9]{8}-[0-9]{6}_[0-9]{3}$ && "${work}" != *..* ]]; then
		echo "${box}: odd work folder: ${work}"; return "${rcFail}"
	fi
	trap '"${sshCmd[@]}" "${target}" "[ ! -L \"${work}\" ] && rm -rf -- \"${work}\"" </dev/null >/dev/null 2>&1 || echo "${box}: could not remove ${work}"' RETURN
	echo "${box}: work folder ${work}"
	"${sshCmd[@]}" "${target}" "cat >'${work}/${app}' && chmod +x '${work}/${app}'" <"${bin}" || { echo "${box}: copy failed"; return "${rcFail}"; }
	got="$(fCases | "${sshCmd[@]}" "${target}" "cd '${work}' && HOME='${work}' XDG_CONFIG_HOME='${work}/.config' TZ=UTC nice -n 19 sh -s './${app}'" 2>&1)" || true
	got="${got//"${work}"/HOME}"
	rc="${rcPass}"
	if [[ "${got}" != "$(<"${want}")" ]]; then
		echo "${box}: answers differ from the native build's (< native, > ${platform})"
		diff <(cat "${want}") <(printf '%s\n' "${got}") | head -40 || true
		rc="${rcFail}"
	fi
	if [[ -n "${pkgResult}" ]]; then fPackage "${rootTarget}" "${pkgFile}" >"${pkgResult}" 2>&1; echo "${box}: package $(head -1 "${pkgResult}")"; tail -n +2 "${pkgResult}"; fi
	return "${rc}"
}

if [[ "${1:-}" == --one ]]; then shift; rc=0; fOne "$@" || rc=$?; exit "${rc}"; fi

## Each box in turn, with one line per check at the end.
fMain(){
	local entry box platform target rootTarget id bin rc failed=0 scratch want pkgId pkgGlob pkgFile pkgResult pkgWord
	local -a summary=() wrap=() held=() pkgArgs=() pkgFound=()
	while [[ "${1:-}" == --wrap ]]; do wrap+=("${2-}"); shift 2 || shift; done
	if ((${#wrap[@]} == 0)); then echo "WARNING: no --wrap, so the boxes are used without the host lock"; fi
	## Inside the run's temp folder, which cicd.bash removes.
	scratch="${CICD_RUN_TMP:?no CICD_RUN_TMP}/remote-hosts"
	mkdir "${scratch}"
	for entry in "$@"; do
		IFS='|' read -r box platform target rootTarget <<<"${entry}"
		pkgId=""; pkgArgs=()
		if read -r pkgId pkgGlob < <(fPackageId "${platform}"); then
			# shellcheck disable=SC2206  ## The glob is meant.
			pkgFound=("${dist}"/${pkgGlob}); pkgFile=""
			[[ -f "${pkgFound[0]}" ]] && pkgFile="$(realpath "${pkgFound[0]}")"
			pkgResult="${scratch}/${box}-${platform}.pkg"; : >"${pkgResult}"
			pkgArgs=("${rootTarget}" "${pkgFile}" "${pkgResult}")
		fi
		id="$(fPlatformId "${platform}")" || { summary+=("FAIL ----- ${platform} on ${box}, no case for it in remote-hosts.bash"); failed=1; continue; }
		bin="${dist}/${app}-${platform}"
		if [[ "${CICD_CROSS_RAN:-1}" != "1" ]]; then
			summary+=("SKIP ${id} ${platform} on ${box}, cross + package didn't run"); [[ -z "${pkgId}" ]] || summary+=("SKIP ${pkgId} ${platform} package on ${box}, cross + package didn't run")
			echo "WARNING: ${box} skipped, cross + package didn't run"; continue
		fi
		if [[ ! -f "${bin}" ]]; then summary+=("FAIL ${id} ${platform} on ${box}, no ${bin}"); failed=1; continue; fi
		if [[ ! -x "${refBin}" ]]; then summary+=("FAIL ${id} ${platform} on ${box}, no native build at ${refBin}"); failed=1; continue; fi
		## Absolute, since the hold may run it from elsewhere.
		bin="$(realpath "${bin}")"
		want="${scratch}/${platform}.want"
		[[ -f "${want}" ]] || fRunLocal "${scratch}/home-${platform}" "$(realpath "${refBin}")" >"${want}"
		echo "${box}: ${platform}"
		rc=0
		held=("${wrap[@]//\{\}/${box}}")
		"${held[@]}" bash "${self}" --one "${box}" "${platform}" "${target}" "${bin}" "${want}" "${pkgArgs[@]}" || rc=$?
		case "${rc}" in
			"${rcPass}") summary+=("PASS ${id} ${platform} on ${box}") ;;
			"${rcFail}") summary+=("FAIL ${id} ${platform} on ${box}"); failed=1 ;;
			"${rcSkip}") summary+=("SKIP ${id} ${platform} on ${box}, no answer"); echo "WARNING: ${box} skipped, no answer" ;;
			*)           summary+=("SKIP ${id} ${platform} on ${box}, couldn't have it (exit ${rc})"); echo "WARNING: ${box} skipped, the hold or the wake failed (exit ${rc})" ;;
		esac
		if [[ -n "${pkgId}" ]]; then
			pkgWord="$(head -1 "${pkgResult}")"
			case "${pkgWord}" in
				PASS)   summary+=("PASS ${pkgId} ${platform} package on ${box}") ;;
				FAIL*)  summary+=("FAIL ${pkgId} ${platform} package on ${box}, ${pkgWord#FAIL }"); failed=1 ;;
				SKIP*)  summary+=("SKIP ${pkgId} ${platform} package on ${box}, ${pkgWord#SKIP }"); echo "WARNING: ${box} package skipped, ${pkgWord#SKIP }" ;;
				*)      summary+=("SKIP ${pkgId} ${platform} package on ${box}, the box didn't get that far") ;;
			esac
		fi
	done
	echo
	printf '%s\n' "${summary[@]}"
	return "${failed}"
}
fMain "$@"


##	History:
##		- 2026-10-25 JC: Created. FreeBSD.
##		- 2026-10-25 JC: The FreeBSD .pkg, installed and removed as root.
