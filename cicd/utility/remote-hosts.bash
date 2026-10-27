#!/usr/bin/env bash

#  shellcheck disable=2016  ## 'Expressions don't expand in single quotes.' Some are meant for the far side.

##	Purpose: The Other hosts step of cicd.bash. Runs a release build on each test
##	box and checks its answers against the native build's.
##	- Syntax: remote-hosts.bash [--wrap WORD]... BOX|PLATFORM|SSH_TARGET[|ROOT_TARGET] ...
##	  e.g. "vmFreeBSD|freebsd-x86_64|bsdtest@vmFreeBSD|root@vmFreeBSD". PLATFORM
##	  picks the build, dist/APP-PLATFORM, and a case in fPlatformId.
##	- ROOT_TARGET, where the platform has a package in fPackageId, a FreeBSD
##	  .pkg or a .deb, installs it, runs the same cases with the installed
##	  binary, and removes it. A package that's already installed, or a binary
##	  already in its place, is a SKIP, so nobody's install is touched. Without
##	  ROOT_TARGET the package is a SKIP.
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
##	- A windows-* box logs in to cmd. Its cases run from a .cmd file, PowerShell
##	  goes over encoded, and files go by scp, to a work folder under the login's
##	  %TEMP%. Its ROOT_TARGET is an elevated login, which runs the setup .exe
##	  through remote-setup.ps1 with the machine PATH saved and put back.
##	- On darwin-x86_64 there's no package, so install.bash is run in its place, as
##	  the box's own user, with a curl that hands it this build as a release.
##	- From cicd.bash: CICD_APP, CICD_DIST, CICD_REF_BIN, CICD_CROSS_RAN, and
##	  CICD_RUN_TMP, the run's temp folder, which it removes.
##	  CICD_SSH and CICD_SCP stand in for ssh and scp in the tests.
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
here="$(dirname "${self}")"
read -r -a sshCmd <<<"${CICD_SSH:-ssh}"
sshCmd+=(-o BatchMode=yes -o ConnectTimeout=10)
read -r -a scpCmd <<<"${CICD_SCP:-scp}"
scpCmd+=(-q -o BatchMode=yes -o ConnectTimeout=10)
declare -ri rcPass=0 rcFail=10 rcSkip=77

## The test ID for each platform's check, per the harness's rule.
fPlatformId(){
	case "$1" in
		freebsd-x86_64) echo dee6x ;;
		windows-x86_64) echo defm6 ;;
		darwin-x86_64) echo defmk ;;
		darwin-universal) echo defmm ;;
		linux-arm64) echo defmy ;;
		*) return 1 ;;
	esac
}

