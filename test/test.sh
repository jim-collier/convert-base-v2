#!/bin/bash

# shellcheck disable=2004  ## Inappropriate complaining of "$/${} is unnecessary on arithmetic variables."
# shellcheck disable=2034  ## Unused variables.
# shellcheck disable=2119  ## Disable confusing and inapplicable warning about function's $1 meaning script's $1.
# shellcheck disable=2155  ## Disable check to 'Declare and assign separately to avoid masking return values'.
# shellcheck disable=2120  ## OK with declaring variables that accept arguments, without calling with arguments (this is 'overloading').
# shellcheck disable=2001  ## Complaining about use of sed istead of bash search & replace.
# shellcheck disable=2002  ## Useless use of cat. This works well though and I don't want to break it for the sake of syntax purity.
# shellcheck disable=2317  ## Can't reach
# shellcheck disable=2143  ## Used grep -q instead of echo | grep
# shellcheck disable=2162
# shellcheck disable=2207
# shellcheck disable=2181


##	Copyright
##		Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##		Licensed under the GNU General Public License v2.0 or later. Full text at:
##			https://spdx.org/licenses/GPL-2.0-or-later.html
##		SPDX-License-Identifier: GPL-2.0-or-later
##	History .................: At bottom of this file.


## Settings
declare -r exePath="$(dirname "${0}")/../src/convert-base-v2"


fUnitTest(){
	local inputVal=""  expectVal=""  gotVal=""

	fEcho_Clean; echo "$(basename "${exePath}")  $("${exePath}" --version)"; fEcho_Clean_Force

	## Expect equal - Byte-aligned binary
	inputVal="9999999999999999999999999999999999999999999999999999999999999999999999999999"
	expectVal="${inputVal}"
	fRunTest  '=='  "'${exePath}'  --to 16  ${inputVal}  |  '${exePath}'  --from 16  --to binary  |  '${exePath}'  --from binary  --to 16  |  '${exePath}'  --from 16  --to 10"

#	## Expect equal - base-65536 with big number [known bug]
#	inputVal="-0012345678999999999999999901234567899999999999999991234567899999999900000000000000000000000000000000000000000000000999999999999999999999999999999999999998765432100.000001234567890000999999999987654321000"
#	expectVal="-12345678999999999999999901234567899999999999999991234567899999999900000000000000000000000000000000000000000000000999999999999999999999999999999999999998765432100.000001234567890000999999999987654321"
#	fRunTest  '=='  "'${exePath}'  --to 65536  --  ${inputVal}  |  '${exePath}'  --from 65536"

	## Expect ERROR - NOT byte-aligned binary [fix in future with padding]
	inputVal="999999999999999999999999999999999999999999999999999999999999999999999999999"
	expectVal="${inputVal}"
	fRunTest  'error'  "'${exePath}'  --to 16  ${inputVal}  |  '${exePath}'  --from 16  --to binary  |  '${exePath}'  --from binary  --to 16  |  '${exePath}'  --from 16  --to 10"



:;}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Generic code
#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fMain(){
	local -i count_Tests=0
	local -i count_Passed=0
	local -i count_Failed=0
	set +e
		fUnitTest
	set -e
	fEcho_Clean; fEcho_Clean "Results:"
	fEcho_Clean "Total tests .........: ${count_Tests}"
	fEcho_Clean "Passed ..............: ${count_Passed}"
	fEcho_Clean "Failed ..............: ${count_Failed}"
	fEcho_Clean "Expected errors .....: ${count_Errors_Expected}"
	fEcho_Clean "Unexpected errors ...: ${count_Errors_Unexpected}"
	fEcho_Clean
	((count_Failed == 0))  ||  exit 1
}

declare -i currentPassStreak=0
fRunTest(){
	local -r  testMode="${1:-}"   ; shift || true   ## 'equal', 'notequal', 'error'.
#	local -r  expectVal="${1:-}"  ; shift || true   ## Inherit from parent instead.
	local -r  cmdStr="${1:-}"     ; shift || true

	local -i  errNum=0
	local     gotVal=""
	local -ri prevCount_Passed=${count_Passed}
	local -ri prevCount_Failed=${count_Failed}
	local -ri prevCount_Errors_Expected=${count_Errors_Expected}
	local -ri prevCount_Errors_Unexpected=${count_Errors_Unexpected}

	((++count_Tests))

	## Run the test
	if [[ "${testMode}" ==  'err'* ]]; then
		isExpectingError=1
		fEcho; fEcho "Test #${count_Tests} Expecting error, BEGIN ..."
		gotVal="$(eval "${cmdStr}")" ; errNum=$? ; true
		fEcho "Test #${count_Tests} Expecting error, END."; fEcho
		isExpectingError=0
	else
		gotVal="$(eval "${cmdStr}")" ; errNum=$? ; true
	fi
	fTallyResult  $errNum  "${testMode}"  "${expectVal}"  "${gotVal}"

	## Show output based on test results

	if ((count_Errors_Expected > prevCount_Errors_Expected)); then
		## Action if the test expectedly errored
		currentPassStreak=0

	fi

	if ((count_Passed > prevCount_Passed)); then
		## Action if the test passed
		if ((currentPassStreak <= 0)); then  fEcho_Clean; echo -n "Test #s passed: ${count_Tests}, "
		else                                              echo -n "${count_Tests}, "
		fi
		fEcho_IsInRawInlineMode_Set 1
		currentPassStreak=$count_Passed
	elif ((count_Failed > prevCount_Failed)); then
		## Action if the test failed
		currentPassStreak=0
		fEcho_Clean
		fEcho_Clean "Test #${count_Tests} Failed:"
		fEcho_Clean "Expected value: '${expectVal}'"
		fEcho_Clean "Actual value  : '${gotVal}'"
		fEcho_Clean "Command:"
		fEcho_Clean "${cmdStr}"
		fEcho_Clean
	elif ((count_Errors_Unexpected > prevCount_Errors_Unexpected)); then
		## Action if the test UN-expectedly errored
		fEcho_Clean
		fEcho_Clean "**** Test errored unexpectedly ****"
		fEcho_Clean "Expected value: '${expectVal}'"
		fEcho_Clean "Actual value  : '${gotVal}'"
		fEcho_Clean "Command:"
		fEcho_Clean "${cmdStr}"
		fEcho_Clean
	fi

:;}

