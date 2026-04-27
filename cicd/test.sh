#!/bin/bash

## Active shellchecks
# shellcheck disable=1090
# shellcheck disable=1091
# shellcheck disable=2001   ## Complaining about use of sed istead of bash search & replace.
# shellcheck disable=2002   ## Useless use of cat. This works well though and I don't want to break it for the sake of syntax purity.
# shellcheck disable=2004   ## Inappropriate complaining of "$/${} is unnecessary on arithmetic variables."
# shellcheck disable=2119   ## Disable confusing and inapplicable warning about function's $1 meaning script's $1.
# shellcheck disable=2120   ## OK with declaring variables that accept arguments, without calling with arguments (this is 'overloading').
# shellcheck disable=2143   ## Used grep -q instead of echo | grep
# shellcheck disable=2154
# shellcheck disable=2155   ## Disable check to 'Declare and assign separately to avoid masking return values'.
# shellcheck disable=2162
# shellcheck disable=2181
# shellcheck disable=2207
# shellcheck disable=2317   ## Can't reach

## Inactive shellchecks
## shellcheck disable=2034  ## Unused variables.


##	Purpose:
##		- CI/CD-friendly test harness that passes or fails.
##		- Tests random output and round-trips through v2 to make sure the initial output was correct (at least if v2 is also correct).
##		- This is NOT part of cicd script, as it's not a requirement to have v2 installed.
##	History: At bottom of this file. (Note: History for this is maintained outside of [or in addition to] git project.)

##	Copyright
##		Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##		Licensed under the GNU General Public License v2.0 or later. Full text at:
##			https://spdx.org/licenses/GPL-2.0-or-later.html
##		SPDX-License-Identifier: GPL-2.0-or-later

declare doLongTest=0 ; [[ "${CICDTEST_DO_LONGTEST}" == "1" ]] && doLongTest=1

