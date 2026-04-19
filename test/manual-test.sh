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

##	Copyright and license ...: Toward bottom of this file.
##	History .................: At bottom of this file.

fMain(){
	local    exePath="$(dirname "${0}")/../src/convert-base-v2"
	local -i count_Tests=0
	local -i count_Passed=0
	local -i count_Failed=0

	echo
	fUnitTest

	echo; echo "Results:"
	echo "Total tests .........: ${count_Tests}"
	echo "Passed ..............: ${count_Passed}"
	echo "Failed ..............: ${count_Failed}"
	echo "Expected errors .....: ${count_Errors_Expected}"
	echo "Unexpected errors ...: ${count_Errors_Unexpected}"
	echo
:;}

fUnitTest(){
	local inputVal=""
	local expectVal=""
	local gotVal=""

	## Expect equal - Byte-aligned binary
	inputVal="9999999999999999999999999999999999999999999999999999999999999999999999999999"
	expectVal="${inputVal}"
	fRunTest  '=='  "'${exePath}'  --to 16  ${inputVal}  |  '${exePath}'  --from 16  --to binary  |  '${exePath}'  --from binary  --to 16  |  '${exePath}'  --from 16  --to 10"

	## Expect error - NOT byte-aligned binary
	inputVal="999999999999999999999999999999999999999999999999999999999999999999999999999"
	expectVal="${inputVal}"
	fRunTest  'error'  "'${exePath}'  --to 16  ${inputVal}  |  '${exePath}'  --from 16  --to binary  |  '${exePath}'  --from binary  --to 16  |  '${exePath}'  --from 16  --to 10"

	## Expect equal - base-65536 with big number
	inputVal="-0012345678999999999999999901234567899999999999999991234567899999999900000000000000000000000000000000000000000000000999999999999999999999999999999999999998765432100.000001234567890000999999999987654321000"
	expectVal="-12345678999999999999999901234567899999999999999991234567899999999900000000000000000000000000000000000000000000000999999999999999999999999999999999999998765432100.000001234567890000999999999987654321"
	fRunTest  '=='  "'${exePath}'  --to 65536  --  ${inputVal}  |  '${exePath}'  --from 65536"








:;}


declare -i currentPassStreak=0
fRunTest(){
	local -r  testMode="${1:-}"   ; shift || true   ## 'equal', 'notequal', 'error'.
#	local -r  expectVal="${1:-}"  ; shift || true   ## Inherit from parent instead.
	local -r  cmdStr="${1:-}"     ; shift || true

	##DEBUG
	#echo "count_Passed ..............: ${count_Passed}"
	#echo "count_Failed ..............: ${count_Failed}"
	#echo "count_Errors_Expected .....: ${count_Errors_Expected}"
	#echo "count_Errors_Unexpected ...: ${count_Errors_Unexpected}"
	#echo

	local -i  errNum=0
	local     gotVal=""
	local -ri prevCount_Passed=${count_Passed}
	local -ri prevCount_Failed=${count_Failed}
	local -ri prevCount_Errors_Expected=${count_Errors_Expected}
	local -ri prevCount_Errors_Unexpected=${count_Errors_Unexpected}

	## Run the test
	[[ "${testMode}" ==  'err'* ]]  &&  isExpectingError=1
		gotVal="$(eval "${cmdStr}")"
		errNum=$? ; true
		fTallyResult  $errNum  "${testMode}"  "${expectVal}"  "${gotVal}"
	[[ "${testMode}" ==  'err'* ]]  &&  isExpectingError=0

	## Show output based on test results

	if ((count_Errors_Expected > prevCount_Errors_Expected)); then
		## Action if the test expectedly errored
		currentPassStreak=0
		echo "[ That was an expected and purposely triggered error. ]"
	fi

	if ((count_Passed > prevCount_Passed)); then
		## Action if the test passed
	#	if ((currentPassStreak <= 0)); then  echo -n "Tests passed: "; printf '•%.0s' $(seq 1 "$count_Passed")
	#	else                                 echo -n '•'
	#	fi
		currentPassStreak=$count_Passed
	elif ((count_Failed > prevCount_Failed)); then
		## Action if the test failed
		currentPassStreak=0
		echo
		echo "Test Failed:"
		echo "Expected value: '${expectVal}'"
		echo "Actual value  : '${gotVal}'"
		echo "Command:"
		echo "${cmdStr}"
	elif ((count_Errors_Unexpected > prevCount_Errors_Unexpected)); then
		## Action if the test UN-expectedly errored
		echo
		echo "**** Test errored unexpectedly ****"
		echo "Expected value: '${expectVal}'"
		echo "Actual value  : '${gotVal}'"
		echo "Command:"
		echo "${cmdStr}"
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
		*)                          echo "$(basename "${0}").${FUNCNAME[0]}() - Error: Unexpected second argument. Should be 'equal', 'notequal', or 'error'."; return 1  ;;
	esac
:;}

## Error-handling
declare -i isExpectingError=0
declare -i count_Errors_Unexpected=0
declare -i count_Errors_Expected=0
trap 'printf "(line %s) " "$LINENO" "$?" >&2; echo; { ((isExpectingError))  &&  ((++count_Errors_Expected)); }  ||  ((++count_Errors_Unexpected))' ERR

## Error and exit settings
 set   -u  ## Require variable declaration. Stronger than mere linting. But can struggle if functions are in sourced files.
#set   -e  #...................: Exit on errors. This is inconsistent (made a little better with settings below), so eventually may move to 'set +e' (which is more constant work and mental overhead).
 set   +e  #...................: Do NOT exit on errors.
 set   -E  #...................: Propagate ERR trap settings into functions, command substitutions, and subshells.
 set   -o pipefail  #..........: Make sure all stages of piped commands also fail the same.
 shopt -s inherit_errexit  #...: Propagate 'set -e' ........ into functions, command substitutions, and subshells. Will fail on Bash <4.4.
 shopt -s dotglob  #...........: Include usually-hidden 'dotfiles' in '*' glob operations - usually desired.
 shopt -s globstar  #..........: ** matches more stuff including recursion.

fMain



##	Copyright
##		Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##		Licensed under the GNU General Public License v2.0 or later. Full text at:
##			https://spdx.org/licenses/GPL-2.0-or-later.html
##	SPDX-License-Identifier: GPL-2.0-or-later
##	Preamble:
##		This program is free software: you can redistribute it and/or modify
##		it under the terms of the GNU General Public License as published by
##		the Free Software Foundation, either version 2 of the License, or
##		(at your option) any later version.
##
##		This program is distributed in the hope that it will be useful,
##		but WITHOUT ANY WARRANTY; without even the implied warranty of
##		MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
##		GNU General Public License for more details.
##
##		You should have received a copy of the GNU General Public License
##		along with this program.  If not, see <https://www.gnu.org/licenses/>.


##	Script history:
##		- 202