## The package each platform installs, as a glob in dist, and its check's ID.
## install.bash means the repo's own installer.
fPackageId(){
	case "$1" in
		freebsd-x86_64) echo "dee9x ${app}-*-$1.pkg" ;;
		windows-x86_64) echo "defm7 ${app}-$1-setup.exe" ;;
		darwin-x86_64) echo "defmn install.bash" ;;
		linux-arm64) echo "defmz ${app}_*_arm64.deb" ;;
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
	local rootTarget="$1" pkgFile="$2" pkgHome="${work}/pkg-home" rc=0 got ext bin doc has add del delYes
	[[ -n "${rootTarget}" ]] || { echo "SKIP no root login for ${box}"; return; }
	[[ -n "${pkgFile}" ]] || { echo "FAIL no package in ${dist}"; return; }
	## FreeBSD's pkg, or dpkg for a .deb.
	ext="${pkgFile##*.}"
	if [[ "${ext}" == deb ]]; then
		bin="/usr/bin/${app}" doc="/usr/share/doc/${app}" has="dpkg -s '${app}' >/dev/null 2>&1"
		add="dpkg -i" del="dpkg -P" delYes=""
	else
		bin="/usr/local/bin/${app}" doc="/usr/local/share/licenses/${app}" has="pkg info -e '${app}'"
		add="pkg add" del="pkg delete" delYes=" -y"
	fi
	"${sshCmd[@]}" "${target}" "cat >'${work}/${app}.${ext}'" <"${pkgFile}" || { echo "FAIL package copy failed"; return; }
	"${sshCmd[@]}" "${rootTarget}" "if ${has}; then exit 77; fi; [ ! -e '${bin}' ] || exit 78
		ASSUME_ALWAYS_YES=yes DEBIAN_FRONTEND=noninteractive nice -n 19 ${add} '${work}/${app}.${ext}'" </dev/null >/dev/null 2>&1 || rc=$?
	case "${rc}" in
		0) ;;
		77) echo "SKIP ${app} is already installed on ${box}, so it's left alone"; return ;;
		78) echo "SKIP ${bin} on ${box} isn't from the package, so it's left alone"; return ;;
		*) echo "FAIL ${add} exit ${rc}"; return ;;
	esac
	got="$(fCases | "${sshCmd[@]}" "${rootTarget}" "mkdir '${pkgHome}' && cd '${pkgHome}' && HOME='${pkgHome}' XDG_CONFIG_HOME='${pkgHome}/.config' TZ=UTC nice -n 19 sh -s '${bin}'" 2>&1)" || true
	got="${got//"${pkgHome}"/HOME}"
	## Removed either way, and nothing of it left behind.
	rc=0; "${sshCmd[@]}" "${rootTarget}" "rm -rf -- '${pkgHome}'; ASSUME_ALWAYS_YES=yes nice -n 19 ${del}${delYes} '${app}' >/dev/null || exit 1
		! ${has} && [ ! -e '${bin}' ] && [ ! -e '${doc}' ]" </dev/null >/dev/null 2>&1 || rc=$?
	if [[ "${got}" != "$(<"${want}")" ]]; then
		echo "FAIL installed package answers differ from the native build's"
		diff <(cat "${want}") <(printf '%s\n' "${got}") | head -40 >&2 || true
	elif ((rc)); then echo "FAIL ${del} left the package or its files on ${box}"
	else echo PASS; fi
}

## One install.bash run. Reads fInstaller's locals.
fInstallRun(){ "${sshCmd[@]}" "${target}" "cd '${inst}' && HOME='${inst}/home' TMPDIR='${inst}/tmp' TZ=UTC PATH='${inst}/shim':\"\$PATH\" nice -n 19 bash ./install.bash -y" </dev/null 2>&1; }

