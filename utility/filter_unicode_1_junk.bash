#!/bin/bash

fMain(){

	## Settings
	local pyScript="include/filter_junk.py"
	pyScript="$(dirname "${BASH_SOURCE[0]}")/${pyScript}"
	pyScript="$(realpath -e "${pyScript}")"
	readonly pyScript

	## Validate
	[[ -f "${pyScript}" ]]     ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}: Can't find Python script to run: '${pyScript}'\n";return 1; }
	which xclip &>/dev/null    ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}: It appears 'xclip' is not installed. Are you using Wayland instead of Xorg?\n";return 1; }
	which python3 &>/dev/null  ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}: It appears 'python3' is not installed or symlinked.\n";return 1; }

	## Prepare
	[[ -x "${pyScript}" ]]   ||  chmod +x "${pyScript}" 1>/dev/null

	## Get clipboard contents
	local -r clipInput="$(xclip -o -selection clipboard)"
	sleep 0.25

	## Validate
	[[ -n "$(tr -d '[:space:]' <<< "${clipInput}")" ]]   ||  { echo -e "\nWarting in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}: No text exists on the X clipboard.\n";return 1; }

	echo

	echo "Input from clipboard:"
	echo "  Count: $(( $(echo "${clipInput}" | tr -d ' ' | wc -m) -1))"
	echo "  '${clipInput}'"

	local sResult="$(python3  "${pyScript}"  "${clipInput}")"
#	sResult="${sResult/'  '/}"
	readonly sResult

	echo
	echo "Output to clipboard:"
	echo "  Count: $(( $(echo "${sResult}" | tr -d ' ' | wc -m) -1))"
	echo "  '${sResult}'"

	## Set the clipboard with potentially modified contents
	echo "${sResult}" | xclip -i -selection clipboard


	echo
}


set -e
fMain