fTallyResult(){
	local -ri errNum=${1:-0}      ; shift || true  ## The integer return value from the command.
	local -r  testMode="${1:-}"   ; shift || true  ## 'equal', 'notequal', 'error'.
	local -r  expectVal="${1:-}"  ; shift || true  ##
	local -r  gotVal="${1:-}"     ; shift || true  ##
	case "${testMode,,}" in
		'eq'*|'pass'|'='|'==')      { [[ "${expectVal}"  ==  "${gotVal}" ]]  &&  ((++count_Passed)); }  ||  ((++count_Failed))   ;;
		'noteq'*|'fail'|'!='|'<>')  { [[ "${expectVal}"  !=  "${gotVal}" ]]  &&  ((++count_Passed)); }  ||  ((++count_Failed))   ;;
		'err'*)                     { ((errNum != 0))                        &&  ((++count_Passed)); }  ||  ((++count_Failed))   ;;
		*)                          fEcho_Clean "$(basename "${0}").${FUNCNAME[0]}() - Error: Unexpected second argument. Should be 'equal', 'notequal', or 'error'."; return 1  ;;
	esac
:;}

## Echo-handling
declare -i _wasLastEchoBlank=0
declare -i _isEchoInRawInlineMode=0
fEcho_ResetBlankCounter()     { _wasLastEchoBlank=0;      }
fEcho_IsInRawInlineMode_Set() { [[ "${1}" == "1" ]]  &&  _isEchoInRawInlineMode=1; }  ## Script it telling fEcho* that something is going to be echoing to the screen in non-linefeed mode without its knowledge. (E.g. "echo -n 'something: '".)
fEcho_IsInRawInlineMode_Get() { { ((_isEchoInRawInlineMode))  &&  return 0; }  ||  return 1; }
fEcho_Clean(){
	((_isEchoInRawInlineMode))  &&  { echo; _wasLastEchoBlank=0; _isEchoInRawInlineMode=0; }
	if [[ -n "${1:-}" ]]; then echo -e "$*"; _wasLastEchoBlank=0; elif [[ $_wasLastEchoBlank -eq 0 ]]; then echo; _wasLastEchoBlank=1; fi; }
fEcho()                   { if [[ -n "$*" ]]; then fEcho_Clean "[ $* ]"; else fEcho_Clean ""; fi; }
fEcho_Force()             { fEcho_ResetBlankCounter; fEcho "$*";       }
fEcho_Clean_Force()       { fEcho_ResetBlankCounter; fEcho_Clean "$*"; }

## Error-handling
declare -i isExpectingError=0
declare -i count_Errors_Unexpected=0
declare -i count_Errors_Expected=0
#trap 'printf "(line %s) " "$LINENO" "$?" >&2; echo; { ((isExpectingError))  &&  ((++count_Errors_Expected)); }  ||  ((++count_Errors_Unexpected))' ERR
trap '{ ((isExpectingError))  &&  ((++count_Errors_Expected)); }  ||  ((++count_Errors_Unexpected))' ERR


## Error and exit settings
 set   -u  ## Require variable declaration. Stronger than mere linting. But can struggle if functions are in sourced files.
 set   -e  #...................: Exit on errors. This is inconsistent (made a little better with settings below), so eventually may move to 'set +e' (which is more constant work and mental overhead).
#set   +e  #...................: Do NOT exit on errors.
 set   -E  #...................: Propagate ERR trap settings into functions, command substitutions, and subshells.
 set   -o pipefail  #..........: Make sure all stages of piped commands also fail the same.
 shopt -s inherit_errexit  #...: Propagate 'set -e' ........ into functions, command substitutions, and subshells. Will fail on Bash <4.4.
 shopt -s dotglob  #...........: Include usually-hidden 'dotfiles' in '*' glob operations - usually desired.
 shopt -s globstar  #..........: ** matches more stuff including recursion.

fMain



##	Script history:
##		- 20260420 JC: Copied for convert-base-v2.
##		- 20260421 JC: Added polish.