## install.bash, as the box's own user, in a HOME and TMPDIR of its own, with a
## curl that hands out this build as the only release. A second run should find
## it current. Reads fOne's locals. Prints the result word and any reason.
fInstaller(){
	local script="$1" inst="${work}/inst" stage pkg ver tag sum first="" again="" left="" got rc1=0 rc2=0
	[[ -n "${script}" ]] || { echo "FAIL no install.bash"; return; }
	pkg="$(sed -n 's/^PKG="\(.*\)"$/\1/p' "${script}")"
	## The native build's --version line, so the tag is the one it reports.
	ver="$(sed -n 2p "${want}")"; read -r _ tag _ <<<"${ver}"
	read -r sum _ < <(sha256sum "${bin}")
	stage="$(dirname "${want}")/inst-${box}-${platform}"
	mkdir -p "${stage}/shim"
	cp "${script}" "${stage}/install.bash"
	printf '%s  %s\n' "${sum}" "${pkg}-${platform}" >"${stage}/shim/checksums.txt"
	printf '[\n  {\n    "tag_name": "%s",\n    "draft": false,\n    "prerelease": false\n  }\n]\n' "${tag}" >"${stage}/shim/releases.json"
	cat >"${stage}/shim/curl" <<-EOF
		#!/bin/sh
		d="\$(cd "\$(dirname "\$0")" && pwd)"; out=""; url=""
		while [ \$# -gt 0 ]; do case "\$1" in -o) out="\$2"; shift 2 ;; -*) shift ;; *) url="\$1"; shift ;; esac; done
		case "\$url" in
			*api.github.com*) cat "\$d/releases.json" ;;
			*/checksums.txt) cp "\$d/checksums.txt" "\$out" ;;
			*) cp "\$d/../../${app}" "\$out" ;;
		esac
	EOF
	chmod +x "${stage}/shim/curl"
	tar -C "${stage}" -cf - . | "${sshCmd[@]}" "${target}" "mkdir '${inst}' '${inst}/home' '${inst}/tmp' && tar -xf - -C '${inst}'" >/dev/null 2>&1 || { echo "FAIL install.bash copy failed"; return; }
	first="$(fInstallRun)" || rc1=$?
	again="$(fInstallRun)" || rc2=$?
	left="$("${sshCmd[@]}" "${target}" "ls -A '${inst}/tmp'" </dev/null 2>&1)" || left="can't list ${inst}/tmp"
	got="$(fCases | "${sshCmd[@]}" "${target}" "mkdir '${inst}/cases' && cd '${inst}/cases' && HOME='${inst}/cases' XDG_CONFIG_HOME='${inst}/cases/.config' TZ=UTC nice -n 19 sh -s '${inst}/home/.local/bin/${pkg}'" 2>&1)" || true
	got="${got//"${inst}/cases"/HOME}"
	if ((rc1)) || [[ "${first}" != *"Release: ${tag} (stable)"* || "${first}" != *"Installed: ${ver}"* ]]; then echo "FAIL install.bash didn't install ${tag} (exit ${rc1})"; printf '%s\n' "${first}"
	elif ((rc2)) || [[ "${again}" != *"is already ${tag}; nothing to do"* ]]; then echo "FAIL a second install.bash run didn't find it current (exit ${rc2})"; printf '%s\n' "${again}"
	elif [[ -n "${left}" ]]; then echo "FAIL install.bash left ${left//$'\n'/ } in its TMPDIR"
	elif [[ "${got}" != "$(<"${want}")" ]]; then
		echo "FAIL the installed binary's answers differ from the native build's"
		diff <(cat "${want}") <(printf '%s\n' "${got}") | head -40 || true
	else echo PASS; fi
}