fMain(){
	set -e

	## Settings
	local -ri doBackwardsCompatTests=1
	local     exeV2="../source/convert-base-v2"
	local     exeV1b="../utility/convert-base-v1b"
	local     baseDefs="base-definitions.sh"
#	local     aliasDefs="alias-definitions.sh"

	## Resolve paths
	fResolvePath  exeV2      "${exeV2}"         ; readonly exeV2
	fResolvePath  exeV1b     "${exeV1b}"     0  ; readonly exeV1b  ## Doesn't need to exist, can run tests without. This is to verify backwards-compatibility.
	fResolvePath  baseDefs   "${baseDefs}"      ; readonly baseDefs
#	fResolvePath  aliasDefs  "${aliasDefs}"     ; readonly aliasDefs

	## Compare to exeV2?
	local -i doComareWith_v1=0
	{ ((doBackwardsCompatTests))  &&  [[ -x "${exeV1b}" ]]; }  &&  doComareWith_v1=1
	readonly doComareWith_v1

	## Load base definitions arrays
	fEcho_Clean
	source "${baseDefs}"
#	source "${aliasDefs}"
	fEcho_Clean_Force

	## Variables
	local inputVal=""  expectVal=""  gotVal=""
	local -i loopCount=0

	####
	#### Will it even load at all

	fEcho_Clean
	fEcho_Clean "Exe source ...: ${exeV2}"
	fEcho_Clean "Version ......: $("${exeV2}" --version)"
	fEcho_Clean_Force
	sleep 1
	if ((doComareWith_v1)); then
		fEcho_Clean "v1b source ...: ${exeV1b}"
		fEcho_Clean "Version ......: $("${exeV1b}" --version)"
		fEcho_Clean_Force
		sleep 1
	fi

	####
	#### Test flags (make sure -e is enabled)
	set -e
	fEcho; fEcho ">>> TESTSECTION: Flags"; fEcho

	fEcho; fEcho "Test --help"
	"${exeV1b}" --help

	fEcho "Test --about"
	"${exeV1b}" --about

	fEcho "Test --version (again)"
	"${exeV1b}" --version
	fEcho_Clean_Force


	####
	#### Test base name aliases
	set +e
	fEcho; fEcho ">>> TESTSECTION: Base name aliases"; fEcho

	inputVal="987654321000055555555550000123456789" #....................................: The value is less important than just the aliases. But also, a large value shouldn't fail either.
	fTestAllAliases  "base10"  "${inputVal}" #...........................................: All should pass
	fRunTest  'error'  "${expectVal}"  "'${exeV2}'  '${inputVal}'  bogusBaseName" #......: This one should fail


	####
	#### Looped random fuzz-testing
	set +e
	loopCount=100
	((doLongTest))  &&  loopCount=5000

	## Test **AGAINST SELF**
	fEcho; fEcho ">>> TESTSECTION: Fuzz-testing against self"; fEcho
	fFuzzTest_Self

	#### Test **AGAINST v1b** (all the bases)
	fEcho; fEcho ">>> TESTSECTION: Fuzz-testing against v1b (all bases)"; fEcho
	((doComareWith_v1))  &&  fFuzzTest_Base10_To_BaseX_AndBack_via_v1b


	####
	#### Test val to use for next sections
	inputVal="01234567899999999999999990123456789999999999999999123456789999999990000000000000000000000000000000000000000000000099999999999999999999999999999999999999876543210"


	####
	#### By-hand one-way tests, expect equal
	fEcho; fEcho ">>> TESTSECTION: By-hand one-way tests, expect equal"; fEcho
	set +e

	## 128v1compat
	#expectVal="$(convert-base-v1  "${inputVal}"  128j1)"  #; echo "${expectVal}"
	expectVal="FrĜЋŝĴR2§⁑⍤🝅⌲μr1ϟỹẼ⌲M§ỹλ🜥ψ🝅ᛘêᚼ75ĜᛝmÑ🜥Ĝλŝ▵ϠĜRλΞãᛎ8hÊᛯĝĵΩJĜ▿ĤxŴĵ£Cᛏẅ8ÂψvÉÉδPĝŷ"
	fRunTest  '=='  "${expectVal}"  "'${exeV2}'  ${inputVal}  128v1compat"

	## 128j1
	#expectVal="$(convert-base-v2  "${inputVal}"  128jc1)"  # ; echo "${expectVal}"
	expectVal="BUΩᛨ¢ΞI2🝅x◂p‡aU1ᛦ⍋¿‡F🝅⍋ZnᛘpdЖl75ΩfRɤnΩZ¢qᛯΩIZᛏ⍤b8P≠eЯфμEΩsƱXϠф🜥AcÎ8∞ᛘVŴŴᛝGЯ¥"
	fRunTest  '=='  "${expectVal}"  "'${exeV2}'  ${inputVal}  128jc1"


	####
	#### By-hand one-way tests, expect NOT equal
	fEcho; fEcho ">>> TESTSECTION: By-hand one-way tests, expect NOT equal"; fEcho
	set +e

	## 128j1 != 128v1compat
	#expectVal="$(convert-base-v1  "${inputVal}"  128j1)"  #; echo "${expectVal}"
	expectVal="FrĜЋŝĴR2§⁑⍤🝅⌲μr1ϟỹẼ⌲M§ỹλ🜥ψ🝅ᛘêᚼ75ĜᛝmÑ🜥Ĝλŝ▵ϠĜRλΞãᛎ8hÊᛯĝĵΩJĜ▿ĤxŴĵ£Cᛏẅ8ÂψvÉÉδPĝŷ"
	fRunTest  '!='  "${expectVal}"  "'${exeV2}'  ${inputVal}  128jc1"


	####
	#### By-hand one-way tests, expect ERROR
	fEcho; fEcho ">>> TESTSECTION: By-hand one-way tests, expect ERROR"; fEcho
	set +e

	## Removed base 16 as input, should error.
	expectVal=""
	fRunTest  'error'  "[anything or nothing]"  "'${exeV2}'  --from 201  'ABCXYZ'  10"


	####
	#### By-hand round-trips self-tests, expect equal.
	fEcho; fEcho ">>> TESTSECTION: By-hand round-trip tests, expect equal"; fEcho
	set +e

	expectVal="1234567899999999999999990123456789999999999999999123456789999999990000000000000000000000000000000000000000000000099999999999999999999999999999999999999876543210"
	fRunChained_TestLast  '=='  "${expectVal}"  "'${exeV2}'  --from 10  --to 16  ${inputVal}; '${exeV2}'  --from 16  --to 10  %CMD1_OUTPUT%"

:; set -e; }


