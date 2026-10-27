#!/usr/bin/env bash

#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

##	Purpose:
##		- Runs the Windows setup .exe under Wine against a few machine PATHs, and checks
##		  what install, a second install and uninstall leave behind.
##		- The setup once replaced a PATH longer than 1024 characters with its own folder
##		  (2026102519371715), so the first case is a long one.
##		- Builds its own setup from installer.nsi, with a stub payload, so it needs no
##		  release build.
##	Syntax:
##		cicd/utility/wine-setup-path.bash WORKDIR [NSI]
##		  WORKDIR  an empty folder it may fill. The Wine prefix there takes about 1.5 GB,
##		           so the caller removes it after.
##		  NSI      the installer script, cicd/utility/nsis/installer.nsi by default.
##	Output:
##		- One line per case that went wrong, and exit 1. Nothing and exit 0 when all pass.
##		- Exit 3 when wine or makensis is missing, and 2 when the setup can't be built
##		  or Wine can't start.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

meDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="${1:?usage: wine-setup-path.bash WORKDIR [NSI]}"
nsi="${2:-${meDir}/nsis/installer.nsi}"
envKey='HKLM\System\CurrentControlSet\Control\Session Manager\Environment'
instDir='C:\Program Files\convert-base-v2'

command -v wine >/dev/null 2>&1 && command -v makensis >/dev/null 2>&1 || exit 3
[[ -d "${work}" ]] || { printf 'no work folder: %s\n' "${work}"; exit 2; }
work="$(cd "${work}" && pwd)"

## No window, no mono or gecko prompt, and nothing of the user's Wine touched.
export WINEPREFIX="${work}/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=,winemenubuilder.exe=d" TMPDIR="${work}" TEMP="${work}" TMP="${work}"
unset DISPLAY WAYLAND_DISPLAY
bad=0

fWine(){ local rc=0; nice -n 19 wine "$@" </dev/null >/dev/null 2>&1 || rc=$?; ((rc == 0)) || { bad=1; printf '%s exited %s\n' "${1##*\\}" "${rc}"; }; }
## The uninstaller hands off to a copy of itself and returns, so wait for the prefix to go idle.
fIdle(){ wineserver -w; }
## TYPE|VALUE, or nothing when there is no Path.
fGetPath(){ wine reg query "${envKey}" /v Path 2>/dev/null </dev/null | tr -d '\r' | sed -n 's/^    Path    \(REG_[A-Z_]*\)    /\1|/p'; }
fSetPath(){
	if [[ -z "${2}" ]]; then wine reg delete "${envKey}" /v Path /f </dev/null >/dev/null 2>&1 || true
	else wine reg add "${envKey}" /v Path /t "${1}" /d "${2}" /f </dev/null >/dev/null 2>&1; fi
}

printf 'MZ' >"${work}/stub.exe"
LC_ALL=C.UTF-8 makensis -V1 -DAPPVERSION=9.9.9 "-DEXEPATH=${work}/stub.exe" "-DOUTFILE=${work}/setup.exe" "${nsi}" >"${work}/makensis.log" 2>&1 \
	|| { printf 'makensis failed: %s\n' "$(tail -3 "${work}/makensis.log" | tr '\n' ' ')"; exit 2; }
if ! nice -n 19 wineboot -i </dev/null >"${work}/wineboot.log" 2>&1; then
	printf 'wineboot failed: %s\n' "$(tail -3 "${work}/wineboot.log" | tr '\n' ' ')"; exit 2
fi
fIdle

fWant(){ local label="$1" want="$2" got; got="$(fGetPath)"; [[ "${got}" == "${want}" ]] && return 0; bad=1; printf '%s: got %s chars [%s...%s]\n' "${label}" "${#got}" "${got:0:40}" "${got: -60}"; }

## Like b29w's: unexpanded entries, about 5000 characters in 78.
longPath='%SystemRoot%\system32;%SystemRoot%;%SystemRoot%\system32\wbem'
for n in $(seq -w 1 75); do longPath+=";C:\\Program Files\\Some Vendor Tool ${n}\\bin\\with a longer folder name"; done
fSetPath REG_EXPAND_SZ "${longPath}"
fWine "${work}/setup.exe" /S;  fIdle; fWant "long PATH, install"   "REG_EXPAND_SZ|${longPath};${instDir}"
fWine "${work}/setup.exe" /S;  fIdle; fWant "long PATH, reinstall" "REG_EXPAND_SZ|${longPath};${instDir}"
fWine "${instDir}\\uninstall.exe" /S; fIdle; fWant "long PATH, uninstall" "REG_EXPAND_SZ|${longPath}"

## Already there in another case with a trailing \, in a REG_SZ: install leaves
## it, uninstall takes it out and keeps the rest and the type.
fSetPath REG_SZ "C:\\a;c:\\program files\\Convert-Base-V2\\;C:\\b;"
fWine "${work}/setup.exe" /S;  fIdle; fWant "already there, install"   "REG_SZ|C:\\a;c:\\program files\\Convert-Base-V2\\;C:\\b;"
fWine "${instDir}\\uninstall.exe" /S; fIdle; fWant "already there, uninstall" "REG_SZ|C:\\a;C:\\b;"

## A trailing ; gets no second one.
fSetPath REG_EXPAND_SZ "C:\\a;"
fWine "${work}/setup.exe" /S;  fIdle; fWant "trailing ;, install" "REG_EXPAND_SZ|C:\\a;${instDir}"
fWine "${instDir}\\uninstall.exe" /S; fIdle; fWant "trailing ;, uninstall" "REG_EXPAND_SZ|C:\\a"

## No PATH at all.
fSetPath REG_EXPAND_SZ ""
fWine "${work}/setup.exe" /S;  fIdle; fWant "no PATH, install" "REG_EXPAND_SZ|${instDir}"

fIdle
exit "${bad}"


##	History:
##		- 20261026 JC: Created.