## Windows boxes log in to cmd. PowerShell goes over encoded, the cases run
## from a .cmd file, and files go by scp. The work folder is under the login's
## %TEMP%, with no spaces in it, since cmd's quoting is no help over ssh.
fWinPs(){ "${sshCmd[@]}" "$1" "powershell -NoProfile -NonInteractive -EncodedCommand $(printf '%s' "$2" | iconv -t UTF-16LE | base64 -w0)" </dev/null 2>/dev/null | tr -d '\r'; }
fWinWorkOk(){ [[ "$1" =~ ^[A-Za-z]:\\[^\'\"\ ]*\\${app}\\[0-9]{8}-[0-9]{6}_[0-9]{3}$ && "$1" != *..* ]]; }
fWinCopy(){ local target="$1" work="$2" file; shift 2; for file in "$@"; do "${scpCmd[@]}" "${file}" "${target}:${work//\\//}/" || return 1; done; }

## Makes the work folder, after removing ours there older than 2 days.
fWinWork(){
	local ps
	ps="$(cat <<-'EOF'
		$ErrorActionPreference = 'Stop'; $t = Join-Path $env:TEMP '@APP@'; New-Item -ItemType Directory -Force -Path $t | Out-Null
		Get-ChildItem -LiteralPath $t -Directory | Where-Object { $_.Name -match '^\d{8}-\d{6}_\d{3}$' -and $_.LastWriteTime -lt (Get-Date).AddDays(-2) -and -not ($_.Attributes -band 'ReparsePoint') } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
		$s = Get-Date -Format 'yyyyMMdd-HHmmss'; for ($n = 1; $n -lt 1000; $n++) { $w = Join-Path $t ('{0}_{1:D3}' -f $s, $n); try { New-Item -ItemType Directory -Path $w | Out-Null; break } catch { $w = '' } }; $w
	EOF
	)"
	fWinPs "$1" "${ps//@APP@/"${app}"}"
}

fWinRemove(){
	local ps
	fWinWorkOk "$2" || return 1
	ps="$(cat <<-'EOF'
		$w = '@WORK@'; $t = Join-Path $env:TEMP '@APP@'
		if ($w.StartsWith($t + '\') -and $w -match '\\\d{8}-\d{6}_\d{3}$' -and (Test-Path -LiteralPath $w) -and -not ((Get-Item -LiteralPath $w -Force).Attributes -band 'ReparsePoint')) { Remove-Item -LiteralPath $w -Recurse -Force; 'removed' }
	EOF
	)"
	ps="${ps//@APP@/"${app}"}"
	[[ "$(fWinPs "$1" "${ps//@WORK@/"$2"}")" == removed ]]
}

## fCases as cases.cmd in DIR, with each piped input as a file beside it. %1 is
## the exe, and the folder the .cmd is in stands in for HOME.
fCasesCmd(){
	local dir="$1" kind rest arg text line n=0 c
	local -a args
	mkdir -p "${dir}"
	{
		printf '@echo off\r\nsetlocal\r\nset "b=%%~1"\r\ncd /d "%%~dp0"\r\nset "USERPROFILE=%%CD%%"\r\nset "HOME=%%CD%%"\r\nset "XDG_CONFIG_HOME=%%CD%%\\.config"\r\n'
		while read -r kind rest; do
			[[ "${kind}" == c || "${kind}" == p ]] || continue
			eval "args=(${rest})"   ## fCases' own fixed text, quoted the sh way.
			line=""
			if [[ "${kind}" == p ]]; then
				n=$((n + 1)); printf '%s' "${args[0]}" >"${dir}/in${n}.txt"
				text="${args[0]} | ${args[*]:1}"; args=("${args[@]:1}")
			else text="${args[*]}"; fi
			for arg in "${args[@]}"; do
				arg="${arg//%/%%}"
				if [[ -z "${arg}" || "${arg}" == *[[:space:]]* ]]; then line+=" \"${arg}\""; else line+=" ${arg}"; fi
			done
			[[ "${kind}" == p ]] && line+=" <in${n}.txt"
			text="${text//%/%%}"; for c in '^' '&' '|' '<' '>'; do text="${text//"${c}"/^${c}}"; done
			printf 'echo == %s\r\n"%%b%%"%s 2>&1\r\necho rc=%%errorlevel%%\r\n' "${text}" "${line}"
		done < <(fCases)
	} >"${dir}/cases.cmd"
}

## Windows answers: echo's CRLF goes, the work folder reads as HOME, with / in
## the config note, and the date after the build number goes on both sides,
## since Go there takes the box's own time zone, not TZ.
fWinNorm(){
	local work="$1" text
	text="$(cat)"; text="${text//$'\r'/}"
	[[ -z "${work}" ]] || text="${text//"${work}"/HOME}"
	printf '%s\n' "${text}" | sed -E '/^note: created default config HOME/ y#\\#/#; s/^(convert-base-v2 .* build [0-9a-z]+) \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$/\1/'
}

## The setup, run elevated by remote-setup.ps1. Reads fOneWindows' locals.
## Prints the result word and any reason.
fPackageWindows(){
	local rootTarget="$1" pkgFile="$2" rwork="" out got why=""
	[[ -n "${rootTarget}" ]] || { echo "SKIP no admin login for ${box}"; return; }
	[[ -n "${pkgFile}" ]] || { echo "FAIL no setup .exe in ${dist}"; return; }
	rwork="$(fWinWork "${rootTarget}")" || true
	fWinWorkOk "${rwork}" || { echo "FAIL odd work folder for the setup: ${rwork}"; return; }
	if ! fWinCopy "${rootTarget}" "${rwork}" "${pkgFile}" "${here}/remote-setup.ps1" "${cases}"/*; then why="FAIL setup copy failed"
	else
		out="$("${sshCmd[@]}" "${rootTarget}" "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ${rwork}\\remote-setup.ps1 -Setup ${rwork}\\${pkgFile##*/} -Cases ${rwork}\\cases.cmd" </dev/null 2>/dev/null | tr -d '\r')" || true
		got="$("${sshCmd[@]}" "${rootTarget}" "type ${rwork}\\installed.txt" </dev/null 2>/dev/null | fWinNorm "${rwork}")" || true
		if grep -q '^RESULT SKIP' <<<"${out}"; then why="SKIP $(sed -n 's/^RESULT SKIP //p' <<<"${out}" | head -1)"
		elif ! grep -qx 'DONE' <<<"${out}"; then why="FAIL the setup check didn't finish"
		elif grep -q '^RESULT FAIL' <<<"${out}"; then why="FAIL $(sed -n 's/^RESULT FAIL //p' <<<"${out}" | head -1)"
		elif ! grep -qx 'FINAL PATH as before' <<<"${out}"; then why="FAIL the machine PATH differs from before"
		elif [[ "${got}" != "$(fWinNorm "" <"${want}")" ]]; then why="FAIL installed exe answers differ from the native build's"
		else why=PASS; fi
	fi
	fWinRemove "${rootTarget}" "${rwork}" || why+="; could not remove ${rwork}"
	echo "${why}"
	grep '^RESULT\|^FINAL' <<<"${out:-}" || true
	[[ "${why}" != "FAIL installed exe answers differ"* ]] || diff <(fWinNorm "" <"${want}") <(printf '%s\n' "${got}") | head -40 || true
}

## fOne for a Windows box.
fOneWindows(){
	local box="$1" platform="$2" target="$3" bin="$4" want="$5" rootTarget="${6:-}" pkgFile="${7:-}" pkgResult="${8:-}" work="" got rc cases
	if ! "${sshCmd[@]}" "${target}" ver </dev/null >/dev/null 2>&1; then
		echo "${box}: no answer from ${target}"; return "${rcSkip}"
	fi
	work="$(fWinWork "${target}")" || true
	fWinWorkOk "${work}" || { echo "${box}: odd work folder: ${work}"; return "${rcFail}"; }
	trap 'trap - RETURN; fWinRemove "${target}" "${work}" || echo "${box}: could not remove ${work}"' RETURN
	echo "${box}: work folder ${work}"
	cases="$(dirname "${want}")/cmd-${box}"
	fCasesCmd "${cases}"
	fWinCopy "${target}" "${work}" "${cases}"/* || { echo "${box}: copy failed"; return "${rcFail}"; }
	"${scpCmd[@]}" "${bin}" "${target}:${work//\\//}/${app}.exe" || { echo "${box}: copy failed"; return "${rcFail}"; }
	got="$("${sshCmd[@]}" "${target}" "start /b /wait /belownormal cmd /d /c ${work}\\cases.cmd ${work}\\${app}.exe" </dev/null 2>/dev/null | fWinNorm "${work}")" || true
	rc="${rcPass}"
	if [[ "${got}" != "$(fWinNorm "" <"${want}")" ]]; then
		echo "${box}: answers differ from the native build's (< native, > ${platform})"
		diff <(fWinNorm "" <"${want}") <(printf '%s\n' "${got}") | head -40 || true
		rc="${rcFail}"
	fi
	if [[ -n "${pkgResult}" ]]; then fPackageWindows "${rootTarget}" "${pkgFile}" >"${pkgResult}" 2>&1; echo "${box}: setup $(head -1 "${pkgResult}")"; tail -n +2 "${pkgResult}"; fi
	return "${rc}"
}

## One box, inside its hold. Exits rcPass, rcFail or rcSkip. A package result,
## when asked for, goes to the file pkgResult.
fOne(){
	local box="$1" platform="$2" target="$3" bin="$4" want="$5" rootTarget="${6:-}" pkgFile="${7:-}" pkgResult="${8:-}" work="" base got rc
	[[ "${platform}" != windows-* ]] || { fOneWindows "$@"; return; }
	## The box's own temp root, for whatever shell it logs in with.
	base='"${TMPDIR:-/tmp}"'
	if ! "${sshCmd[@]}" "${target}" 'uname -sm' </dev/null >/dev/null 2>&1; then
		echo "${box}: no answer from ${target}"; return "${rcSkip}"
	fi
	## macOS's TMPDIR ends in a slash.
	work="$("${sshCmd[@]}" "${target}" "set -e; umask 077; t=${base}; t=\"\${t%/}/${app}\"; mkdir -p \"\$t\"
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
	if [[ -n "${pkgResult}" && "$(fPackageId "${platform}")" == *" install.bash" ]]; then fInstaller "${pkgFile}" >"${pkgResult}" 2>&1; echo "${box}: install.bash $(head -1 "${pkgResult}")"; tail -n +2 "${pkgResult}"
	elif [[ -n "${pkgResult}" ]]; then fPackage "${rootTarget}" "${pkgFile}" >"${pkgResult}" 2>&1; echo "${box}: package $(head -1 "${pkgResult}")"; tail -n +2 "${pkgResult}"; fi
	return "${rc}"
}

if [[ "${1:-}" == --one ]]; then shift; rc=0; fOne "$@" || rc=$?; exit "${rc}"; fi

## Each box in turn, with one line per check at the end.
fMain(){
	local entry box platform target rootTarget id bin rc failed=0 scratch want pkgId pkgGlob pkgFile pkgResult pkgWord pkgWhat
	local -a summary=() wrap=() held=() pkgArgs=() pkgFound=()
	while [[ "${1:-}" == --wrap ]]; do wrap+=("${2-}"); shift 2 || shift; done
	if ((${#wrap[@]} == 0)); then echo "WARNING: no --wrap, so the boxes are used without the host lock"; fi
	## Inside the run's temp folder, which cicd.bash removes.
	scratch="${CICD_RUN_TMP:?no CICD_RUN_TMP}/remote-hosts"
	mkdir "${scratch}"
	for entry in "$@"; do
		IFS='|' read -r box platform target rootTarget <<<"${entry}"
		pkgId=""; pkgArgs=(); pkgWhat=package
		if read -r pkgId pkgGlob < <(fPackageId "${platform}"); then
			# shellcheck disable=SC2206  ## The glob is meant.
			pkgFound=("${dist}"/${pkgGlob}); pkgFile=""
			[[ "${pkgGlob}" != install.bash ]] || { pkgFound=("${here}/../../install.bash"); pkgWhat=install.bash; }
			[[ -f "${pkgFound[0]}" ]] && pkgFile="$(realpath "${pkgFound[0]}")"
			pkgResult="${scratch}/${box}-${platform}.pkg"; : >"${pkgResult}"
			pkgArgs=("${rootTarget}" "${pkgFile}" "${pkgResult}")
		fi
		id="$(fPlatformId "${platform}")" || { summary+=("FAIL ----- ${platform} on ${box}, no case for it in remote-hosts.bash"); failed=1; continue; }
		bin="${dist}/${app}-${platform}"; [[ "${platform}" != windows-* ]] || bin+=".exe"
		if [[ "${CICD_CROSS_RAN:-1}" != "1" ]]; then
			summary+=("SKIP ${id} ${platform} on ${box}, cross + package didn't run"); [[ -z "${pkgId}" ]] || summary+=("SKIP ${pkgId} ${platform} ${pkgWhat} on ${box}, cross + package didn't run")
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
				PASS)   summary+=("PASS ${pkgId} ${platform} ${pkgWhat} on ${box}") ;;
				FAIL*)  summary+=("FAIL ${pkgId} ${platform} ${pkgWhat} on ${box}, ${pkgWord#FAIL }"); failed=1 ;;
				SKIP*)  summary+=("SKIP ${pkgId} ${platform} ${pkgWhat} on ${box}, ${pkgWord#SKIP }"); echo "WARNING: ${box} ${pkgWhat} skipped, ${pkgWord#SKIP }" ;;
				*)      summary+=("SKIP ${pkgId} ${platform} ${pkgWhat} on ${box}, the box didn't get that far") ;;
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
##		- 2026-10-26 JC: Windows, and its setup .exe.
##		- 2026-10-26 JC: macOS, x86_64 and universal, and install.bash there.
##		- 2026-10-26 JC: Linux arm64, and its .deb.