fFuzzTest_Self(){

	## Settings
	local -r  LANG="C.UTF-8"
	local -ri maxTestInputChars=1024
	local -ri count_TotalDefinedBases_Input=${#bases_Input_IdxToKey[@]}
	local -ri count_TotalDefinedBases_Output=${#bases_Output_IdxToKey[@]}  ## Will hopefully be the same as input, but not necessarily forever and always in the future.

	## Loop variables
	local -i  tmpRandomBaseIdx=-1
	local -i  random_InputLen=0
	local     inputStr=""
	local     inputBaseName=""
	local     inputBaseSymbols=""
	local     intermediateBaseName=""
	local     intermediateVal=""
	local     exeV2name=""
	local     exeV2args=""

	for ((i=1; i<=loopCount; i++)); do

		## Get a random input base and its list of symbols
		tmpRandomBaseIdx=$((0 + $(od -An -N1 -tu2 /dev/urandom) % (count_TotalDefinedBases_Input - 1) ))
		inputBaseName="${bases_Input_IdxToKey[tmpRandomBaseIdx]}"
		inputBaseSymbols="${bases_Input_KeyToVal["${inputBaseName}"]}"

		## Get a random input of random in-base symbols, of random length
		random_InputLen=$((1 + $(od -An -N2 -tu2 /dev/urandom) % maxTestInputChars))
		[[ -z "${inputBaseSymbols}" ]] && { echo -e "\nError in ${meName_t4rgd}.${FUNCNAME[0]}(): \$inputBaseSymbols == '', aborting.\n" ; exit 1; }
		((random_InputLen <=0))        && { echo -e "\nError in ${meName_t4rgd}.${FUNCNAME[0]}(): \$random_InputLen == 0, aborting.\n"   ; exit 1; }
		fScrambleString  inputStr  "${inputBaseSymbols}"   $random_InputLen

		## To avoid falsely triggering an error:
		## Strip off leading symbols representing '0' from input, which will be gone from the output during conversion.
		expectVal="${inputStr}"
		until [[ "${expectVal:0:1}" !=  "${inputBaseSymbols:0:1}" ]]; do expectVal="${expectVal:1}"; done
		[[ -z "${expectVal}" ]]  &&  continue  ## If it's empty now, just skip to next test.

		## Pick a random intermediate output base
		tmpRandomBaseIdx=$((0 + $(od -An -N1 -tu2 /dev/urandom) % (count_TotalDefinedBases_Output - 1) ))
		intermediateBaseName="${bases_Output_IdxToKey[tmpRandomBaseIdx]}"

		## Format and prepare the first command for display, to be shown in output (via variable "hook"); and run it
		exeV2name=""  exeV2args=""
		fGetIsolatedExeName  exeV2name  exeV2args  "'${exeV2}'  --from '${inputBaseName}'  --to '${intermediateBaseName}'  --  '${expectVal}'"
		__fRunTest_EchoHook1="Cmd 1 ..........: '${exeV2name}'${exeV2args}"
		intermediateVal="$("${exeV2}"  --from "${inputBaseName}"  --to "${intermediateBaseName}"  --  "${expectVal}")"

		#DEBUG
		sleep 2
		echo
		echo "inputBaseName ...............: ${inputBaseName}"
		echo "inputBaseSymbols ............: ${inputBaseSymbols}"
		echo "random_InputLen .............: ${random_InputLen}"
		echo "inputStr ....................: ${inputStr}"
		echo "expectVal ...................: ${expectVal}"
		echo "intermediateBaseName ........: ${intermediateBaseName}"
		echo "intermediateVal .............: ${intermediateVal}"
		echo

		## Run the second command with the previous command's output as this command's input.
		## This command's output should be the same as the previous command's input.
		fRunTest  '=='  "${expectVal}"  "'${exeV2}'  --from '${intermediateBaseName}'  --to '${inputBaseName}'  --  '${intermediateVal}'"

		#DEBUG
		[[ -z "${inputBaseSymbols}" ]] && { echo -e "\ninputBaseSymbols = '', aborting.\n"; return 1; }

	done

}

fFuzzTest_Base10_To_BaseX_AndBack_via_v1b(){

	## Settings
	local -r  LANG="C.UTF-8"
	local -ri maxTestInputChars=256
	local -ri count_TotalDefinedBases_Output=${#bases_Output_IdxToKey[@]}

	## Loop variables
	local -i  random_InputLen=0
	local     inputStr=""
	local -i  tmpRandomBaseIdx=-1
	local     intermediateBaseName=""
	local     intermediateVal=""
	local     exeV1bname=""
	local     exeV1bargs=""

	for ((i=1; i<=loopCount; i++)); do

		## Generate a random base 10 number for first input
		random_InputLen=$((1 + $(od -An -N2 -tu2 /dev/urandom) % maxTestInputChars))
		fScrambleString  inputStr  "0123456789"   $random_InputLen

		## To avoid falsely triggering an error:
		## Strip off leading symbols representing '0' from input, which will be gone from the output during conversion.
		shopt -s extglob
		expectVal="${inputStr#"${inputStr%%[!0]*}"}"
		[[ -z "${expectVal}" ]]  &&  continue

		## Pick a random intermediate v1b output -> v2 input base
		tmpRandomBaseIdx=$((0 + $(od -An -N1 -tu2 /dev/urandom) % (count_TotalDefinedBases_Output - 1) ))
		intermediateBaseName="${bases_Output_IdxToKey[tmpRandomBaseIdx]:-}"

		## Format and prepare the first command for display, to be shown in output (via variable "hook"); and run it
		exeV1bname=""  exeV1bargs=""
		fGetIsolatedExeName  exeV1bname  exeV1bargs  "'${exeV1b}'  --ibase 10  '${expectVal}'  '${intermediateBaseName}'"
		__fRunTest_EchoHook1="Cmd 1 ..........: '${exeV1bname}'${exeV1bargs}"
		intermediateVal="$("${exeV1b}"  --ibase 10  "${expectVal}"  "${intermediateBaseName}")"

		##DEBUG
		#echo
		#echo "random_InputLen .............: ${random_InputLen}"
		#echo "inputStr ....................: ${inputStr}"
		#echo "expectVal ...................: ${expectVal}"
		#echo "tmpRandomBaseIdx ...: ${tmpRandomBaseIdx}"
		#echo "intermediateBaseName ........: ${intermediateBaseName}"
		#echo "intermediateVal .............: ${intermediateVal}"
		#sleep 5

		## Run the second command with the previous command's output as this command's input.
		## This command's output should be the same as the previous command's input.
		fRunTest  '=='  "${expectVal}"  "'${exeV2}'  --from '${intermediateBaseName}'  --to 10  --  '${intermediateVal}'"

	done

}


fTestAllAliases(){
	local -r inputBase="${1:-}"  ; shift || true
	local -r inputVal="${1:-}"   ; shift || true
	for nextBase in "${baseAliasesArr[@]}"; do
		fRunTest  'no_error'  "[anything or nothing]"  "'${exeV2}'  --from ${inputBase}  ${inputVal}  ${nextBase}"
	done
}


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Generic function prototypes for reference and linting correctness. Overridden with real function when generic script is sourced at the bottom of this script.
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fEntryPoint(){
	local -i count_Tests=0
	local -i count_Passed=0
	local -i count_Failed=0
:;}
fRunTest(){
	local -r  testMode="${1:-}"   ; shift || true   ## 'equal', 'notequal', 'error'.
	local -r  expectVal="${1:-}"  ; shift || true   ## Inherit from parent instead.
	local -r  cmdStr="${1:-}"     ; shift || true
:;}
fRunChained_TestLast(){
	local -r  testMode="${1:-}"   ; shift || true   ## 'equal', 'notequal', 'error'.
	local -r  expectVal="${1:-}"  ; shift || true   ## Inherit from parent instead.
	local -r  cmdStrs="${1:-}"    ; shift || true   ## >=1 commands with ';' as delimiter.
:;}
fPipe_LogAndShowPartialOutput_InitLogfile(){
	local filePath_Log="${1:-}" ; shift || true  ## If you want to override the logfile path. Otherwise it's the path of this script+basename, + '.log'.
:;}
fPipe_LogAndShowPartialOutput(){ :; }
fPipe_LogOnly(){ :; }
fGetIsolatedExeName(){
	local -n  retVarName_CmdName_1myq1b5="${1:-}"   ; shift || true   ## The parent variable to populate with the isolated command 'basename' (no path).
	local -n  retVarName_TheRest_1myq1b5="${1:-}"   ; shift || true   ## The parent variable to populate with the rest of the command-line after the executable.
	local -r  commandString="${1:-}"                ; shift || true   ## The full command line
:;}
fScrambleString(){
	local -n  outputVarName_1myn9vt=${1:-}   ; shift || true  ## The parent variable to put the results in. The results should have no spaces, unless a space is one of the inputs as a symbol to randomize. But will still work with spaces.
	local -r  inputSymbolList="${1:-}"       ; shift || true  ## List of symbols to scramble, as a regular UTF-8 bash string. Will have no spaces or delimiters, unless a space is one of the inputs as a symbol to randomize.
	local -ri outputLen=${1:-1}              ; shift || true  ## Output scrambled string length
	local -ri canRepeatChars=${1:-1}         ; shift || true  ## 0: Don't repeat any symbols if possible (i.e. if input len > output len). 1: Try to repeat symbols in the random output.
}
fTallyResult(){
	local -ri errNum=${1:-0}      ; shift || true  ## The integer return value from the command.
	local -r  testMode="${1:-}"   ; shift || true  ## 'equal', 'notequal', 'error'.
	local -r  expectVal="${1:-}"  ; shift || true  ##
	local -r  gotVal="${1:-}"     ; shift || true  ##
:;}
fEcho_ResetBlankCounter()     { :; }
fEcho_WasLastEchoBlank_Set()  { local -i arg1=${1:-0}; }
fEcho_WasLastEchoBlank_Get()  { return 0; }
fEcho_IsInRawInlineMode_Set() { local -i arg1=${1:-0}; }
fEcho_IsInRawInlineMode_Get() { return 0; }
fEcho_Clean()             { local -i arg1="${1:-0}"; }
fEcho()                   { local -i arg1="${1:-0}"; }
fEcho_Force()             { local -i arg1="${1:-0}"; }
fEcho_Clean_Force()       { local -i arg1="${1:-0}"; }


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Generic function(s) that can't be 'sourced'.
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fResolvePath(){
	## First looks at specified raw path. Next, same path but relative to this script. Next, in $PATH for an executable. Next, in this script's path, + /lib, /include, then /includes.
	local -n parentVarName_ResolvedPath_t4rej=${1:-}  ; shift || true  ## Parent variable to store fully resolved path in.
	local    nameOrPath="${1:-}"                      ; shift || true  ## File or folder path (relative or absolute). If an executable file, can be just a name to search in $PATH, to fully resolve.
	local -i mustExist=${1:-1}                        ; shift || true  ## 1 [default]: path must exist or error occurs. 0: Just rationalize paths.
	[[   -z "${nameOrPath}" ]]  &&  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}")·${FUNCNAME[0]}(): No path specified to resolve.\n"; fEcho_WasLastEchoBlank_Set 1; return 1; }
	local -r mePath_t4rmy="$(dirname "${BASH_SOURCE[0]}")"
	local -i isNopathObject=0 ; [[ "${nameOrPath}" == "$(basename "${nameOrPath}")" ]] && isNopathObject=1 ; readonly isNopathObject
	local    testPath="${nameOrPath}"
	{ [[ ! -e "${testPath}"   ]]                          ; }  &&  testPath="${mePath_t4rmy}/${nameOrPath}"
	{ [[ ! -e "${testPath}"   ]] && ((isNopathObject))    ; }  &&  testPath="$(which "${nameOrPath}" 2>/dev/null || true)"
	{ [[ ! -e "${testPath}"   ]] && ((isNopathObject))    ; }  &&  testPath="${mePath_t4rmy}/lib/${nameOrPath}"
	{ [[ ! -e "${testPath}"   ]] && ((isNopathObject))    ; }  &&  testPath="${mePath_t4rmy}/include/${nameOrPath}"
	{ [[ ! -e "${testPath}"   ]] && ((isNopathObject))    ; }  &&  testPath="${mePath_t4rmy}/includes/${nameOrPath}"
	{ [[ ! -e "${testPath}"   ]] && ((mustExist))         ; }  &&  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}")·${FUNCNAME[0]}(): Could not resolve path '${nameOrPath}' [£ǝŔc].\n"; fEcho_WasLastEchoBlank_Set 1; return 1; }
	{ [[ ! -e "${testPath}"   ]] || [[ -z "${testPath}" ]]; }  &&  testPath="${nameOrPath}"  ## Revert to original definition
	if ((mustExist)); then testPath="$(realpath -e "${testPath}" 2>/dev/null || true)"
	else                   testPath="$(realpath -m "${testPath}" 2>/dev/null || true)"; fi
	## Last check to fail on
	{ [[ -z "${testPath}" ]] || { [[ ! -e "${testPath}" ]] && ((mustExist)); }; }  &&  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}")·${FUNCNAME[0]}(): Could not resolve path '${nameOrPath}' [£ǝŔs].\n"; fEcho_WasLastEchoBlank_Set 1; return 1; }
	## Success
	parentVarName_ResolvedPath_t4rej="${testPath}"
}


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Entry point
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••

if [[ -z "${meName_t4rgd+x}" ]]; then
	declare -r mePath_t4rgd="${BASH_SOURCE[0]}"
	declare -r meName_t4rgd="$(basename "${mePath_t4rgd}")"
	declare -r meDir_t4rgd="$(dirname "${mePath_t4rgd}")"
	declare -r serialDT_t4rgd="$(date "+%Y%m%d-%H%M%S")"
fi


## Source the generic script 'utility/n8test'. It will call fMain() above.
declare n8test_resolved="../utility/n8test"
fResolvePath  n8test_resolved  "${n8test_resolved}" ; readonly n8test_resolved
[[ -z "${n8test_resolved}" ]] || source "${n8test_resolved}"

## Initialize logging (fPipe_LogAndShowPartialOutput_InitLogfile() is defined in 'n8test')
declare logFile="${mePath_t4rgd%.*}.log"
fResolvePath  logFile    "${logFile}"  0
fPipe_LogAndShowPartialOutput_InitLogfile "${logFile}"

## Kick off testing (functions are defined in 'n8test')
fEntryPoint | fPipe_LogAndShowPartialOutput



#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##	Script history:
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##		- 20260420 JC: Copied test.sh to test_against_v2.sh.
##		- 20260425 JC: Finished.
