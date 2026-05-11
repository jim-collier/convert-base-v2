#!/bin/bash

fMain(){

	## Settings
	local pyScript1="include/filter_1_junk.py"   ; pyScript1="$(dirname "${BASH_SOURCE[0]}")/${pyScript1}" ; pyScript1="$(realpath -e "${pyScript1}")" ; readonly pyScript1
	local pyScript2="include/filter_2_messy.py"  ; pyScript2="$(dirname "${BASH_SOURCE[0]}")/${pyScript2}" ; pyScript2="$(realpath -e "${pyScript2}")" ; readonly pyScript2
	local pyScript3="include/filter_3_visual.py" ; pyScript3="$(dirname "${BASH_SOURCE[0]}")/${pyScript3}" ; pyScript3="$(realpath -e "${pyScript3}")" ; readonly pyScript3


	## Validate
	[[ -f "${pyScript1}" ]]     ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}: Can't find Python script to run: '${pyScript1}'\n";return 1; }
	[[ -f "${pyScript2}" ]]     ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}: Can't find Python script to run: '${pyScript2}'\n";return 1; }
	[[ -f "${pyScript3}" ]]     ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}: Can't find Python script to run: '${pyScript3}'\n";return 1; }
	which python3  &>/dev/null  ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}: It appears 'python3' is not installed or symlinked.\n";return 1; }
	which xclip    &>/dev/null  ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}: It appears 'xclip' is not installed. Are you using Wayland instead of Xorg?\n";return 1; }
	which eog      &>/dev/null  ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}: It appears 'python3' is not installed or symlinked.\n";return 1; }

	## Prepare
	[[ -x "${pyScript1}" ]]   ||  chmod +x "${pyScript1}" 1>/dev/null
	[[ -x "${pyScript2}" ]]   ||  chmod +x "${pyScript2}" 1>/dev/null
	[[ -x "${pyScript3}" ]]   ||  chmod +x "${pyScript3}" 1>/dev/null

	## Get clipboard contents
	local -r clipInput="$(xclip -o -selection clipboard)"
	sleep 0.25

	## Validate
	[[ -n "$(tr -d '[:space:]' <<< "${clipInput}")" ]]   ||  { echo -e "\nWarning in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}: No text exists on the X clipboard.\n";return 1; }

	echo

	echo "Input from clipboard:"
	echo "  '${clipInput}'"
	local sResult1="" sResult2="" sResult3=""

	echo -e "\n[ Running '${pyScript1}' ... ]"
#	sleep 0.5
	sResult1="$(python3  "${pyScript1}"  --debug  "${clipInput}")"
	[[ -n "${sResult1}" ]]  ||  { echo -e "\n$(basename "${pyScript1}"): No output.\n"; return 1; }

	echo -e "\n[ Running '${pyScript2}' ... ]"
#	sleep 0.5
	sResult2="$(python3  "${pyScript2}"  --debug  "${sResult1}")"
	[[ -n "${sResult2}" ]]  ||  { echo -e "\n$(basename "${pyScript2}"): No output.\n"; return 1; }

	echo -e "\n[ Running '${pyScript3}' ... ]"
#	sleep 0.5
	sResult3="$(python3  "${pyScript3}"  --debug  "${sResult2}")"
#	[[ -n "${sResult3}" ]]  ||  { echo -e "\n$(basename "${pyScript3}"): No output.\n"; return 1; }

	echo
	echo "Stats:"
	echo "  Original count : $(( $(echo "${clipInput}" | tr -d ' ' | wc -m) -1))"
	echo "  Final Count ...: $(( $(echo "${sResult3}"   | tr -d ' ' | wc -m) -1))"
	echo "Final output:"
	echo "${sResult3}"

#	## Set the clipboard with potentially modified contents
#	echo "${sResult}" | xclip -i -selection clipboard

	## Show results on CLI
	fScr "${sResult3}01234ABCDefgh"

	## "eog": Eye Of Gnome, simple image viewer.
	local -r outputFile="$(ls -t "${HOME}/var/unicode-visual-debug/"*  | head -n 1)"
	[[ -n "${outputFile}" ]]  &&  [[ -f "${outputFile}" ]]  &&  ( (nohup bash -c "eog '${outputFile}'" &>/dev/null) & disown )

	echo
}


fScr(){
	local -ri minLen=999
	sanitized=$(echo "${1}" | tr -d '[:space:]')
	echo -e "\nOutput to scramble for test:"
	echo -e "${sanitized}\n${sanitized}"
	local -i doLen=${#sanitized} ; ((doLen < minLen)) && doLen=minLen ; readonly doLen
	local scrambled=""
	while ((${#scrambled} < doLen)); do scrambled+="${sanitized}"; done
	scrambled=$(echo "${scrambled}" | grep -o . | shuf | head -n ${doLen} | tr -d '\n')
	echo -e "\nScrabled example:\n${scrambled}\n"
}


set -e
fMain
